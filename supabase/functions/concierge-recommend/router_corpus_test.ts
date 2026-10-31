// Corpora EXECUTION (router half): runs tests/concierge-corpora/router_{en,de}.json (67 cases)
// through the PRODUCTION routing chain (router.ts). The shape check of the same files stays in
// scripts/quality-gates/test_concierge_corpora.sh ("corpora-shape").
//
// Cases whose corpus expectation disagrees with production are NOT re-expected silently: they
// are pinned below with the current production route, so the gate stays green, prints them,
// and fails (asking for review) the moment production changes for any of them.
import { strict as assert } from "node:assert";
import { FALLBACK_MODES, MIGRATION_CHAIN_MODES, routePrompt } from "./router_test_support.ts";
import routerEn from "../../../tests/concierge-corpora/router_en.json" with { type: "json" };
import routerDe from "../../../tests/concierge-corpora/router_de.json" with { type: "json" };

type RouterCorpusCase = { id: string; input: string; expected_mode: string; excluded_genres?: string[] };
const CASES = [...routerEn, ...routerDe] as RouterCorpusCase[];

/**
 * Corpus expectation != production route (pinned production route + why). Empty since the F28 repair
 * (2026-10-05): router_de_005 'romantisches' -> romcom and router_de_029 'schauriges' ->
 * horror_supernatural now route as the corpus intends (GERMAN_VIBE_FORMS + the romance strong-genre rule).
 */
const KNOWN_DIVERGENCES: Record<string, { production: string; why: string }> = {};

Deno.test("router corpora: 67 cases executed through the production chain (migration-chain modes)", async () => {
  assert.equal(CASES.length, 67);
  const failures: string[] = [];
  const pinned: string[] = [];
  const contingent: string[] = [];
  for (const c of CASES) {
    const r = await routePrompt(c.input);
    for (const g of c.excluded_genres ?? []) {
      if (!r.excludedGenres.includes(g)) failures.push(`${c.id}: production did not derive excluded genre ${g}`);
    }
    if (r.searchCalls.length > 0 && r.primaryReason !== "bare title seed similarity") contingent.push(c.id);
    const divergence = KNOWN_DIVERGENCES[c.id];
    if (divergence) {
      if (r.primaryId === c.expected_mode) {
        failures.push(`${c.id}: listed as a known divergence but production now matches the corpus (${c.expected_mode}); remove it from KNOWN_DIVERGENCES`);
      } else if (r.primaryId !== divergence.production) {
        failures.push(`${c.id}: production route changed from pinned ${divergence.production} to ${r.primaryId}; review`);
      } else {
        pinned.push(`${c.id} "${c.input}": corpus ${c.expected_mode}, production ${r.primaryId}`);
      }
      continue;
    }
    if (r.primaryId !== c.expected_mode) failures.push(`${c.id} "${c.input}": expected ${c.expected_mode}, production routed ${r.primaryId} (${r.primaryReason})`);
  }
  console.log(`[corpora-execution] router: ${CASES.length} cases executed; ${CASES.length - pinned.length - failures.length} match, ${pinned.length} pinned divergences:`);
  for (const p of pinned) console.log(`  DIVERGENCE ${p}`);
  console.log(`  ${contingent.length} cases are bare-title candidates contingent on live search_titles (no confident row assumed).`);
  assert.deepEqual(failures, []);
  assert.equal(pinned.length, Object.keys(KNOWN_DIVERGENCES).length);
});

// Under the code fallback (defaultModes(), 17 modes) the six v8 modes are missing and the v7
// German synonyms are absent. Pin exactly which corpus cases change and why.
const V8_ONLY_MODES = new Set(["mecha", "mystery_detective", "music_performance", "historical", "school_coming_of_age", "shoujo_josei"]);
/** Route under the migration config relies on a v7 German synonym that defaultModes() lacks. */
const V7_SYNONYM_DEPENDENT: Record<string, string> = {
  router_de_001: "premium_picks", // 'duesteres' synonym on dark_serious
  router_de_026: "premium_picks", // 'geister' synonym on horror_supernatural
};

Deno.test("router corpora under fallback modes: only v8-mode and v7-synonym cases change", async () => {
  const changed: string[] = [];
  for (const c of CASES) {
    const withConfig = await routePrompt(c.input, MIGRATION_CHAIN_MODES);
    const withFallback = await routePrompt(c.input, FALLBACK_MODES);
    if (V8_ONLY_MODES.has(withConfig.primaryId)) {
      assert.notEqual(withFallback.primaryId, withConfig.primaryId, c.id);
      changed.push(c.id);
    } else if (c.id in V7_SYNONYM_DEPENDENT) {
      assert.equal(withFallback.primaryId, V7_SYNONYM_DEPENDENT[c.id], c.id);
      assert.notEqual(withFallback.primaryId, withConfig.primaryId, c.id);
      changed.push(c.id);
    } else {
      assert.equal(withFallback.primaryId, withConfig.primaryId, `${c.id} "${c.input}" differs under fallback modes`);
    }
  }
  console.log(`[corpora-execution] router under defaultModes(): ${changed.length}/${CASES.length} cases change: ${changed.join(" ")}`);
  // 14 v8-mode cases + 2 v7-synonym cases (router_de_005 romcom and router_de_029 horror_supernatural
  // route through the strong-genre rule, and both modes exist in defaultModes(), so they do not change).
  assert.equal(changed.length, 16);
});
