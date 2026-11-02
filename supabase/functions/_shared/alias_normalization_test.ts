// F31: one alias key policy for Parse (lookup) and Apply (record). The record-then-lookup check through
// the real concierge-parse handler lives in concierge-parse/handler_test.ts; these cases pin the key rules.
import { assertEquals } from "jsr:@std/assert@1";
import { aliasLookupKeys, legacyApplyAliasKey, normalizeAliasKey } from "./alias_normalization.ts";

Deno.test("EN/DE/rating-bearing lines: the key Apply records is the first key Parse looks up", () => {
  const lines: Array<[string, string]> = [
    ["I watched Attack on Titan 9/10", "attack on titan"],
    ["ich habe Kämpfer gesehen, eine 8", "kaempfer"],
    ["I started reading Berserk", "berserk"],
    ["ich habe Mob Psycho 100 angefangen", "mob psycho 100"],
    ["Fullmetal Alchemist: Brotherhood ⭐⭐⭐", "fullmetal alchemist brotherhood"],
  ];
  for (const [line, key] of lines) {
    assertEquals(normalizeAliasKey(line), key, line);
    assertEquals(aliasLookupKeys(line)[0], normalizeAliasKey(line), line);
  }
});

Deno.test("aliases persisted with the legacy Apply key stay readable: the legacy key is the second lookup key", () => {
  assertEquals(legacyApplyAliasKey("I watched Attack on Titan 9/10"), "attack on titan 9 10");
  assertEquals(aliasLookupKeys("I watched Attack on Titan 9/10"), ["attack on titan", "attack on titan 9 10"]);
  assertEquals(aliasLookupKeys("ich habe Kämpfer gesehen, eine 8"), ["kaempfer", "kämpfer eine 8"]);
});

Deno.test("F82: the key ignores explicit progress phrases but keeps bare numbers that may be part of the title", () => {
  const key = normalizeAliasKey;
  assertEquals(key("naruto episode 50"), "naruto");
  assertEquals(key("naruto episode 51"), key("naruto episode 50"));
  assertEquals(key("I'm watching Naruto ep 220"), "naruto");
  assertEquals(key("One Piece chapter 1100"), "one piece");
  assertEquals(key("AoT up to episode 5"), "aot");
  assertEquals(key("Berserk until chapter 12"), "berserk");
  assertEquals(key("ich habe Berserk gelesen bis Kapitel 200"), "berserk");
  assertEquals(key("Naruto Folge 3 von 220"), "naruto");
  assertEquals(key("Berserk Band 3"), "berserk");
  assertEquals(key("Naruto e50"), "naruto");
  // German perfect with a trailing progress phrase: the typed line and the raw the parser rebuilds (R1).
  assertEquals(key("ich habe Vinland Saga gesehen, bis Kapitel 200"), "vinland saga");
  assertEquals(key("ich habe Vinland Saga gesehen bis Kapitel 200"), "vinland saga");
  // Bare numbers stay: they can be the title.
  assertEquals(key("Mob Psycho 100 completed"), "mob psycho 100");
  assertEquals(key("86 completed"), "86");
});

Deno.test("F82: a season number is catalog identity (one entry per season), kept as one token in every notation", () => {
  const key = normalizeAliasKey;
  for (const line of ["AoT season 2 episode 5", "AoT S2E5", "AoT 2x05", "AoT Staffel 2 Folge 5", "AoT season 2"]) {
    assertEquals(key(line), "aot s2", line);
  }
  assertEquals(key("AoT season 3 episode 1"), "aot s3");
});

Deno.test("identical keys are not repeated and empty input has no lookup key", () => {
  assertEquals(aliasLookupKeys("Steins;Gate"), ["steins gate"]);
  assertEquals(aliasLookupKeys(""), []);
  assertEquals(aliasLookupKeys("watched"), []);
});
