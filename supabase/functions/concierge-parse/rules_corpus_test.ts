// Corpora EXECUTION (parser half): runs tests/concierge-corpora/parser_{en,de}.json (107 cases)
// through the PRODUCTION parser (rules.ts: splitItems + parseLine, exactly what the parse handler
// runs per request before the title search). The shape check stays in test_concierge_corpora.sh.
//
// What is asserted per case (against the INTENDED outcome):
//   - slots: every parsed item carries each slot value (a null slot means "absent");
//   - ambiguity (non-null): the first item's ambiguity kind;
//   - ambiguity null on an `import` case, or adjudicated to null: no item asks a clarification.
// Not executable here (reported, not asserted): `expected_intent` and `expected_confidence_min`.
// Import-vs-recommend routing is client-side Swift (`ConciergeRouting` / `looksLikeImport`) and
// confidence comes from search_titles candidate scores, so recommend/gibberish prompts never depend
// on this parser.
//
// Three kinds of case, so the gate tells defects apart from accepted semantic choices (F29):
//   - as authored: the corpus `expected_*` is the intended outcome;
//   - adjudicated: the CANONICAL fixture carries `adjudication` (decision, intended_slots /
//     intended_ambiguity, rationale) next to the untouched authored expectation. Decisions:
//     `corrected-expectation` (the authored value contradicted the parser's deliberate rule) and
//     `accepted-production` (the authored value is not import-relevant; rationale says why);
//   - KNOWN_DEFECTS (below): intended outcome known, production differs. Production output is pinned
//     verbatim; the gate prints the defect and fails when production changes (fixed or regressed), so
//     a defect is never re-expected silently. Empty since the F27/F29 repairs (2026-10-05).
import { strict as assert } from "node:assert";
import { type ParsedItem, parseLine, splitItems } from "./rules.ts";
import parserEn from "../../../tests/concierge-corpora/parser_en.json" with { type: "json" };
import parserDe from "../../../tests/concierge-corpora/parser_de.json" with { type: "json" };

type Adjudication = {
  decision: "corrected-expectation" | "accepted-production";
  intended_slots?: Record<string, unknown>;
  intended_ambiguity?: string | null;
  rationale: string;
};
type ParserCorpusCase = {
  id: string;
  input: string;
  expected_intent: string;
  expected_slots: Record<string, unknown>;
  expected_ambiguity: string | null;
  adjudication?: Adjudication;
};
const CASES = [...parserEn, ...parserDe] as ParserCorpusCase[];

type Observation = { raws: string[]; slots: Record<string, unknown[]>; ambiguity: (string | null)[] };

/** Intended outcome known, production differs (pinned verbatim; `why` names the defect). */
const KNOWN_DEFECTS: Record<string, { production: Observation; why: string }> = {};

function parseCase(input: string): ParsedItem[] {
  return splitItems(input).map((raw) => parseLine(raw, {}));
}

function observe(items: ParsedItem[], slotKeys: string[]): Observation {
  const slots: Record<string, unknown[]> = {};
  for (const k of slotKeys) slots[k] = items.map((i) => (i as Record<string, unknown>)[k] ?? null);
  return { raws: items.map((i) => i.raw), slots, ambiguity: items.map((i) => i.ambiguity?.kind ?? null) };
}

function intended(c: ParserCorpusCase): { slots: Record<string, unknown>; ambiguity: string | null; assertNoClarification: boolean } {
  const adj = c.adjudication;
  const slots = adj?.intended_slots ?? c.expected_slots;
  const adjudicatedAmbiguity = adj !== undefined && "intended_ambiguity" in adj;
  const ambiguity = adjudicatedAmbiguity ? (adj.intended_ambiguity ?? null) : c.expected_ambiguity;
  return { slots, ambiguity, assertNoClarification: ambiguity == null && (c.expected_intent === "import" || adjudicatedAmbiguity) };
}

function mismatches(c: ParserCorpusCase, items: ParsedItem[]): string[] {
  const want = intended(c);
  const out: string[] = [];
  for (const [k, v] of Object.entries(want.slots)) {
    if (items.length === 0) out.push(`${k}: no parsed items`);
    for (const it of items) {
      const got = (it as Record<string, unknown>)[k];
      if (v === null ? got != null : got !== v) out.push(`${k}: expected ${JSON.stringify(v)}, got ${JSON.stringify(got)}`);
    }
  }
  const kinds = items.map((i) => i.ambiguity?.kind ?? null);
  if (want.ambiguity != null) {
    if (kinds[0] !== want.ambiguity) out.push(`ambiguity: expected ${want.ambiguity}, got ${JSON.stringify(kinds)}`);
  } else if (want.assertNoClarification && kinds.some((k) => k != null)) {
    out.push(`ambiguity: expected no clarification, got ${JSON.stringify(kinds)}`);
  }
  return out;
}

Deno.test("parser corpora: 107 cases executed through the production parser against their intended outcome", () => {
  assert.equal(CASES.length, 107);
  const failures: string[] = [];
  const defects: string[] = [];
  const adjudicated: Record<string, string[]> = { "corrected-expectation": [], "accepted-production": [] };
  for (const c of CASES) {
    const items = parseCase(c.input);
    const problems = mismatches(c, items);
    const defect = KNOWN_DEFECTS[c.id];
    if (defect) {
      const actual = observe(items, Object.keys(defect.production.slots));
      if (problems.length === 0) {
        failures.push(`${c.id}: listed as a known defect but production now gives the intended outcome; remove it from KNOWN_DEFECTS`);
      } else {
        try {
          assert.deepEqual(actual, defect.production);
          defects.push(`${c.id} "${c.input}": ${problems.join("; ")}`);
        } catch {
          failures.push(`${c.id}: production output changed from the pinned defect observation: ${JSON.stringify(actual)}`);
        }
      }
      continue;
    }
    if (c.adjudication) {
      assert.ok(c.adjudication.decision in adjudicated && c.adjudication.rationale.length > 0, `${c.id}: malformed adjudication`);
      adjudicated[c.adjudication.decision].push(c.id);
    }
    if (problems.length) failures.push(`${c.id} "${c.input}": ${problems.join("; ")}`);
  }
  const notExecutable = CASES.filter((c) => c.expected_intent !== "import" && intended(c).ambiguity == null && !intended(c).assertNoClarification).length;
  const nAdjudicated = adjudicated["corrected-expectation"].length + adjudicated["accepted-production"].length;
  console.log(
    `[corpora-execution] parser: ${CASES.length} cases executed; ${CASES.length - defects.length - failures.length} give the intended outcome ` +
      `(${CASES.length - nAdjudicated - defects.length - failures.length} as authored; adjudicated in the fixture: ` +
      `corrected-expectation ${adjudicated["corrected-expectation"].join(" ")}; accepted-production ${adjudicated["accepted-production"].join(" ")}), ` +
      `${defects.length} known defects${defects.length ? ":" : "."}`,
  );
  for (const d of defects) console.log(`  KNOWN DEFECT ${d}`);
  console.log(
    `  not asserted (client-side): expected_intent for all ${CASES.length} cases and expected_confidence_min; ` +
      `ambiguity of ${notExecutable} recommend/gibberish cases (Swift routes those away from concierge-parse).`,
  );
  assert.deepEqual(failures, []);
  assert.equal(defects.length, Object.keys(KNOWN_DEFECTS).length);
});

Deno.test("parser: title punctuation never splits a title; real separators still do (F27, F71)", () => {
  const raws = (input: string) => splitItems(input);
  // F27: a glued ';' is part of the title, a spaced ';' separates.
  assert.deepEqual(raws("ich habe Robotics;Notes und Chaos;Head gesehen"), ["ich habe Robotics;Notes gesehen", "ich habe Chaos;Head gesehen"]);
  assert.deepEqual(raws("I watched Robotics;Notes, Chaos;Head"), ["I watched Robotics;Notes", "I watched Chaos;Head"]);
  // F71: a '.' after an honorific, or 'No.' before a number, is part of the title.
  assert.deepEqual(raws("I watched Dr. Stone"), ["I watched Dr. Stone"]);
  assert.deepEqual(raws("Kaiju No. 8 fertig"), ["Kaiju No. 8 fertig"]);
  assert.deepEqual(raws("I watched Naruto. I dropped Bleach"), ["I watched Naruto.", "I dropped Bleach"]);
  // F27: the German perfect keeps its trailing phrase on the last title only.
  const items = parseCase("ich habe Naruto und Bleach gesehen bis Folge 10");
  assert.deepEqual(items.map((i) => [i.normalized, i.progressEpisodes ?? null, i.ambiguity?.kind ?? null]), [
    ["Naruto", null, "status_unclear"],
    ["Bleach", 10, null],
  ]);
});

Deno.test("parser: after the German participle only progress/rating/completion phrases are kept, never commentary (review R1)", () => {
  const one = (input: string) => {
    const items = parseCase(input);
    assert.equal(items.length, 1, input);
    const it = items[0];
    return [it.normalized, it.progressEpisodes ?? null, it.rating ?? null, it.status ?? null];
  };
  assert.deepEqual(one("ich habe Vinland Saga gesehen und fand es super"), ["Vinland Saga", null, null, "WATCHING"]);
  assert.deepEqual(one("ich habe Naruto gesehen, war ok"), ["Naruto", null, null, "WATCHING"]);
  assert.deepEqual(one("ich habe Naruto gesehen aber abgebrochen"), ["Naruto", null, null, "WATCHING"]);
  assert.deepEqual(one("ich habe Monster gesehen bis Folge 40 und pausiert"), ["Monster", 40, null, "WATCHING"]);
  assert.deepEqual(one("ich habe Naruto gesehen, 9/10"), ["Naruto", null, 9, "WATCHING"]);
  assert.deepEqual(one("ich habe Naruto gesehen - eine 8"), ["Naruto", null, 8, "WATCHING"]);
  assert.deepEqual(one("ich habe AoT gesehen bis zur letzten Folge"), ["AoT", null, null, "COMPLETED"]);
});

Deno.test("parser: the explicit-completion fallback is for list lines only, not wishes or questions (review A3)", () => {
  const status = (input: string) => parseCase(input).map((i) => i.status ?? null);
  assert.deepEqual(status("Naruto fully"), ["COMPLETED"]);
  assert.deepEqual(status("Steins;Gate to the end"), ["COMPLETED"]);
  assert.deepEqual(status("I want to watch all of it"), [null]);
  assert.deepEqual(status("should I watch Naruto to the end?"), [null]);
});

Deno.test("parser: bare finished/completed/fertig with partial or positional progress is in progress, like 'I finished' (F72)", () => {
  const one = (input: string) => {
    const [it] = parseCase(input);
    return [it.normalized, it.status ?? null, it.progressEpisodes ?? null];
  };
  assert.deepEqual(one("finished AoT up to episode 5"), ["AoT", "WATCHING", 5]);
  assert.deepEqual(one("Naruto episode 220 completed"), ["Naruto", "WATCHING", 220]);
  assert.deepEqual(one("Naruto Folge 220 fertig"), ["Naruto", "WATCHING", 220]);
  assert.deepEqual(one("I watched AoT to episode 5"), ["AoT", "WATCHING", 5]);
  // Unchanged: completion without a position, and explicit completion phrases.
  assert.deepEqual(one("Naruto completed"), ["Naruto", "COMPLETED", null]);
  assert.deepEqual(one("Naruto completed to the end"), ["Naruto", "COMPLETED", null]);
  assert.deepEqual(one("Naruto bis Folge 220 komplett"), ["Naruto", "COMPLETED", 220]);
});

Deno.test("parser: Finished with no title stores no status (locked product rule)", () => {
  for (const input of ["Finished", "finished", "Fertig", "I finished", "Completed", "done"]) {
    const [it] = parseCase(input);
    assert.equal(it.normalized, "", input);
    assert.equal(it.status ?? null, null, input);
    assert.equal(it.completed ?? null, null, input);
  }
});

Deno.test("parser: bare number in a titled name stays part of the title (Mob Psycho 100)", () => {
  const [it] = parseCase("Mob Psycho 100");
  assert.equal(it.normalized, "Mob Psycho 100");
  assert.equal(it.status ?? null, null);
  assert.equal(it.progressEpisodes ?? null, null);
  assert.equal(it.ambiguity?.kind ?? null, "intent_unclear");
});

Deno.test("parser: multi-title line splits into one item per title with the shared verb", () => {
  const items = parseCase("I watched Cowboy Bebop, Trigun, and Samurai Champloo");
  assert.deepEqual(items.map((i) => i.normalized), ["Cowboy Bebop", "Trigun", "Samurai Champloo"]);
  assert.ok(items.every((i) => i.status === "WATCHING"));
});
