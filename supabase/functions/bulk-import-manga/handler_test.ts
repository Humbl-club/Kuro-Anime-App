// Offline run tests for bulk-import-manga. They call the real run() with an in-memory
// table stand-in and an injected AniList page fetch. No network. Not a Supabase test.
// The stand-in lives in this file so production index.ts never imports it.
// Run: deno test --no-prompt supabase/functions/bulk-import-manga/handler_test.ts
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
    title: { romaji: `Manga ${id}`, english: `Manga ${id}` },
    format: "MANGA",
    status: "FINISHED",
    chapters: 20,
    volumes: 2,
    updatedAt: 1_700_000_000,
  };
}

function cursor(db: Db): number | undefined {
  return db.rows("import_state").find((r) => r.media_type === "MANGA")?.last_page as number | undefined;
}

Deno.test("successful batch persists the fetched page, advances the cursor, and releases the lock", async () => {
  const db = new Db();
  db.seed("import_state", [{ media_type: "MANGA", last_page: 4 }]);
  const pages: number[] = [];
  const res = await run({
    useCursor: true,
    lightweight: true,
    pagesPerBatch: 1,
    perPage: 25,
    delayMs: 0,
    runToEnd: false,
    includeRelations: false,
    includeChapters: false,
    includeVolumes: false,
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
  assert.equal(body.results.manga, 1);
  assert.equal(body.results.chapters, 0);
  assert.equal(body.results.errors, 0);
  assert.equal(body.nextStartPage, 6);
  assert.equal(body.trackKey, null);
  assert.equal(body.trackPreset, null);
  assert.deepEqual(pages, [5]);
  assert.equal(cursor(db), 5);
  const row = db.rows("manga").find((r) => r.anilist_id === 501);
  assert.equal(row?.title_romaji, "Manga 501");
  assert.equal(row?.chapters, 20);
  assert.deepEqual(db.rpcs.map((r) => r.name), ["acquire_import_lock", "release_import_lock"]);
  assert.equal(db.rpcs[0].args.p_key, "manga");
  assert.equal(db.lockHeld.size, 0);
  assert.equal(db.rows("import_runs")[0].status, "success");
});

Deno.test("provider failure releases the lock and does not advance the cursor past unpersisted work", async () => {
  const db = new Db();
  db.seed("import_state", [{ media_type: "MANGA", last_page: 4 }]);
  const pages: number[] = [];
  const res = await run({
    useCursor: true,
    lightweight: true,
    pagesPerBatch: 2,
    perPage: 25,
    delayMs: 0,
    runToEnd: false,
    includeRelations: false,
    includeChapters: false,
    includeVolumes: false,
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
  assert.deepEqual(db.rows("manga").map((r) => r.anilist_id), [501]);
  assert.deepEqual(db.rpcs.map((r) => r.name), ["acquire_import_lock", "release_import_lock"]);
  assert.equal(db.rpcs[0].args.p_key, "manga");
  assert.equal(db.rpcs[1].args.p_key, "manga");
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
    includeChapters: false,
    includeVolumes: false,
  };
}

Deno.test("lock rpc error does not import, write the catalog, advance the cursor, or release", async () => {
  const db = new Db();
  db.lockMode = "error";
  db.lockErrorMessage = "lock rpc failed";
  db.seed("import_state", [{ media_type: "MANGA", last_page: 4 }]);
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
  assert.equal(db.rows("manga").length, 0);
  assert.equal(cursor(db), 4);
  assert.deepEqual(db.rpcs.map((r) => r.name), ["acquire_import_lock"]);
  assert.equal(db.rows("import_runs")[0].status, "error");
  assert.equal(db.rows("import_runs")[0].message, "lock rpc failed");
});

Deno.test("lock rpc throw does not import, write the catalog, advance the cursor, or release", async () => {
  const db = new Db();
  db.lockMode = "throw";
  db.lockErrorMessage = "lock rpc threw";
  db.seed("import_state", [{ media_type: "MANGA", last_page: 4 }]);
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
  assert.equal(db.rows("manga").length, 0);
  assert.equal(cursor(db), 4);
  assert.deepEqual(db.rpcs.map((r) => r.name), ["acquire_import_lock"]);
  assert.notEqual(db.rows("import_runs")[0].status, "success");
});

Deno.test("busy lock (rpc false) skips without importing or releasing", async () => {
  const db = new Db();
  db.lockHeld.add("manga");
  db.seed("import_state", [{ media_type: "MANGA", last_page: 4 }]);
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
  assert.equal(db.rows("manga").length, 0);
  assert.equal(cursor(db), 4);
  assert.deepEqual(db.rpcs.map((r) => r.name), ["acquire_import_lock"]);
  assert.equal(db.rpcs[0].args.p_key, "manga");
  assert.equal(db.lockHeld.has("manga"), true);
  assert.equal(db.rows("import_runs")[0].status, "skipped");
  assert.equal(db.rows("import_runs")[0].message, "locked");
});

Deno.test("busy lock (rpc null) skips without importing or releasing", async () => {
  const db = new Db();
  db.lockMode = "null";
  db.seed("import_state", [{ media_type: "MANGA", last_page: 4 }]);
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
  assert.equal(db.rows("manga").length, 0);
  assert.equal(cursor(db), 4);
  assert.deepEqual(db.rpcs.map((r) => r.name), ["acquire_import_lock"]);
  assert.equal(db.rows("import_runs")[0].status, "skipped");
});

Deno.test("a failed primary upsert does not complete the page, and replaying it is idempotent", async () => {
  const db = new Db();
  db.seed("import_state", [{ media_type: "MANGA", last_page: 4 }]);
  db.failUpsert = { table: "manga", anilistId: 502, message: "manga upsert failed" };
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
  assert.equal(body.error, "manga upsert failed");
  assert.equal(cursor(db), 4);
  assert.deepEqual(db.rows("manga").map((r) => r.anilist_id).sort(), [501, 503]);
  assert.equal(db.rows("import_runs")[0].status, "error");
  assert.notEqual(db.rows("import_runs")[0].status, "success");
  const firstResults = db.rows("import_runs")[0].results as { manga: number; errors: number };
  assert.equal(firstResults.manga, 2);
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
  assert.deepEqual(db.rows("manga").map((r) => r.anilist_id).sort(), [501, 502, 503]);
  assert.equal(db.rows("manga").length, 3);
  assert.equal(db.rows("import_runs").at(-1)?.status, "success");
});

// ---------------------------------------------------------------------------
// 2026-11-01 intake robustness: provider errors, per-track queries, clobber guards.
// ---------------------------------------------------------------------------
import { AniListError, AniListLimiter, createAniListClient } from "../_shared/anilist_client.ts";
import { fetchAniListMangaData } from "./anilist.ts";

function realTransport(bodies: unknown[]) {
  const queries: { query: string; variables: Record<string, unknown> }[] = [];
  const client = createAniListClient({
    limiter: new AniListLimiter(0),
    sleep: () => Promise.resolve(),
    random: () => 0,
    fetch: (_input, init) => {
      queries.push(JSON.parse(String(init?.body)));
      return Promise.resolve(new Response(JSON.stringify(bodies.shift()), { status: 200, headers: { "Content-Type": "application/json" } }));
    },
  });
  return {
    queries,
    fetchPage: (page: number, perPage: number, rel: boolean, retries: number, query: any) =>
      fetchAniListMangaData(page, perPage, rel, retries, query, client),
  };
}

for (const [label, body] of [
  ["200 with GraphQL errors", { data: null, errors: [{ message: "Internal Server Error" }] }],
  ["200 without data.Page", { data: {} }],
] as const) {
  Deno.test(`${label} is a failed run: no cursor wrap, no advance, lock released`, async () => {
    const db = new Db();
    db.seed("import_state", [{ media_type: "MANGA", last_page: 4 }]);
    const transport = realTransport([body]);
    const res = await run(cursorRunPayload(), { supabase: db, heavyImportsEnabled: true, fetchPage: transport.fetchPage });
    assert.equal(res.status, 500);
    assert.equal(cursor(db), 4);
    assert.equal(db.rows("import_runs")[0].status, "error");
    assert.equal(db.lockHeld.size, 0);
  });
}

Deno.test("a rate-limit stop before any request commits persisted pages and does not wrap", async () => {
  const db = new Db();
  db.seed("import_state", [{ media_type: "MANGA", last_page: 4 }]);
  const res = await run({ ...cursorRunPayload(), pagesPerBatch: 3 }, {
    supabase: db,
    heavyImportsEnabled: true,
    fetchPage(page) {
      if (page === 6) return Promise.reject(new AniListError("rate_limited", "paused"));
      return Promise.resolve([media(page * 10)]);
    },
  });
  const out = await res.json();
  assert.equal(res.status, 200);
  assert.equal(out.stoppedEarly, "rate_limited");
  assert.equal(cursor(db), 5);
});

Deno.test("a null AniList chapter count never overwrites a known count and next_chapter_* is not written", async () => {
  const db = new Db();
  db.seed("manga", [{
    id: 1,
    anilist_id: 77,
    updated_at_anilist: new Date(1 * 1000).toISOString(),
    chapters: 1196,
    volumes: 113,
    next_chapter_number: 1197,
    description: "Pirates.",
    cover_image_large: "https://x.supabase.co/storage/v1/object/public/media/manga/77.webp",
    synopsis_enhanced_state: "done",
  }]);
  const item = { ...media(77), updatedAt: 2, status: "RELEASING", chapters: null, volumes: null, description: "Pirates.", coverImage: { large: "https://s4.anilist.co/77.jpg" } };
  const res = await run({ ...cursorRunPayload(), useCursor: false }, { supabase: db, heavyImportsEnabled: true, fetchPage: () => Promise.resolve([item]) });
  assert.equal(res.status, 200);
  const row = db.rows("manga")[0];
  assert.equal(row.chapters, 1196);
  assert.equal(row.volumes, 113);
  assert.equal(row.next_chapter_number, 1197, "bulk import must not null next_chapter_*");
  assert.equal(row.status, "RELEASING");
  assert.equal(row.cover_image_large, "https://x.supabase.co/storage/v1/object/public/media/manga/77.webp");
  assert.equal(row.synopsis_enhanced_state, "done");
  assert.equal(db.rows("manga").length, 1);
});

Deno.test("an unchanged manga gets no write (last_synced_at untouched)", async () => {
  const db = new Db();
  db.seed("manga", [{ id: 1, anilist_id: 78, updated_at_anilist: new Date(1_700_000_000 * 1000).toISOString(), last_synced_at: "2026-01-01T00:00:00.000Z" }]);
  await run({ ...cursorRunPayload(), useCursor: false }, { supabase: db, heavyImportsEnabled: true, fetchPage: () => Promise.resolve([media(78)]) });
  assert.equal(db.rows("manga")[0].last_synced_at, "2026-01-01T00:00:00.000Z");
});

Deno.test("manga join-table re-imports update in place", async () => {
  const db = new Db();
  const item = (rank: number, updatedAt: number) => ({
    ...media(79),
    updatedAt,
    tags: [{ id: 9, name: "Seinen", rank }],
    staff: { nodes: [{ id: 6, name: { full: "B" } }], edges: [{ role: "Story" }] },
    characters: { nodes: [{ id: 5, name: { full: "A" } }], edges: [{ role: "MAIN" }] },
    externalLinks: [{ site: "Viz", url: "https://viz.example/x", isDisabled: true }],
  });
  const payload = { ...cursorRunPayload(), useCursor: false, includeRelations: true, lightweight: false };
  await run(payload, { supabase: db, heavyImportsEnabled: true, fetchPage: () => Promise.resolve([item(60, 1)]) });
  const second = await run(payload, { supabase: db, heavyImportsEnabled: true, fetchPage: () => Promise.resolve([item(90, 2)]) });
  assert.equal((await second.json()).results.errors, 0);
  assert.equal(db.rows("manga_tags").length, 1);
  assert.equal(db.rows("manga_tags")[0].rank, 90);
  assert.equal(db.rows("manga_authors").length, 1);
  assert.equal(db.rows("manga_staff").length, 1);
  assert.equal(db.rows("manga_characters").length, 1);
  assert.equal(db.rows("external_links")[0].is_disabled, true);
});

Deno.test("manga releasing track uses status_in + UPDATED_AT_DESC and its own cursor", async () => {
  const db = new Db();
  db.seed("import_state", [{ media_type: "MANGA", last_page: 9 }]);
  const transport = realTransport([{ data: { Page: { media: [{ ...media(80), updatedAt: 50 }] } } }]);
  const res = await run({ trackPreset: "airing_or_releasing", pagesPerBatch: 1, delayMs: 0, includeRelations: false, initialSweepPages: 1 }, {
    supabase: db,
    heavyImportsEnabled: true,
    fetchPage: transport.fetchPage,
  });
  assert.equal(res.status, 200);
  assert.deepEqual(transport.queries[0].variables.sort, ["UPDATED_AT_DESC"]);
  assert.deepEqual(transport.queries[0].variables.statusIn, ["RELEASING", "NOT_YET_RELEASED"]);
  assert.match(transport.queries[0].query, /status_in: \$statusIn/);
  const row = db.rows("import_track_state").find((r) => r.track_key === "manga:airing_or_releasing") as any;
  assert.equal(row.last_results.cursor.watermark, 50);
  assert.equal(cursor(db), 9);
});

Deno.test("AniList page depth: the last reachable page is imported and the next page ends the list", async () => {
  // perPage 25: page 200 holds entries 4,976–5,000; AniList refuses page 201 (entry 5,025).
  const db = new Db();
  db.seed("import_state", [{ media_type: "MANGA", last_page: 199 }]);
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
  db.seed("import_state", [{ media_type: "MANGA", last_page: 200 }]);
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

import { characterAge } from "../bulk-import-anime/mapping.ts";

Deno.test("character age: only a plain whole number is stored (AniList ages are free text)", () => {
  assert.equal(characterAge("17"), 17);
  assert.equal(characterAge(" 30 "), 30);
  assert.equal(characterAge(16), 16);
  for (const raw of ["17-18", "16+", "15 (Past) 18 (Present)", "", null, undefined, "abc", 1.5, -3, "99999999999"]) {
    assert.equal(characterAge(raw), null, `"${raw}" is not a plain age`);
  }
});
