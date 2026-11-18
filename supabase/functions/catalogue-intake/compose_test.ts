// Offline tests for the shadow composer (catalogue Task 7). Fake supabase only; records are real
// captures (fixtures/README.md) or hand-built. Run: cd supabase/functions/catalogue-intake && deno test --no-prompt
import { strict as assert } from "node:assert";
import { fakeSupabase, type Row } from "./fake_supabase.ts";
import { compose, runCompose } from "./compose.ts";
import { parseAnnApi } from "./ann.ts";
import { parseMuSeries } from "./mangaupdates.ts";
import { ANN_API_ONE } from "./fixtures/ann_fixtures.ts";
import seriesBerserk from "./fixtures/mu_series_berserk.json" with { type: "json" };

const annRecord = parseAnnApi(ANN_API_ONE).records[0];
const muRecord = parseMuSeries(seriesBerserk)!;

const link = (kind: string, kuro_id: number, source: string, source_key: string, status = "accepted"): Row => ({ kind, kuro_id, source, source_key, method: "wikidata", status });
const rec = (source: string, source_key: string, medium: string, payload: unknown): Row => ({ source, source_key, medium, payload, payload_hash: "h", licence: "x" });
const wd = (qid: string, medium: string, props: Record<string, string[]>) => rec("wikidata", qid, medium, { qid, medium, anilist_ids: [], props });

const shadow = (db: ReturnType<typeof fakeSupabase>, field: string, mediaId = 1) =>
  db.tables.catalogue_shadow_values?.find((r) => r.field === field && r.media_id === mediaId);

function animeDb(extra: { links?: Row[]; records?: Row[]; anime?: Row[] } = {}) {
  return fakeSupabase({
    tables: {
      anime: extra.anime ?? [{ id: 1, is_adult: false }, { id: 2, is_adult: false }],
      catalogue_id_links: [link("anime", 1, "wikidata", "Q1"), link("anime", 1, "ann", "4658"), ...(extra.links ?? [])],
      catalogue_source_records: [
        wd("Q1", "anime", { "label:en": ["Jinki Extend"], "label:ja": ["ジンキ"], P580: ["2005-01-01T00:00:00Z"], P1113: ["12"] }),
        rec("ann", "4658", "anime", annRecord),
        ...(extra.records ?? []),
      ],
    },
  });
}

Deno.test("writesDataSources", async () => {
  const db = animeDb();
  const res = await compose({ supabase: db.client }, "anime", [1]);
  assert.ok(res.written > 0);
  // Wikidata wins titles and native; ANN wins romaji and format; both used.
  assert.equal(shadow(db, "title_english")?.source, "wikidata");
  assert.equal(shadow(db, "title_english")?.value, "Jinki Extend");
  assert.equal(shadow(db, "title_romaji")?.source, "ann");
  assert.equal(shadow(db, "format")?.value, "TV");
  const ds = shadow(db, "data_sources");
  assert.ok(Array.isArray(ds?.value));
  assert.deepEqual([...(ds?.value as string[])].sort(), ["ann", "wikidata"]);
  // ordered by number of fields used, most first
  const counts = new Map<string, number>();
  for (const r of db.tables.catalogue_shadow_values) if (r.field !== "data_sources" && !String(r.field).startsWith("credits:proposed") && !String(r.field).startsWith("credits:review") && typeof r.source === "string") counts.set(r.source as string, (counts.get(r.source as string) ?? 0) + 1);
  const ordered = [...counts.entries()].sort((a, b) => b[1] - a[1]).map(([s]) => s);
  assert.deepEqual(ds?.value, ordered);
});

Deno.test("idempotentSecondRunNoWrites", async () => {
  const db = animeDb();
  await compose({ supabase: db.client }, "anime", [1]);
  const before = db.opsOn("catalogue_shadow_values").length;
  const again = await compose({ supabase: db.client }, "anime", [1]);
  assert.equal(again.written, 0);
  assert.equal(db.opsOn("catalogue_shadow_values").length, before);
});

Deno.test("proposedLinkIsNotUsed", async () => {
  const db = animeDb();
  db.tables.catalogue_id_links = db.tables.catalogue_id_links.map((l) => (l.source === "ann" ? { ...l, status: "proposed" } : l));
  await compose({ supabase: db.client }, "anime", [1]);
  assert.deepEqual(shadow(db, "data_sources")?.value, ["wikidata"]);
  assert.equal(shadow(db, "format"), undefined);
});

Deno.test("dateTripleComesFromOneSource", async () => {
  // Wikidata has the start year only (01-01 reads as year-only) and wins the year; ANN's month and
  // day must not be mixed in.
  const db = animeDb();
  await compose({ supabase: db.client }, "anime", [1]);
  assert.equal(shadow(db, "start_date_year")?.source, "wikidata");
  assert.equal(shadow(db, "start_date_month"), undefined);
  assert.equal(shadow(db, "start_date_day"), undefined);
});

Deno.test("adultStaysAdultAndGoesToReview", async () => {
  const db = animeDb({ anime: [{ id: 1, is_adult: true }] });
  await compose({ supabase: db.client }, "anime", [1]);
  assert.equal(shadow(db, "is_adult")?.value, true);
  const review = shadow(db, "review:adult");
  assert.ok(review, "review row written");
  assert.equal((review?.value as { reason: string }).reason, "adult_today_no_source_says_adult");
});

Deno.test("sourceSaysAdultWinsAndIsListedAsNewlyAdult", async () => {
  const adultAnn = { ...annRecord, genres: ["erotica"] };
  const db = animeDb({ records: [] });
  db.tables.catalogue_source_records = db.tables.catalogue_source_records.map((r) => (r.source === "ann" ? { ...r, payload: adultAnn } : r));
  await compose({ supabase: db.client }, "anime", [1]);
  assert.equal(shadow(db, "is_adult")?.value, true);
  assert.equal((shadow(db, "review:adult")?.value as { reason: string }).reason, "newly_adult");
});

Deno.test("noAdultDataKeepsTodayWithoutReview", async () => {
  const db = fakeSupabase({
    tables: {
      anime: [{ id: 1, is_adult: false }],
      catalogue_id_links: [link("anime", 1, "wikidata", "Q1")],
      catalogue_source_records: [wd("Q1", "anime", { "label:en": ["X"] })],
    },
  });
  await compose({ supabase: db.client }, "anime", [1]);
  assert.equal(shadow(db, "is_adult"), undefined);
  assert.equal(shadow(db, "review:adult"), undefined);
});

Deno.test("relationsResolveThroughAcceptedLinksOnly", async () => {
  const db = animeDb({
    links: [link("anime", 2, "wikidata", "Q2")],
    records: [],
  });
  db.tables.catalogue_source_records = db.tables.catalogue_source_records.map((r) =>
    r.source === "wikidata" ? { ...r, payload: { ...(r.payload as object), props: { ...(r.payload as { props: object }).props, P156: ["Q2", "Q777"] } } } : r,
  );
  await compose({ supabase: db.client }, "anime", [1]);
  assert.deepEqual(shadow(db, "relations")?.value, [{ type: "SEQUEL", kind: "anime", target_id: 2, sources: ["wikidata"], status: "accepted" }]);
});

Deno.test("mangaFactsComeFromMangaUpdates", async () => {
  const db = fakeSupabase({
    tables: {
      manga: [{ id: 5, is_adult: false }],
      catalogue_id_links: [link("manga", 5, "mangaupdates", String(muRecord.seriesId))],
      catalogue_source_records: [rec("mangaupdates", String(muRecord.seriesId), "manga", muRecord)],
    },
  });
  await compose({ supabase: db.client }, "manga", [5]);
  assert.equal(shadow(db, "format", 5)?.value, "MANGA");
  assert.equal(shadow(db, "status", 5)?.value, "RELEASING");
  assert.equal(shadow(db, "volumes", 5)?.value, 43);
  assert.equal(shadow(db, "start_date_year", 5)?.value, 1989);
  assert.equal(shadow(db, "country_of_origin", 5)?.value, "JP");
  assert.equal(shadow(db, "title_native", 5), undefined);
});

Deno.test("runComposeAdvancesCursorOverLinkedTitles", async () => {
  const db = animeDb();
  const out = await runCompose({ supabase: db.client, clients: {} as never, medium: "anime", limit: 10, deadlineMs: Date.now() + 10_000, now: Date.now });
  assert.equal((out.results as { titles: number }).titles, 1);
  assert.ok(db.tables.import_track_state?.some((r) => r.track_key === "catalogue-intake:compose:anime"));
});

Deno.test("composeWritesCreditsInShadowWithoutInsertingEntities", async () => {
  const db = animeDb();
  db.tables.staff = [{ id: 8, anilist_id: 1, name_full: "Toshiro Tsuchida", name_native: null, name_romaji: null }];
  const person = annRecord.staff[0];
  db.tables.staff[0].name_full = person.name;
  db.tables.anime_staff = [{ anime_id: 1, staff_id: 8 }];
  await compose({ supabase: db.client }, "anime", [1]);
  const credits = shadow(db, "credits:staff")?.value as { kuro_id: number; role: string }[];
  assert.ok(credits.some((c) => c.kuro_id === 8));
  assert.equal(db.opsOn("staff").length, 0);
  assert.equal(db.opsOn("studios").length, 0);
  assert.ok(shadow(db, "credits:proposed_entities"), "unmatched credits are proposals");
  const before = db.opsOn("catalogue_shadow_values").length;
  const again = await compose({ supabase: db.client }, "anime", [1]);
  assert.equal(again.written, 0, "second run writes nothing, credits included");
  assert.equal(db.opsOn("catalogue_shadow_values").length, before);
});
