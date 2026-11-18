// Link-trust tests for queued credit links (security review 2026-11-18): a candidate queued for batching must not be
// treated as accepted before applyLinks has run its conflict checks, and credits must match what was persisted.
import { strict as assert } from "node:assert";
import { fakeSupabase } from "./fake_supabase.ts";
import { composeCredits, type EntityDeps } from "./entities.ts";
import { parseAnnApi } from "./ann.ts";
import { ANN_API_ONE } from "./fixtures/ann_fixtures.ts";

const annRecord = parseAnnApi(ANN_API_ONE).records[0];
const person = (personId: number, name: string, task = "Script") => ({ task, personId, name });
const staffRow = (id: number, name: string) => ({ id, anilist_id: null, name_full: name, name_native: null, name_romaji: null });

Deno.test("twoCreditsClaimingOneKeyForDifferentPeopleAreNotCachedOrPersistedAsAccepted", async () => {
  const db = fakeSupabase({
    tables: {
      staff: [staffRow(1, "Alpha One"), staffRow(2, "Beta Two")],
      anime_staff: [{ anime_id: 1, staff_id: 1 }, { anime_id: 1, staff_id: 2 }],
    },
  });
  const linkMap = new Map<string, number | null>();
  const deps: EntityDeps = { supabase: db.client, medium: "anime", linkMap };
  const ann = { ...annRecord, staff: [person(9001, "Alpha One"), person(9001, "Beta Two", "Music")], companies: [], cast: [] };
  const { fields } = await composeCredits(deps, 1, { ann });
  const k = "staff|ann|9001";
  assert.ok(![1, 2].includes(Number(linkMap.get(k))), `the contested key was cached as accepted: ${linkMap.get(k)}`);
  assert.equal((db.tables.catalogue_id_links ?? []).filter((l) => l.status === "accepted").length, 0, "applyLinks accepted neither");
  assert.equal(fields.find((f) => f.field === "credits:staff"), undefined, "neither credit is published as resolved");
  const review = fields.find((f) => f.field === "credits:review")?.value as { sourceKey: string; reason: string }[];
  assert.equal(review.length, 2);
  assert.ok(review.every((r) => r.sourceKey === "9001" && r.reason === "link_not_accepted"));
});

Deno.test("aSecondTitleUsesTheLinkTheFirstOnePersisted", async () => {
  const db = fakeSupabase({
    tables: {
      staff: [staffRow(1, "Alpha One"), staffRow(3, "Alpha One")],
      anime_staff: [{ anime_id: 1, staff_id: 1 }, { anime_id: 2, staff_id: 3 }],
    },
  });
  const deps: EntityDeps = { supabase: db.client, medium: "anime", linkMap: new Map(), crosswalkMap: new Map(), creditedCache: new Map() };
  const ann = { ...annRecord, staff: [person(9001, "Alpha One")], companies: [], cast: [] };
  const first = await composeCredits(deps, 1, { ann });
  assert.deepEqual(first.fields.find((f) => f.field === "credits:staff")?.value, [{ kuro_id: 1, role: "Script" }]);
  assert.equal(deps.linkMap?.get("staff|ann|9001"), 1, "cached after applyLinks accepted it");
  const second = await composeCredits(deps, 2, { ann });
  // Title 2 credits a different row with the same name; the persisted accepted link wins and the credit follows it.
  assert.deepEqual(second.fields.find((f) => f.field === "credits:staff")?.value, [{ kuro_id: 1, role: "Script" }]);
  assert.equal(db.tables.catalogue_id_links.filter((l) => l.status === "accepted").length, 1);
});

Deno.test("aKeyTheOwnerRejectedIsNeverCachedAsAccepted", async () => {
  const db = fakeSupabase({
    tables: {
      staff: [staffRow(1, "Alpha One")],
      anime_staff: [{ anime_id: 1, staff_id: 1 }],
      catalogue_id_links: [{ id: 1, kind: "staff", kuro_id: 1, source: "ann", source_key: "9001", method: "name_match", status: "rejected" }],
    },
  });
  const linkMap = new Map<string, number | null>();
  const ann = { ...annRecord, staff: [person(9001, "Alpha One")], companies: [], cast: [] };
  const { fields } = await composeCredits({ supabase: db.client, medium: "anime", linkMap }, 1, { ann });
  assert.equal(linkMap.get("staff|ann|9001") ?? null, null);
  assert.equal(fields.find((f) => f.field === "credits:staff"), undefined);
});
