// Offline tests for credits entity resolution (catalogue Task 7b): people, companies, characters.
// Fake supabase only. wikidata_people_live.json / wikidata_companies_live.json are live WDQS replies
// (fixtures/README.md); the AniList-staff link case is hand-built because no live person in the
// sample carried a P11227 value.
// Run: cd supabase/functions/catalogue-intake && deno test --no-prompt
import { strict as assert } from "node:assert";
import { PoliteLimiter } from "../_shared/polite_fetch.ts";
import { createSourceClient } from "../_shared/catalogue/source_http.ts";
import { fakeSupabase, queuedFetch, type Row } from "./fake_supabase.ts";
import {
  composeCredits,
  crosswalkKey,
  normaliseName,
  resolveAuthor,
  resolveCharacter,
  resolvePerson,
  resolveStudio,
} from "./entities.ts";
import { buildEntityQuery, parseEntityBindings, runEntityCrosswalk, wikidataEntityCrosswalk } from "./wikidata.ts";
import peopleLive from "./fixtures/wikidata_people_live.json" with { type: "json" };
import companiesLive from "./fixtures/wikidata_companies_live.json" with { type: "json" };

const fast = { sleep: () => Promise.resolve(), now: () => 0, random: () => 0 };
const crosswalkRec = (kind: "person" | "company", key: string, payload: Row): Row => ({
  source: "wikidata", source_key: crosswalkKey(kind, key), medium: "anime", payload, payload_hash: "h", licence: "CC0-1.0",
});
const staff = (id: number, name: string, anilist: number | null = null): Row => ({ id, anilist_id: anilist, name_full: name, name_native: null, name_romaji: null });
const links = (db: ReturnType<typeof fakeSupabase>) => db.tables.catalogue_id_links ?? [];

Deno.test("normaliseNameIgnoresOrderCaseAndDiacritics", () => {
  assert.equal(normaliseName("SAWANO Hiroyuki"), normaliseName("Hiroyuki Sawano"));
  assert.equal(normaliseName("Kōji  Mori"), normaliseName("koji mori"));
  assert.equal(normaliseName("  "), "");
});

Deno.test("wikidataPersonLinksExistingStaff", async () => {
  const db = fakeSupabase({
    tables: {
      staff: [staff(7, "Hiroyuki Sawano", 555), staff(9, "Someone Else", 556)],
      catalogue_source_records: [crosswalkRec("person", "3610", { qid: "Q1", anilistStaffId: 555 })],
    },
  });
  const got = await resolvePerson({ supabase: db.client, medium: "anime" }, "ann", "3610", "SAWANO Hiroyuki", 1);
  assert.deepEqual(got, { kuroId: 7, created: false });
  assert.deepEqual(links(db).map((l) => [l.kind, l.kuro_id, l.source, l.source_key, l.method, l.status]), [["staff", 7, "ann", "3610", "wikidata", "accepted"]]);
  // A second resolution reuses the accepted link (no new link row).
  const again = await resolvePerson({ supabase: db.client, medium: "anime" }, "ann", "3610", "SAWANO Hiroyuki", 2);
  assert.deepEqual(again, { kuroId: 7, created: false });
  assert.equal(links(db).length, 1);
});

Deno.test("wikidataPersonWhoseNameDisagreesIsOnlyProposed", async () => {
  // Wikidata is openly editable: a crosswalk to a staff row whose name does not agree is not accepted.
  const db = fakeSupabase({
    tables: { staff: [staff(7, "Hiroyuki Sawano", 555)], catalogue_source_records: [crosswalkRec("person", "3610", { qid: "Q1", anilistStaffId: 555 })] },
  });
  const got = await resolvePerson({ supabase: db.client, medium: "anime" }, "ann", "3610", "Totally Different", 1);
  assert.ok("proposedNew" in got);
  assert.deepEqual(links(db).map((l) => [l.kuro_id, l.method, l.status]), [[7, "wikidata", "proposed"]]);
});

Deno.test("sameNameOnSameTitleReused", async () => {
  const db = fakeSupabase({ tables: { staff: [staff(8, "Yoko Kanno")], anime_staff: [{ anime_id: 1, staff_id: 8, role: "Music" }] } });
  const got = await resolvePerson({ supabase: db.client, medium: "anime" }, "ann", "42", "Kanno Yoko", 1);
  assert.deepEqual(got, { kuroId: 8, created: false });
  assert.deepEqual(links(db).map((l) => [l.kind, l.kuro_id, l.method, l.status]), [["staff", 8, "name_match", "accepted"]]);
});

Deno.test("sameNameOnDifferentTitleNotMerged", async () => {
  const db = fakeSupabase({ tables: { staff: [staff(8, "Yoko Kanno")], anime_staff: [{ anime_id: 2, staff_id: 8 }] } });
  const got = await resolvePerson({ supabase: db.client, medium: "anime", allowCreate: true }, "ann", "42", "Yoko Kanno", 1);
  assert.ok("kuroId" in got && got.created === true && got.kuroId !== 8);
  assert.equal(db.tables.staff.length, 2);
});

Deno.test("sameNameTwiceOnSameTitleGoesToReview", async () => {
  const db = fakeSupabase({
    tables: { staff: [staff(8, "Yoko Kanno"), staff(9, "Kanno Yoko")], anime_staff: [{ anime_id: 1, staff_id: 8 }, { anime_id: 1, staff_id: 9 }] },
  });
  const got = await resolvePerson({ supabase: db.client, medium: "anime", allowCreate: true }, "ann", "42", "Yoko Kanno", 1);
  assert.deepEqual(got, { review: true, reason: "ambiguous_name_on_title" });
  assert.equal(db.tables.staff.length, 2);
  assert.equal(links(db).length, 0);
});

Deno.test("newPersonCreatedWithNullAniListId", async () => {
  const db = fakeSupabase({ tables: { staff: [] } });
  const got = await resolvePerson({ supabase: db.client, medium: "anime", allowCreate: true }, "ann", "77", "New Person", 1);
  assert.ok("kuroId" in got && got.created);
  const row = db.tables.staff[0];
  assert.equal(row.anilist_id, null);
  assert.equal(row.name_full, "New Person");
  assert.deepEqual(links(db).map((l) => [l.kind, l.source, l.source_key, l.status]), [["staff", "ann", "77", "accepted"]]);
});

Deno.test("shadowModeProposesInsteadOfInserting", async () => {
  const db = fakeSupabase({ tables: { staff: [] } });
  const got = await resolvePerson({ supabase: db.client, medium: "anime" }, "ann", "77", "New Person", 1);
  assert.deepEqual(got, { proposedNew: { kind: "staff", source: "ann", sourceKey: "77", name: "New Person" } });
  assert.equal(db.tables.staff.length, 0);
  assert.equal(db.opsOn("staff").length, 0);
});

Deno.test("studioMatchesOnSameTitleThenCreates", async () => {
  const db = fakeSupabase({
    tables: { studios: [{ id: 3, anilist_id: 9, name: "Madhouse", name_romaji: null, name_native: null }], anime_studios: [{ anime_id: 1, studio_id: 3 }] },
  });
  const hit = await resolveStudio({ supabase: db.client, medium: "anime" }, "ann", "160", "MADHOUSE", 1);
  assert.deepEqual(hit, { kuroId: 3, created: false });
  const made = await resolveStudio({ supabase: db.client, medium: "anime", allowCreate: true }, "ann", "161", "Brand New Studio", 1);
  assert.ok("kuroId" in made && made.created);
  assert.equal(db.tables.studios[1].anilist_id, null);
  assert.equal(db.tables.studios[1].name, "Brand New Studio");
});

Deno.test("companyNameFromWikidataLabelHelpsStudioMatch", async () => {
  const db = fakeSupabase({
    tables: {
      studios: [{ id: 3, anilist_id: 9, name: "Feel.", name_romaji: null, name_native: null }],
      anime_studios: [{ anime_id: 1, studio_id: 3 }],
      catalogue_source_records: [crosswalkRec("company", "8883", { qid: "Q307291", label: "Feel" })],
    },
  });
  const got = await resolveStudio({ supabase: db.client, medium: "anime" }, "ann", "8883", "Feel Inc.", 1);
  assert.deepEqual(got, { kuroId: 3, created: false });
});

Deno.test("authorResolvesWithinMangaTitle", async () => {
  const db = fakeSupabase({
    tables: { authors: [{ id: 4, anilist_id: 1, name_full: "Kentaro Miura", name_native: null, name_romaji: null }], manga_authors: [{ manga_id: 5, author_id: 4 }] },
  });
  const got = await resolveAuthor({ supabase: db.client, medium: "manga" }, "mangaupdates", "38824888050", "Miura Kentaro", 5);
  assert.deepEqual(got, { kuroId: 4, created: false });
  assert.equal(links(db)[0].kind, "author");
});

Deno.test("characterMatchedOnlyWithinTitle", async () => {
  const chars = [
    { id: 1, anilist_id: 1, name_full: "Guts", name_native: null, name_alternative: ["Gatsu"] },
    { id: 2, anilist_id: 2, name_full: "Casca", name_native: null, name_alternative: null },
  ];
  const db = fakeSupabase({ tables: { characters: chars, manga_characters: [{ manga_id: 5, character_id: 1 }] } });
  const deps = { supabase: db.client, medium: "manga" as const };
  assert.deepEqual(await resolveCharacter(deps, 5, "gatsu"), { kuroId: 1, created: false });
  // Casca exists in the catalogue but not on this title: never merged across titles.
  const other = await resolveCharacter({ ...deps, allowCreate: true }, 5, "Casca");
  assert.ok("kuroId" in other && other.created && other.kuroId !== 2);
  assert.equal(db.tables.characters.at(-1)?.image_large ?? null, null);
  // shadow mode proposes
  assert.ok("proposedNew" in (await resolveCharacter(deps, 5, "Griffith")));
});

Deno.test("entityQueryBatchesAndParsesLiveFixtures", async () => {
  const q = buildEntityQuery("person", ["3610", "668"]);
  assert.match(q, /wdt:P1982/);
  assert.match(q, /"3610" "668"/);
  const people = parseEntityBindings(peopleLive);
  assert.deepEqual(people.get("68814"), { qid: "Q20038518", anilistStaffId: null, label: null });
  const companies = parseEntityBindings(companiesLive);
  assert.equal(companies.get("8883")?.label, "Feel");
  // 501 keys need two queries
  const { fetch, calls } = queuedFetch([
    new Response(JSON.stringify(peopleLive), { status: 200, headers: { "content-type": "application/sparql-results+json" } }),
    new Response(JSON.stringify({ results: { bindings: [] } }), { status: 200, headers: { "content-type": "application/sparql-results+json" } }),
  ]);
  const client = createSourceClient("wikidata", new PoliteLimiter(0), { ...fast, fetch });
  const db = fakeSupabase();
  const keys = ["68814", ...Array.from({ length: 500 }, (_, i) => String(1000 + i))];
  const res = await wikidataEntityCrosswalk({ supabase: db.client, client }, "person", keys);
  assert.equal(calls.length, 2);
  assert.equal(res.queries, 2);
  // Every key gets a record, a negative one when Wikidata has no item.
  const stored = db.tables.catalogue_source_records ?? [];
  assert.equal(stored.length, 501);
  assert.equal(stored.filter((r) => (r.payload as { qid: string | null }).qid === null).length, 500);
});

Deno.test("composeCreditsListsKuroIdsAndRoles", async () => {
  const db = fakeSupabase({
    tables: {
      staff: [staff(8, "Yoko Kanno")],
      anime_staff: [{ anime_id: 1, staff_id: 8 }],
      studios: [],
      characters: [{ id: 1, anilist_id: 1, name_full: "Spike Spiegel", name_native: null, name_alternative: null }],
      anime_characters: [{ anime_id: 1, character_id: 1 }],
    },
  });
  const annRecord = {
    staff: [{ task: "Music", personId: 42, name: "Yoko Kanno" }, { task: "Director", personId: 43, name: "Shinichiro Watanabe" }],
    cast: [{ role: "Spike Spiegel", personId: 1, name: "Koichi Yamadera", lang: "JA" }, { role: "Spike Spiegel", personId: 2, name: "Steven Blum", lang: "EN" }],
    companies: [{ task: "Animation Production", companyId: 8, name: "Sunrise" }],
  };
  const out = await composeCredits({ supabase: db.client, medium: "anime" }, 1, { ann: annRecord as never });
  const byField = Object.fromEntries(out.fields.map((f) => [f.field, f.value]));
  assert.deepEqual(byField["credits:staff"], [{ kuro_id: 8, role: "Music" }]);
  assert.equal(byField["credits:characters"] instanceof Array && (byField["credits:characters"] as unknown[]).length, 1);
  // Unresolved new people and companies are proposals, never inserts, in shadow mode.
  const proposed = byField["credits:proposed_entities"] as { kind: string; name: string }[];
  assert.deepEqual(proposed.map((p) => [p.kind, p.name]).sort(), [["staff", "Shinichiro Watanabe"], ["studio", "Sunrise"]]);
  assert.equal(db.opsOn("staff").length, 0);
  assert.equal(db.opsOn("studios").length, 0);
  assert.equal(out.fields.every((f) => f.source === "ann"), true);
});

Deno.test("entityCrosswalkAsksEachKeyOnceAndAdvancesCursor", async () => {
  const annPayload = { staff: [{ task: "Music", personId: 68814, name: "X" }], companies: [{ task: "Animation Production", companyId: 8883, name: "Feel" }, { task: "Distribution", companyId: 5, name: "D" }] };
  const db = fakeSupabase({ tables: { catalogue_source_records: [{ source: "ann", source_key: "4658", medium: "anime", payload: annPayload }, { source: "ann", source_key: "report:anime", medium: "anime", payload: { items: [] } }] } });
  const ok = (j: unknown) => new Response(JSON.stringify(j), { status: 200, headers: { "content-type": "application/sparql-results+json" } });
  const net = queuedFetch([ok(peopleLive), ok(companiesLive)]);
  const client = createSourceClient("wikidata", new PoliteLimiter(0), { ...fast, fetch: net.fetch });
  const ctx = { supabase: db.client, clients: { wikidata: client } as never, medium: "anime" as const, limit: undefined, deadlineMs: Date.now() + 60_000, now: Date.now };
  const first = await runEntityCrosswalk(ctx);
  assert.equal(first.queries, 2);
  assert.match(net.calls[1].body, /"8883"/);
  assert.doesNotMatch(net.calls[1].body, /"5"/, "only production companies are asked");
  const keys = db.tables.catalogue_source_records.filter((r) => r.source === "wikidata").map((r) => r.source_key).sort();
  assert.deepEqual(keys, ["company:ann:8883", "person:ann:68814"]);
  // A second run asks nothing: both keys already have a record.
  const second = await runEntityCrosswalk(ctx);
  assert.equal(second.queries, 0);
});
