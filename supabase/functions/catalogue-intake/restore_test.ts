// Offline tests for restore (catalogue Task 15). Run: cd supabase/functions/catalogue-intake && deno test --no-prompt
import { strict as assert } from "node:assert";
import { FIELD_GROUP_NAMES, type FieldGroup, type Mode } from "../_shared/catalogue/field_groups.ts";
import { fakeSupabase, type Row } from "./fake_supabase.ts";
import { publish } from "./publish.ts";
import { publishModel } from "./publish_model.ts";
import { restore } from "./restore.ts";

const cutover = (over: Partial<Record<FieldGroup, Mode>>): Row[] => FIELD_GROUP_NAMES.map((g) => ({ field_group: g, mode: over[g] ?? "anilist" }));
const SWITCHED = ["titles", "facts", "credits", "relations"] as const;
const noCompose = () => Promise.resolve({ titles: 0, written: 0, unchanged: 0, reviews: 0 });

Deno.test("rollbackRestoresSnapshotWithoutBlanking", async () => {
  // Any AniList request would go through fetch: count it.
  const realFetch = globalThis.fetch;
  let requests = 0;
  globalThis.fetch = (() => {
    requests++;
    return Promise.reject(new Error("no network in restore"));
  }) as typeof fetch;
  try {
    const db = fakeSupabase({
      tables: {
        catalogue_cutover: cutover({}),
        anime: [{ id: 1, title_english: "Old", title_romaji: "Old R", format: "TV", episodes: 12, data_sources: null }],
        anime_staff: [{ id: 7, anime_id: 1, staff_id: 100, role: "Old" }],
        media_relations: [{ from_media_id: 1, relation_type: "SEQUEL", to_media_id: 2, source: "anilist" }],
        catalogue_shadow_values: [
          { medium: "anime", media_id: 1, field: "title_english", value: "New", computed_at: "x" },
          { medium: "anime", media_id: 1, field: "format", value: "MOVIE", computed_at: "x" },
          { medium: "anime", media_id: 1, field: "credits:staff", value: [{ kuro_id: 200, role: "Director" }], computed_at: "x" },
          { medium: "anime", media_id: 1, field: "relations", value: [{ type: "SEQUEL", kind: "anime", target_id: 3, status: "accepted" }], computed_at: "x" },
        ],
      },
      rpcHandlers: publishModel() as never,
    });
    const noBlank = () => {
      const a = db.tables.anime[0];
      for (const c of ["title_english", "title_romaji", "format", "episodes"]) assert.notEqual(a[c] ?? null, null, `${c} blank`);
    };
    // a column that is null and an absent column are the same state (the SQL snapshot lists every column)
    const state = () => JSON.stringify([db.tables.anime[0], db.tables.anime_staff, db.tables.media_relations], (_k, v) => (v === null ? undefined : v));
    const mode = (g: string, m: Mode) => {
      db.tables.catalogue_cutover.find((r) => r.field_group === g)!.mode = m;
    };
    const before = state();

    for (const g of SWITCHED) mode(g, "new");
    await publish({ supabase: db.client, compose: noCompose }, "anime", [1]);
    noBlank();
    assert.equal(db.tables.anime[0].title_english, "New");
    assert.notEqual(state(), before);

    await assert.rejects(() => restore({ supabase: db.client }, "titles"), /still 'new'/);
    for (const g of SWITCHED) mode(g, "anilist");
    for (const g of SWITCHED) {
      await restore({ supabase: db.client }, g);
      noBlank();
    }
    assert.equal(state(), before, "columns and linked rows equal the pre-switch state");
    assert.equal(db.tables.catalogue_rollback_snapshots.length, 0);
    assert.equal(requests, 0, "no AniList (or any network) request");
  } finally {
    globalThis.fetch = realFetch;
  }
});

Deno.test("restoreRecordsItsDurationInImportRuns", async () => {
  let t = 1_000;
  const db = fakeSupabase({ tables: { catalogue_cutover: cutover({}), anime: [], manga: [] }, rpcHandlers: publishModel() as never });
  const r = await restore({ supabase: db.client, now: () => (t += 250) }, "facts");
  assert.ok(r.durationMs > 0);
  assert.equal(db.tables.import_runs[0].run_type, "catalogue_restore_facts");
});

Deno.test("restoreBatchesUntilNothingRemains", async () => {
  const log: { name: string; args: Row }[] = [];
  let remaining = 1200;
  const db = fakeSupabase({
    tables: { catalogue_cutover: cutover({}) },
    rpcHandlers: {
      catalogue_restore_batch_v1: (args: Row) => {
        log.push({ name: "r", args });
        const n = args.p_medium === "anime" ? Math.min(500, remaining) : 0;
        remaining -= n;
        return { data: { restored: n, remaining: args.p_medium === "anime" ? remaining : 0 }, error: null };
      },
    },
  });
  const r = await restore({ supabase: db.client }, "adult");
  assert.equal(r.restored.anime, 1200);
  assert.ok(log.every((l) => l.args.p_limit === 500));
});

Deno.test("restoreOfAnUnknownGroupIsRefused", async () => {
  const db = fakeSupabase({ tables: { catalogue_cutover: cutover({}) } });
  await assert.rejects(() => restore({ supabase: db.client }, "colour" as FieldGroup), /unknown group/);
});

Deno.test("restoring identity makes every list_only title visible again", async () => {
  const applied: Row[] = [];
  let remaining = 2;
  const db = fakeSupabase({
    tables: { catalogue_cutover: cutover({}) },
    rpcHandlers: {
      catalogue_restore_batch_v1: () => ({ data: { restored: 0, remaining: 0 }, error: null }),
      catalogue_apply_visibility_v1: (args: Row) => {
        applied.push(args);
        const n = remaining;
        remaining = 0;
        return { data: n, error: null };
      },
    },
  });
  await restore({ supabase: db.client }, "identity");
  assert.deepEqual(applied.map((a) => a.p_medium), ["anime", "anime", "manga"]);
});

Deno.test("restoring another group does not touch visibility", async () => {
  const db = fakeSupabase({
    tables: { catalogue_cutover: cutover({}) },
    rpcHandlers: {
      catalogue_restore_batch_v1: () => ({ data: { restored: 0, remaining: 0 }, error: null }),
      catalogue_apply_visibility_v1: () => {
        throw new Error("must not be called");
      },
    },
  });
  await restore({ supabase: db.client }, "titles");
});
