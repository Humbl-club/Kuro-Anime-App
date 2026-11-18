// Offline tests for the catalogue field-group definitions (Task 2).
// Run: cd supabase/functions/_shared && deno test --no-prompt catalogue/
import { strict as assert } from "node:assert";
import {
  type Mode,
  columnsOwnedByNew,
  FIELD_GROUP_COLUMNS,
  FIELD_GROUP_NAMES,
  FIELD_GROUP_TABLES,
  type FieldGroup,
  groupIsAniListOwned,
  readCutoverModes,
} from "./field_groups.ts";

// Column lists of public.anime / public.manga. SOURCE NOTE: the plan asked for a paste of the
// 2026-11-09 live schema query; no hosted query is allowed in this task, so these lists are
// the baseline capture (supabase/migrations/20260807000000_baseline_capture_v1.sql) plus
// data_sources (prepared 20261112100000). Re-paste from a read-only live query before cutover.
const ANIME_COLUMNS = [
  "id", "anilist_id", "mal_id", "kitsu_id", "title_english", "title_romaji", "title_native", "title_synonyms",
  "cover_image_large", "cover_image_medium", "cover_image_color", "banner_image", "format", "status", "description",
  "description_normalized", "episodes", "duration", "total_duration", "season", "season_year", "next_episode_number",
  "next_airing_at", "start_date_year", "start_date_month", "start_date_day", "end_date_year", "end_date_month",
  "end_date_day", "average_score", "mean_score", "popularity", "trending", "favourites", "genres", "source",
  "country_of_origin", "is_adult", "age_rating", "site_url", "created_at", "updated_at", "last_synced_at",
  "updated_at_anilist", "synopsis_enhanced", "synopsis_enhanced_source", "synopsis_enhanced_model",
  "synopsis_enhanced_version", "synopsis_enhanced_updated_at", "synopsis_enhanced_state",
  "synopsis_enhanced_retry_count", "synopsis_enhanced_last_attempt_at", "synopsis_enhanced_next_retry_at",
  "synopsis_enhanced_last_error", "synopsis_enhanced_source_hash", "safety_state", "safety_blocked",
  "safety_reason_codes", "safety_rule_hits", "safety_model_label", "safety_model_confidence",
  "safety_model_rationale", "safety_suggested_lexicon", "safety_source_hash", "safety_last_scanned_at",
  "safety_last_attempt_at", "safety_next_scan_at", "safety_retry_count", "safety_last_error", "data_sources",
];
const MANGA_COLUMNS = [
  "id", "anilist_id", "mal_id", "kitsu_id", "title_english", "title_romaji", "title_native", "title_synonyms",
  "cover_image_large", "cover_image_medium", "cover_image_color", "banner_image", "format", "status", "description",
  "description_normalized", "chapters", "volumes", "next_chapter_number", "next_chapter_at", "start_date_year",
  "start_date_month", "start_date_day", "end_date_year", "end_date_month", "end_date_day", "average_score",
  "mean_score", "popularity", "trending", "favourites", "genres", "source", "country_of_origin", "is_adult",
  "age_rating", "site_url", "created_at", "updated_at", "last_synced_at", "updated_at_anilist", "synopsis_enhanced",
  "synopsis_enhanced_source", "synopsis_enhanced_model", "synopsis_enhanced_version", "synopsis_enhanced_updated_at",
  "synopsis_enhanced_state", "synopsis_enhanced_retry_count", "synopsis_enhanced_last_attempt_at",
  "synopsis_enhanced_next_retry_at", "synopsis_enhanced_last_error", "synopsis_enhanced_source_hash", "safety_state",
  "safety_blocked", "safety_reason_codes", "safety_rule_hits", "safety_model_label", "safety_model_confidence",
  "safety_model_rationale", "safety_suggested_lexicon", "safety_source_hash", "safety_last_scanned_at",
  "safety_last_attempt_at", "safety_next_scan_at", "safety_retry_count", "safety_last_error", "data_sources",
];
const LIVE: Record<"anime" | "manga", string[]> = { anime: ANIME_COLUMNS, manga: MANGA_COLUMNS };

function allModes(mode: Mode): Record<FieldGroup, Mode> {
  return Object.fromEntries(FIELD_GROUP_NAMES.map((g) => [g, mode])) as Record<FieldGroup, Mode>;
}

Deno.test("there are exactly the 12 field groups of the cutover table", () => {
  assert.deepEqual([...FIELD_GROUP_NAMES].sort(), [
    "adult", "credits", "episodes", "facts", "identity", "images", "links", "popularity", "relations", "synopsis", "tags", "titles",
  ]);
});

Deno.test("everyPublishedColumnHasOneGroup", () => {
  for (const medium of ["anime", "manga"] as const) {
    const all = FIELD_GROUP_NAMES.flatMap((g) => [...FIELD_GROUP_COLUMNS[medium][g]]);
    assert.equal(new Set(all).size, all.length, `${medium}: a column sits in two groups`);
    for (const column of all) assert.ok(LIVE[medium].includes(column), `${medium}.${column} is not a live column`);
    // The documented groups cover these published columns, including the ones that live in a group by rule.
    for (const column of ["genres", "site_url", "age_rating", "is_adult", "description", "mal_id"]) {
      assert.ok(all.includes(column), `${medium}.${column} must belong to a group`);
    }
  }
});

Deno.test("group contents follow the plan", () => {
  const anime = FIELD_GROUP_COLUMNS.anime;
  assert.deepEqual(anime.facts, [
    "format", "status", "start_date_year", "start_date_month", "start_date_day", "end_date_year", "end_date_month",
    "end_date_day", "episodes", "duration", "total_duration", "season", "season_year", "country_of_origin", "source",
  ]);
  assert.deepEqual(anime.titles, ["title_english", "title_romaji", "title_native", "title_synonyms"]);
  assert.deepEqual(anime.popularity, ["popularity", "trending", "average_score", "mean_score", "favourites"]);
  assert.deepEqual(anime.adult, ["is_adult", "age_rating"]);
  assert.deepEqual(anime.synopsis, ["description"]);
  assert.deepEqual(anime.images, ["cover_image_large", "cover_image_medium", "cover_image_color", "banner_image"]);
  assert.deepEqual(anime.episodes, ["next_episode_number", "next_airing_at"]);
  assert.deepEqual(anime.identity, ["mal_id"]);
  assert.deepEqual(anime.tags, ["genres"]);
  assert.deepEqual(anime.links, ["site_url"]);
  const manga = FIELD_GROUP_COLUMNS.manga;
  assert.deepEqual(manga.facts, [
    "format", "status", "start_date_year", "start_date_month", "start_date_day", "end_date_year", "end_date_month",
    "end_date_day", "chapters", "volumes", "country_of_origin", "source",
  ]);
  assert.deepEqual(manga.episodes, ["next_chapter_number", "next_chapter_at"]);
  assert.deepEqual(anime.relations, []);
  assert.deepEqual(anime.credits, []);
});

Deno.test("columnsOwnedByNewEmptyWhenAllAniList", () => {
  assert.equal(columnsOwnedByNew("anime", allModes("anilist")).size, 0);
  assert.equal(columnsOwnedByNew("manga", allModes("anilist")).size, 0);
});

Deno.test("shadow mode does not own columns either", () => {
  assert.equal(columnsOwnedByNew("anime", allModes("shadow")).size, 0);
});

Deno.test("columnsOwnedByNewReturnsFactsColumns", () => {
  const modes = { ...allModes("anilist"), facts: "new" as Mode };
  assert.deepEqual([...columnsOwnedByNew("anime", modes)].sort(), [...FIELD_GROUP_COLUMNS.anime.facts].sort());
  assert.deepEqual([...columnsOwnedByNew("manga", modes)].sort(), [...FIELD_GROUP_COLUMNS.manga.facts].sort());
  const two = { ...modes, episodes: "new" as Mode };
  assert.ok(columnsOwnedByNew("manga", two).has("next_chapter_at"));
  assert.ok(!columnsOwnedByNew("manga", two).has("next_episode_number"));
});

Deno.test("groupIsAniListOwned is false only for new", () => {
  const modes = { ...allModes("anilist"), facts: "shadow" as Mode, links: "new" as Mode };
  assert.equal(groupIsAniListOwned("identity", modes), true);
  assert.equal(groupIsAniListOwned("facts", modes), true);
  assert.equal(groupIsAniListOwned("links", modes), false);
});

Deno.test("everyLinkedTableHasOneGroup", () => {
  for (const medium of ["anime", "manga"] as const) {
    const seen = new Map<string, string>();
    for (const [group, tables] of Object.entries(FIELD_GROUP_TABLES[medium])) {
      for (const table of tables ?? []) {
        assert.ok(!seen.has(table), `${medium}: ${table} is in ${seen.get(table)} and ${group}`);
        seen.set(table, group);
      }
    }
  }
  assert.deepEqual(FIELD_GROUP_TABLES.anime.links, ["external_links"]);
  assert.deepEqual(FIELD_GROUP_TABLES.anime.episodes, ["episodes"]);
  assert.deepEqual(FIELD_GROUP_TABLES.manga.episodes, ["chapters", "volumes"]);
  assert.deepEqual(FIELD_GROUP_TABLES.anime.credits, ["anime_studios", "anime_characters", "anime_staff", "character_voice_actors"]);
  assert.deepEqual(FIELD_GROUP_TABLES.manga.credits, ["manga_authors", "manga_characters", "manga_staff"]);
  assert.deepEqual(FIELD_GROUP_TABLES.anime.tags, ["anime_tags"]);
  assert.deepEqual(FIELD_GROUP_TABLES.manga.tags, ["manga_tags"]);
  assert.deepEqual(FIELD_GROUP_TABLES.anime.relations, ["media_relations"]);
});

function fakeModesClient(result: { data: unknown; error: unknown } | "throw") {
  return {
    from(table: string) {
      assert.equal(table, "catalogue_cutover");
      return {
        select(columns: string) {
          assert.equal(columns, "field_group, mode");
          if (result === "throw") return Promise.reject(new Error("network down"));
          return Promise.resolve(result);
        },
      };
    },
  };
}

Deno.test("readCutoverModes returns every group", async () => {
  const rows = FIELD_GROUP_NAMES.map((g) => ({ field_group: g, mode: g === "facts" ? "new" : "anilist" }));
  const modes = await readCutoverModes(fakeModesClient({ data: rows, error: null }));
  assert.equal(modes.facts, "new");
  assert.equal(modes.titles, "anilist");
});

Deno.test("readCutoverModes fails closed", async () => {
  await assert.rejects(readCutoverModes(fakeModesClient({ data: null, error: { message: "boom" } })), /cutover/);
  await assert.rejects(readCutoverModes(fakeModesClient("throw")));
  // A missing group or an unknown mode must not read as "anilist".
  const missing = FIELD_GROUP_NAMES.filter((g) => g !== "images").map((g) => ({ field_group: g, mode: "anilist" }));
  await assert.rejects(readCutoverModes(fakeModesClient({ data: missing, error: null })), /images/);
  const odd = FIELD_GROUP_NAMES.map((g) => ({ field_group: g, mode: g === "tags" ? "both" : "anilist" }));
  await assert.rejects(readCutoverModes(fakeModesClient({ data: odd, error: null })), /tags/);
});
