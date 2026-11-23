// Offline tests for the pure precedence policy (catalogue Task 7).
// Run: cd supabase/functions/_shared && deno test --no-prompt catalogue/
import { strict as assert } from "node:assert";
import {
  classifyRefreshTier,
  composeAdult,
  deriveAnimeSeason,
  deriveAnimeStatus,
  mapRelations,
  pick,
  PRECEDENCE,
  prioritizeRefreshTier,
  type RawRelation,
} from "./precedence.ts";

Deno.test("firstSourceWithValueWins", () => {
  // feature "Precedence picks...": native title from wikidata, then ann.
  const got = pick("title_native", "anime", [
    { source: "ann", value: "ANN native" },
    { source: "wikidata", value: "Wikidata native" },
  ]);
  assert.deepEqual(got, { source: "wikidata", value: "Wikidata native" });
  // romaji prefers ann
  assert.equal(pick("title_romaji", "anime", [{ source: "wikidata", value: "w" }, { source: "ann", value: "a" }])?.source, "ann");
  // manga facts prefer mangaupdates
  assert.equal(pick("format", "manga", [{ source: "wikidata", value: "ONE_SHOT" }, { source: "mangaupdates", value: "MANGA" }])?.value, "MANGA");
  // anime format/episodes/duration prefer ann
  for (const c of ["format", "episodes", "duration"]) assert.equal(PRECEDENCE.anime[c][0], "ann");
});

Deno.test("nullAndEmptyStringSkipped", () => {
  const got = pick("title_english", "anime", [
    { source: "wikidata", value: null },
    { source: "ann", value: "  " },
  ]);
  assert.equal(got, null);
  const next = pick("title_english", "anime", [
    { source: "wikidata", value: "" },
    { source: "ann", value: "Fallback" },
  ]);
  assert.deepEqual(next, { source: "ann", value: "Fallback" });
  assert.equal(pick("title_synonyms", "anime", [{ source: "wikidata", value: [] }, { source: "ann", value: ["x"] }])?.source, "ann");
  // zero is a value
  assert.equal(pick("episodes", "anime", [{ source: "ann", value: 0 }])?.value, 0);
});

Deno.test("sourceNotListedForColumnIsIgnored", () => {
  assert.equal(pick("title_native", "manga", [{ source: "ann", value: "x" }]), null);
  assert.equal(pick("no_such_column", "anime", [{ source: "ann", value: "x" }]), null);
});

Deno.test("adultAnySourceTrue", () => {
  assert.deepEqual(composeAdult(false, [false, true]), { value: true, review: false, newlyAdult: true });
  assert.deepEqual(composeAdult(null, [true]), { value: true, review: false, newlyAdult: true });
  assert.deepEqual(composeAdult(true, [true, false]), { value: true, review: false, newlyAdult: false });
  assert.deepEqual(composeAdult(false, [false]), { value: false, review: false, newlyAdult: false });
});

Deno.test("adultNeverClearsWithoutReview", () => {
  // today adult, no source says adult: stays adult and goes to the review list.
  assert.deepEqual(composeAdult(true, [false, false]), { value: true, review: true, newlyAdult: false });
  // no source carries adult data at all: also stays adult, also reviewed.
  assert.deepEqual(composeAdult(true, []), { value: true, review: true, newlyAdult: false });
  // no adult data and today is not adult: keeps today's value, no review.
  assert.deepEqual(composeAdult(false, []), { value: false, review: false, newlyAdult: false });
  assert.deepEqual(composeAdult(null, []), { value: false, review: false, newlyAdult: false });
});

type Known = Record<string, { kind: "anime" | "manga"; id: number }>;
const resolve = (known: Known) => (source: string, key: string) => known[`${source}:${key}`] ?? null;

Deno.test("relationToUnlinkedTitleDropped", () => {
  const raw: RawRelation[] = [
    { source: "wikidata", type: "SEQUEL", targetKey: "Q2" },
    { source: "wikidata", type: "PREQUEL", targetKey: "Q999" },
  ];
  const out = mapRelations(raw, resolve({ "wikidata:Q2": { kind: "anime", id: 20 } }));
  assert.deepEqual(out.relations, [{ type: "SEQUEL", kind: "anime", target_id: 20, sources: ["wikidata"], status: "accepted" }]);
  assert.equal(out.dropped, 1);
});

Deno.test("relationTypesOutsideKuroSetDropped", () => {
  const out = mapRelations([{ source: "mangaupdates", type: "SHARED_CHARACTER", targetKey: "5" }], resolve({ "mangaupdates:5": { kind: "manga", id: 5 } }));
  assert.deepEqual(out.relations, []);
  assert.equal(out.dropped, 1);
});

Deno.test("relationSourcesAgreeMergeAndDisagreeProposed", () => {
  const known: Known = {
    "wikidata:Q2": { kind: "anime", id: 20 },
    "ann:200": { kind: "anime", id: 20 },
    "ann:300": { kind: "anime", id: 30 },
    "wikidata:Q3": { kind: "anime", id: 30 },
  };
  const out = mapRelations(
    [
      { source: "wikidata", type: "SEQUEL", targetKey: "Q2" },
      { source: "ann", type: "SEQUEL", targetKey: "200" },
      { source: "wikidata", type: "SEQUEL", targetKey: "Q3" },
      { source: "ann", type: "SPIN_OFF", targetKey: "300" },
    ],
    resolve(known),
  );
  const by = (id: number, type: string) => out.relations.find((r) => r.target_id === id && r.type === type);
  assert.deepEqual(by(20, "SEQUEL")?.sources, ["ann", "wikidata"]);
  assert.equal(by(20, "SEQUEL")?.status, "accepted");
  assert.equal(by(30, "SEQUEL")?.status, "proposed");
  assert.equal(by(30, "SPIN_OFF")?.status, "proposed");
});

Deno.test("derivativeWorkIsAdaptationOnlyAcrossMedia", () => {
  const known: Known = { "wikidata:Q1": { kind: "manga", id: 1 }, "wikidata:Q2": { kind: "anime", id: 2 } };
  const out = mapRelations(
    [
      { source: "wikidata", type: "DERIVATIVE", targetKey: "Q1" },
      { source: "wikidata", type: "DERIVATIVE", targetKey: "Q2" },
    ],
    resolve(known),
    "anime",
  );
  assert.deepEqual(out.relations.map((r) => [r.type, r.target_id]), [["ADAPTATION", 1]]);
  assert.equal(out.dropped, 1);
});

Deno.test("deriveAnimeSeasonMapsCalendarQuarters", () => {
  assert.deepEqual(deriveAnimeSeason({ year: 2027, month: 1, day: 8 }), { season: "WINTER", season_year: 2027 });
  assert.deepEqual(deriveAnimeSeason({ year: 2026, month: 4, day: 1 }), { season: "SPRING", season_year: 2026 });
  assert.deepEqual(deriveAnimeSeason({ year: 2026, month: 7, day: null }), { season: "SUMMER", season_year: 2026 });
  assert.deepEqual(deriveAnimeSeason({ year: 2026, month: 10, day: 5 }), { season: "FALL", season_year: 2026 });
  assert.equal(deriveAnimeSeason({ year: 2026, month: null, day: null }), null);
});

Deno.test("deriveAnimeStatusHandlesUpcomingReleasingFinishedAndMovies", () => {
  const now = Date.UTC(2026, 10, 19); // 2026-11-19
  assert.equal(deriveAnimeStatus({ year: 2027, month: 1, day: 8 }, null, "TV", now), "NOT_YET_RELEASED");
  assert.equal(deriveAnimeStatus({ year: 2026, month: 10, day: 5 }, null, "TV", now), "RELEASING");
  assert.equal(
    deriveAnimeStatus({ year: 2023, month: 9, day: 29 }, { year: 2024, month: 3, day: 22 }, "TV", now),
    "FINISHED",
  );
  assert.equal(deriveAnimeStatus({ year: 2026, month: 8, day: 1 }, null, "MOVIE", now), "FINISHED");
});

Deno.test("prioritizeRefreshTierOrdersHotWarmCold", () => {
  const now = Date.UTC(2026, 10, 19);
  const items = [
    { id: 1, status: "FINISHED", createdAtMs: Date.UTC(2020, 0, 1) }, // cold
    { id: 2, status: "FINISHED", createdAtMs: Date.UTC(2020, 0, 1), inUserList: true }, // warm
    { id: 3, status: "NOT_YET_RELEASED", createdAtMs: Date.UTC(2026, 1, 1) }, // hot
    { id: 4, status: "FINISHED", createdAtMs: now - 5 * 86_400_000 }, // hot (newly added)
  ];
  assert.equal(classifyRefreshTier(items[0], now), "cold");
  assert.equal(classifyRefreshTier(items[1], now), "warm");
  assert.equal(classifyRefreshTier(items[2], now), "hot");
  assert.equal(classifyRefreshTier(items[3], now), "hot");
  assert.deepEqual(prioritizeRefreshTier(items, now).map((x) => x.id), [3, 4, 2, 1]);
});
