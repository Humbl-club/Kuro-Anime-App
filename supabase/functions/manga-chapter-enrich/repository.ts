// Table and RPC access for manga-chapter-enrich. Every read and write takes
// the injected Supabase client. Review retry delays are unchanged.
import type { CandidateRow, MangaDexManga, MappingMethod, MatcherMode } from "./matching.ts";
import type { AggregateVolume } from "./mangadex.ts";

export interface MappingRow {
  provider_media_id: string;
  next_verify_at?: string | null;
  verify_status?: string | null;
  verify_fail_count?: number | null;
  last_mismatch_at?: string | null;
}

export interface RuntimeMatcherConfig {
  mode: MatcherMode;
  modeDegraded: boolean;
}

export interface CandidateProcessResult {
  mappingMethod?: MappingMethod;
  providerMediaId?: string | null;
  unresolved: boolean;
  unresolvedReason?: string;
  insertedCount: number;
  fractionalSkipped: number;
}

function computeNextRetryAt(retryCount: number): string {
  let delayMs = 24 * 60 * 60 * 1000;
  if (retryCount <= 1) delayMs = 15 * 60 * 1000;
  else if (retryCount == 2) delayMs = 60 * 60 * 1000;
  else if (retryCount == 3) delayMs = 6 * 60 * 60 * 1000;
  return new Date(Date.now() + delayMs).toISOString();
}

export async function resolveRuntimeMatcherConfig(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  configuredMode: MatcherMode,
  wrongMapProxyRateLimit: number,
): Promise<RuntimeMatcherConfig> {
  if (configuredMode !== "fuzzy_v2") {
    return { mode: configuredMode, modeDegraded: false };
  }

  try {
    const { data, error } = await supabase.rpc("get_manga_match_quality_metrics", { p_hours: 24 });
    if (error) {
      console.warn("manga matcher mode guard rpc unavailable:", error.message);
      return { mode: configuredMode, modeDegraded: false };
    }

    const row = Array.isArray(data) ? data[0] : data;
    const wrongProxy = Number(row?.wrong_map_proxy_rate_pct ?? 0);
    if (Number.isFinite(wrongProxy) && wrongProxy > wrongMapProxyRateLimit) {
      return { mode: "strict", modeDegraded: true };
    }
  } catch (error) {
    console.warn("manga matcher mode guard failed:", error);
  }

  return { mode: configuredMode, modeDegraded: false };
}

export async function fetchCandidates(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  limit: number,
  forceMangaId: number | null,
  zeroRowOnly: boolean,
): Promise<CandidateRow[]> {
  const next = await supabase.rpc("get_manga_chapter_enrich_candidates", {
    p_limit: limit,
    p_force_manga_id: forceMangaId,
    p_zero_row_only: zeroRowOnly,
  });
  if (!next.error) return (next.data ?? []) as CandidateRow[];

  // Backward-compatible fallback while some deployments still expose the 2-arg RPC.
  console.warn("candidate RPC without p_zero_row_only fallback:", next.error.message);
  const legacy = await supabase.rpc("get_manga_chapter_enrich_candidates", {
    p_limit: limit,
    p_force_manga_id: forceMangaId,
  });
  if (legacy.error) throw legacy.error;
  const rows = (legacy.data ?? []) as CandidateRow[];
  if (!zeroRowOnly) return rows;
  return rows.filter((row) => Number(row.chapter_row_count ?? 0) === 0);
}

export async function fetchExistingMapping(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  mangaId: number,
): Promise<MappingRow | null> {
  let { data, error } = await supabase
    .from("manga_source_links")
    .select("provider_media_id,next_verify_at,verify_status,verify_fail_count,last_mismatch_at")
    .eq("manga_id", mangaId)
    .eq("provider", "mangadex")
    .eq("status", "active")
    .maybeSingle();

  // Backward-compatible fallback in case new verification columns are not present yet.
  if (error) {
    if (error.code !== "PGRST204" && error.code !== "42703") throw error;
    const fallback = await supabase
      .from("manga_source_links")
      .select("provider_media_id")
      .eq("manga_id", mangaId)
      .eq("provider", "mangadex")
      .eq("status", "active")
      .maybeSingle();
    data = fallback.data;
    error = fallback.error;
  }

  if (error) throw error;
  // Only a successful, explicit no-row answer permits finding a new mapping.
  if (data === null) return null;
  if (!data || Array.isArray(data) || typeof data.provider_media_id !== "string" || !data.provider_media_id.trim()) {
    throw new Error("Malformed active MangaDex mapping response");
  }
  return data as MappingRow;
}

export async function persistVerifyState(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  mangaId: number,
  payload: Record<string, unknown>,
) {
  const { error } = await supabase
    .from("manga_source_links")
    .update(payload)
    .eq("manga_id", mangaId)
    .eq("provider", "mangadex");

  if (error) {
    // Backward-compatible fallback for environments where verification columns are not migrated yet.
    // A transport/permission failure does not prove that the old schema is in use.
    if (error.code !== "PGRST204" && error.code !== "42703") throw error;
    const fallbackPayload: Record<string, unknown> = {};
    if (payload.status !== undefined) fallbackPayload.status = payload.status;
    if (Object.keys(fallbackPayload).length > 0) {
      const fallback = await supabase
        .from("manga_source_links")
        .update(fallbackPayload)
        .eq("manga_id", mangaId)
        .eq("provider", "mangadex");
      if (fallback.error) throw fallback.error;
    }
  }
}

export async function upsertMapping(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  mangaId: number,
  mapping: {
    mangaDexId: string;
    providerUrl: string;
    method: MappingMethod;
    confidence: number;
    nextVerifyAt: string;
  },
): Promise<boolean> {
  const { error } = await supabase
    .from("manga_source_links")
    .upsert({
      manga_id: mangaId,
      provider: "mangadex",
      provider_media_id: mapping.mangaDexId,
      provider_url: mapping.providerUrl,
      mapping_method: mapping.method,
      confidence: mapping.confidence,
      status: "active",
      verify_status: "unverified",
      verify_fail_count: 0,
      last_verify_reason: null,
      last_mismatch_at: null,
      next_verify_at: mapping.nextVerifyAt,
    }, { onConflict: "manga_id,provider" });
  if (error) {
    const fallback = await supabase
      .from("manga_source_links")
      .upsert({
        manga_id: mangaId,
        provider: "mangadex",
        provider_media_id: mapping.mangaDexId,
        provider_url: mapping.providerUrl,
        mapping_method: mapping.method,
        confidence: mapping.confidence,
        status: "active",
      }, { onConflict: "manga_id,provider" });
    if (fallback.error) {
      console.error("manga_source_links upsert failed:", fallback.error);
      return false;
    }
    return true;
  }
  return true;
}

export async function enqueueMappingReview(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  candidate: CandidateRow,
  input: { provider: string; queryTitle: string; reason: string; sample: unknown[] },
) {
  const { data: existing } = await supabase
    .from("manga_source_link_review")
    .select("id,retry_count")
    .eq("provider", input.provider)
    .eq("manga_id", candidate.id)
    .eq("status", "pending")
    .limit(1);
  if ((existing ?? []).length > 0) {
    const row = existing[0] as { id: number; retry_count?: number | null };
    const retryCount = Number(row.retry_count ?? 0) + 1;
    const nextRetryAt = computeNextRetryAt(retryCount);
    let updateError = (await supabase
      .from("manga_source_link_review")
      .update({
        reason: input.reason,
        retry_count: retryCount,
        next_retry_at: nextRetryAt,
      })
      .eq("id", row.id)).error;
    if (updateError) {
      updateError = (await supabase
        .from("manga_source_link_review")
        .update({ reason: input.reason })
        .eq("id", row.id)).error;
      if (updateError) {
        console.error("manga_source_link_review update failed:", updateError);
      }
    }
    return;
  }

  const payload = {
    candidate: {
      id: candidate.id,
      anilist_id: candidate.anilist_id,
      mal_id: candidate.mal_id,
      title_english: candidate.title_english,
      title_romaji: candidate.title_romaji,
      title_native: candidate.title_native,
      title_synonyms: candidate.title_synonyms ?? [],
    },
    sample: input.sample,
  };

  const { error } = await supabase
    .from("manga_source_link_review")
    .insert({
      provider: input.provider,
      manga_id: candidate.id,
      query_title: input.queryTitle,
      candidate_payload: payload,
      reason: input.reason,
      status: "pending",
      retry_count: 1,
      next_retry_at: computeNextRetryAt(1),
    });
  if (!error) return;

  const fallback = await supabase
    .from("manga_source_link_review")
    .insert({
      provider: input.provider,
      manga_id: candidate.id,
      query_title: input.queryTitle,
      candidate_payload: payload,
      reason: input.reason,
      status: "pending",
    });
  if (fallback.error) {
    console.error("manga_source_link_review insert failed:", fallback.error);
  }
}

export async function filterMatchesWithAliasMemory(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  mangaId: number,
  provider: string,
  matches: MangaDexManga[],
): Promise<{ matches: MangaDexManga[]; aliasHit: boolean }> {
  const candidateIds = Array.from(new Set(matches.map((item) => item.id)));
  if (candidateIds.length === 0) return { matches, aliasHit: false };

  const { data, error } = await supabase
    .from("manga_mapping_alias_memory")
    .select("provider_media_id,decision")
    .eq("manga_id", mangaId)
    .eq("provider", provider)
    .in("provider_media_id", candidateIds);

  // Unknown decision memory must not let a rejected identity be selected again.
  // A missing schema is unknown too; only a successful array establishes decisions.
  if (error) throw error;
  if (!Array.isArray(data)) throw new Error("Malformed MangaDex alias memory response");

  const decisionById = new Map<string, string>();
  for (const row of data) {
    if (!row || typeof row.provider_media_id !== "string" || !row.provider_media_id.trim() ||
      !["accepted", "rejected_collision", "rejected_conflict"].includes(row.decision)) {
      throw new Error("Malformed MangaDex alias memory row");
    }
    decisionById.set(row.provider_media_id, row.decision);
  }

  const accepted = matches.filter((item) => decisionById.get(item.id) == "accepted");
  if (accepted.length === 1) {
    return { matches: accepted, aliasHit: true };
  }

  const filtered = matches.filter((item) => {
    const decision = decisionById.get(item.id);
    return decision !== "rejected_collision" && decision !== "rejected_conflict";
  });
  if (filtered.length < matches.length) {
    return { matches: filtered, aliasHit: true };
  }
  return { matches, aliasHit: false };
}

export async function rememberAliasDecision(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  mangaId: number,
  provider: string,
  providerMediaId: string,
  decision: "accepted" | "rejected_collision" | "rejected_conflict",
  reason: string,
) {
  const { error } = await supabase
    .from("manga_mapping_alias_memory")
    .upsert({
      manga_id: mangaId,
      provider,
      provider_media_id: providerMediaId,
      decision,
      reason,
      created_at: new Date().toISOString(),
    }, { onConflict: "manga_id,provider,provider_media_id" });
  if (error) {
    // Backward-compatible no-op if table is not migrated yet.
    return;
  }
}

export async function upsertChapterRows(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  mangaId: number,
  chapterNumbers: number[],
) {
  const chunkSize = 400;
  for (let i = 0; i < chapterNumbers.length; i += chunkSize) {
    const chunk = chapterNumbers.slice(i, i + chunkSize);
    const { data: existingRows, error: existingError } = await supabase
      .from("chapters")
      .select("number")
      .eq("manga_id", mangaId)
      .in("number", chunk);
    if (existingError) throw existingError;

    const existingNumbers = new Set<number>(
      (existingRows ?? [])
        .map((row: { number?: number | null }) => Number(row?.number))
        .filter((value: number) => Number.isFinite(value)),
    );
    const missing = chunk.filter((number) => !existingNumbers.has(number));
    if (missing.length === 0) continue;

    const payload = missing.map((number) => ({
      manga_id: mangaId,
      number,
      title: `Chapter ${number}`,
    }));

    const { error } = await supabase.from("chapters").insert(payload);
    if (error?.code === "23505") {
      // In rare race windows, another worker may insert between read+insert.
      for (const row of payload) {
        const { error: singleError } = await supabase.from("chapters").insert(row);
        if (singleError && singleError.code !== "23505") throw singleError;
      }
      continue;
    }
    if (error) throw error;
  }
}

/** Display range stored in volumes.description ("Chapters 1–8"); see upsertVolumeRows. */
export function volumeRangeText(firstChapter: number, lastChapter: number): string {
  return firstChapter === lastChapter ? `Chapter ${firstChapter}` : `Chapters ${firstChapter}–${lastChapter}`;
}

const VOLUME_RANGE_PATTERN = /^Chapters? \d+(–\d+)?$/;

/**
 * Real volume rows from the MangaDex /aggregate grouping (same read-then-write pattern as
 * upsertChapterRows; the (manga_id, number) unique index is partial, so PostgREST onConflict
 * cannot target it). `volumes` has no chapter-range columns, so the range goes into
 * `description` ("Chapters 1–8"). Missing volumes are inserted; an existing row is updated only
 * when its description is empty (an AniList placeholder) or one this writer owns (range text)
 * that changed. Rows with other descriptions are never touched; nothing is deleted.
 */
export async function upsertVolumeRows(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  mangaId: number,
  volumes: AggregateVolume[],
): Promise<{ inserted: number; updated: number }> {
  let inserted = 0;
  let updated = 0;
  const chunkSize = 200;
  for (let i = 0; i < volumes.length; i += chunkSize) {
    const chunk = volumes.slice(i, i + chunkSize);
    const { data: existingRows, error: existingError } = await supabase
      .from("volumes")
      .select("id, number, title, description")
      .eq("manga_id", mangaId)
      .in("number", chunk.map((v) => v.volume));
    if (existingError) throw existingError;
    const existing = new Map<number, { id: number; title: string | null; description: string | null }>();
    for (const row of (existingRows ?? []) as { id: number; number: number; title: string | null; description: string | null }[]) {
      existing.set(Number(row.number), row);
    }

    const missing = chunk.filter((v) => !existing.has(v.volume));
    if (missing.length > 0) {
      const payload = missing.map((v) => ({
        manga_id: mangaId,
        number: v.volume,
        title: `Volume ${v.volume}`,
        description: volumeRangeText(v.firstChapter, v.lastChapter),
      }));
      const { error } = await supabase.from("volumes").insert(payload);
      if (error?.code === "23505") {
        // Another writer inserted between read and insert: fall back to one row at a time.
        for (const row of payload) {
          const { error: singleError } = await supabase.from("volumes").insert(row);
          if (singleError && singleError.code !== "23505") throw singleError;
          if (!singleError) inserted++;
        }
      } else if (error) {
        throw error;
      } else {
        inserted += payload.length;
      }
    }

    for (const v of chunk) {
      const row = existing.get(v.volume);
      if (!row) continue;
      const range = volumeRangeText(v.firstChapter, v.lastChapter);
      const owned = row.description == null || row.description.trim() === "" || VOLUME_RANGE_PATTERN.test(row.description);
      if (!owned || row.description === range) continue;
      const patch: Record<string, unknown> = { description: range };
      if (!row.title) patch.title = `Volume ${v.volume}`;
      const { error } = await supabase.from("volumes").update(patch).eq("id", row.id);
      if (error) throw error;
      updated++;
    }
  }
  return { inserted, updated };
}

export async function fetchChapterCount(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  mangaId: number,
): Promise<number> {
  const { count, error } = await supabase
    .from("chapters")
    .select("id", { head: true, count: "exact" })
    .eq("manga_id", mangaId);
  if (error) throw error;
  return count ?? 0;
}

export async function updateMangaSyncFields(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  candidate: CandidateRow,
  maxImportedNumber: number | null,
) {
  const updatePayload: Record<string, unknown> = {
    last_synced_at: new Date().toISOString(),
  };

  if (maxImportedNumber && maxImportedNumber > 0) {
    const existing = candidate.chapters ?? 0;
    updatePayload.chapters = Math.max(existing, maxImportedNumber);
  }

  const { error } = await supabase
    .from("manga")
    .update(updatePayload)
    .eq("id", candidate.id);
  if (error) throw error;
}

/** acquired proceeds and is released; busy and unavailable do not run and are not released. */
export type ImportLockOutcome = "acquired" | "busy" | "unavailable";

export async function acquireImportLock(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  key: string,
  ttlSeconds: number,
): Promise<ImportLockOutcome> {
  try {
    const { data, error } = await supabase.rpc("acquire_import_lock", {
      p_key: key,
      p_ttl_seconds: ttlSeconds,
    });
    if (error) {
      console.error("Acquire lock error:", error);
      return "unavailable";
    }
    return data === true ? "acquired" : "busy";
  } catch (error) {
    console.error("Acquire lock exception:", error);
    return "unavailable";
  }
}

export async function releaseImportLock(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  key: string,
): Promise<void> {
  try {
    const { error } = await supabase.rpc("release_import_lock", { p_key: key });
    if (error) console.error("Release lock error:", error);
  } catch (error) {
    console.error("Release lock exception:", error);
  }
}

export async function startImportRun(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  mediaType: string,
  runType: string,
  payload: unknown,
): Promise<number | null> {
  try {
    const { data, error } = await supabase
      .from("import_runs")
      .insert({
        media_type: mediaType,
        run_type: runType,
        payload,
        status: "running",
        started_at: new Date().toISOString(),
      })
      .select("id")
      .single();
    if (error) {
      console.error("import_runs insert error:", error);
      return null;
    }
    return data?.id ?? null;
  } catch (error) {
    console.error("import_runs insert exception:", error);
    return null;
  }
}

export async function finishImportRun(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  runId: number | null,
  status: string,
  results: unknown,
  message: string | null,
  startedAtMs: number,
) {
  if (!runId) return;
  try {
    const durationMs = Date.now() - startedAtMs;
    const { error } = await supabase
      .from("import_runs")
      .update({
        status,
        results,
        message,
        finished_at: new Date().toISOString(),
        duration_ms: durationMs,
      })
      .eq("id", runId);
    if (error) {
      console.error("import_runs update error:", error);
    }
  } catch (error) {
    console.error("import_runs update exception:", error);
  }
}

export async function persistMangaChapterEnrichState(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  candidate: CandidateRow,
  result: CandidateProcessResult,
  runId: number | null,
  startedMs: number,
  message: string | null = null,
): Promise<void> {
  const now = new Date().toISOString();
  const state = result.unresolved ? "unresolved" : (result.insertedCount > 0 || result.mappingMethod ? "mapped" : "skipped");
  const visibility = result.unresolved ? "review" : (result.insertedCount > 0 || result.mappingMethod ? "visible" : "hidden");
  const details = {
    unresolved_reason: result.unresolvedReason ?? null,
    inserted_count: result.insertedCount,
    fractional_skipped: result.fractionalSkipped,
    run_id: runId,
    started_ms: startedMs,
    message,
  };

  try {
    const { error } = await supabase
      .from("manga_chapter_enrich_state")
      .upsert({
        manga_id: candidate.id,
        state,
        visibility,
        mapping_method: result.mappingMethod ?? null,
        provider_media_id: result.providerMediaId ?? null,
        chapter_row_count: candidate.chapter_row_count ?? 0,
        inserted_count: result.insertedCount,
        fractional_skipped: result.fractionalSkipped,
        last_run_at: now,
        last_message: message ?? result.unresolvedReason ?? null,
        details,
        updated_at: now,
      }, { onConflict: "manga_id" });
    if (error) {
      console.error("manga_chapter_enrich_state upsert error:", error);
    }
  } catch (error) {
    console.error("manga_chapter_enrich_state upsert exception:", error);
  }
}
