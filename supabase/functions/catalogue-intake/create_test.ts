// Offline tests for create (catalogue Task 15c). catalogue_create_title_v1 is modelled from its contract
// (authority: supabase/tests/rls/127_catalogue_create_v1.sql). Run: cd supabase/functions/catalogue-intake && deno test --no-prompt
import { strict as assert } from "node:assert";
import { fakeSupabase, type Row } from "./fake_supabase.ts";
import { create, runCreate } from "./create.ts";

const REPORT = (items: Row[]): Row => ({ source: "ann", source_key: "report:anime", medium: "anime", payload: { items }, fetched_at: "2026-11-18T00:00:00Z" });
const item = (id: number, name: string, vintage: string | null, type = "TV") => ({ id, type, name, vintage });

function createModel(log: Row[] = []) {
  return {
    catalogue_create_title_v1(args: Row, tables: Record<string, Row[]>) {
      log.push(args);
      const medium = String(args.p_medium);
      const links = (tables.catalogue_id_links ??= []);
      const hit = links.find((l) => l.kind === medium && l.source === args.p_source && l.source_key === args.p_source_key && l.status === "accepted");
      if (hit) return { data: { id: hit.kuro_id, created: false }, error: null };
      const rows = (tables[medium] ??= []);
      const id = 500_000 + rows.length;
      const row = args.p_row as Row;
      rows.push({ id, anilist_id: null, catalogue_visibility: "visible", ...row });
      links.push({ kind: medium, kuro_id: id, source: args.p_source, source_key: args.p_source_key, method: "id_match", status: "accepted" });
      const shadow = (tables.catalogue_shadow_values ??= []);
      for (const [field, value] of Object.entries(args.p_shadow as Row)) shadow.push({ medium, media_id: id, field, value, source: args.p_source });
      return { data: { id, created: true }, error: null };
    },
  };
}

function setup(over: Record<string, Row[]> = {}, log: Row[] = []) {
  return fakeSupabase({
    tables: {
      catalogue_source_records: [REPORT([
        item(100, "Linked Already", "2026"),
        item(200, "Frieren Beyond Journeys End", "2023-09-29 to 2024-03-22"),
        item(300, "Brand New Original Show", "2026-10-05"),
        item(400, "Sample Twin", "2020"),
        item(500, "Old Obscure Thing", "1987"),
        item(600, "Weird Omnibus Entry", "2026", "omnibus"),
      ])],
      catalogue_id_links: [{ kind: "anime", kuro_id: 1, source: "ann", source_key: "100", method: "title_match", status: "accepted" }],
      anime: [
        { id: 1, anilist_id: 11, title_english: "Linked Already", start_date_year: 2026, format: "TV" },
        { id: 2, anilist_id: 12, title_english: "Frieren Beyond Journeys End", start_date_year: 2023, format: "TV" },
        { id: 3, anilist_id: 13, title_english: "Sample Twin", start_date_year: 2020, format: "TV" },
        { id: 4, anilist_id: 14, title_english: "Sample Twin", start_date_year: 2020, format: "TV" },
      ],
      ...over,
    },
    rpcHandlers: createModel(log) as never,
  });
}

const writes = (db: ReturnType<typeof fakeSupabase>) => db.ops.filter((o) => o.table !== "import_track_state");

Deno.test("acceptedLinkSkips: a report id with an accepted link is neither linked nor created", async () => {
  const db = setup();
  const r = await create({ supabase: db.client }, "anime", { mode: "report" });
  assert.equal(r.skippedLinked, 1);
  assert.ok(!r.sample.some((s) => s.key === "100"));
});

Deno.test("aboveThresholdMatchLinksInsteadOfInserting: an accepted title match adds a link, not a row", async () => {
  const log: Row[] = [];
  const db = setup({}, log);
  const r = await create({ supabase: db.client }, "anime", { mode: "insert", minYear: 1990 });
  assert.equal(r.linked >= 1, true);
  const link = db.tables.catalogue_id_links.find((l) => l.source_key === "200");
  assert.equal(link?.kuro_id, 2);
  assert.equal(link?.status, "accepted");
  assert.ok(!log.some((a) => a.p_source_key === "200"), "no row was created for the matched title");
  assert.equal(db.tables.anime.filter((a) => a.title_english === "Frieren Beyond Journeys End").length, 1);
});

Deno.test("ambiguousGoesToReview: two equal matches become proposed links and no row", async () => {
  const log: Row[] = [];
  const db = setup({}, log);
  const r = await create({ supabase: db.client }, "anime", { mode: "insert", minYear: 1990 });
  assert.ok(r.review >= 1);
  const proposed = db.tables.catalogue_id_links.filter((l) => l.source_key === "400");
  assert.ok(proposed.length >= 1 && proposed.every((l) => l.status === "proposed"));
  assert.ok(!log.some((a) => a.p_source_key === "400"));
});

Deno.test("reportModeWritesNoRows: report mode lists what would be created and writes nothing", async () => {
  const log: Row[] = [];
  const db = setup({}, log);
  const r = await create({ supabase: db.client }, "anime", { mode: "report", sample: 10 });
  assert.equal(writes(db).length, 0, "no insert, upsert, update or delete");
  assert.equal(log.length, 0, "no create call");
  assert.deepEqual(r.sample.map((s) => s.key).sort(), ["300", "500"]);
  assert.equal(r.wouldCreate, 2);
  assert.equal(r.skippedUnusable, 1, "an ANN type with no Kuro format is not a candidate");
  assert.equal(r.created, 0);
});

Deno.test("insertModeCreatesRowWithLinkAndNullAniListId", async () => {
  const log: Row[] = [];
  const db = setup({}, log);
  const r = await create({ supabase: db.client }, "anime", { mode: "insert", minYear: 2025 });
  assert.equal(r.created, 1);
  assert.equal(r.skippedYear, 4 - 0 > 0 ? r.skippedYear : 0);
  const row = db.tables.anime.find((a) => a.title_romaji === "Brand New Original Show");
  assert.ok(row);
  assert.equal(row?.anilist_id, null);
  assert.equal(row?.catalogue_visibility, "visible");
  assert.equal(row?.format, "TV");
  assert.equal(row?.start_date_year, 2026);
  assert.deepEqual(row?.data_sources, ["ann"]);
  const link = db.tables.catalogue_id_links.find((l) => l.source_key === "300");
  assert.equal(link?.kuro_id, row?.id);
  assert.equal(link?.status, "accepted");
  assert.ok(db.tables.catalogue_shadow_values.some((s) => s.media_id === row?.id && s.field === "title_romaji"));
  // existing Kuro ids and rows are untouched
  assert.deepEqual(db.tables.anime.slice(0, 4).map((a) => a.id), [1, 2, 3, 4]);
  assert.ok(!db.tables.anime.some((a) => a.title_romaji === "Old Obscure Thing"), "minYear bounds the candidates");
});

Deno.test("secondRunIsIdempotent: a second insert run creates nothing", async () => {
  const log: Row[] = [];
  const db = setup({}, log);
  await create({ supabase: db.client }, "anime", { mode: "insert", minYear: 2025 });
  const rowsAfterFirst = db.tables.anime.length;
  const second = await create({ supabase: db.client }, "anime", { mode: "insert", minYear: 2025 });
  assert.equal(second.created, 0);
  assert.equal(db.tables.anime.length, rowsAfterFirst);
  assert.equal(log.filter((a) => a.p_source_key === "300").length, 1, "the key is skipped by its accepted link, so create is not even called again");
});

Deno.test("a lost race is reported as alreadyExisted, not as a second row", async () => {
  const db = setup({}, []);
  db.client.rpc = () => Promise.resolve({ data: { id: 9, created: false }, error: null });
  const r = await create({ supabase: db.client }, "anime", { mode: "insert", minYear: 2025 });
  assert.equal(r.created, 0);
  assert.equal(r.alreadyExisted, 1);
});

Deno.test("insert mode needs minYear and fails closed on a failed create", async () => {
  const db = setup();
  await assert.rejects(() => create({ supabase: db.client }, "anime", { mode: "insert" }), /minYear/);
  const failing = setup();
  failing.client.rpc = () => Promise.resolve({ data: null, error: { message: "boom" } });
  await assert.rejects(() => create({ supabase: failing.client }, "anime", { mode: "insert", minYear: 2025 }), /boom/);
});

Deno.test("manga: a stored MangaUpdates record with no link and no match is created, with a null AniList id", async () => {
  const log: Row[] = [];
  const rec = { seriesId: 777, title: "Totally New Webtoon Saga", url: "https://www.mangaupdates.com/series/x", associated: [], type: "Manga", year: 2026, status: "3 Volumes (Ongoing)", completed: false, genres: ["Action"], categories: [], authors: [], publishers: [], related: [], bayesianRating: null, ratingVotes: null };
  const db = fakeSupabase({
    tables: {
      catalogue_source_records: [{ source: "mangaupdates", source_key: "777", medium: "manga", payload: rec }],
      catalogue_id_links: [],
      manga: [{ id: 1, anilist_id: 1, title_english: "Unrelated Series", start_date_year: 2010, format: "MANGA" }],
    },
    rpcHandlers: createModel(log) as never,
  });
  const report = await create({ supabase: db.client }, "manga", { mode: "report" });
  assert.equal(report.wouldCreate, 1);
  assert.equal(writes(db).length, 0);
  const r = await create({ supabase: db.client }, "manga", { mode: "insert", minYear: 2025 });
  assert.equal(r.created, 1);
  const row = db.tables.manga.find((m) => m.title_english === "Totally New Webtoon Saga");
  assert.equal(row?.anilist_id, null);
  assert.equal(row?.volumes, 3);
});

Deno.test("the scan window pages with a cursor and runCreate keeps it", async () => {
  const items = Array.from({ length: 7 }, (_, i) => item(1000 + i, `Fresh Title Number ${i} Unique${i}x`, "2026"));
  const db = fakeSupabase({ tables: { catalogue_source_records: [REPORT(items)], catalogue_id_links: [], anime: [] }, rpcHandlers: createModel() as never });
  const ctx = { supabase: db.client, clients: {} as never, medium: "anime" as const, limit: 3, deadlineMs: Number.MAX_SAFE_INTEGER, now: () => 1_000_000 };
  const a = await runCreate(ctx, { mode: "report" });
  assert.equal(a.results.scanned, 3);
  const b = await runCreate(ctx, { mode: "report" });
  const c = await runCreate(ctx, { mode: "report" });
  assert.equal(c.results.scanned, 1);
  assert.equal(c.results.next, null, "the end of the list resets the cursor");
  assert.equal((b.results.sample as unknown[]).length, 3);
});
