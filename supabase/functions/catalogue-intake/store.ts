// Persistence helpers shared by the catalogue-intake source handlers: raw records (hash-gated
// upserts), id-link application with conflict handling, and the per-handler cursor.
// Only service-role writes; nothing here talks to a source.
import type { SupabaseLike } from "../_shared/catalogue/intake_persistence.ts";

export type Medium = "anime" | "manga";
/** Kinds a catalogue_id_links row can have (titles and credited entities). */
export type LinkKind = Medium | "staff" | "studio" | "character" | "author";
export type SourceCode = "wikidata" | "ann" | "mangaupdates" | "pageviews" | "episodes_provider" | "editorial" | "syoboi";

export const WRITE_BATCH = 500;

export function chunk<T>(items: readonly T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}

export function clampInt(raw: unknown, fallback: number, min: number, max: number): number {
  const n = Number(raw);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(min, Math.min(max, Math.floor(n)));
}

export const PAGE_ROWS = 1000;

/**
 * Reads EVERY row of a query, paging with a stable order and `.range()`: PostgREST silently truncates a
 * select at its max-rows setting (1,000 by default), so any read that can match more rows must page.
 * `build` returns a fresh filtered query each call; `orderBy` must end in a unique column so pages
 * never overlap or skip. Throws `<what> read failed: ...` on a database error.
 */
export async function selectAll<T>(
  // deno-lint-ignore no-explicit-any
  build: () => any,
  orderBy: string[],
  what: string,
  pageSize: number = PAGE_ROWS,
): Promise<T[]> {
  const out: T[] = [];
  for (let from = 0;; from += pageSize) {
    let q = build();
    for (const col of orderBy) q = q.order(col, { ascending: true });
    const { data, error } = await q.range(from, from + pageSize - 1);
    if (error) throw new Error(`${what} read failed: ${error.message ?? error}`);
    const page = (data ?? []) as T[];
    out.push(...page);
    if (page.length < pageSize) return out;
  }
}

/** JSON with object keys sorted, so equal payloads hash equally whatever order a source answered in. */
export function stableStringify(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(",")}]`;
  if (value && typeof value === "object") {
    const o = value as Record<string, unknown>;
    return `{${Object.keys(o).filter((k) => o[k] !== undefined).sort().map((k) => `${JSON.stringify(k)}:${stableStringify(o[k])}`).join(",")}}`;
  }
  return JSON.stringify(value) ?? "null";
}

export async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

export async function payloadHash(payload: unknown): Promise<string> {
  return sha256Hex(stableStringify(payload));
}

// ---------------------------------------------------------------------------------------------
// Raw records

export type SourceRecordInput = { source: SourceCode; sourceKey: string; medium: Medium; payload: unknown; licence: string };

export type ExistingRecord = { source_key: string; payload_hash: string; fetched_at: string | null };

export async function readExistingRecords(supabase: SupabaseLike, source: SourceCode, medium: Medium, keys: string[]): Promise<Map<string, ExistingRecord>> {
  const out = new Map<string, ExistingRecord>();
  for (const part of chunk(keys, WRITE_BATCH)) {
    const rows = await selectAll<ExistingRecord>(
      () => supabase.from("catalogue_source_records").select("source_key, payload_hash, fetched_at").eq("source", source).eq("medium", medium).in("source_key", part),
      ["source_key"],
      "catalogue_source_records",
    );
    for (const row of rows) out.set(row.source_key, row);
  }
  return out;
}

/** Upserts only records whose payload hash changed (or that are new). Unchanged hashes write nothing. */
export async function upsertRecords(
  supabase: SupabaseLike,
  records: SourceRecordInput[],
  nowIso: string = new Date().toISOString(),
  opts: { touch?: boolean } = {},
): Promise<{ written: number; unchanged: number }> {
  if (records.length === 0) return { written: 0, unchanged: 0 };
  const bySource = new Map<string, SourceRecordInput[]>();
  for (const r of records) {
    const k = `${r.source}|${r.medium}`;
    bySource.set(k, [...(bySource.get(k) ?? []), r]);
  }
  let written = 0;
  let unchanged = 0;
  for (const group of bySource.values()) {
    const existing = await readExistingRecords(supabase, group[0].source, group[0].medium, group.map((g) => g.sourceKey));
    const changed: Record<string, unknown>[] = [];
    const unchangedKeys: string[] = [];
    for (const r of group) {
      const hash = await payloadHash(r.payload);
      if (existing.get(r.sourceKey)?.payload_hash === hash) {
        unchanged++;
        unchangedKeys.push(r.sourceKey);
        continue;
      }
      changed.push({ source: r.source, source_key: r.sourceKey, medium: r.medium, payload: r.payload, payload_hash: hash, licence: r.licence, fetched_at: nowIso });
    }
    for (const part of chunk(changed, WRITE_BATCH)) {
      const { error } = await supabase.from("catalogue_source_records").upsert(part, { onConflict: "source,source_key,medium" });
      if (error) throw new Error(`catalogue_source_records upsert failed: ${error.message ?? error}`);
      written += part.length;
    }
    // Handlers that refresh by age (fetched_at) record freshness without rewriting the payload.
    if (opts.touch) {
      for (const part of chunk(unchangedKeys, WRITE_BATCH)) {
        const { error } = await supabase
          .from("catalogue_source_records")
          .update({ fetched_at: nowIso })
          .eq("source", group[0].source)
          .eq("medium", group[0].medium)
          .in("source_key", part);
        if (error) throw new Error(`catalogue_source_records touch failed: ${error.message ?? error}`);
      }
    }
  }
  return { written, unchanged };
}

// ---------------------------------------------------------------------------------------------
// Id links

export type LinkMethod = "wikidata" | "id_match" | "title_match" | "name_match" | "editorial";

export type LinkCandidate = {
  kuroId: number;
  source: SourceCode;
  sourceKey: string;
  method: LinkMethod;
  confidence: number | null;
  status: "accepted" | "proposed";
};

export type Conflict = {
  kind: LinkKind;
  source: SourceCode;
  /** The contested source key, or null when one Kuro title has several keys. */
  sourceKey: string | null;
  kuroIds: number[];
  reason: string;
};

type ExistingLink = { id: number; kuro_id: number; source: string; source_key: string; status: string };

async function readExistingLinks(supabase: SupabaseLike, kind: LinkKind, source: string, kuroIds: number[], keys: string[]): Promise<ExistingLink[]> {
  const seen = new Map<number, ExistingLink>();
  const run = async (col: "kuro_id" | "source_key", values: (number | string)[]) => {
    for (const part of chunk(values, WRITE_BATCH)) {
      // One Kuro title can hold many links (every status), so this read pages past the 1,000-row cap.
      const rows = await selectAll<ExistingLink>(
        () => supabase.from("catalogue_id_links").select("id, kuro_id, source, source_key, status").eq("kind", kind).eq("source", source).in(col, part),
        ["id"],
        "catalogue_id_links",
      );
      for (const row of rows) seen.set(row.id, row);
    }
  };
  await run("kuro_id", kuroIds);
  await run("source_key", keys);
  return [...seen.values()];
}

/**
 * Applies link candidates for one medium. Accepted candidates become accepted links only when
 * nothing contradicts them (same Kuro title with another key, same key on another title, or
 * contradicting candidates in this batch); contradictions are reported as conflicts and stored as
 * `proposed` links for review. Existing links (any status) are never duplicated, so a repeat run
 * writes nothing.
 */
export async function applyLinks(
  supabase: SupabaseLike,
  kind: LinkKind,
  candidates: LinkCandidate[],
  nowIso: string = new Date().toISOString(),
): Promise<{ accepted: number; proposed: number; skipped: number; conflicts: Conflict[] }> {
  const conflicts: Conflict[] = [];
  let accepted = 0;
  let proposed = 0;
  let skipped = 0;
  if (candidates.length === 0) return { accepted, proposed, skipped, conflicts };

  const sources = [...new Set(candidates.map((c) => c.source))];
  const existingBySource = new Map<string, ExistingLink[]>();
  for (const source of sources) {
    const sub = candidates.filter((c) => c.source === source);
    existingBySource.set(source, await readExistingLinks(supabase, kind, source, [...new Set(sub.map((c) => c.kuroId))], [...new Set(sub.map((c) => c.sourceKey))]));
  }
  const exactStatus = new Map<string, ExistingLink>();
  const acceptedKeyByKuro = new Map<string, string>();
  const acceptedKuroByKey = new Map<string, number>();
  for (const [source, links] of existingBySource) {
    for (const l of links) {
      exactStatus.set(`${source}|${l.source_key}|${l.kuro_id}`, l);
      if (l.status === "accepted") {
        acceptedKeyByKuro.set(`${source}|${l.kuro_id}`, l.source_key);
        acceptedKuroByKey.set(`${source}|${l.source_key}`, l.kuro_id);
      }
    }
  }

  // Contradictions inside this batch.
  const blocked = new Set<LinkCandidate>();
  const acceptedCands = candidates.filter((c) => c.status === "accepted");
  const groupBy = <K>(keyOf: (c: LinkCandidate) => K) => {
    const m = new Map<K, LinkCandidate[]>();
    for (const c of acceptedCands) m.set(keyOf(c), [...(m.get(keyOf(c)) ?? []), c]);
    return m;
  };
  for (const group of groupBy((c) => `${c.source}|${c.kuroId}`).values()) {
    if (new Set(group.map((c) => c.sourceKey)).size > 1) {
      group.forEach((c) => blocked.add(c));
      conflicts.push({ kind, source: group[0].source, sourceKey: null, kuroIds: [group[0].kuroId], reason: "several_keys_for_one_title" });
    }
  }
  for (const group of groupBy((c) => `${c.source}|${c.sourceKey}`).values()) {
    const ids = [...new Set(group.map((c) => c.kuroId))];
    if (ids.length > 1) {
      group.forEach((c) => blocked.add(c));
      conflicts.push({ kind, source: group[0].source, sourceKey: group[0].sourceKey, kuroIds: ids, reason: "one_key_for_several_titles" });
    }
  }

  const toInsert: Record<string, unknown>[] = [];
  const toPromote: ExistingLink[] = [];
  const pendingKeys = new Set<string>();
  const pushRow = (c: LinkCandidate, status: "accepted" | "proposed") => {
    const dedupe = `${c.source}|${c.sourceKey}|${c.kuroId}|${status}`;
    if (pendingKeys.has(dedupe)) return;
    pendingKeys.add(dedupe);
    toInsert.push({
      kind,
      kuro_id: c.kuroId,
      source: c.source,
      source_key: c.sourceKey,
      method: c.method,
      confidence: c.confidence,
      status,
      ...(status === "accepted" ? { decided_at: nowIso } : {}),
    });
    if (status === "accepted") accepted++;
    else proposed++;
  };

  for (const c of candidates) {
    const exact = exactStatus.get(`${c.source}|${c.sourceKey}|${c.kuroId}`);
    const otherKey = acceptedKeyByKuro.get(`${c.source}|${c.kuroId}`);
    const otherKuro = acceptedKuroByKey.get(`${c.source}|${c.sourceKey}`);
    if (c.status === "proposed") {
      if (exact || otherKey !== undefined) skipped++;
      else pushRow(c, "proposed");
      continue;
    }
    if (blocked.has(c)) {
      if (exact) skipped++;
      else pushRow(c, "proposed");
      continue;
    }
    if (exact?.status === "accepted" || exact?.status === "rejected") {
      skipped++;
      continue;
    }
    if (otherKey !== undefined && otherKey !== c.sourceKey) {
      conflicts.push({ kind, source: c.source, sourceKey: c.sourceKey, kuroIds: [c.kuroId], reason: "title_already_linked_to_other_key" });
      if (exact) skipped++;
      else pushRow(c, "proposed");
      continue;
    }
    if (otherKuro !== undefined && otherKuro !== c.kuroId) {
      conflicts.push({ kind, source: c.source, sourceKey: c.sourceKey, kuroIds: [otherKuro, c.kuroId], reason: "key_already_linked_to_other_title" });
      if (exact) skipped++;
      else pushRow(c, "proposed");
      continue;
    }
    if (exact) {
      toPromote.push(exact);
      accepted++;
      continue;
    }
    pushRow(c, "accepted");
  }

  for (const link of toPromote) {
    const { error } = await supabase.from("catalogue_id_links").update({ status: "accepted", decided_at: nowIso }).eq("id", link.id);
    if (error) throw new Error(`catalogue_id_links update failed: ${error.message ?? error}`);
  }
  for (const part of chunk(toInsert, WRITE_BATCH)) {
    const { error } = await supabase.from("catalogue_id_links").insert(part);
    if (!error) continue;
    if (error.code !== "23505") throw new Error(`catalogue_id_links insert failed: ${error.message ?? error}`);
    // A concurrent writer took a unique slot: retry row by row and report the losers.
    for (const row of part) {
      const one = await supabase.from("catalogue_id_links").insert(row);
      if (!one.error) continue;
      if (one.error.code !== "23505") throw new Error(`catalogue_id_links insert failed: ${one.error.message ?? one.error}`);
      if (row.status === "accepted") {
        accepted--;
        conflicts.push({ kind, source: row.source as SourceCode, sourceKey: String(row.source_key), kuroIds: [Number(row.kuro_id)], reason: "unique_race" });
      }
    }
  }
  return { accepted, proposed, skipped, conflicts };
}

// ---------------------------------------------------------------------------------------------
// Cursor (import_track_state, track_key `catalogue-intake:<handler>:<medium>`)

export function cursorKey(handler: string, medium: Medium): string {
  return `catalogue-intake:${handler}:${medium}`;
}

export async function readCursor<T extends Record<string, unknown>>(supabase: SupabaseLike, key: string): Promise<T | null> {
  try {
    const { data, error } = await supabase.from("import_track_state").select("last_results").eq("track_key", key).maybeSingle();
    if (error) {
      console.error("catalogue cursor read error:", error);
      return null;
    }
    const raw = data?.last_results?.cursor;
    return raw && typeof raw === "object" ? (raw as T) : null;
  } catch (e) {
    console.error("catalogue cursor read exception:", e);
    return null;
  }
}

export async function writeCursor(
  supabase: SupabaseLike,
  key: string,
  medium: Medium,
  cursor: Record<string, unknown>,
  results: Record<string, unknown>,
  message: string | null,
  nowIso: string = new Date().toISOString(),
): Promise<void> {
  const { error } = await supabase.from("import_track_state").upsert(
    {
      track_key: key,
      media_type: medium.toUpperCase(),
      // The table's CHECK allows the four AniList presets only; catalogue cursors use the neutral one.
      track_preset: "catalog_backfill",
      last_page: 0,
      state: "success",
      visibility: "active",
      last_run_at: nowIso,
      last_message: message,
      last_results: { ...results, cursor },
      updated_at: nowIso,
    },
    { onConflict: "track_key" },
  );
  if (error) throw new Error(`import_track_state upsert failed: ${error.message ?? error}`);
}
