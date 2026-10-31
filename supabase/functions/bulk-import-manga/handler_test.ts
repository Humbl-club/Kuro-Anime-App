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
    let action: "select" | "insert" | "update" | "upsert" = "select";
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
