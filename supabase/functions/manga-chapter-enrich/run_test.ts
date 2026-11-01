// Offline run of manga-chapter-enrich: an ambiguous strict-title match stays unresolved
// (review row, no mapping write), a MangaDex failure still releases the import lock,
// and a held body that outlives the run budget does not succeed later. Only an
// acquired lock is released.
import { assertEquals } from "jsr:@std/assert@1";
import { allCandidateTitles, preferredMangaDexTitle, selectTitleMatch, type CandidateRow } from "./matching.ts";
import { runChapterEnrich } from "./run.ts";
import { fetchExistingMapping, persistVerifyState, type MappingRow } from "./repository.ts";

const CANDIDATE = {
  id: 42,
  anilist_id: null,
  mal_id: null,
  title_english: "Blue Box",
  title_romaji: null,
  title_native: null,
  title_synonyms: null,
  status: "FINISHED",
  chapters: 10,
  last_synced_at: null,
  chapter_row_count: 0,
  priority_class: 1,
};

const PAYLOAD = {
  limit: 1,
  scheduleSafe: false,
  timeBudgetMs: 20_000,
  languages: ["en"],
  includeFallbackAllLanguages: false,
  forceMangaId: 42,
  lockTtlSeconds: 900,
  zeroRowOnly: false,
  crunchMode: false,
  matcherMode: "strict" as const,
  minConfidence: 0.95,
  minMargin: 0.1,
  verifyMappings: false,
  collisionTieBreakEnabled: false,
  wrongMapProxyRateLimit: 0.3,
};

type Op =
  | { op: "rpc"; name: string; args: Record<string, unknown> }
  | { op: "insert" | "update" | "upsert" | "select"; table: string; body?: unknown };

type LockMode = "acquired" | "busy" | "error" | "throw";

function enrichFake(lock: LockMode = "acquired", options: {
  candidate?: CandidateRow;
  aliases?: { provider_media_id: string; decision: string }[];
  aliasReply?: { data: unknown; error: { message: string; code: string } | null };
  mapping?: MappingRow;
  mappingReplies?: { data: unknown; error: { message: string; code: string } | null }[];
  updateErrors?: ({ message: string; code: string } | null)[];
} = {}) {
  const ops: Op[] = [];
  let updateIndex = 0;
  let mappingReadIndex = 0;
  function from(table: string) {
    const execSelect = () => {
      ops.push({ op: "select", table });
      if (table === "manga_source_links") return options.mappingReplies?.[mappingReadIndex++] ?? { data: options.mapping ?? null, error: null };
      if (table === "manga_mapping_alias_memory") return options.aliasReply ?? { data: options.aliases ?? [], error: null };
      return { data: [] as unknown[], error: null };
    };
    const builder = {
      select() {
        return builder;
      },
      eq() {
        return builder;
      },
      in() {
        return builder;
      },
      limit() {
        return builder;
      },
      maybeSingle() {
        const result = execSelect();
        return Promise.resolve(result);
      },
      insert(body: unknown) {
        ops.push({ op: "insert", table, body });
        return {
          select() {
            return { single: () => Promise.resolve({ data: { id: 11 }, error: null }) };
          },
          then(resolve: (value: { data: null; error: null }) => unknown, reject?: (reason: unknown) => unknown) {
            return Promise.resolve({ data: null, error: null }).then(resolve, reject);
          },
        };
      },
      update(body: unknown) {
        ops.push({ op: "update", table, body });
        const error = options.updateErrors?.[updateIndex++] ?? null;
        const update = {
          eq() { return update; },
          then(resolve: (value: { error: typeof error }) => unknown, reject?: (reason: unknown) => unknown) {
            return Promise.resolve({ error }).then(resolve, reject);
          },
        };
        return update;
      },
      upsert(body: unknown) {
        ops.push({ op: "upsert", table, body });
        return Promise.resolve({ error: null });
      },
      then(resolve: (value: { data: unknown; error: { message: string; code: string } | null }) => unknown, reject?: (reason: unknown) => unknown) {
        return Promise.resolve(execSelect()).then(resolve, reject);
      },
    };
    return builder;
  }
  const client = {
    from,
    rpc(name: string, args: Record<string, unknown> = {}) {
      ops.push({ op: "rpc", name, args });
      if (name === "acquire_import_lock") {
        if (lock === "error") return Promise.resolve({ data: null, error: { message: "lock rpc failed" } });
        if (lock === "throw") return Promise.reject(new Error("lock rpc threw"));
        if (lock === "busy") return Promise.resolve({ data: false, error: null });
        return Promise.resolve({ data: true, error: null });
      }
      if (name === "get_manga_chapter_enrich_candidates") return Promise.resolve({ data: [options.candidate ?? CANDIDATE], error: null });
      return Promise.resolve({ data: null, error: null });
    },
  };
  return { client, ops };
}

const instant = () => Promise.resolve();

function lockReleased(ops: Op[]) {
  const release = ops.filter((op) => op.op === "rpc" && op.name === "release_import_lock");
  assertEquals(release.length, 1);
  assertEquals(release[0].op === "rpc" ? release[0].args.p_key : null, "manga-chapter-enrich");
  const names = ops.map((op) => op.op === "rpc" ? op.name : `${op.op}:${op.table}`);
  const acquired = names.indexOf("acquire_import_lock");
  const released = names.lastIndexOf("release_import_lock");
  assertEquals(acquired >= 0 && released > acquired, true);
}

function chapterOrMappingWrites(ops: Op[]) {
  return ops.filter((op) =>
    (op.op === "insert" || op.op === "update" || op.op === "upsert") &&
    (op.table === "chapters" || op.table === "manga_source_links")
  );
}

Deno.test("pure matcher resolves nothing for an ambiguous title with no network", () => {
  const results = [
    { id: "aaaaaaaaaaaaaaaa", attributes: { title: { en: "Blue Box" }, altTitles: [], links: {} } },
    { id: "bbbbbbbbbbbbbbbb", attributes: { title: { en: "Blue Box" }, altTitles: [], links: {} } },
  ];
  const queryTitles = allCandidateTitles(CANDIDATE).slice(0, 8);
  const sample = results.slice(0, 8).map((item) => ({
    id: item.id,
    title: preferredMangaDexTitle(item),
    links: item.attributes?.links ?? {},
  }));
  const metrics = {
    skipped_ambiguous: 0,
    skipped_low_confidence: 0,
    fuzzy_attempted: 0,
    fuzzy_auto_mapped: 0,
  };
  const originalFetch = globalThis.fetch;
  let networkCalls = 0;
  globalThis.fetch = (() => {
    networkCalls += 1;
    return Promise.reject(new Error("pure matcher must not use the network"));
  }) as typeof fetch;
  try {
    const resolution = selectTitleMatch({
      candidate: CANDIDATE,
      results,
      queryTitles,
      matcherMode: "strict",
      minConfidence: PAYLOAD.minConfidence,
      minMargin: PAYLOAD.minMargin,
      sample,
      metrics,
    });
    assertEquals(networkCalls, 0);
    assertEquals(resolution.mapped, false);
    assertEquals(resolution.reason, "ambiguous_title_strict");
    assertEquals(resolution.mangaDexId, undefined);
    assertEquals(resolution.sample?.length, 2);
    assertEquals(metrics.skipped_ambiguous, 1);
    assertEquals(metrics.fuzzy_attempted, 0);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("ambiguous strict title matches stay unresolved and are queued for review", async () => {
  const fake = enrichFake();
  const urls: string[] = [];
  const fetchImpl: typeof fetch = (input) => {
    urls.push(String(input));
    const body = {
      data: [
        { id: "aaaaaaaaaaaaaaaa", attributes: { title: { en: "Blue Box" }, altTitles: [], links: {} } },
        { id: "bbbbbbbbbbbbbbbb", attributes: { title: { en: "Blue Box" }, altTitles: [], links: {} } },
      ],
    };
    return Promise.resolve(new Response(JSON.stringify(body), { status: 200 }));
  };

  const res = await runChapterEnrich({ supabase: fake.client, payload: PAYLOAD, fetch: fetchImpl, sleep: instant });
  const body = await res.json();

  assertEquals(res.status, 200);
  assertEquals(body.success, true);
  assertEquals(body.results.unresolved_mappings, 1);
  assertEquals(body.results.skipped_ambiguous, 1);
  assertEquals(body.results.mapped_by_title_strict, 0);
  assertEquals(body.results.errors, 0);
  assertEquals(urls.length, 1);

  const linkWrites = fake.ops.filter((op) =>
    (op.op === "insert" || op.op === "upsert") && op.table === "manga_source_links"
  );
  assertEquals(linkWrites, []);

  const review = fake.ops.find((op) => op.op === "insert" && op.table === "manga_source_link_review");
  const reviewBody = review && review.op === "insert" ? review.body as { reason: string; candidate_payload: { sample: unknown[] } } : null;
  assertEquals(reviewBody?.reason, "ambiguous_title_strict");
  assertEquals(reviewBody?.candidate_payload.sample.length, 2);

  const state = fake.ops.find((op) => op.op === "upsert" && op.table === "manga_chapter_enrich_state");
  const stateBody = state && state.op === "upsert" ? state.body as { state: string; provider_media_id: string | null } : null;
  assertEquals(stateBody?.state, "unresolved");
  assertEquals(stateBody?.provider_media_id, null);
  lockReleased(fake.ops);
});

Deno.test("provider failure records the candidate error and still releases the import lock", async () => {
  const fake = enrichFake();
  let calls = 0;
  const fetchImpl: typeof fetch = () => {
    calls += 1;
    return Promise.reject(new Error("mangadex down"));
  };

  const res = await runChapterEnrich({ supabase: fake.client, payload: PAYLOAD, fetch: fetchImpl, sleep: instant });
  const body = await res.json();

  assertEquals(res.status, 200);
  assertEquals(body.success, true);
  assertEquals(body.results.errors, 1);
  assertEquals(body.results.manga_processed, 0);
  assertEquals(calls, 4);

  const chapterWrites = fake.ops.filter((op) => op.op !== "rpc" && op.table === "chapters");
  assertEquals(chapterWrites, []);
  const linkWrites = fake.ops.filter((op) =>
    (op.op === "insert" || op.op === "upsert") && op.table === "manga_source_links"
  );
  assertEquals(linkWrites, []);

  const state = fake.ops.find((op) => op.op === "upsert" && op.table === "manga_chapter_enrich_state");
  const stateBody = state && state.op === "upsert"
    ? state.body as { state: string; last_message: string; details: { unresolved_reason: string } }
    : null;
  assertEquals(stateBody?.state, "unresolved");
  assertEquals(stateBody?.last_message, "mangadex down");
  assertEquals(stateBody?.details.unresolved_reason, "worker_error");

  const names = fake.ops.map((op) => op.op === "rpc" ? op.name : `${op.op}:${op.table}`);
  const persisted = names.indexOf("upsert:manga_chapter_enrich_state");
  const released = names.lastIndexOf("release_import_lock");
  assertEquals(persisted >= 0 && released > persisted, true);
  lockReleased(fake.ops);
});

Deno.test("actual run honors rejected aliases before single external, collision, or title matching", async () => {
  for (const mode of ["single_external", "all_external", "title"] as const) {
    const external = mode !== "title";
    const rows = ["aaaaaaaaaaaaaaaa", "bbbbbbbbbbbbbbbb"].slice(0, mode === "single_external" ? 1 : 2).map((id) => ({
      id, attributes: { title: { en: "Blue Box" }, altTitles: [], links: external ? { al: "7" } : {} },
    }));
    const fake = enrichFake("acquired", {
      candidate: { ...CANDIDATE, anilist_id: external ? 7 : null },
      aliases: rows.map((item) => ({ provider_media_id: item.id, decision: "rejected_collision" })),
    });
    let fetches = 0;
    const res = await runChapterEnrich({
      supabase: fake.client, payload: PAYLOAD, sleep: instant,
      fetch: () => { fetches += 1; return Promise.resolve(Response.json({ data: rows })); },
    });
    const body = await res.json();
    assertEquals(body.results.errors, 0, mode);
    assertEquals(body.results.unresolved_mappings, 1, mode);
    assertEquals(body.results.alias_memory_hits, 1, mode);
    assertEquals(body.results.unresolved_reason_counts.alias_rejected, 1, mode);
    assertEquals(chapterOrMappingWrites(fake.ops), [], mode);
    assertEquals(fetches, 1, "rejected candidates must not reach aggregate transport");
    lockReleased(fake.ops);
  }
  const row = { id: "aaaaaaaaaaaaaaaa", attributes: { title: { en: "Blue Box" }, altTitles: [], links: { al: "7" } } };
  for (const aliasReply of [
    { data: null, error: { message: "database unavailable", code: "08006" } },
    { data: null, error: { message: "alias table missing", code: "42P01" } },
    { data: null, error: null },
    { data: {}, error: null },
    { data: [null], error: null },
    { data: [{ provider_media_id: "", decision: "accepted" }], error: null },
    { data: [{ provider_media_id: row.id, decision: "unknown" }], error: null },
    { data: [{ provider_media_id: row.id }], error: null },
  ]) {
    const fake = enrichFake("acquired", { candidate: { ...CANDIDATE, anilist_id: 7 }, aliasReply });
    let fetches = 0;
    const res = await runChapterEnrich({
      supabase: fake.client, payload: PAYLOAD, sleep: instant,
      fetch: () => { fetches += 1; return Promise.resolve(Response.json({ data: [row] })); },
    });
    const body = await res.json();
    assertEquals(body.results.errors, 1);
    assertEquals(body.results.manga_processed, 0);
    assertEquals(chapterOrMappingWrites(fake.ops), []);
    assertEquals(fake.ops.some((op) => op.op === "upsert" && op.table === "manga_mapping_alias_memory"), false);
    assertEquals(fetches, 1, "unknown alias memory must stop before aggregate fetch or acceptance");
    lockReleased(fake.ops);
  }
});

Deno.test("actual run retains accepted alias selection among colliding external ids", async () => {
  const rows = ["aaaaaaaaaaaaaaaa", "bbbbbbbbbbbbbbbb"].map((id) => ({
    id, attributes: { title: { en: "Blue Box" }, altTitles: [], links: { al: "7" } },
  }));
  const fake = enrichFake("acquired", {
    candidate: { ...CANDIDATE, anilist_id: 7 },
    aliases: [{ provider_media_id: rows[1].id, decision: "accepted" }],
  });
  const res = await runChapterEnrich({
    supabase: fake.client, payload: PAYLOAD, sleep: instant,
    fetch: (input) => Promise.resolve(Response.json(String(input).includes("/aggregate") ? { volumes: {} } : { data: rows })),
  });
  const body = await res.json();
  assertEquals(body.results.errors, 0);
  assertEquals(body.results.mapped_by_al, 1);
  const writes = fake.ops.filter((op) => op.op === "upsert" && op.table === "manga_source_links");
  assertEquals(writes.length, 1);
  assertEquals((writes[0] as { body: { provider_media_id: string } }).body.provider_media_id, rows[1].id);
  lockReleased(fake.ops);
});

Deno.test("actual run stops before remapping when verification deactivation cannot be persisted", async () => {
  for (const updateErrors of [
    [{ message: "database unavailable", code: "08006" }],
    [{ message: "verification column missing", code: "PGRST204" }, { message: "status write failed", code: "08006" }],
  ]) {
    const fake = enrichFake("acquired", {
      mapping: { provider_media_id: "old-mapping", verify_fail_count: 1, last_mismatch_at: "2020-01-01T00:00:00Z" },
      updateErrors,
    });
    let fetches = 0;
    const res = await runChapterEnrich({
      supabase: fake.client, payload: { ...PAYLOAD, verifyMappings: true }, sleep: instant,
      fetch: () => { fetches += 1; return Promise.resolve(Response.json({}, { status: 404 })); },
    });
    const body = await res.json();
    assertEquals(body.results.errors, 1);
    assertEquals(body.results.verify_deactivated, 0);
    assertEquals(body.results.manga_processed, 0);
    assertEquals(fetches, 1, "no new search or aggregate after failed deactivation");
    assertEquals(fake.ops.some((op) => op.op === "upsert" && op.table === "manga_source_links"), false);
    assertEquals(fake.ops.some((op) => op.op !== "rpc" && op.table === "chapters"), false);
    const writes = fake.ops.filter((op) => op.op === "update" && op.table === "manga_source_links");
    assertEquals(writes.length, updateErrors.length);
    lockReleased(fake.ops);
  }
  const legacy = enrichFake("acquired", { updateErrors: [{ message: "missing column", code: "42703" }, null] });
  await persistVerifyState(legacy.client, CANDIDATE.id, { verify_status: "mismatch", status: "inactive" });
  assertEquals(legacy.ops.flatMap((op) => op.op === "update" ? [op.body] : []), [
    { verify_status: "mismatch", status: "inactive" }, { status: "inactive" },
  ]);
});

Deno.test("actual run fails closed on an unknown active mapping; only successful absence permits remapping", async () => {
  const operational = { data: null, error: { message: "database unavailable", code: "08006" } };
  const missingColumns = { data: null, error: { message: "verification column missing", code: "PGRST204" } };
  for (const mappingReplies of [
    [operational],
    [missingColumns, operational],
    [{ data: {}, error: null }],
    [{ data: undefined, error: null }],
    [{ data: [], error: null }],
    [{ data: { provider_media_id: " " }, error: null }],
    [missingColumns, { data: {}, error: null }],
  ]) {
    const fake = enrichFake("acquired", { mappingReplies });
    let fetches = 0;
    const res = await runChapterEnrich({
      supabase: fake.client, payload: PAYLOAD, sleep: instant,
      fetch: () => { fetches += 1; return Promise.resolve(Response.json({ data: [] })); },
    });
    const body = await res.json();
    assertEquals(body.results.errors, 1);
    assertEquals(body.results.manga_processed, 0);
    assertEquals(fetches, 0, "unknown mapping must stop before MangaDex search or chapter requests");
    assertEquals(chapterOrMappingWrites(fake.ops), []);
    assertEquals(fake.ops.filter((op) => op.op === "select" && op.table === "manga_source_links").length, mappingReplies.length);
    lockReleased(fake.ops);
  }
  const legacy = enrichFake("acquired", { mappingReplies: [missingColumns, { data: { provider_media_id: "existing" }, error: null }] });
  assertEquals(await fetchExistingMapping(legacy.client, 42), { provider_media_id: "existing" });
  assertEquals(await fetchExistingMapping(enrichFake().client, 42), null);
});

Deno.test("a held MangaDex body expires at the run deadline and only an acquired lock is released", async () => {
  for (const lock of ["busy", "error", "throw"] as const) {
    const fake = enrichFake(lock);
    let fetches = 0;
    const res = await runChapterEnrich({
      supabase: fake.client,
      payload: PAYLOAD,
      fetch: () => {
        fetches += 1;
        return Promise.reject(new Error("should not fetch"));
      },
      sleep: instant,
    });
    const body = await res.json();
    assertEquals(res.status, 200);
    assertEquals(body.success, true);
    assertEquals(body.skipped, true);
    assertEquals(body.reason, lock === "busy" ? "locked" : "unavailable");
    assertEquals(fetches, 0);
    assertEquals(chapterOrMappingWrites(fake.ops), []);
    assertEquals(fake.ops.some((op) => op.op === "rpc" && op.name === "acquire_import_lock"), true);
    assertEquals(fake.ops.some((op) => op.op === "rpc" && op.name === "release_import_lock"), false);
    assertEquals(fake.ops.some((op) => op.op === "rpc" && op.name === "get_manga_chapter_enrich_candidates"), false);
  }

  const fake = enrichFake("acquired");
  let releaseByte: () => void = () => {};
  const gate = new Promise<void>((resolve) => {
    releaseByte = resolve;
  });
  let cancelled = false;
  let lateSuccess = false;
  let fetches = 0;
  let signal: AbortSignal | undefined;
  const successBody = JSON.stringify({
    data: [
      { id: "cccccccccccccccc", attributes: { title: { en: "Blue Box" }, altTitles: [], links: {} } },
    ],
  });
  const fetchImpl: typeof fetch = (_input, init) => {
    fetches += 1;
    signal = init?.signal ?? undefined;
    if (signal?.aborted) {
      lateSuccess = true;
      return Promise.resolve(new Response(successBody, { status: 200, headers: { "content-type": "application/json" } }));
    }
    const stream = new ReadableStream<Uint8Array>({
      async pull(controller) {
        try {
          await gate;
          if (cancelled || signal?.aborted) return;
          controller.enqueue(new TextEncoder().encode(successBody));
          controller.close();
          lateSuccess = true;
        } catch {
          // Cancelled while the body was held.
        }
      },
      cancel() {
        cancelled = true;
      },
    });
    return Promise.resolve(new Response(stream, { status: 200, headers: { "content-type": "application/json" } }));
  };

  let guard: ReturnType<typeof setTimeout> | undefined;
  const runPromise = runChapterEnrich({
    supabase: fake.client,
    payload: { ...PAYLOAD, timeBudgetMs: 8_000 },
    fetch: fetchImpl,
    sleep: instant,
  });
  try {
    const res = await Promise.race([
      runPromise,
      new Promise<never>((_, reject) => {
        guard = setTimeout(() => reject(new Error("held MangaDex body exceeded the run deadline")), 20_000);
      }),
    ]);
    const body = await res.json();
    assertEquals(res.status, 200);
    assertEquals(body.success, true);
    assertEquals(body.results.errors, 1);
    assertEquals(body.results.manga_processed, 0);
    assertEquals(body.results.chapters_upserted, 0);
    assertEquals(body.results.mapped_by_title_strict, 0);
    assertEquals(fetches, 1);
    assertEquals(signal?.aborted, true);
    assertEquals(cancelled, true);
    assertEquals(lateSuccess, false);
    assertEquals(chapterOrMappingWrites(fake.ops), []);
    lockReleased(fake.ops);
  } finally {
    if (guard !== undefined) clearTimeout(guard);
    releaseByte();
  }

  await new Promise((resolve) => setTimeout(resolve, 40));
  assertEquals(lateSuccess, false);
  assertEquals(fetches, 1);
  assertEquals(chapterOrMappingWrites(fake.ops), []);
  lockReleased(fake.ops);
});

Deno.test("actual run keeps the aggregate volume grouping as volume rows (2026-11-01)", async () => {
  const rows = ["aaaaaaaaaaaaaaaa", "bbbbbbbbbbbbbbbb"].map((id) => ({
    id, attributes: { title: { en: "Blue Box" }, altTitles: [], links: { al: "7" } },
  }));
  const fake = enrichFake("acquired", {
    candidate: { ...CANDIDATE, anilist_id: 7 },
    aliases: [{ provider_media_id: rows[1].id, decision: "accepted" }],
  });
  const aggregate = { volumes: { "1": { chapters: { "1": {}, "2": {} } }, "none": { chapters: { "3": {} } } } };
  const res = await runChapterEnrich({
    supabase: fake.client, payload: PAYLOAD, sleep: instant,
    fetch: (input) => Promise.resolve(Response.json(String(input).includes("/aggregate") ? aggregate : { data: rows })),
  });
  const body = await res.json();
  assertEquals(body.results.errors, 0);
  const volumeInserts = fake.ops.filter((op) => op.op === "insert" && op.table === "volumes");
  assertEquals(volumeInserts.length, 1);
  assertEquals((volumeInserts[0] as { body: unknown }).body, [
    { manga_id: 42, number: 1, title: "Volume 1", description: "Chapters 1–2" },
  ]);
  lockReleased(fake.ops);
});
