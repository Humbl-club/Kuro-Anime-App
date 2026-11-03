// Offline run tests for bulk-import-anime. They call the real run() with an in-memory
// table stand-in and an injected AniList page fetch. No network. Not a Supabase test.
// The stand-in lives in this file so production index.ts never imports it.
// Run: deno test --no-prompt supabase/functions/bulk-import-anime/handler_test.ts
import { strict as assert } from "node:assert";
import { run } from "./handler.ts";

type Row = Record<string, unknown>;

class Db {
  tables: Record<string, Row[]> = {};
  rpcs: { name: string; args: Row }[] = [];
  lockHeld = new Set<string>();
  lockMode: "default" | "error" | "throw" | "null" = "default";
  lockErrorMessage = "lock rpc failed";
  // Consumed by the first matching primary upsert so a replay can persist that row.
  failUpsert: { table: string; anilistId: number; message: string } | null = null;
  private seq = 1;

  rows(table: string): Row[] {
    return this.tables[table] ?? [];
  }

  seed(table: string, rows: Row[]) {
    this.tables[table] = rows.map((r) => ({ ...r }));
  }

  from(table: string) {
    const db = this;
    let action: "select" | "insert" | "update" | "upsert" | "delete" = "select";
    let payload: Row | Row[] | null = null;
    let conflict: string[] = [];
    const filters: [string, unknown][] = [];
    const exec = () => {
      const rows = (db.tables[table] ??= []);
      const matches = (row: Row) => filters.every(([k, v]) => row[k] === v);
      if (action === "select") {
        const found = rows.filter(matches);
        return { data: found[0] ?? null, error: null };
      }
      if (action === "insert") {
        const incoming = Array.isArray(payload) ? payload : [payload as Row];
        const stored = incoming.map((p) => ({ id: db.seq++, ...p }));
        rows.push(...stored);
        return { data: Array.isArray(payload) ? stored : stored[0], error: null };
      }
      if (action === "update") {
        for (const row of rows) if (matches(row)) Object.assign(row, payload);
        return { data: null, error: null };
      }
      if (action === "delete") {
        db.tables[table] = rows.filter((row) => !matches(row));
        return { data: null, error: null };
      }
      const incoming = Array.isArray(payload) ? payload : [payload as Row];
      if (
        db.failUpsert &&
        table === db.failUpsert.table &&
        incoming.some((row) => row.anilist_id === db.failUpsert?.anilistId)
      ) {
        const message = db.failUpsert.message;
        db.failUpsert = null;
        return { data: null, error: { message } };
      }
      const stored = incoming.map((p) => {
        const existing = rows.find((r) => conflict.every((k) => r[k] === p[k]));
        if (existing) {
          Object.assign(existing, p);
          return existing;
        }
        const row = { id: db.seq++, ...p };
        rows.push(row);
        return row;
      });
      return { data: Array.isArray(payload) ? stored : stored[0], error: null };
    };
    const builder = {
      select() {
        return builder;
      },
      insert(p: Row | Row[]) {
        action = "insert";
        payload = p;
        return builder;
      },
      update(p: Row) {
        action = "update";
        payload = p;
        return builder;
      },
      delete() {
        action = "delete";
        return builder;
      },
      upsert(p: Row | Row[], opts?: { onConflict?: string }) {
        action = "upsert";
        payload = p;
        conflict = (opts?.onConflict ?? "id").split(",").map((s) => s.trim());
        return builder;
      },
      eq(k: string, v: unknown) {
        filters.push([k, v]);
        return builder;
      },
      maybeSingle() {
        return Promise.resolve(exec());
      },
      single() {
        return Promise.resolve(exec());
      },
      then(ok: (v: { data: unknown; error: { message: string } | null }) => unknown, err?: (e: unknown) => unknown) {
        return Promise.resolve(exec()).then(ok, err);
      },
    };
    return builder;
  }

  rpc(name: string, args: Row) {
    this.rpcs.push({ name, args });
    if (name === "acquire_import_lock") {
      if (this.lockMode === "throw") throw new Error(this.lockErrorMessage);
      if (this.lockMode === "error") return Promise.resolve({ data: null, error: { message: this.lockErrorMessage } });
      if (this.lockMode === "null") return Promise.resolve({ data: null, error: null });
      const key = String(args.p_key);
      if (this.lockHeld.has(key)) return Promise.resolve({ data: false, error: null });
      this.lockHeld.add(key);
      return Promise.resolve({ data: true, error: null });
    }
    if (name === "release_import_lock") {
      this.lockHeld.delete(String(args.p_key));
      return Promise.resolve({ data: null, error: null });
    }
    return Promise.resolve({ data: null, error: { message: "unknown rpc" } });
  }
}

function media(id: number) {
  return {
    id,
    idMal: id + 1000,
    title: { romaji: `Anime ${id}`, english: `Anime ${id}` },
    format: "TV",
    status: "FINISHED",
    episodes: 12,
    duration: 24,
    updatedAt: 1_700_000_000,
  };
}

function cursor(db: Db): number | undefined {
  return db.rows("import_state").find((r) => r.media_type === "ANIME")?.last_page as number | undefined;
}

Deno.test("successful batch persists the fetched page, advances the cursor, and releases the lock", async () => {
  const db = new Db();
  db.seed("import_state", [{ media_type: "ANIME", last_page: 4 }]);
  const pages: number[] = [];
  const res = await run({
    useCursor: true,
    lightweight: true,
    pagesPerBatch: 1,
    perPage: 25,
    delayMs: 0,
    runToEnd: false,
    includeRelations: false,
    includeEpisodes: false,
  }, {
    supabase: db,
    heavyImportsEnabled: true,
    fetchPage(page) {
      pages.push(page);
      return Promise.resolve([media(501)]);
    },
  });
  const body = await res.json();
  assert.equal(res.status, 200);
  assert.equal(body.success, true);
  assert.equal(body.results.anime, 1);
  assert.equal(body.results.errors, 0);
  assert.equal(body.nextStartPage, 6);
  assert.equal(body.trackKey, null);
  assert.equal(body.trackPreset, null);
  assert.deepEqual(pages, [5]);
  assert.equal(cursor(db), 5);
  const row = db.rows("anime").find((r) => r.anilist_id === 501);
  assert.equal(row?.title_romaji, "Anime 501");
  assert.equal(row?.episodes, 12);
  assert.deepEqual(db.rpcs.map((r) => r.name), ["acquire_import_lock", "release_import_lock"]);
  assert.equal(db.rpcs[0].args.p_key, "anime");
  assert.equal(db.lockHeld.size, 0);
  assert.equal(db.rows("import_runs")[0].status, "success");
});

Deno.test("provider failure releases the lock and does not advance the cursor past unpersisted work", async () => {
  const db = new Db();
  db.seed("import_state", [{ media_type: "ANIME", last_page: 4 }]);
  const pages: number[] = [];
  const res = await run({
    useCursor: true,
    lightweight: true,
    pagesPerBatch: 2,
    perPage: 25,
    delayMs: 0,
    runToEnd: false,
    includeRelations: false,
    includeEpisodes: false,
  }, {
    supabase: db,
    heavyImportsEnabled: true,
    fetchPage(page) {
      pages.push(page);
      if (page === 6) throw new Error("AniList error 503");
      return Promise.resolve([media(501)]);
    },
  });
  const body = await res.json();
  assert.equal(res.status, 500);
  assert.deepEqual(body, { success: false, error: "AniList error 503" });
  assert.deepEqual(pages, [5, 6]);
  // Page 5 was written, page 6 was not. The checkpoint stays at the pre-run page
  // (4): the failed page is not stored, and this run's partial page is not either.
  assert.equal(cursor(db), 4);
  assert.deepEqual(db.rows("anime").map((r) => r.anilist_id), [501]);
  assert.deepEqual(db.rpcs.map((r) => r.name), ["acquire_import_lock", "release_import_lock"]);
  assert.equal(db.rpcs[0].args.p_key, "anime");
  assert.equal(db.rpcs[1].args.p_key, "anime");
  assert.equal(db.lockHeld.size, 0);
  assert.equal(db.rows("import_runs")[0].status, "error");
  assert.equal(db.rows("import_runs")[0].message, "AniList error 503");
});

function cursorRunPayload() {
  return {
    useCursor: true,
    lightweight: true,
    pagesPerBatch: 1,
    perPage: 25,
    delayMs: 0,
    runToEnd: false,
    includeRelations: false,
    includeEpisodes: false,
  };
}

Deno.test("lock rpc error does not import, write the catalog, advance the cursor, or release", async () => {
  const db = new Db();
  db.lockMode = "error";
  db.lockErrorMessage = "lock rpc failed";
  db.seed("import_state", [{ media_type: "ANIME", last_page: 4 }]);
  const pages: number[] = [];
  const res = await run(cursorRunPayload(), {
    supabase: db,
    heavyImportsEnabled: true,
    fetchPage(page) {
      pages.push(page);
      return Promise.resolve([media(501)]);
    },
  });
  const body = await res.json();
  assert.equal(res.status, 500);
  assert.equal(body.success, false);
  assert.equal(body.skipped, true);
  assert.equal(body.reason, "lock_unavailable");
  assert.equal(body.error, "lock rpc failed");
  assert.deepEqual(pages, []);
  assert.equal(db.rows("anime").length, 0);
  assert.equal(cursor(db), 4);
  assert.deepEqual(db.rpcs.map((r) => r.name), ["acquire_import_lock"]);
  assert.equal(db.rows("import_runs")[0].status, "error");
  assert.equal(db.rows("import_runs")[0].message, "lock rpc failed");
});

Deno.test("lock rpc throw does not import, write the catalog, advance the cursor, or release", async () => {
  const db = new Db();
  db.lockMode = "throw";
  db.lockErrorMessage = "lock rpc threw";
  db.seed("import_state", [{ media_type: "ANIME", last_page: 4 }]);
  const pages: number[] = [];
  const res = await run(cursorRunPayload(), {
    supabase: db,
    heavyImportsEnabled: true,
    fetchPage(page) {
      pages.push(page);
      return Promise.resolve([media(501)]);
    },
  });
  const body = await res.json();
  assert.equal(res.status, 500);
  assert.equal(body.success, false);
  assert.equal(body.reason, "lock_unavailable");
  assert.equal(body.error, "lock rpc threw");
  assert.deepEqual(pages, []);
  assert.equal(db.rows("anime").length, 0);
  assert.equal(cursor(db), 4);
  assert.deepEqual(db.rpcs.map((r) => r.name), ["acquire_import_lock"]);
  assert.notEqual(db.rows("import_runs")[0].status, "success");
});

Deno.test("busy lock (rpc false) skips without importing or releasing", async () => {
  const db = new Db();
  db.lockHeld.add("anime");
  db.seed("import_state", [{ media_type: "ANIME", last_page: 4 }]);
  const pages: number[] = [];
  const res = await run(cursorRunPayload(), {
    supabase: db,
    heavyImportsEnabled: true,
    fetchPage(page) {
      pages.push(page);
      return Promise.resolve([media(501)]);
    },
  });
  const body = await res.json();
  assert.equal(res.status, 200);
  assert.equal(body.success, true);
  assert.equal(body.skipped, true);
  assert.equal(body.reason, "locked");
  assert.deepEqual(pages, []);
  assert.equal(db.rows("anime").length, 0);
  assert.equal(cursor(db), 4);
  assert.deepEqual(db.rpcs.map((r) => r.name), ["acquire_import_lock"]);
  assert.equal(db.rpcs[0].args.p_key, "anime");
  assert.equal(db.lockHeld.has("anime"), true);
  assert.equal(db.rows("import_runs")[0].status, "skipped");
  assert.equal(db.rows("import_runs")[0].message, "locked");
});

Deno.test("busy lock (rpc null) skips without importing or releasing", async () => {
  const db = new Db();
  db.lockMode = "null";
  db.seed("import_state", [{ media_type: "ANIME", last_page: 4 }]);
  const pages: number[] = [];
  const res = await run(cursorRunPayload(), {
    supabase: db,
    heavyImportsEnabled: true,
    fetchPage(page) {
      pages.push(page);
      return Promise.resolve([media(501)]);
    },
  });
  const body = await res.json();
  assert.equal(res.status, 200);
  assert.equal(body.success, true);
  assert.equal(body.skipped, true);
  assert.equal(body.reason, "locked");
  assert.deepEqual(pages, []);
  assert.equal(db.rows("anime").length, 0);
  assert.equal(cursor(db), 4);
  assert.deepEqual(db.rpcs.map((r) => r.name), ["acquire_import_lock"]);
  assert.equal(db.rows("import_runs")[0].status, "skipped");
});

Deno.test("a failed primary upsert does not complete the page, and replaying it is idempotent", async () => {
  const db = new Db();
  db.seed("import_state", [{ media_type: "ANIME", last_page: 4 }]);
  db.failUpsert = { table: "anime", anilistId: 502, message: "anime upsert failed" };
  const pages: number[] = [];
  const fetchPage = (page: number) => {
    pages.push(page);
    return Promise.resolve([media(501), media(502), media(503)]);
  };
  const res = await run(cursorRunPayload(), {
    supabase: db,
    heavyImportsEnabled: true,
    fetchPage,
  });
  const body = await res.json();
  assert.equal(res.status, 500);
  assert.equal(body.success, false);
  assert.equal(body.error, "anime upsert failed");
  assert.equal(cursor(db), 4);
  assert.deepEqual(db.rows("anime").map((r) => r.anilist_id).sort(), [501, 503]);
  assert.equal(db.rows("import_runs")[0].status, "error");
  assert.notEqual(db.rows("import_runs")[0].status, "success");
  const firstResults = db.rows("import_runs")[0].results as { anime: number; errors: number };
  assert.equal(firstResults.anime, 2);
  assert.equal(firstResults.errors, 1);
  assert.deepEqual(db.rpcs.map((r) => r.name), ["acquire_import_lock", "release_import_lock"]);
  assert.equal(db.lockHeld.size, 0);
  assert.deepEqual(pages, [5]);

  const replay = await run(cursorRunPayload(), {
    supabase: db,
    heavyImportsEnabled: true,
    fetchPage,
  });
  const replayBody = await replay.json();
  assert.equal(replay.status, 200);
  assert.equal(replayBody.success, true);
  assert.equal(cursor(db), 5);
  assert.deepEqual(db.rows("anime").map((r) => r.anilist_id).sort(), [501, 502, 503]);
  assert.equal(db.rows("anime").length, 3);
  assert.equal(db.rows("import_runs").at(-1)?.status, "success");
});

// ---------------------------------------------------------------------------
// 2026-11-01 intake robustness: provider errors, per-track queries, clobber guards.
// ---------------------------------------------------------------------------
import { AniListError, AniListLimiter, createAniListClient } from "../_shared/anilist_client.ts";
import { fetchAniListAnimeData } from "./anilist.ts";

function fakeAniList(bodies: unknown[]) {
  const queries: { query: string; variables: Record<string, unknown> }[] = [];
  const client = createAniListClient({
    limiter: new AniListLimiter(0),
    sleep: () => Promise.resolve(),
    random: () => 0,
    fetch: (_input, init) => {
      const parsed = JSON.parse(String(init?.body));
      queries.push(parsed);
      const body = bodies.shift();
      return Promise.resolve(new Response(JSON.stringify(body), { status: 200, headers: { "Content-Type": "application/json" } }));
    },
  });
  return { client, queries };
}

function realTransport(bodies: unknown[]) {
  const fake = fakeAniList(bodies);
  return {
    queries: fake.queries,
    fetchPage: (page: number, perPage: number, rel: boolean, eps: boolean, retries: number, query: any) =>
      fetchAniListAnimeData(page, perPage, rel, eps, retries, query, fake.client),
  };
}

for (const [label, body] of [
  ["200 with GraphQL errors", { data: null, errors: [{ message: "Internal Server Error" }] }],
  ["200 without data.Page", { data: { Page: null } }],
  ["200 with data null", { data: null }],
] as const) {
  Deno.test(`${label} is a failed run: no cursor wrap, no advance, lock released`, async () => {
    const db = new Db();
    db.seed("import_state", [{ media_type: "ANIME", last_page: 4 }]);
    const transport = realTransport([body]);
    const res = await run(cursorRunPayload(), { supabase: db, heavyImportsEnabled: true, fetchPage: transport.fetchPage });
    const out = await res.json();
    assert.equal(res.status, 500);
    assert.equal(out.success, false);
    assert.equal(cursor(db), 4, "the cursor must not wrap to 0 or advance");
    assert.equal(db.rows("import_runs")[0].status, "error");
    assert.equal(db.lockHeld.size, 0);
  });
}

Deno.test("a real empty page still wraps the legacy popularity cursor", async () => {
  const db = new Db();
  db.seed("import_state", [{ media_type: "ANIME", last_page: 4 }]);
  const transport = realTransport([{ data: { Page: { media: [] } } }]);
  const res = await run(cursorRunPayload(), { supabase: db, heavyImportsEnabled: true, fetchPage: transport.fetchPage });
  assert.equal(res.status, 200);
  assert.equal(cursor(db), 0);
  assert.equal(transport.queries[0].variables.sort?.toString(), "POPULARITY_DESC");
  assert.equal("statusIn" in transport.queries[0].variables, false);
});

Deno.test("a budget stop before any request commits the pages already persisted", async () => {
  const db = new Db();
  db.seed("import_state", [{ media_type: "ANIME", last_page: 4 }]);
  const res = await run({ ...cursorRunPayload(), pagesPerBatch: 3 }, {
    supabase: db,
    heavyImportsEnabled: true,
    fetchPage(page) {
      if (page === 6) return Promise.reject(new AniListError("budget", "would exceed budget"));
      return Promise.resolve([media(page * 100)]);
    },
  });
  const out = await res.json();
  assert.equal(res.status, 200);
  assert.equal(out.stoppedEarly, "budget");
  assert.equal(cursor(db), 5);
  assert.equal(db.rows("import_runs")[0].message, "stopped_early:budget");
});

Deno.test("join-table re-imports update in place (onConflict on the natural key)", async () => {
  const db = new Db();
  const withTag = (rank: number, updatedAt: number) => ({
    ...media(700),
    updatedAt,
    tags: [{ id: 9, name: "Isekai", rank }],
    studios: { nodes: [{ id: 4, name: "Studio" }] },
    characters: { nodes: [{ id: 5, name: { full: "A" } }], edges: [{ role: "MAIN" }] },
    staff: { nodes: [{ id: 6, name: { full: "B" } }], edges: [{ role: "Director" }] },
  });
  const payload = { ...cursorRunPayload(), useCursor: false, includeRelations: true, lightweight: false };
  const first = await run(payload, { supabase: db, heavyImportsEnabled: true, fetchPage: () => Promise.resolve([withTag(60, 1)]) });
  const second = await run(payload, { supabase: db, heavyImportsEnabled: true, fetchPage: () => Promise.resolve([withTag(90, 2)]) });
  assert.equal(first.status, 200);
  assert.equal(second.status, 200);
  assert.equal((await second.json()).results.errors, 0);
  assert.equal(db.rows("anime_tags").length, 1);
  assert.equal(db.rows("anime_tags")[0].rank, 90);
  assert.equal(db.rows("anime_studios").length, 1);
  assert.equal(db.rows("anime_characters").length, 1);
  assert.equal(db.rows("anime_staff").length, 1);
});

Deno.test("a stale refresh keeps Storage-mirrored images and the synopsis state when the description is unchanged", async () => {
  const db = new Db();
  db.seed("anime", [{
    id: 1,
    anilist_id: 800,
    updated_at_anilist: new Date(1 * 1000).toISOString(),
    description: "Same story.",
    cover_image_large: "https://x.supabase.co/storage/v1/object/public/media/anime/800/large.webp",
    cover_image_medium: "https://s4.anilist.co/old-medium.jpg",
    synopsis_enhanced_state: "done",
  }]);
  const item = {
    ...media(800),
    updatedAt: 2,
    description: "Same story.",
    coverImage: { large: "https://s4.anilist.co/large.jpg", medium: "https://s4.anilist.co/new-medium.jpg" },
  };
  const payload = { ...cursorRunPayload(), useCursor: false };
  await run(payload, { supabase: db, heavyImportsEnabled: true, fetchPage: () => Promise.resolve([item]) });
  const row = db.rows("anime")[0];
  assert.equal(row.cover_image_large, "https://x.supabase.co/storage/v1/object/public/media/anime/800/large.webp");
  assert.equal(row.cover_image_medium, "https://s4.anilist.co/new-medium.jpg");
  assert.equal(row.synopsis_enhanced_state, "done");
  assert.equal(db.rows("anime").length, 1);

  await run(payload, {
    supabase: db,
    heavyImportsEnabled: true,
    fetchPage: () => Promise.resolve([{ ...item, updatedAt: 3, description: "A rewritten story." }]),
  });
  assert.equal(db.rows("anime")[0].synopsis_enhanced_state, "pending");
  assert.equal(db.rows("anime")[0].description, "A rewritten story.");
});

Deno.test("an unchanged title gets no write; only a changed next airing is patched", async () => {
  const db = new Db();
  const airing = 1_800_000_000;
  db.seed("anime", [{
    id: 1,
    anilist_id: 900,
    updated_at_anilist: new Date(1_700_000_000 * 1000).toISOString(),
    episodes: 12,
    next_episode_number: 5,
    next_airing_at: new Date(airing * 1000).toISOString(),
    last_synced_at: "2026-01-01T00:00:00.000Z",
  }]);
  const item = { ...media(900), nextAiringEpisode: { episode: 5, airingAt: airing } };
  const payload = { ...cursorRunPayload(), useCursor: false };
  await run(payload, { supabase: db, heavyImportsEnabled: true, fetchPage: () => Promise.resolve([item]) });
  assert.equal(db.rows("anime")[0].last_synced_at, "2026-01-01T00:00:00.000Z");
  await run(payload, {
    supabase: db,
    heavyImportsEnabled: true,
    fetchPage: () => Promise.resolve([{ ...item, nextAiringEpisode: { episode: 6, airingAt: airing + 604800 } }]),
  });
  assert.equal(db.rows("anime")[0].next_episode_number, 6);
  assert.notEqual(db.rows("anime")[0].last_synced_at, "2026-01-01T00:00:00.000Z");
});

Deno.test("external link isDisabled is stored", async () => {
  const db = new Db();
  const item = { ...media(950), externalLinks: [{ site: "Crunchyroll", url: "https://cr.example/x", isDisabled: true }] };
  await run({ ...cursorRunPayload(), useCursor: false }, { supabase: db, heavyImportsEnabled: true, fetchPage: () => Promise.resolve([item]) });
  assert.equal(db.rows("external_links")[0].is_disabled, true);
});

function trackRow(db: Db, key: string) {
  return db.rows("import_track_state").find((r) => r.track_key === key);
}

Deno.test("airing track queries status_in + UPDATED_AT_DESC, sweeps to the watermark and leaves import_state alone", async () => {
  const db = new Db();
  db.seed("import_state", [{ media_type: "ANIME", last_page: 41 }]);
  db.seed("import_track_state", [{
    track_key: "anime:airing_or_releasing",
    last_page: 0,
    last_results: { cursor: { query_version: "updated_at_desc+status_releasing:v2", preset: "airing_or_releasing", mode: "updated_watermark", watermark: 10_000, sweep_top: null } },
  }]);
  const calls: { page: number; query: any }[] = [];
  const pages: Record<number, any[]> = {
    1: [{ ...media(1), updatedAt: 20_000 }, { ...media(2), updatedAt: 19_000 }],
    2: [{ ...media(3), updatedAt: 9_000 }],
  };
  const res = await run({ trackPreset: "airing_or_releasing", pagesPerBatch: 5, delayMs: 0, includeRelations: false, includeEpisodes: false }, {
    supabase: db,
    heavyImportsEnabled: true,
    fetchPage(page, _pp, _r, _e, _retries, query) {
      calls.push({ page, query });
      return Promise.resolve(pages[page] ?? []);
    },
  });
  const out = await res.json();
  assert.equal(res.status, 200);
  assert.equal(out.sweepCompleted, true);
  assert.deepEqual(calls.map((c) => c.page), [1, 2]);
  assert.equal(calls[0].query.sort, "UPDATED_AT_DESC");
  assert.deepEqual(calls[0].query.statusIn, ["RELEASING", "NOT_YET_RELEASED"]);
  const row = trackRow(db, "anime:airing_or_releasing") as any;
  assert.equal(row.last_page, 0);
  assert.equal(row.last_results.cursor.watermark, 20_000);
  assert.equal(row.last_results.cursor.sweep_top, null);
  assert.equal(row.track_preset, "airing_or_releasing");
  assert.equal(cursor(db), 41, "a tracked run must not overwrite the legacy cursor");
});

Deno.test("an unfinished sweep resumes at the next page with the same watermark", async () => {
  const db = new Db();
  db.seed("import_track_state", [{
    track_key: "anime:recent_updates",
    last_page: 0,
    last_results: { cursor: { query_version: "updated_at_desc:v2", preset: "recent_updates", mode: "updated_watermark", watermark: 1_000, sweep_top: null } },
  }]);
  const seen: number[] = [];
  const fetchPage = (page: number) => {
    seen.push(page);
    return Promise.resolve([{ ...media(page), updatedAt: 50_000 - page * 10 }]);
  };
  const payload = { trackPreset: "recent_updates", pagesPerBatch: 2, delayMs: 0, includeRelations: false, includeEpisodes: false };
  await run(payload, { supabase: db, heavyImportsEnabled: true, fetchPage });
  let row = trackRow(db, "anime:recent_updates") as any;
  assert.equal(row.last_page, 2);
  assert.equal(row.last_results.cursor.watermark, 1_000);
  assert.equal(row.last_results.cursor.sweep_top, 49_990);
  await run(payload, { supabase: db, heavyImportsEnabled: true, fetchPage });
  row = trackRow(db, "anime:recent_updates") as any;
  assert.deepEqual(seen, [1, 2, 3, 4]);
  assert.equal(row.last_page, 4);
});

Deno.test("a cursor from a different query version restarts at page 1", async () => {
  const db = new Db();
  // Legacy row from the old popularity-sorted airing preset: no cursor version, page 37.
  db.seed("import_track_state", [{ track_key: "anime:airing_or_releasing", last_page: 37, last_results: {} }]);
  const seen: number[] = [];
  await run({ trackPreset: "airing_or_releasing", pagesPerBatch: 1, delayMs: 0, includeRelations: false, includeEpisodes: false }, {
    supabase: db,
    heavyImportsEnabled: true,
    fetchPage(page) {
      seen.push(page);
      return Promise.resolve([{ ...media(1), updatedAt: 5 }]);
    },
  });
  assert.deepEqual(seen, [1]);
});

Deno.test("a popularity track keeps its legacy page cursor and stores its query version", async () => {
  const db = new Db();
  db.seed("import_track_state", [{ track_key: "anime:popularity_core", last_page: 12, last_results: {} }]);
  const seen: { page: number; sort: string }[] = [];
  await run({ trackPreset: "popularity_core", pagesPerBatch: 1, delayMs: 0 }, {
    supabase: db,
    heavyImportsEnabled: true,
    fetchPage(page, _pp, _r, _e, _retries, query) {
      seen.push({ page, sort: query.sort });
      return Promise.resolve([media(1)]);
    },
  });
  assert.deepEqual(seen, [{ page: 13, sort: "POPULARITY_DESC" }]);
  const row = trackRow(db, "anime:popularity_core") as any;
  assert.equal(row.last_page, 13);
  assert.equal(row.last_results.cursor.query_version, "popularity_desc:v1");
});

Deno.test("new_titles sorts by ID_DESC and is persisted under an allowed track_preset value", async () => {
  const db = new Db();
  const seen: string[] = [];
  await run({ trackPreset: "new_titles", pagesPerBatch: 1, delayMs: 0, includeRelations: false, initialSweepPages: 1 }, {
    supabase: db,
    heavyImportsEnabled: true,
    fetchPage(_page, _pp, _r, _e, _retries, query) {
      seen.push(query.sort);
      return Promise.resolve([media(300), media(299)]);
    },
  });
  assert.deepEqual(seen, ["ID_DESC"]);
  const row = trackRow(db, "anime:new_titles") as any;
  assert.equal(row.track_preset, "recent_updates");
  assert.equal(row.last_results.cursor.preset, "new_titles");
  assert.equal(row.last_results.cursor.watermark, 300);
  assert.equal(row.last_page, 0);
});

Deno.test("AniList page depth: the last reachable page is imported and the next page ends the list", async () => {
  // perPage 25: page 200 holds entries 4,976–5,000; AniList refuses page 201 (entry 5,025).
  const db = new Db();
  db.seed("import_state", [{ media_type: "ANIME", last_page: 199 }]);
  const fetched: number[] = [];
  const res = await run({ ...cursorRunPayload(), pagesPerBatch: 2 }, {
    supabase: db,
    heavyImportsEnabled: true,
    fetchPage(page) {
      fetched.push(page);
      return Promise.resolve([media(page * 10)]);
    },
  });
  assert.equal(res.status, 200);
  assert.deepEqual(fetched, [200], "page 201 must never be requested");
  assert.equal(cursor(db), 200);
});

Deno.test("AniList page depth: a cursor at the limit wraps to page 1 without a request", async () => {
  const db = new Db();
  db.seed("import_state", [{ media_type: "ANIME", last_page: 200 }]);
  const fetched: number[] = [];
  const res = await run(cursorRunPayload(), {
    supabase: db,
    heavyImportsEnabled: true,
    fetchPage(page) {
      fetched.push(page);
      return Promise.resolve([media(page * 10)]);
    },
  });
  assert.equal(res.status, 200);
  assert.deepEqual(fetched, []);
  assert.equal(cursor(db), 0);
  assert.equal(db.lockHeld.size, 0);
});

// ---- Voice actors (2026-11-03, owner item 4): opt-in, JAPANESE, last-good on failure ------
import { buildAnimePageQuery } from "./anilist.ts";
import { characterAge, voiceActorsOfEdge, voiceActorStaffRow } from "./mapping.ts";

Deno.test("the voice-actor fragment is only in the query when requested (default query unchanged)", () => {
  const plain = buildAnimePageQuery(true, true, false);
  assert.equal(plain.includes("voiceActors"), false);
  assert.equal(plain, buildAnimePageQuery(true, true, false, false));
  const withVoices = buildAnimePageQuery(true, false, false, true);
  assert.match(withVoices, /edges \{ role node \{ id \} voiceActors\(language: JAPANESE, sort: \[RELEVANCE, ID\]\)/);
  assert.equal(buildAnimePageQuery(false, false, false, true).includes("voiceActors"), false, "no relations, no characters, no voices");
});

Deno.test("includeVoiceActors reaches the AniList query only when the payload asks for it", async () => {
  for (const [flag, expected] of [[undefined, false], [false, false], [true, true]] as const) {
    const db = new Db();
    const transport = realTransport([{ data: { Page: { media: [] } } }]);
    const payload = { ...cursorRunPayload(), useCursor: false, includeRelations: true, lightweight: false, includeVoiceActors: flag };
    await run(payload, { supabase: db, heavyImportsEnabled: true, fetchPage: transport.fetchPage });
    assert.equal(String(transport.queries[0].query).includes("voiceActors"), expected, `flag ${flag}`);
  }
});

function voicedMedia(id: number, updatedAt: number, voices: unknown) {
  return {
    ...media(id),
    updatedAt,
    characters: {
      nodes: [
        { id: 51, name: { full: "Hero" }, age: "17" },
        { id: 52, name: { full: "Rival" }, age: "17-18" },
        { id: 53, name: { full: "Misaligned" } },
      ],
      edges: [
        { role: "MAIN", node: { id: 51 }, voiceActors: voices },
        { role: "SUPPORTING", node: { id: 52 }, voiceActors: [] },
        { role: "BACKGROUND", node: { id: 999 }, voiceActors: [{ id: 77, name: { full: "Wrong Person" } }] },
      ],
    },
  };
}

Deno.test("voice actors: stored per character in order, staff upserted without nulling, misaligned edges skipped", async () => {
  const db = new Db();
  db.seed("staff", [{ id: 900, anilist_id: 61, name_full: "Old Name", description: "Kept bio", primary_occupations: ["Voice Actor"] }]);
  const voices = [
    { id: 61, name: { full: "Kana Hanazawa", native: "花澤香菜" }, image: { large: "https://s4.anilist.co/va61.jpg" } },
    { id: 62, name: { full: "Second Voice" }, image: { large: null } },
    { id: 61, name: { full: "Duplicate" } },
    { id: 63 }, { id: 64 }, { id: -1 },
  ];
  const payload = { ...cursorRunPayload(), useCursor: false, includeRelations: true, lightweight: false, includeVoiceActors: true };
  const res = await run(payload, { supabase: db, heavyImportsEnabled: true, fetchPage: () => Promise.resolve([voicedMedia(710, 1, voices)]) });
  const out = await res.json();
  assert.equal(res.status, 200);
  assert.equal(out.results.errors, 0);
  const anime = db.rows("anime")[0];
  const hero = db.rows("characters").find((c) => c.anilist_id === 51);
  const rows = db.rows("character_voice_actors").filter((r) => r.character_id === hero?.id);
  assert.equal(rows.length, 3, "deduped and capped at 3 per character");
  assert.deepEqual(rows.map((r) => [r.anime_id, r.language, r.sort_order]), [[anime.id, "JAPANESE", 0], [anime.id, "JAPANESE", 1], [anime.id, "JAPANESE", 2]]);
  assert.equal(rows[0].staff_id, 900, "the existing staff row is reused by AniList id");
  const kana = db.rows("staff").find((s) => s.anilist_id === 61);
  assert.equal(kana?.name_full, "Kana Hanazawa");
  assert.equal(kana?.description, "Kept bio", "a voice-actor edge never nulls a stored description");
  assert.deepEqual(kana?.primary_occupations, ["Voice Actor"]);
  const second = db.rows("staff").find((s) => s.anilist_id === 62);
  assert.equal("image_large" in (second ?? {}), false, "a missing image is left out, not written as null");
  assert.equal(db.rows("staff").some((s) => s.anilist_id === 77), false, "misaligned edge: no person stored");
  assert.equal(out.results.voiceActors, 3);
  // The character age fix stays: plain numbers only.
  assert.equal(hero?.age, 17);
  assert.equal(db.rows("characters").find((c) => c.anilist_id === 52)?.age, null);
  assert.equal(characterAge("16+"), null);
});

Deno.test("voice actors: a re-import replaces the character's rows; absent voiceActors keeps them", async () => {
  const db = new Db();
  const payload = { ...cursorRunPayload(), useCursor: false, includeRelations: true, lightweight: false, includeVoiceActors: true };
  await run(payload, { supabase: db, heavyImportsEnabled: true, fetchPage: () => Promise.resolve([voicedMedia(720, 1, [{ id: 71 }, { id: 72 }])]) });
  assert.equal(db.rows("character_voice_actors").length, 2);
  await run(payload, { supabase: db, heavyImportsEnabled: true, fetchPage: () => Promise.resolve([voicedMedia(720, 2, [{ id: 72 }])]) });
  const after = db.rows("character_voice_actors");
  assert.equal(after.length, 1, "the dropped voice actor's row is removed");
  assert.equal(after[0].staff_id, db.rows("staff").find((s) => s.anilist_id === 72)?.id);
  assert.equal(after[0].sort_order, 0);
  // A run without the option (or an edge without voiceActors) leaves the stored rows alone.
  await run({ ...payload, includeVoiceActors: false }, { supabase: db, heavyImportsEnabled: true, fetchPage: () => Promise.resolve([voicedMedia(720, 3, [])]) });
  assert.equal(db.rows("character_voice_actors").length, 1);
});

Deno.test("voice actors: a failed person upsert keeps the stored rows (last-good) and counts an error", async () => {
  const db = new Db();
  const payload = { ...cursorRunPayload(), useCursor: false, includeRelations: true, lightweight: false, includeVoiceActors: true };
  await run(payload, { supabase: db, heavyImportsEnabled: true, fetchPage: () => Promise.resolve([voicedMedia(730, 1, [{ id: 81 }])]) });
  assert.equal(db.rows("character_voice_actors").length, 1);
  db.failUpsert = { table: "staff", anilistId: 82, message: "boom" };
  const res = await run(payload, { supabase: db, heavyImportsEnabled: true, fetchPage: () => Promise.resolve([voicedMedia(730, 2, [{ id: 82 }])]) });
  const out = await res.json();
  assert.equal(out.results.errors, 1);
  assert.equal(db.rows("character_voice_actors").length, 1);
  assert.equal(db.rows("character_voice_actors")[0].staff_id, db.rows("staff").find((s) => s.anilist_id === 81)?.id);
});

Deno.test("voiceActorsOfEdge / voiceActorStaffRow: pure rules", () => {
  assert.equal(voiceActorsOfEdge({ role: "MAIN" }, { id: 1 }), null, "not requested");
  assert.equal(voiceActorsOfEdge({ node: { id: 2 }, voiceActors: [{ id: 5 }] }, { id: 1 }), null, "misaligned");
  assert.deepEqual(voiceActorsOfEdge({ voiceActors: [] }, { id: 1 }), [], "AniList lists none");
  assert.deepEqual(voiceActorStaffRow({ id: 9, name: { full: " ", native: "名" }, image: { large: "http://insecure" } }), { anilist_id: 9, name_native: "名" });
});

// The voice-actor backfill runbook (docs/details-songs-2026-11-03/data/BACKFILL.md §2): its exact
// payload imports TWO pages per run and answers nextStartPage = startPage + 2, so the next run's
// startPage is always the previous nextStartPage (never a fixed step that skips pages).
Deno.test("backfill runbook payload: 2 pages per run, nextStartPage = startPage + 2, no cursor written", async () => {
  for (const startPage of [1, 3, 101]) {
    const db = new Db();
    const pages: number[] = [];
    const res = await run({
      useCursor: false,
      startPage,
      pagesPerBatch: 2,
      perPage: 10,
      runToEnd: false,
      lightweight: false,
      includeRelations: true,
      includeEpisodes: false,
      includeVoiceActors: true,
      forceRefresh: true,
      scheduleSafe: true,
      delayMs: 0,
    }, {
      supabase: db,
      heavyImportsEnabled: true,
      fetchPage(page) {
        pages.push(page);
        return Promise.resolve([media(9000 + page)]);
      },
    });
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.equal(body.success, true);
    assert.deepEqual(pages, [startPage, startPage + 1], `pages for startPage ${startPage}`);
    assert.equal(body.nextStartPage, startPage + 2);
    assert.equal(cursor(db), undefined, "the scheduled cursor moved");
  }
});

Deno.test("backfill runbook: scheduleSafe caps pagesPerBatch at 2 (a larger value never skips pages silently)", async () => {
  const db = new Db();
  const pages: number[] = [];
  const res = await run({
    useCursor: false, startPage: 7, pagesPerBatch: 4, maxPagesPerRun: 4, perPage: 10, runToEnd: false,
    lightweight: false, includeRelations: true, includeEpisodes: false, includeVoiceActors: true,
    forceRefresh: true, scheduleSafe: true, delayMs: 0,
  }, {
    supabase: db,
    heavyImportsEnabled: true,
    fetchPage(page) {
      pages.push(page);
      return Promise.resolve([media(9100 + page)]);
    },
  });
  const body = await res.json();
  assert.deepEqual(pages, [7, 8]);
  assert.equal(body.nextStartPage, 9);
});
