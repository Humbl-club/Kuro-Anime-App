// Offline router gate: executes the PRODUCTION concierge-recommend routing chain (router.ts,
// imported by handler.ts) against the 75 cases in scripts/quality-gates/router_test_cases.js.
// Replaces the former hand-maintained copy of the router in that file.
//
// Run: deno test --no-prompt supabase/functions/concierge-recommend/router_test.ts
//      (or bash scripts/quality-gates/test_router_offline.sh). No permissions, no network.
import { strict as assert } from "node:assert";
import {
  isClassicIntent,
  isGatewayIntent,
  isHiddenGemsIntent,
  mapStrongGenreToModeId,
} from "./router.ts";
import { catalogSearch, FALLBACK_MODES, MIGRATION_CHAIN_MODES, routePrompt } from "./router_test_support.ts";
import { ROUTER_OFFLINE_CASES } from "../../../scripts/quality-gates/router_test_cases.js";

type OfflineCase = { prompt: string; expected: string; note: string; excludedGenres?: string[] };
const CASES = ROUTER_OFFLINE_CASES as OfflineCase[];

Deno.test("router cases file still holds the 75 offline cases", () => {
  assert.equal(CASES.length, 75);
});

Deno.test("75 offline cases route as expected through the production chain (migration-chain modes)", async () => {
  const failures: string[] = [];
  const contingent: string[] = [];
  for (const [i, c] of CASES.entries()) {
    const r = await routePrompt(c.prompt);
    // Production derives exclusions from the text; the hand-written list must be a subset.
    for (const g of c.excludedGenres ?? []) {
      if (!r.excludedGenres.includes(g)) failures.push(`#${i + 1} "${c.prompt}": production did not derive excluded genre ${g} (got ${JSON.stringify(r.excludedGenres)})`);
    }
    if (r.primaryId !== c.expected) failures.push(`#${i + 1} "${c.prompt}": expected ${c.expected}, production routed ${r.primaryId} (${r.primaryReason})`);
    if (r.searchCalls.length > 0 && r.primaryReason !== "bare title seed similarity") contingent.push(`#${i + 1}`);
  }
  console.log(
    `[router-rules] executed ${CASES.length} offline cases through router.ts routePrimaryMode; ` +
      `${CASES.length - failures.length} passed. ${contingent.length} non-title prompts are bare-title candidates whose ` +
      `route assumes live search_titles returns no row with score >= 0.45: ${contingent.join(" ")}`,
  );
  assert.deepEqual(failures, []);
});

// The 22 alternatives that existed only in production (the deleted test copy lacked them).
// Each is checked at the rule it belongs to AND through the full chain.
const GERMAN_ONLY_ALTERNATIVES: Array<{ alt: string; prompt: string; rule: (t: string) => boolean; mode: string }> = [
  // isClassicIntent (6)
  { alt: "klassiker", prompt: "ein klassiker bitte", rule: isClassicIntent, mode: "classics_expanded" },
  { alt: "klassisch", prompt: "etwas klassisch gutes", rule: isClassicIntent, mode: "classics_expanded" },
  { alt: "meisterwerk", prompt: "ein echtes meisterwerk bitte", rule: isClassicIntent, mode: "classics_expanded" },
  { alt: "muss man gesehen haben", prompt: "anime die muss man gesehen haben", rule: isClassicIntent, mode: "classics_expanded" },
  { alt: "legendaer", prompt: "etwas legendär gutes", rule: isClassicIntent, mode: "classics_expanded" },
  { alt: "legendaere", prompt: "die legendäre serie von damals", rule: isClassicIntent, mode: "classics_expanded" },
  // isGatewayIntent (4)
  { alt: "erstes anime", prompt: "mein erstes anime überhaupt", rule: isGatewayIntent, mode: "gateway_start_here" },
  { alt: "erstes manga", prompt: "mein erstes manga überhaupt", rule: isGatewayIntent, mode: "gateway_start_here" },
  { alt: "womit anfangen", prompt: "womit anfangen bei anime", rule: isGatewayIntent, mode: "gateway_start_here" },
  { alt: "wo fange ich an", prompt: "wo fange ich an mit anime", rule: isGatewayIntent, mode: "gateway_start_here" },
  // isHiddenGemsIntent (5)
  { alt: "geheimtipp", prompt: "ein geheimtipp für heute abend", rule: isHiddenGemsIntent, mode: "hidden_gems" },
  { alt: "unterschaetzt", prompt: "etwas unterschätzt gutes", rule: isHiddenGemsIntent, mode: "hidden_gems" },
  { alt: "unbekannt", prompt: "eher unbekannt aber gut", rule: isHiddenGemsIntent, mode: "hidden_gems" },
  { alt: "wenig bekannt", prompt: "wenig bekannt aber stark", rule: isHiddenGemsIntent, mode: "hidden_gems" },
  { alt: "insider", prompt: "ein insider tipp für mich", rule: isHiddenGemsIntent, mode: "hidden_gems" },
  // mapStrongGenreToModeId (7)
  { alt: "filme", prompt: "gute anime filme für heute", rule: (t) => mapStrongGenreToModeId(t) === "movie_night", mode: "movie_night" },
  { alt: "filmabend", prompt: "anime für den filmabend", rule: (t) => mapStrongGenreToModeId(t) === "movie_night", mode: "movie_night" },
  { alt: "kinofilm", prompt: "ein anime kinofilm bitte", rule: (t) => mapStrongGenreToModeId(t) === "movie_night", mode: "movie_night" },
  { alt: "1 staffel", prompt: "anime mit nur 1 staffel", rule: (t) => mapStrongGenreToModeId(t) === "short_one_season", mode: "short_one_season" },
  { alt: "kurz und gut", prompt: "kurz und gut soll es sein", rule: (t) => mapStrongGenreToModeId(t) === "short_one_season", mode: "short_one_season" },
  { alt: "nicht isekai", prompt: "fantasy aber nicht isekai", rule: (t) => mapStrongGenreToModeId(t) === "fantasy_non_isekai", mode: "fantasy_non_isekai" },
  { alt: "kein isekai", prompt: "fantasy und kein isekai", rule: (t) => mapStrongGenreToModeId(t) === "fantasy_non_isekai", mode: "fantasy_non_isekai" },
];

Deno.test("22 production-only German alternatives fire their rule and route through the chain", async () => {
  assert.equal(GERMAN_ONLY_ALTERNATIVES.length, 22);
  for (const a of GERMAN_ONLY_ALTERNATIVES) {
    assert.ok(a.rule(a.prompt), `rule did not fire for "${a.alt}" in "${a.prompt}"`);
    const r = await routePrompt(a.prompt);
    assert.equal(r.primaryId, a.mode, `"${a.prompt}" (${a.alt}) routed ${r.primaryId} (${r.primaryReason})`);
  }
});

Deno.test("chain order is production's: classic beats gateway, gateway beats hidden gems", async () => {
  // The deleted copy checked gateway before classic.
  assert.equal((await routePrompt("first anime classic")).primaryId, "classics_expanded");
  assert.equal((await routePrompt("first anime hidden gem")).primaryId, "gateway_start_here");
});

Deno.test("bare-title path: a confident search_titles row turns a short prompt into a seed (live-DB contingency)", async () => {
  // Same prompt, two controlled search outcomes. Production behaviour for every short,
  // non-'recommend' prompt depends on this RPC result.
  const noRow = await routePrompt("gundam style anime");
  assert.equal(noRow.primaryId, "mecha");
  assert.deepEqual(noRow.searchCalls, ["ANIME:gundam style anime"]);

  const confident = await routePrompt("gundam style anime", MIGRATION_CHAIN_MODES, {
    search: (calls) => catalogSearch(calls, ["gundam style anime"], 0.46),
  });
  assert.equal(confident.primaryId, "similar_to_seed");
  assert.equal(confident.bareSeed?.query, "gundam style anime");

  const belowThreshold = await routePrompt("gundam style anime", MIGRATION_CHAIN_MODES, {
    search: (calls) => catalogSearch(calls, ["gundam style anime"], 0.44),
  });
  assert.equal(belowThreshold.primaryId, "mecha");
});

Deno.test("abbreviation seed: AOT is verified through search_titles and adopted as the seed", async () => {
  const r = await routePrompt("AOT");
  assert.equal(r.primaryId, "similar_to_seed");
  assert.equal(r.primaryReason, "bare title seed similarity");
  assert.equal(r.bareSeed?.query, "Attack on Titan");
  assert.deepEqual(r.searchCalls, ["ANIME:Attack on Titan"]);
});

// Characterisation of the code fallback (defaultModes(), 17 modes) used when get_concierge_config
// yields no valid modes: the six v8 modes are absent, so strong-genre hits for them fall through
// to scoring. Every other case must route exactly as with the migration-chain config.
const V8_ONLY_MODES = new Set(["mecha", "mystery_detective", "music_performance", "historical", "school_coming_of_age", "shoujo_josei"]);

Deno.test("fallback modes: only cases targeting the six v8-only modes degrade", async () => {
  const fallbackIds = new Set(FALLBACK_MODES.map((m) => m.id));
  for (const id of V8_ONLY_MODES) assert.equal(fallbackIds.has(id), false, `${id} unexpectedly present in defaultModes()`);
  const degraded: string[] = [];
  for (const [i, c] of CASES.entries()) {
    const withConfig = await routePrompt(c.prompt, MIGRATION_CHAIN_MODES);
    const withFallback = await routePrompt(c.prompt, FALLBACK_MODES);
    if (V8_ONLY_MODES.has(withConfig.primaryId)) {
      assert.notEqual(withFallback.primaryId, withConfig.primaryId);
      degraded.push(`#${i + 1}->${withFallback.primaryId}`);
    } else {
      assert.equal(withFallback.primaryId, withConfig.primaryId, `#${i + 1} "${c.prompt}" differs under fallback modes`);
    }
  }
  console.log(`[router-rules] fallback defaultModes(): ${degraded.length}/${CASES.length} cases lose their v8 mode: ${degraded.join(" ")}`);
  assert.equal(degraded.length, 13);
});
