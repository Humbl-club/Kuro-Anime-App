// Offline tests for keeping the MangaDex /aggregate volume grouping (2026-11-01).
// Pure parser + the repository writer against the shared query fake. No network.
// Run: deno test --no-prompt supabase/functions/manga-chapter-enrich/volumes_test.ts
import { strict as assert } from "node:assert";
import { queryFake } from "../_shared/test_query_fake.ts";
import { parseAggregatePayload } from "./mangadex.ts";
import { upsertVolumeRows, volumeRangeText } from "./repository.ts";

// Shape of GET /manga/{id}/aggregate: volumes keyed by volume number, plus "none".
const AGGREGATE = {
  result: "ok",
  volumes: {
    "1": { volume: "1", count: 8, chapters: { "1": {}, "2": {}, "3": {}, "4": {}, "5": {}, "6": {}, "7": {}, "8": {} } },
    "2": { volume: "2", count: 10, chapters: { "9": {}, "10": {}, "10.5": {}, "17": {} } },
    "none": { volume: "none", count: 2, chapters: { "18": {}, "19": {} } },
  },
};

Deno.test("aggregate parsing keeps volume groups with integer chapter ranges", () => {
  const parsed = parseAggregatePayload(AGGREGATE);
  assert.deepEqual(parsed.chapterNumbers, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 17, 18, 19]);
  assert.equal(parsed.fractionalSkipped, 1);
  assert.deepEqual(parsed.volumes, [
    { volume: 1, firstChapter: 1, lastChapter: 8, chapterCount: 8 },
    { volume: 2, firstChapter: 9, lastChapter: 17, chapterCount: 3 },
  ]);
  assert.deepEqual(parseAggregatePayload({}), { chapterNumbers: [], fractionalSkipped: 0, volumes: [] });
});

Deno.test("volume rows: missing volumes are inserted, placeholders get their range, foreign text is kept", async () => {
  const fake = queryFake({
    tables: {
      volumes: [
        { id: 1, manga_id: 7, number: 1, title: "Volume 1", description: null },
        { id: 2, manga_id: 7, number: 2, title: "Volume 2", description: "Editor note: deluxe edition" },
        { id: 3, manga_id: 8, number: 3, title: "Other manga", description: null },
      ],
    },
  });
  const out = await upsertVolumeRows(fake.client, 7, [
    { volume: 1, firstChapter: 1, lastChapter: 8, chapterCount: 8 },
    { volume: 2, firstChapter: 9, lastChapter: 17, chapterCount: 3 },
    { volume: 3, firstChapter: 18, lastChapter: 18, chapterCount: 1 },
  ]);
  assert.deepEqual(out, { inserted: 1, updated: 1 });
  const rows = fake.tables.volumes;
  assert.equal(rows.find((r) => r.id === 1)?.description, "Chapters 1–8");
  assert.equal(rows.find((r) => r.id === 2)?.description, "Editor note: deluxe edition");
  assert.equal(rows.find((r) => r.id === 3)?.description, null, "another manga's row is untouched");
  const inserted = rows.find((r) => r.manga_id === 7 && r.number === 3);
  assert.deepEqual({ title: inserted?.title, description: inserted?.description }, { title: "Volume 3", description: "Chapter 18" });

  // Re-running with the same grouping writes nothing; a grown range updates the owned row.
  const again = await upsertVolumeRows(fake.client, 7, [{ volume: 1, firstChapter: 1, lastChapter: 8, chapterCount: 8 }]);
  assert.deepEqual(again, { inserted: 0, updated: 0 });
  const grown = await upsertVolumeRows(fake.client, 7, [{ volume: 3, firstChapter: 18, lastChapter: 26, chapterCount: 9 }]);
  assert.deepEqual(grown, { inserted: 0, updated: 1 });
  assert.equal(volumeRangeText(18, 26), "Chapters 18–26");
});
