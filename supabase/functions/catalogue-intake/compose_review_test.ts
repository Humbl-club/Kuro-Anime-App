// Review-fix tests for the shadow composer (2026-11-18): stale shadow values, the 1,000-row cap, the
// time budget inside a title's credits, and bounded round trips per credit. Fake supabase only.
// Run: cd supabase/functions/catalogue-intake && deno test --no-prompt
import { strict as assert } from "node:assert";
import { fakeSupabase, type Row } from "./fake_supabase.ts";
import { compose, runCompose } from "./compose.ts";
import { parseAnnApi } from "./ann.ts";
import { ANN_API_ONE } from "./fixtures/ann_fixtures.ts";
import { PoliteLimiter } from "../_shared/polite_fetch.ts";
import { createSourceClient } from "../_shared/catalogue/source_http.ts";
import { run } from "./handler.ts";

const annRecord = parseAnnApi(ANN_API_ONE).records[0];

const link = (kind: string, kuro_id: number, source: string, source_key: string, status = "accepted"): Row => ({ kind, kuro_id, source, source_key, method: "wikidata", status });
const rec = (source: string, source_key: string, medium: string, payload: unknown): Row => ({ source, source_key, medium, payload, payload_hash: "h", licence: "x" });
const wd = (qid: string, medium: string, props: Record<string, string[]>) => rec("wikidata", qid, medium, { qid, medium, anilist_ids: [], props });
const shadow = (db: ReturnType<typeof fakeSupabase>, field: string, mediaId = 1) => db.tables.catalogue_shadow_values?.find((r) => r.field === field && r.media_id === mediaId);

const manyStaff = (n: number, base = 1000) => Array.from({ length: n }, (_, i) => ({ task: "Script", personId: base + i, name: `Person ${base + i}` }));
const bigAnn = (id: number, staff: number, base = 1000) => ({ ...annRecord, id, staff: manyStaff(staff, base), companies: [], cast: [] });

function animeDb(extra: { anime?: Row[] } = {}) {
  return fakeSupabase({
    tables: {
      anime: extra.anime ?? [{ id: 1, is_adult: false }, { id: 2, is_adult: false }],
      catalogue_id_links: [link("anime", 1, "wikidata", "Q1"), link("anime", 1, "ann", "4658")],
      catalogue_source_records: [
        wd("Q1", "anime", { "label:en": ["Jinki Extend"], "label:ja": ["ジンキ"], P580: ["2005-01-01T00:00:00Z"], P1113: ["12"] }),
        rec("ann", "4658", "anime", annRecord),
      ],
    },
  });
}

Deno.test("reviewFlagClearsWhenCauseIsFixed", async () => {
  const db = animeDb({ anime: [{ id: 1, is_adult: true }] });
  await compose({ supabase: db.client }, "anime", [1]);
  assert.ok(shadow(db, "review:adult"), "flag raised: adult today but no source says so");
  // The cause is fixed: ANN now says adult, so nothing needs the owner's eyes.
  db.tables.catalogue_source_records = db.tables.catalogue_source_records.map((r) => (r.source === "ann" ? { ...r, payload: { ...annRecord, genres: ["erotica"] } } : r));
  const again = await compose({ supabase: db.client }, "anime", [1]);
  assert.equal(shadow(db, "review:adult"), undefined, "the stale flag is deleted");
  assert.ok(again.removed >= 1);
  assert.equal(shadow(db, "is_adult")?.value, true);
});

Deno.test("droppedSourceFieldRemovesShadowRow", async () => {
  const db = animeDb();
  await compose({ supabase: db.client }, "anime", [1]);
  assert.equal(shadow(db, "title_native")?.value, "ジンキ");
  assert.ok(shadow(db, "credits:proposed_entities"), "unmatched credits are proposed");
  assert.equal(shadow(db, "format")?.value, "TV");
  // The ANN link is withdrawn (proposed again) and Wikidata loses the Japanese label: every field only they produced goes.
  db.tables.catalogue_id_links = db.tables.catalogue_id_links.map((l) => (l.source === "ann" ? { ...l, status: "proposed" } : l));
  db.tables.catalogue_source_records = db.tables.catalogue_source_records.map((r) =>
    r.source === "wikidata"
      ? { ...r, payload: { ...(r.payload as { props: Record<string, string[]> }), props: { "label:en": ["Jinki Extend"], P580: ["2005-01-01T00:00:00Z"], P1113: ["12"] } } }
      : r
  );
  const res = await compose({ supabase: db.client }, "anime", [1]);
  assert.equal(shadow(db, "title_native"), undefined, "dropped label field removed");
  assert.equal(shadow(db, "format"), undefined, "a field of the withdrawn source is removed");
  assert.equal(shadow(db, "credits:proposed_entities"), undefined, "credits of the withdrawn source are removed");
  assert.ok(res.removed >= 3);
  assert.equal(shadow(db, "title_english")?.value, "Jinki Extend", "fields still produced stay");
  // Another title's rows are never touched.
  db.tables.catalogue_shadow_values.push({ medium: "anime", media_id: 2, field: "format", value: "TV", source: "ann", computed_at: "x" });
  await compose({ supabase: db.client }, "anime", [1]);
  assert.ok(shadow(db, "format", 2));
});

Deno.test("composeReadsPagePastTheRowCap", async () => {
  // 100 titles with well over 1,000 shadow rows between them: a truncated read would rewrite unchanged rows.
  const ids = Array.from({ length: 100 }, (_, i) => i + 1);
  const db = fakeSupabase({
    tables: {
      anime: ids.map((id) => ({ id, is_adult: false })),
      catalogue_id_links: ids.map((id) => link("anime", id, "wikidata", `Q${id}`)),
      catalogue_source_records: ids.map((id) =>
        wd(`Q${id}`, "anime", { "label:en": [`T${id}`], "label:ja": [`J${id}`], "alias:en": [`A${id}`], P580: ["2005-03-04T00:00:00Z"], P582: ["2005-06-07T00:00:00Z"], P1113: ["12"], P136: ["Q1"], P156: ["Q2"] })
      ),
    },
  });
  const first = await compose({ supabase: db.client }, "anime", ids);
  assert.ok(db.tables.catalogue_shadow_values.length > 1000, `fixture must exceed the cap, has ${db.tables.catalogue_shadow_values.length}`);
  const again = await compose({ supabase: db.client }, "anime", ids);
  assert.equal(again.written, 0, "nothing is rewritten when every row was read");
  assert.equal(again.removed, 0);
  assert.equal(again.unchanged, first.written);
});

Deno.test("composeStopsAtTheBudgetInsideATitleAndKeepsTheCursor", async () => {
  let t = 0;
  const now = () => t++;
  const db = fakeSupabase({
    tables: {
      anime: [{ id: 1, is_adult: false }, { id: 2, is_adult: false }, { id: 3, is_adult: false }],
      catalogue_id_links: [1, 2, 3].map((id) => link("anime", id, "ann", String(4000 + id))),
      catalogue_source_records: [1, 2, 3].map((id) => rec("ann", String(4000 + id), "anime", bigAnn(4000 + id, 30, id * 1000))),
    },
  });
  const out = await runCompose({ supabase: db.client, clients: {} as never, medium: "anime", limit: 10, deadlineMs: 50, now });
  assert.equal(out.stoppedEarly, "budget");
  const cursor = db.tables.import_track_state.find((r) => r.track_key === "catalogue-intake:compose:anime");
  assert.equal((cursor?.last_results as { cursor: { last_id: number } }).cursor.last_id, 1, "cursor at the last fully composed title");
  assert.ok(shadow(db, "credits:proposed_entities", 1), "title 1 is complete");
  assert.equal(shadow(db, "credits:proposed_entities", 2), undefined, "the interrupted title keeps nothing");
  assert.equal(shadow(db, "format", 2), undefined);
  assert.equal(shadow(db, "credits:proposed_entities", 3), undefined);
  assert.equal((out.results as { titles: number }).titles, 1);
});

Deno.test("composeStopReleasesTheLockAndFinishesTheRun", async () => {
  let t = 1_000_000;
  const db = fakeSupabase({
    tables: {
      anime: [{ id: 1, is_adult: false }, { id: 2, is_adult: false }],
      catalogue_id_links: [1, 2].map((id) => link("anime", id, "ann", String(4000 + id))),
      catalogue_source_records: [1, 2].map((id) => rec("ann", String(4000 + id), "anime", bigAnn(4000 + id, 80, id * 1000))),
    },
  });
  const mk = (s: "wikidata" | "ann" | "mangaupdates" | "pageviews") =>
    createSourceClient(s, new PoliteLimiter(0), { sleep: () => Promise.resolve(), now: () => 0, random: () => 0, fetch: (() => Promise.reject(new Error("no network"))) as typeof fetch });
  // Every clock read costs 100 ms; the 5 s minimum budget is crossed inside the first title's credits.
  const res = await run({ handler: "compose", medium: "anime", timeBudgetMs: 5000 }, {
    supabase: db.client,
    clients: { wikidata: mk("wikidata"), ann: mk("ann"), mangaupdates: mk("mangaupdates"), pageviews: mk("pageviews") },
    now: () => (t += 100),
  });
  const body = await res.json();
  assert.equal(body.success, true);
  assert.equal(body.stoppedEarly, "budget");
  assert.ok(db.rpcs.some((r) => r.name === "release_import_lock"), "lock released");
  const cursor = db.tables.import_track_state.find((r) => r.track_key === "catalogue-intake:compose:anime");
  assert.equal((cursor?.last_results as { cursor: { last_id: number } }).cursor.last_id, 0, "no title finished, so the cursor did not move");
  assert.equal(db.tables.catalogue_shadow_values?.length ?? 0, 0, "an interrupted title leaves no rows");
});

Deno.test("creditsRoundTripsAreBoundedPerChunkNotPerCredit", async () => {
  const people = manyStaff(200, 5000);
  const db = fakeSupabase({
    tables: {
      anime: [{ id: 1, is_adult: false }],
      catalogue_id_links: [link("anime", 1, "ann", "7001")],
      catalogue_source_records: [
        rec("ann", "7001", "anime", { ...annRecord, id: 7001, staff: people, companies: [], cast: [] }),
        // the first 100 people have a Wikidata crosswalk naming an AniList staff id
        ...people.slice(0, 100).map((p, i) => rec("wikidata", `person:ann:${p.personId}`, "anime", { annKey: String(p.personId), qid: `Q${i}`, anilistStaffId: 90000 + i, label: null })),
      ],
      staff: people.map((p, i) => ({ id: 200 + i, anilist_id: 90000 + i, name_full: p.name, name_native: null, name_romaji: null })),
      anime_staff: people.map((_, i) => ({ anime_id: 1, staff_id: 200 + i })),
    },
  });
  const res = await compose({ supabase: db.client }, "anime", [1]);
  assert.equal(res.titles, 1);
  const credits = shadow(db, "credits:staff")?.value as { kuro_id: number }[];
  assert.equal(credits.length, 200);
  assert.ok(db.reads.length <= 40, `reads must not grow per credit, got ${db.reads.length}`);
  const linkInserts = db.opsOn("catalogue_id_links", "insert").length;
  assert.ok(linkInserts <= 3, `links are written in batches, got ${linkInserts} insert calls`);
  assert.equal(db.tables.catalogue_id_links.filter((l) => l.kind === "staff" && l.status === "accepted").length, 200);
});
