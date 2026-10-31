// mirror-images run. index.ts binds the repository, storage and fetch.
// Bucket is only `media`. Object paths are derived from media type, id and asset
// key. A failed fetch or upload does not write the catalog image column.
import {
  ASSET_KEYS,
  tableFor,
  type CatalogRow,
  type MediaType,
  type MirrorRepository,
} from "./mirror_repository.ts";
import { ALLOWED_BUCKET, type MirrorStorage } from "./mirror_storage.ts";
import {
  classifySourceUrl,
  DEFAULT_FETCH_TIMEOUT_MS,
  DEFAULT_MAX_IMAGE_BYTES,
  fetchBoundedImage,
} from "./source_fetch.ts";

export const MIRROR_CONCURRENCY = 4;
const PRIORITY_LIMIT = 50;

const KNOWN_TYPES = new Set<string>(["ANIME", "MANGA", "CHARACTER", "STAFF"]);

export type MirrorPayload = {
  bucket?: unknown;
  mediaTypes?: unknown;
  limit?: unknown;
  offset?: unknown;
  overwrite?: unknown;
  skipIfMirrored?: unknown;
  cacheControl?: unknown;
  timeBudgetMs?: unknown;
  lockTtlSeconds?: unknown;
  /** Ignored. Paths are never taken from the payload. */
  path?: unknown;
};

export type MirrorRunInput = {
  repository: MirrorRepository;
  storage: MirrorStorage;
  fetch: (input: string, init?: RequestInit) => Promise<Response>;
  now: () => number;
  supabaseUrl: string;
  payload: MirrorPayload;
  maxImageBytes?: number;
  fetchTimeoutMs?: number;
};

type AssetJob = {
  mediaType: MediaType;
  mediaId: number;
  assetKey: string;
  sourceUrl: string | null;
  basePath: string;
  updates: Record<string, string>;
};

export function runMirrorImages(input: MirrorRunInput): Promise<Response> {
  return run(input);
}

async function run(input: MirrorRunInput): Promise<Response> {
  const bucket = resolveBucket(input.payload.bucket);
  if (!bucket) {
    return json({ success: false, error: "invalid_bucket" }, 400);
  }

  const mediaTypes = normalizeMediaTypes(input.payload.mediaTypes);
  const limit = asNumber(input.payload.limit, 200);
  const offset = asNumber(input.payload.offset, 0);
  const overwrite = asBoolean(input.payload.overwrite, false);
  const skipIfMirrored = asBoolean(input.payload.skipIfMirrored, true);
  const cacheControl = input.payload.cacheControl !== undefined
    ? String(input.payload.cacheControl)
    : "max-age=31536000, immutable";
  const timeBudgetMs = asNumber(input.payload.timeBudgetMs, 90_000);
  const lockTtlSeconds = asNumber(input.payload.lockTtlSeconds, 120);
  const startedMs = input.now();
  const shouldStop = () => (input.now() - startedMs) >= timeBudgetMs;
  const lockKey = `mirror-images:${[...mediaTypes].sort().join(",")}:${offset}`;
  const nowIso = () => new Date(input.now()).toISOString();

  const ctx: Ctx = {
    ...input,
    bucket,
    overwrite,
    skipIfMirrored,
    cacheControl,
    shouldStop,
    nowIso,
    maxImageBytes: input.maxImageBytes ?? DEFAULT_MAX_IMAGE_BYTES,
    fetchTimeoutMs: input.fetchTimeoutMs ?? DEFAULT_FETCH_TIMEOUT_MS,
  };

  let runId: number | null = null;
  let lockAcquired = false;
  try {
    runId = await input.repository.startRun(input.payload, nowIso());
    const outcome = await input.repository.acquireLock(lockKey, lockTtlSeconds);
    if (outcome === "busy") {
      await input.repository.finishRun(runId, "skipped", {}, `locked (key=${lockKey})`, nowIso(), input.now() - startedMs);
      return json({ success: true, skipped: true, reason: "locked", lockKey });
    }
    lockAcquired = outcome === "acquired";

    const results: Record<string, number> = {};
    results["priority"] = await drainPriorityQueue(ctx);

    if (mediaTypes.includes("ANIME")) results["anime"] = await mirrorGroup(ctx, "ANIME", limit, offset);
    if (mediaTypes.includes("MANGA")) results["manga"] = await mirrorGroup(ctx, "MANGA", limit, offset);
    if (mediaTypes.includes("CHARACTER")) results["characters"] = await mirrorGroup(ctx, "CHARACTER", limit, offset);
    if (mediaTypes.includes("STAFF")) results["staff"] = await mirrorGroup(ctx, "STAFF", limit, offset);

    await input.repository.finishRun(runId, "success", results, null, nowIso(), input.now() - startedMs);
    return json({ success: true, results });
  } catch (e) {
    try {
      await input.repository.finishRun(runId, "error", {}, (e as Error).message, nowIso(), input.now() - startedMs);
    } catch (_ignored) { /* best-effort, same as before */ }
    return json({ success: false, error: (e as Error).message }, 500);
  } finally {
    if (lockAcquired) await input.repository.releaseLock(lockKey);
  }
}

type Ctx = MirrorRunInput & {
  bucket: typeof ALLOWED_BUCKET;
  overwrite: boolean;
  skipIfMirrored: boolean;
  cacheControl: string;
  shouldStop: () => boolean;
  nowIso: () => string;
  maxImageBytes: number;
  fetchTimeoutMs: number;
};

function resolveBucket(raw: unknown): typeof ALLOWED_BUCKET | null {
  if (raw === undefined || raw === null) return ALLOWED_BUCKET;
  return raw === ALLOWED_BUCKET ? ALLOWED_BUCKET : null;
}

function normalizeMediaTypes(raw: unknown): string[] {
  if (!Array.isArray(raw)) return ["ANIME", "MANGA"];
  const types = raw.filter((value): value is string => typeof value === "string");
  return types.length > 0 ? types : ["ANIME", "MANGA"];
}

function asNumber(value: unknown, fallback: number): number {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function asBoolean(value: unknown, fallback: boolean): boolean {
  return typeof value === "boolean" ? value : fallback;
}

async function drainPriorityQueue(ctx: Ctx): Promise<number> {
  const pending = await ctx.repository.pendingPriority(PRIORITY_LIMIT);
  if (pending.length === 0) return 0;

  const idsByType: Record<string, number[]> = {};
  for (const row of pending) {
    if (!KNOWN_TYPES.has(row.media_type)) continue;
    (idsByType[row.media_type] ??= []).push(row.media_id);
  }
  const liveByKey: Record<string, CatalogRow> = {};
  for (const mediaType of Object.keys(idsByType) as MediaType[]) {
    const rows = await ctx.repository.liveRows(mediaType, idsByType[mediaType]);
    for (const row of rows) liveByKey[`${mediaType}:${row.id}`] = row;
  }

  const updatesByKey: Record<string, Record<string, string>> = {};
  const jobs: Array<AssetJob & { permanent: boolean; clear: () => Promise<void> }> = [];
  const skips: Array<AssetJob & { permanent: boolean; clear: () => Promise<void> }> = [];

  for (const row of pending) {
    if (!KNOWN_TYPES.has(row.media_type)) continue;
    const mediaType = row.media_type;
    const live = liveByKey[`${mediaType}:${row.media_id}`];
    const raw = live ? live[row.asset_key] : null;
    const sourceUrl = typeof raw === "string" && raw.length > 0 ? raw : null;
    const key = `${mediaType}:${row.media_id}`;
    const updates = updatesByKey[key] ??= {};
    const job = {
      mediaType,
      mediaId: row.media_id,
      assetKey: row.asset_key,
      sourceUrl,
      basePath: basePathFor(mediaType, row.media_id, row.asset_key),
      updates,
      permanent: !sourceUrl || !isRemoteAndNotMirrored(sourceUrl, ctx),
      clear: () => ctx.repository.clearPriority(mediaType, row.media_id, row.asset_key, ctx.nowIso()),
    };
    if (needsFetch(sourceUrl, ctx)) jobs.push(job);
    else skips.push(job);
  }

  let mirroredCount = 0;
  for (const job of skips) {
    if (ctx.shouldStop()) break;
    const mirrored = await mirrorAsset(ctx, job);
    if (mirrored) mirroredCount += 1;
    if (mirrored || job.permanent) await job.clear();
  }
  await mapBounded(jobs, MIRROR_CONCURRENCY, async (job) => {
    if (ctx.shouldStop()) return;
    const mirrored = await mirrorAsset(ctx, job);
    if (mirrored) mirroredCount += 1;
    if (mirrored || job.permanent) await job.clear();
  });

  for (const key of Object.keys(updatesByKey)) {
    const updates = updatesByKey[key];
    if (Object.keys(updates).length === 0) continue;
    const [mediaType, idStr] = key.split(":");
    const { error } = await ctx.repository.updateCatalogRow(mediaType as MediaType, Number(idStr), updates);
    if (error) console.error("priority drain update error:", error);
  }
  return mirroredCount;
}

async function mirrorGroup(ctx: Ctx, mediaType: MediaType, limit: number, offset: number): Promise<number> {
  const rows = await ctx.repository.remoteWindow(mediaType, offset, limit);
  const plans = new Map<number, Record<string, string>>();
  const jobs: AssetJob[] = [];

  for (const row of rows) {
    if (ctx.shouldStop()) break;
    const updates: Record<string, string> = {};
    plans.set(row.id, updates);
    for (const assetKey of ASSET_KEYS[mediaType]) {
      const raw = row[assetKey];
      const sourceUrl = typeof raw === "string" && raw.length > 0 ? raw : null;
      const job: AssetJob = {
        mediaType,
        mediaId: row.id,
        assetKey,
        sourceUrl,
        basePath: basePathFor(mediaType, row.id, assetKey),
        updates,
      };
      if (needsFetch(sourceUrl, ctx)) jobs.push(job);
      else await mirrorAsset(ctx, job);
    }
  }

  await mapBounded(jobs, MIRROR_CONCURRENCY, async (job) => {
    if (ctx.shouldStop()) return;
    await mirrorAsset(ctx, job);
  });

  let updated = 0;
  for (const [id, updates] of plans) {
    if (Object.keys(updates).length === 0) continue;
    const { error } = await ctx.repository.updateCatalogRow(mediaType, id, updates);
    if (error) console.error(`${mediaType} update error:`, error);
    else updated += 1;
  }
  return updated;
}

function needsFetch(sourceUrl: string | null, ctx: Ctx): boolean {
  if (!sourceUrl || !isRemoteAndNotMirrored(sourceUrl, ctx)) return false;
  return classifySourceUrl(sourceUrl).ok;
}

async function mirrorAsset(ctx: Ctx, job: AssetJob): Promise<boolean> {
  const { mediaType, mediaId, assetKey, sourceUrl, basePath, updates } = job;
  if (!sourceUrl) {
    await record(ctx, {
      mediaType, mediaId, assetKey, sourceUrl: null, mirroredUrl: null,
      state: "skipped", visibility: "hidden",
      details: { overwrite: ctx.overwrite, reason: "missing_source" },
    });
    return false;
  }

  if (!isRemoteAndNotMirrored(sourceUrl, ctx)) {
    const stored = isStorageUrl(sourceUrl, ctx.supabaseUrl);
    await record(ctx, {
      mediaType, mediaId, assetKey, sourceUrl,
      mirroredUrl: stored ? sourceUrl : null,
      state: "skipped",
      visibility: stored ? "public" : "remote",
      details: { overwrite: ctx.overwrite, reason: stored ? "already_mirrored" : "non_remote" },
    });
    return false;
  }

  const classified = classifySourceUrl(sourceUrl);
  if (!classified.ok) {
    await record(ctx, {
      mediaType, mediaId, assetKey, sourceUrl, mirroredUrl: null,
      state: "failed", visibility: "remote",
      details: { overwrite: ctx.overwrite, reason: classified.reason },
    });
    return false;
  }

  const fetched = await fetchBoundedImage(sourceUrl, {
    fetch: ctx.fetch,
    timeoutMs: ctx.fetchTimeoutMs,
    maxBytes: ctx.maxImageBytes,
  });
  if (!fetched.ok) {
    await record(ctx, {
      mediaType, mediaId, assetKey, sourceUrl, mirroredUrl: null,
      state: "failed", visibility: "remote",
      details: { overwrite: ctx.overwrite, reason: fetched.reason },
    });
    return false;
  }

  const path = `${basePath}.${fetched.extension}`;
  let uploaded: { error: { message: string } | null };
  try {
    uploaded = await ctx.storage.upload(ctx.bucket, path, fetched.bytes, {
      contentType: fetched.contentType,
      cacheControl: ctx.cacheControl,
      upsert: true,
    });
  } catch (error) {
    uploaded = { error: { message: (error as Error).message } };
  }
  if (uploaded.error) {
    await record(ctx, {
      mediaType, mediaId, assetKey, sourceUrl, mirroredUrl: null,
      state: "failed", visibility: "remote",
      details: { overwrite: ctx.overwrite, reason: "upload_failed" },
    });
    return false;
  }

  const mirroredUrl = ctx.storage.publicUrl(ctx.bucket, path);
  updates[assetKey] = mirroredUrl;
  await record(ctx, {
    mediaType, mediaId, assetKey, sourceUrl, mirroredUrl,
    state: "mirrored", visibility: "public",
    details: { overwrite: ctx.overwrite, storage_path: path },
  });
  return true;
}

function record(ctx: Ctx, input: Parameters<MirrorRepository["recordState"]>[0]) {
  return ctx.repository.recordState(input, ctx.bucket, ctx.nowIso());
}

function basePathFor(mediaType: MediaType, mediaId: number, assetKey: string): string {
  const table = tableFor(mediaType);
  switch (assetKey) {
    case "cover_image_large":
      return `${table}/${mediaId}/cover_large`;
    case "cover_image_medium":
      return `${table}/${mediaId}/cover_medium`;
    case "banner_image":
      return `${table}/${mediaId}/banner`;
    default:
      return `${table}/${mediaId}`;
  }
}

function isRemote(url: string): boolean {
  return url.startsWith("http://") || url.startsWith("https://");
}

function isStorageUrl(url: string, supabaseUrl: string): boolean {
  if (!url) return false;
  try {
    const parsed = new URL(url);
    const host = new URL(supabaseUrl).host;
    return parsed.host === host && parsed.pathname.includes("/storage/v1/object/public/");
  } catch {
    return url.includes("/storage/v1/object/public/");
  }
}

function isRemoteAndNotMirrored(url: string, ctx: Ctx): boolean {
  if (!isRemote(url)) return false;
  if (ctx.skipIfMirrored && isStorageUrl(url, ctx.supabaseUrl)) return false;
  return true;
}

async function mapBounded<T>(items: T[], limit: number, worker: (item: T) => Promise<void>): Promise<void> {
  if (items.length === 0) return;
  const width = Math.max(1, Math.min(limit, items.length));
  let cursor = 0;
  async function runWorker() {
    while (true) {
      const index = cursor;
      cursor += 1;
      if (index >= items.length) return;
      await worker(items[index]);
    }
  }
  await Promise.all(Array.from({ length: width }, () => runWorker()));
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
