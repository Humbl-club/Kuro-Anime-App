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
  for (const r of db.tables.catalogue_shadow_values) if (r.field !== "data_sources" && !String(r.field).startsWith("credits:proposed") && !String(r.field).startsWith("credits:review") && typeof r.source === "string" && r.source !== "kuro_index") counts.set(r.source as string, (counts.get(r.source as string) ?? 0) + 1);
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

Deno.test("popularityFieldsAreShadowedFromPageviewsVotesAndListAdds", async () => {
  const db = animeDb({ records: [rec("pageviews", "1", "anime", { total365: 120_000, last30: 5_100, prev30: 100 })] });
  const votes = annRecord.ratings?.votes ?? 0;
  db.tables.anime_user_lists = [
    { id: 1, user_id: "u1", anime_id: 1 },
    { id: 2, user_id: "u2", anime_id: 1 },
    { id: 3, user_id: "u3", anime_id: 1 },
    { id: 4, user_id: "u3", anime_id: 2 },
  ];
  await compose({ supabase: db.client }, "anime", [1]);
  assert.equal(shadow(db, "popularity")?.value, 200 + votes + 150);
  assert.equal(shadow(db, "popularity")?.source, "kuro_index");
  assert.equal(shadow(db, "trending")?.value, 50);
  // Only counts reach the shadow table: no user id is stored.
  assert.ok(!JSON.stringify(db.tables.catalogue_shadow_values).includes("u1"));
  const before = db.opsOn("catalogue_shadow_values").length;
  const again = await compose({ supabase: db.client }, "anime", [1]);
  assert.equal(again.written, 0);
  assert.equal(db.opsOn("catalogue_shadow_values").length, before);
});

Deno.test("popularityScoreNeedsTwentyVotesAndTitleWithoutInputsGetsNoPopularity", async () => {
  const lowVotes = { ...annRecord, ratings: { votes: 5, weighted: 8, bayesian: 8 } };
  const db = animeDb({ records: [] });
  db.tables.catalogue_source_records = db.tables.catalogue_source_records.map((r) => (r.source === "ann" ? { ...r, payload: lowVotes } : r));
  await compose({ supabase: db.client }, "anime", [1]);
  assert.equal(shadow(db, "average_score"), undefined, "5 votes give no score");
  const enough = { ...annRecord, ratings: { votes: 40, weighted: 7.5, bayesian: 7 } };
  db.tables.catalogue_source_records = db.tables.catalogue_source_records.map((r) => (r.source === "ann" ? { ...r, payload: enough } : r));
  await compose({ supabase: db.client }, "anime", [1]);
  assert.equal(shadow(db, "average_score")?.value, 75);
  // A title with no pageviews, votes or list adds has no popularity field.
  const bare = fakeSupabase({ tables: { anime: [{ id: 9, is_adult: false }], catalogue_id_links: [link("anime", 9, "wikidata", "Q9")], catalogue_source_records: [wd("Q9", "anime", { "label:en": ["X"] })] } });
  await compose({ supabase: bare.client }, "anime", [9]);
  assert.equal(shadow(bare, "popularity", 9), undefined);
});

const TAG_MAP = [
  { source: "ann", source_label: "Drama", tag_id: 11, weight: 1 },
  { source: "ann", source_label: "mecha", tag_id: 12, weight: 1 },
  { source: "wikidata", source_label: "Q777", tag_id: 12, weight: 0.5 },
  { source: "mangaupdates", source_label: "Action", tag_id: 21, weight: 1 },
  { source: "mangaupdates", source_label: "Time Travel", tag_id: 22, weight: 1 },
];
const tagRpc = (rows: unknown) => ({ catalogue_tag_map_v1: () => ({ data: rows, error: null }) });

Deno.test("tagsListIsShadowedFromTheReviewedMap", async () => {
  const db = fakeSupabase({
    tables: {
      anime: [{ id: 1, is_adult: false }],
      catalogue_id_links: [link("anime", 1, "wikidata", "Q1"), link("anime", 1, "ann", "4658")],
      catalogue_source_records: [wd("Q1", "anime", { "label:en": ["Jinki Extend"], P136: ["Q777"] }), rec("ann", "4658", "anime", annRecord)],
    },
    rpcHandlers: tagRpc(TAG_MAP),
  });
  await compose({ supabase: db.client }, "anime", [1]);
  const tags = shadow(db, "tags:list");
  assert.deepEqual(tags?.value, [{ tag_id: 12, rank: 100 }, { tag_id: 11, rank: 67 }]);
  assert.equal(tags?.source, "kuro_tag_map");
  const again = await compose({ supabase: db.client }, "anime", [1]);
  assert.equal(again.written, 0, "second run writes nothing");
});

Deno.test("noTagsListWhenTheMapIsEmptyOrNothingMatches", async () => {
  // The map table holds only reviewed rows; an unreviewed map is an empty one.
  for (const rows of [[], null, [{ source: "ann", source_label: "Nothing", tag_id: 1, weight: 1 }]]) {
    const db = fakeSupabase({
      tables: { anime: [{ id: 1, is_adult: false }], catalogue_id_links: [link("anime", 1, "ann", "4658")], catalogue_source_records: [rec("ann", "4658", "anime", annRecord)] },
      rpcHandlers: tagRpc(rows),
    });
    await compose({ supabase: db.client }, "anime", [1]);
    assert.equal(shadow(db, "tags:list"), undefined);
  }
});

Deno.test("mangaTagsCountCategoriesOnlyWithTwoPositiveVotes", async () => {
  const record = { ...muRecord, categories: [{ category: "Time Travel", votes: 9, votesPlus: 1, votesMinus: 8 }] };
  const make = (r: unknown) =>
    fakeSupabase({
      tables: {
        manga: [{ id: 5, is_adult: false }],
        catalogue_id_links: [link("manga", 5, "mangaupdates", String(muRecord.seriesId))],
        catalogue_source_records: [rec("mangaupdates", String(muRecord.seriesId), "manga", r)],
      },
      rpcHandlers: tagRpc(TAG_MAP),
    });
  const one = make(record);
  await compose({ supabase: one.client }, "manga", [5]);
  assert.deepEqual(shadow(one, "tags:list", 5)?.value, [{ tag_id: 21, rank: 100 }], "one positive vote: the category is ignored, the genre counts");
  const two = make({ ...record, categories: [{ category: "Time Travel", votes: 9, votesPlus: 2, votesMinus: 7 }] });
  await compose({ supabase: two.client }, "manga", [5]);
  assert.deepEqual(shadow(two, "tags:list", 5)?.value, [{ tag_id: 21, rank: 100 }, { tag_id: 22, rank: 100 }]);
});

Deno.test("mangaPopularityUsesMangaUpdatesVotesAndMangaListAdds", async () => {
  const db = fakeSupabase({
    tables: {
      manga: [{ id: 5, is_adult: false }],
      catalogue_id_links: [link("manga", 5, "mangaupdates", String(muRecord.seriesId))],
      catalogue_source_records: [rec("mangaupdates", String(muRecord.seriesId), "manga", muRecord)],
      manga_user_lists: [{ id: 1, user_id: "u1", manga_id: 5 }],
    },
  });
  await compose({ supabase: db.client }, "manga", [5]);
  assert.equal(shadow(db, "popularity", 5)?.value, (muRecord.ratingVotes ?? 0) + 50);
});
