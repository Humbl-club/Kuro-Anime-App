// Offline mirror run: oversized, timeout (including a stalled body), unapproved
// redirect and invalid bucket fail closed without replacing a catalog URL.
// A successful window uploads once per image at the concurrency cap, to derived
// media-bucket paths.
import { assertEquals } from "jsr:@std/assert@1";
import {
  type CatalogRow,
  type LockOutcome,
  type MediaType,
  type MirrorRepository,
  type MirrorStateInput,
} from "./mirror_repository.ts";
import { MIRROR_CONCURRENCY, runMirrorImages, type MirrorPayload } from "./mirror_run.ts";
import type { MirrorStorage } from "./mirror_storage.ts";

const SUPABASE_URL = "https://project.supabase.co";
const SOURCE = "https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/bx7.jpg";

type Call = { op: string; detail?: unknown };

function memoryRepo(initial: CatalogRow[]): MirrorRepository & { calls: Call[]; rows: Map<number, CatalogRow> } {
  const rows = new Map(initial.map((row) => [row.id, { ...row }]));
  const calls: Call[] = [];
  const repository: MirrorRepository & { calls: Call[]; rows: Map<number, CatalogRow> } = {
    calls,
    rows,
    startRun() {
      calls.push({ op: "start" });
      return Promise.resolve(1);
    },
    finishRun(_id, status, results) {
      calls.push({ op: "finish", detail: { status, results } });
      return Promise.resolve();
    },
    acquireLock(key) {
      calls.push({ op: "acquire", detail: key });
      return Promise.resolve("acquired" as LockOutcome);
    },
    releaseLock(key) {
      calls.push({ op: "release", detail: key });
      return Promise.resolve();
    },
    pendingPriority() {
      return Promise.resolve([]);
    },
    liveRows() {
      return Promise.resolve([]);
    },
    remoteWindow(mediaType, offset, limit) {
      calls.push({ op: "window", detail: { mediaType, offset, limit } });
      return Promise.resolve([...rows.values()]);
    },
    updateCatalogRow(mediaType, id, updates) {
      calls.push({ op: "update", detail: { mediaType, id, updates: { ...updates } } });
      const row = rows.get(id);
      if (!row) return Promise.resolve({ error: { message: "missing" } });
      for (const [key, value] of Object.entries(updates)) {
        if (!value.includes("/storage/v1/object/public/media/")) {
          return Promise.resolve({ error: { message: `refusing non-storage write for ${key}` } });
        }
        row[key] = value;
      }
      return Promise.resolve({ error: null });
    },
    clearPriority() {
      return Promise.resolve();
    },
    recordState(input: MirrorStateInput) {
      calls.push({ op: "state", detail: input });
      return Promise.resolve();
    },
  };
  return repository;
}

function storage(): MirrorStorage & { uploads: Array<{ bucket: string; path: string }> } {
  const uploads: Array<{ bucket: string; path: string }> = [];
  return {
    uploads,
    upload(bucket, path) {
      uploads.push({ bucket, path });
      return Promise.resolve({ error: null });
    },
    publicUrl(bucket, path) {
      return `${SUPABASE_URL}/storage/v1/object/public/${bucket}/${path}`;
    },
  };
}

function row(id: number, cover: string): CatalogRow {
  return { id, cover_image_large: cover, cover_image_medium: null, banner_image: null };
}

async function runCase(
  payload: MirrorPayload,
  fetchImpl: (input: string, init?: RequestInit) => Promise<Response>,
  extra: { maxImageBytes?: number; fetchTimeoutMs?: number; rows?: CatalogRow[] } = {},
) {
  const repository = memoryRepo(extra.rows ?? [row(7, SOURCE)]);
  const dest = storage();
  const res = await runMirrorImages({
    repository,
    storage: dest,
    fetch: fetchImpl,
    now: () => Date.now(),
    supabaseUrl: SUPABASE_URL,
    payload,
    maxImageBytes: extra.maxImageBytes,
    fetchTimeoutMs: extra.fetchTimeoutMs,
  });
  return { res, body: await res.json(), repository, dest };
}

Deno.test("oversized, timeout, unapproved redirect and invalid bucket fail closed without erasing the catalog URL", async () => {
  const base: MirrorPayload = { bucket: "media", mediaTypes: ["ANIME"], limit: 1, offset: 0, path: "evil/owned" };

  const oversized = await runCase(base, () => {
    const chunk = new Uint8Array(64);
    let sent = false;
    const stream = new ReadableStream<Uint8Array>({
      pull(controller) {
        if (sent) {
          controller.close();
          return;
        }
        sent = true;
        controller.enqueue(chunk);
      },
    });
    return Promise.resolve(new Response(stream, { status: 200, headers: { "content-type": "image/jpeg" } }));
  }, { maxImageBytes: 16 });
  assertEquals(oversized.res.status, 200);
  assertEquals(oversized.body.results.anime, 0);
  assertEquals(oversized.dest.uploads, []);
  assertEquals(oversized.repository.rows.get(7)?.cover_image_large, SOURCE);
  assertEquals(oversized.repository.calls.filter((call) => call.op === "update"), []);
  const oversizedState = oversized.repository.calls.find((call) =>
    call.op === "state" && (call.detail as MirrorStateInput).assetKey === "cover_image_large"
  );
  assertEquals((oversizedState?.detail as MirrorStateInput).details?.reason, "oversized");
  assertEquals(oversized.repository.calls.filter((call) => call.op === "release").map((call) => call.detail), ["mirror-images:ANIME:0"]);

  const timeout = await runCase(base, (_input, init) => {
    return new Promise((_resolve, reject) => {
      const signal = init?.signal;
      if (!signal) {
        reject(new Error("missing abort signal"));
        return;
      }
      signal.addEventListener("abort", () => reject(signal.reason ?? new DOMException("Aborted", "AbortError")));
    });
  }, { fetchTimeoutMs: 20 });
  assertEquals(timeout.res.status, 200);
  assertEquals(timeout.dest.uploads, []);
  assertEquals(timeout.repository.rows.get(7)?.cover_image_large, SOURCE);
  const timeoutState = timeout.repository.calls.find((call) =>
    call.op === "state" && (call.detail as MirrorStateInput).assetKey === "cover_image_large"
  );
  assertEquals((timeoutState?.detail as MirrorStateInput).details?.reason, "timeout");
  assertEquals(timeout.repository.calls.some((call) => call.op === "release"), true);

  const followed: string[] = [];
  const redirect = await runCase(base, (input) => {
    followed.push(input);
    return Promise.resolve(new Response(null, { status: 302, headers: { location: "https://evil.example/collect" } }));
  });
  assertEquals(redirect.dest.uploads, []);
  assertEquals(redirect.repository.rows.get(7)?.cover_image_large, SOURCE);
  assertEquals(followed.length, 1);
  assertEquals(new URL(followed[0]).hostname, "s4.anilist.co");
  const redirectState = redirect.repository.calls.find((call) =>
    call.op === "state" && (call.detail as MirrorStateInput).assetKey === "cover_image_large"
  );
  assertEquals((redirectState?.detail as MirrorStateInput).details?.reason, "redirect_unapproved");
  assertEquals(redirect.repository.calls.some((call) => call.op === "release"), true);

  let fetched = false;
  const invalid = await runCase(
    { ...base, bucket: "not-media" },
    () => {
      fetched = true;
      return Promise.reject(new Error("should not fetch"));
    },
  );
  assertEquals(invalid.res.status, 400);
  assertEquals(invalid.body, { success: false, error: "invalid_bucket" });
  assertEquals(fetched, false);
  assertEquals(invalid.dest.uploads, []);
  assertEquals(invalid.repository.calls, []);
  assertEquals(invalid.repository.rows.get(7)?.cover_image_large, SOURCE);
});

Deno.test("a stalled image body times out, aborts, and cancels without accepting a late byte", async () => {
  const payload: MirrorPayload = { bucket: "media", mediaTypes: ["ANIME"], limit: 1, offset: 0, path: "evil/owned" };
  let releaseByte: () => void = () => {};
  const gate = new Promise<void>((resolve) => {
    releaseByte = resolve;
  });
  let cancelled = false;
  let delivered = false;
  let signal: AbortSignal | undefined;
  let guard: ReturnType<typeof setTimeout> | undefined;

  const pending = runCase(payload, (_input, init) => {
    signal = init?.signal ?? undefined;
    const stream = new ReadableStream<Uint8Array>({
      async pull(controller) {
        try {
          await gate;
          if (cancelled || signal?.aborted) return;
          controller.enqueue(new Uint8Array([0xff, 0xd8, 0xff, 0xd9]));
          controller.close();
          delivered = true;
        } catch {
          // Cancelled while the body was held.
        }
      },
      cancel() {
        cancelled = true;
      },
    });
    return Promise.resolve(new Response(stream, {
      status: 200,
      headers: { "content-type": "image/jpeg" },
    }));
  }, { fetchTimeoutMs: 40 });

  let timeout: Awaited<ReturnType<typeof runCase>>;
  try {
    timeout = await Promise.race([
      pending,
      new Promise<never>((_, reject) => {
        guard = setTimeout(() => reject(new Error("stalled body exceeded the fetch timeout")), 1_000);
      }),
    ]);
    assertEquals(timeout.res.status, 200);
    assertEquals(timeout.dest.uploads, []);
    assertEquals(timeout.repository.rows.get(7)?.cover_image_large, SOURCE);
    assertEquals(timeout.repository.calls.filter((call) => call.op === "update"), []);
    const timeoutState = timeout.repository.calls.find((call) =>
      call.op === "state" && (call.detail as MirrorStateInput).assetKey === "cover_image_large"
    );
    assertEquals((timeoutState?.detail as MirrorStateInput).details?.reason, "timeout");
    assertEquals(signal?.aborted, true);
    assertEquals(cancelled, true);
  } finally {
    if (guard !== undefined) clearTimeout(guard);
    releaseByte();
  }

  await new Promise((resolve) => setTimeout(resolve, 30));
  assertEquals(delivered, false);
  assertEquals(timeout!.dest.uploads, []);
  assertEquals(timeout!.repository.rows.get(7)?.cover_image_large, SOURCE);
  assertEquals(timeout!.repository.calls.filter((call) => call.op === "update"), []);
});

Deno.test("a catalog window mirrors once with bounded concurrency onto derived media paths", async () => {
  const rows = Array.from({ length: 6 }, (_, index) => row(
    index + 1,
    `https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/bx${index + 1}.jpg`,
  ));
  let inFlight = 0;
  let maxInFlight = 0;
  const fetched: string[] = [];
  const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xd9]);
  const fetchImpl = async (input: string) => {
    fetched.push(input);
    inFlight += 1;
    maxInFlight = Math.max(maxInFlight, inFlight);
    try {
      await new Promise((resolve) => setTimeout(resolve, 40));
      return new Response(jpeg, { status: 200, headers: { "content-type": "image/jpeg" } });
    } finally {
      inFlight -= 1;
    }
  };

  const repository = memoryRepo(rows);
  const dest = storage();
  const res = await runMirrorImages({
    repository,
    storage: dest,
    fetch: fetchImpl,
    now: () => Date.now(),
    supabaseUrl: SUPABASE_URL,
    payload: {
      bucket: "media",
      mediaTypes: ["ANIME"],
      limit: 6,
      offset: 20,
      path: "evil/owned",
      skipIfMirrored: true,
    },
  });
  const body = await res.json();

  assertEquals(res.status, 200);
  assertEquals(body.success, true);
  assertEquals(body.results, { priority: 0, anime: 6 });
  assertEquals(fetched.length, 6);
  assertEquals(maxInFlight, MIRROR_CONCURRENCY);
  assertEquals(maxInFlight <= MIRROR_CONCURRENCY, true);
  assertEquals(dest.uploads.length, 6);
  assertEquals(dest.uploads.every((upload) => upload.bucket === "media"), true);
  assertEquals(dest.uploads.every((upload) => /^anime\/\d+\/cover_large\.jpg$/.test(upload.path)), true);
  assertEquals(dest.uploads.some((upload) => upload.path.includes("evil")), false);
  for (const catalog of rows) {
    const saved = String(repository.rows.get(catalog.id)?.cover_image_large);
    assertEquals(saved.startsWith(`${SUPABASE_URL}/storage/v1/object/public/media/anime/`), true);
    assertEquals(saved.includes("s4.anilist.co"), false);
  }
  assertEquals(
    repository.calls.find((call) => call.op === "window")?.detail,
    { mediaType: "ANIME" as MediaType, offset: 20, limit: 6 },
  );
  assertEquals(repository.calls.filter((call) => call.op === "release").map((call) => call.detail), ["mirror-images:ANIME:20"]);
});
