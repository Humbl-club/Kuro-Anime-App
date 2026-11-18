// Tests for store.ts persistence helpers: paging past PostgREST's row cap, idempotent proposed links.
// Run: cd supabase/functions/catalogue-intake && deno test --no-prompt
import { strict as assert } from "node:assert";
import { fakeSupabase, type Row } from "./fake_supabase.ts";
import { applyLinks, selectAll } from "./store.ts";

Deno.test("fakeSupabaseEnforcesTheRowCap", async () => {
  const rows: Row[] = Array.from({ length: 1500 }, (_, i) => ({ id: i + 1 }));
  const db = fakeSupabase({ tables: { t: rows } });
  const plain = await db.client.from("t").select("id");
  assert.equal(plain.data.length, 1000, "an unpaged select is truncated at 1000");
  const limited = await db.client.from("t").select("id").limit(5000);
  assert.equal(limited.data.length, 1000, "a larger limit is capped too");
  const small = fakeSupabase({ tables: { t: rows }, maxRows: 10 });
  assert.equal((await small.client.from("t").select("id")).data.length, 10);
  const all = await selectAll<Row>(() => db.client.from("t").select("id"), ["id"], "t");
  assert.equal(all.length, 1500, "selectAll pages past the cap");
  assert.deepEqual(all.map((r) => r.id), rows.map((r) => r.id));
});

Deno.test("applyLinksSeesAnAcceptedLinkBeyondTheFirstThousandRows", async () => {
  // Title 1 holds 1,100 proposed links and, last, one accepted link. A truncated read never sees the accepted one.
  const links: Row[] = Array.from({ length: 1100 }, (_, i) => ({ id: i + 1, kind: "anime", kuro_id: 1, source: "wikidata", source_key: `QP${i}`, status: "proposed" }));
  links.push({ id: 5000, kind: "anime", kuro_id: 1, source: "wikidata", source_key: "QACCEPTED", status: "accepted" });
  const db = fakeSupabase({ tables: { catalogue_id_links: links } });
  const res = await applyLinks(db.client, "anime", [{ kuroId: 1, source: "wikidata", sourceKey: "QNEW", method: "wikidata", confidence: 1, status: "accepted" }]);
  assert.equal(res.accepted, 0);
  assert.ok(res.conflicts.some((c) => c.reason === "title_already_linked_to_other_key"), JSON.stringify(res.conflicts));
  assert.equal(db.tables.catalogue_id_links.filter((l) => l.status === "accepted").length, 1);
});

Deno.test("repeatedProposedLinkIsNotWrittenTwice", async () => {
  const db = fakeSupabase();
  const cand = { kuroId: 1, source: "ann" as const, sourceKey: "9", method: "title_match" as const, confidence: 0.5, status: "proposed" as const };
  await applyLinks(db.client, "anime", [cand]);
  const again = await applyLinks(db.client, "anime", [cand]);
  assert.equal(again.proposed, 0);
  assert.equal(db.tables.catalogue_id_links.length, 1);
});
