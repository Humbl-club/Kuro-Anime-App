// Offline tests for title normalisation (Task 4).
// Run: cd supabase/functions/_shared && deno test --no-prompt catalogue/
import { strict as assert } from "node:assert";
import { normaliseTitle } from "./normalise_title.ts";

const cases: [string, string][] = [
  ["Shingeki no Kyojin Season 2", "shingeki no kyojin s2"],
  ["Re:ZERO -Starting Life in Another World-", "re zero starting life in another world"],
  ["ＳＰＹ×ＦＡＭＩＬＹ", "spy family"],
  ["The Seven Deadly Sins", "seven deadly sins"],
  ["A Silent Voice", "silent voice"],
  ["Attack on Titan 2nd Season", "attack on titan s2"],
  ["Overlord 4th Season", "overlord s4"],
  ["Mob Psycho 100 II", "mob psycho 100 s2"],
  ["Sword Art Online III", "sword art online s3"],
  ["Attack on Titan: Final Season Part 2", "attack on titan final season s2"],
  ["Kaguya-sama: Love is War", "kaguya sama love is war"],
  ["Pokémon  Journeys", "pokemon journeys"],
  ["鬼滅の刃　遊郭編", "鬼滅の刃 遊郭編"],
  ["Gintama'", "gintama"],
  ["  !!!  ", ""],
];

for (const [input, expected] of cases) {
  Deno.test(`normalises ${JSON.stringify(input)}`, () => {
    assert.equal(normaliseTitle(input), expected);
  });
}

Deno.test("keepsKanaVoicingMarks", () => {
  // Combining marks of kana are not diacritics to strip: が must stay が.
  assert.equal(normaliseTitle("ガンダム"), "ガンダム");
});

Deno.test("aLoneIIsNotARomanNumeral", () => {
  assert.equal(normaliseTitle("Hello I"), "hello i");
  assert.equal(normaliseTitle("Season 2"), "s2");
});

Deno.test("isIdempotent", () => {
  for (const [input] of cases) assert.equal(normaliseTitle(normaliseTitle(input)), normaliseTitle(input), input);
});
