// Offline tests for publish (catalogue Task 15). The SQL batch is modelled from its contract in
// publish_model.ts (authority: supabase/tests/rls/124_catalogue_publish_lists.sql).
// Run: cd supabase/functions/catalogue-intake && deno test --no-prompt
import { strict as assert } from "node:assert";
import { FIELD_GROUP_NAMES, type FieldGroup, type Mode } from "../_shared/catalogue/field_groups.ts";
import { fakeSupabase, type Row } from "./fake_supabase.ts";
import { publish, readShadowIds, runPublish } from "./publish.ts";
import { publishModel } from "./publish_model.ts";

function cutover(over: Partial<Record<FieldGroup, Mode>>): Row[] {
  return FIELD_GROUP_NAMES.map((g) => ({ field_group: g, mode: over[g] ?? "anilist" }));
}

function setup(over: Partial<Record<FieldGroup, Mode>>, extra: Record<string, Row[]> = {}) {
  const log: { name: string; args: Row }[] = [];
  const db = fakeSupabase({
    tables: {
      catalogue_cutover: cutover(over),
      anime: [{ id: 1, title_english: "Old", format: "TV", is_adult: true, data_sources: null }],
      catalogue_shadow_values: [
        { medium: "anime", media_id: 1, field: "title_english", value: "New", source: "wikidata", computed_at: "2026-11-18T10:00:00Z" },
        { medium: "anime", media_id: 1, field: "format", value: "MOVIE", source: "ann", computed_at: "2026-11-18T10:00:00Z" },
        { medium: "anime", media_id: 1, field: "is_adult", value: false, source: "ann", computed_at: "2026-11-18T10:00:00Z" },
        { medium: "anime", media_id: 1, field: "data_sources", value: ["wikidata", "ann"], source: "composer", computed_at: "2026-11-18T10:00:00Z" },
      ],
      ...extra,
    },
    rpcHandlers: publishModel(log) as never,
  });
  return { db, log };
}

const noCompose = () => Promise.resolve({ titles: 0, written: 0, unchanged: 0, reviews: 0 });

Deno.test("onlyNewGroupsWritten", async () => {
  const { db, log } = setup({ titles: "new", facts: "shadow", adult: "anilist" });
  const r = await publish({ supabase: db.client }, "anime", [1]);
  assert.deepEqual(log.map((l) => l.args.p_group), ["titles"]);
  assert.deepEqual(log[0].args.p_columns, ["title_english", "title_romaji", "title_native", "title_synonyms"]);
  assert.equal(db.tables.anime[0].title_english, "New");
  assert.equal(db.tables.anime[0].format, "TV", "a group in shadow mode is not written");
  assert.equal(db.tables.anime[0].is_adult, true, "a group in anilist mode is not written");
  assert.ok(r.skippedGroups.includes("facts") && !r.skippedGroups.includes("titles"));
});

Deno.test("dataSourcesRidesWithTheFirstNewGroupOnly", async () => {
  const { db, log } = setup({ titles: "new", facts: "new" });
  await publish({ supabase: db.client }, "anime", [1]);
  assert.deepEqual(log.map((l) => [l.args.p_group, l.args.p_with_data_sources]), [["titles", true], ["facts", false]]);
  assert.deepEqual(db.tables.anime[0].data_sources, ["wikidata", "ann"]);
});

Deno.test("adultNeverClearsThroughPublish", async () => {
  const { db } = setup({ adult: "new" });
  await publish({ supabase: db.client }, "anime", [1]);
  assert.equal(db.tables.anime[0].is_adult, true);
});

Deno.test("noNewGroupMakesNoCalls", async () => {
  const { db, log } = setup({ titles: "shadow" });
  const r = await publish({ supabase: db.client }, "anime", [1]);
  assert.equal(log.length, 0);
  assert.equal(r.skippedGroups.length, 12);
});

Deno.test("batchesAreAtMost500Titles", async () => {
  const { db, log } = setup({ titles: "new" });
  await publish({ supabase: db.client }, "anime", Array.from({ length: 1201 }, (_, i) => i + 1));
  assert.deepEqual(log.map((l) => (l.args.p_media_ids as number[]).length), [500, 500, 201]);
});

Deno.test("firstPublishSnapshotsThenReplacesLinkedRows", async () => {
  const { db } = setup({ credits: "new" }, {
    anime_staff: [{ id: 7, anime_id: 1, staff_id: 100, role: "Old" }],
    catalogue_shadow_values: [{ medium: "anime", media_id: 1, field: "credits:staff", value: [{ kuro_id: 200, role: "Director" }], source: "ann", computed_at: "x" }],
  });
  const composed: number[][] = [];
  await publish({
    supabase: db.client,
    compose: (d, _m, ids) => {
      assert.equal(d.allowCreate, true);
      composed.push(ids);
      return noCompose();
    },
  }, "anime", [1]);
  assert.deepEqual(composed, [[1]], "credits creation runs through the composer with allowCreate before the SQL batch");
  assert.deepEqual(db.tables.anime_staff.map((r) => [r.staff_id, r.role]), [[200, "Director"]]);
  const snap = db.tables.catalogue_rollback_snapshots[0].payload as { tables: Record<string, Row[]> };
  assert.deepEqual(snap.tables.anime_staff.map((r) => r.id), [7], "the snapshot holds the pre-switch rows");
});

Deno.test("composerIsNotRunUnlessCreditsIsNew", async () => {
  const { db } = setup({ titles: "new" });
  await publish({ supabase: db.client, compose: () => { throw new Error("must not compose"); } }, "anime", [1]);
});

Deno.test("relationsKeepAniListRowsAndAddKuroRows", async () => {
  const { db } = setup({ relations: "new" }, {
    media_relations: [{ from_media_id: 1, relation_type: "SEQUEL", to_media_id: 2, source: "anilist" }],
    catalogue_shadow_values: [{
      medium: "anime", media_id: 1, field: "relations", source: "wikidata", computed_at: "x",
      value: [{ type: "SEQUEL", kind: "anime", target_id: 3, status: "accepted" }, { type: "PREQUEL", kind: "anime", target_id: 4, status: "proposed" }],
    }],
  });
  await publish({ supabase: db.client }, "anime", [1]);
  assert.deepEqual(db.tables.media_relations.map((r) => `${r.source}:${r.to_media_id}`).sort(), ["anilist:2", "kuro:3"]);
});

Deno.test("aFailedBatchThrows", async () => {
  const failing = fakeSupabase({
    tables: { catalogue_cutover: cutover({ titles: "new" }) },
    rpcHandlers: { catalogue_publish_batch_v1: () => ({ data: null, error: { message: "boom" } }) },
  });
  await assert.rejects(() => publish({ supabase: failing.client }, "anime", [1]), /boom/);
});

Deno.test("unreadableCutoverFailsClosed", async () => {
  const db = fakeSupabase({ tables: {} });
  await assert.rejects(() => publish({ supabase: db.client }, "anime", [1]), /catalogue_cutover/);
});

Deno.test("shadowIdsPagePastTheThousandRowCap", async () => {
  // Shadow rows are 3 per title over 700 titles = 2,100 rows. The fake does not cap, so cap pages here.
  const rows: Row[] = [];
  for (let id = 1; id <= 700; id++) for (const f of ["a", "b", "c"]) rows.push({ medium: "anime", media_id: id, field: f, computed_at: "2026-11-18T10:00:00Z" });
  const db = fakeSupabase({ tables: { catalogue_shadow_values: rows } });
  const ids = await readShadowIds(db.client, "anime", 0, null, 5000);
  assert.equal(ids.length, 700);
  assert.equal(new Set(ids).size, 700);
  assert.ok(db.reads.filter((r) => r.table === "catalogue_shadow_values").length >= 2, "more than one page was read");
});

function ctxFor(db: ReturnType<typeof fakeSupabase>, nowIso: string) {
  return { supabase: db.client, clients: {} as never, medium: "anime" as const, limit: undefined, deadlineMs: Number.MAX_SAFE_INTEGER, now: () => Date.parse(nowIso) };
}

Deno.test("runPublishKeepsAWatermarkPerGroupAndSkipsUnchangedTitles", async () => {
  const { db, log } = setup({ titles: "new" });
  const first = await runPublish(ctxFor(db, "2026-11-18T12:00:00Z"));
  assert.equal(first.results.titles, 1);
  assert.equal(log.length, 1);
  const second = await runPublish(ctxFor(db, "2026-11-18T12:30:00Z"));
  assert.equal(second.results.titles, 0, "nothing computed since the last completed pass");
  assert.equal(log.length, 1);
  for (const r of db.tables.catalogue_shadow_values) r.computed_at = "2026-11-18T13:00:00Z";
  const third = await runPublish(ctxFor(db, "2026-11-18T14:00:00Z"));
  assert.equal(third.results.titles, 1);
});

Deno.test("aGroupSwitchedBackLosesItsWatermark", async () => {
  const { db } = setup({ titles: "new" });
  await runPublish(ctxFor(db, "2026-11-18T12:00:00Z"));
  const titles = db.tables.catalogue_cutover.find((r) => r.field_group === "titles")!;
  titles.mode = "anilist";
  await runPublish(ctxFor(db, "2026-11-18T12:10:00Z"));
  titles.mode = "new";
  const again = await runPublish(ctxFor(db, "2026-11-18T12:20:00Z"));
  assert.equal(again.results.titles, 1, "a re-switched group starts from the beginning");
});
