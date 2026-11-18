// Offline tests for Kuro tag assignment (catalogue Task 11). Pure functions, no I/O.
import { strict as assert } from "node:assert";
import { assignTags, MAX_TAGS_PER_TITLE, parseTagMapCsv, type TagMapRow } from "./tags.ts";

const map: TagMapRow[] = [
  { source: "ann", source_label: "Action", tag_id: 1, weight: 1 },
  { source: "wikidata", source_label: "Q1", tag_id: 1, weight: 0.5 },
  { source: "ann", source_label: "Comedy", tag_id: 2, weight: 1 },
  { source: "mangaupdates", source_label: "Isekai", tag_id: 3, weight: 1 },
  { source: "mangaupdates", source_label: "Time Travel", tag_id: 4, weight: 1 },
];

Deno.test("rankIsWeightedShare", () => {
  // tag 1 scores 1 + 0.5, tag 2 scores 1; ranks are shares of the strongest tag (0-100).
  const out = assignTags([{ source: "ann", label: "action" }, { source: "wikidata", label: "Q1" }, { source: "ann", label: "COMEDY" }], map);
  assert.deepEqual(out, [{ tag_id: 1, rank: 100 }, { tag_id: 2, rank: 67 }]);
});

Deno.test("categoryNeedsTwoVotes", () => {
  assert.deepEqual(assignTags([{ source: "mangaupdates", label: "Isekai", votes: 1 }], map), []);
  assert.deepEqual(assignTags([{ source: "mangaupdates", label: "Isekai", votes: 0 }], map), []);
  assert.deepEqual(assignTags([{ source: "mangaupdates", label: "Isekai", votes: 2 }], map), [{ tag_id: 3, rank: 100 }]);
  // A genre carries no vote count and always counts.
  assert.deepEqual(assignTags([{ source: "mangaupdates", label: "Isekai" }], map), [{ tag_id: 3, rank: 100 }]);
});

Deno.test("capsAt20", () => {
  const big: TagMapRow[] = Array.from({ length: 30 }, (_, i) => ({ source: "ann", source_label: `L${i}`, tag_id: 100 + i, weight: 1 + i / 100 }));
  const out = assignTags(big.map((m) => ({ source: "ann" as const, label: m.source_label })), big);
  assert.equal(out.length, MAX_TAGS_PER_TITLE);
  assert.equal(MAX_TAGS_PER_TITLE, 20);
  assert.equal(out[0].tag_id, 129, "strongest first");
  assert.ok(out.every((t, i) => i === 0 || out[i - 1].rank >= t.rank));
});

Deno.test("unmappedLabelIgnored", () => {
  assert.deepEqual(assignTags([{ source: "ann", label: "Nonexistent" }], map), []);
  // A label only counts for its own source.
  assert.deepEqual(assignTags([{ source: "ann", label: "Isekai" }], map), []);
  assert.deepEqual(assignTags([], map), []);
});

Deno.test("duplicateLabelsCountOnce", () => {
  const out = assignTags([{ source: "ann", label: "Action" }, { source: "ann", label: "action" }, { source: "ann", label: "Comedy" }], map);
  assert.deepEqual(out, [{ tag_id: 1, rank: 100 }, { tag_id: 2, rank: 100 }]);
});

Deno.test("onlyReviewedYesRowsWithATagIdAreLoaded", () => {
  const csv = [
    "source,source_label,tag_name,tag_id,weight,reviewed,note",
    "ann,Action,Action,1,1,yes,",
    "ann,Comedy,Comedy,2,1,no,",
    "ann,Drama,Drama,,1,yes,no tag id",
    'mangaupdates,"Slice, of Life",Slice of Life,5,1,YES,quoted comma',
    "anidb,Action,Action,1,1,yes,excluded source",
    "ann,Bad,Bad,7,0,yes,non-positive weight",
    "ann,Blank,Blank,8,,yes,default weight",
  ].join("\n");
  const rows = parseTagMapCsv(csv);
  assert.deepEqual(rows, [
    { source: "ann", source_label: "Action", tag_id: 1, weight: 1 },
    { source: "mangaupdates", source_label: "Slice, of Life", tag_id: 5, weight: 1 },
    { source: "ann", source_label: "Blank", tag_id: 8, weight: 1 },
  ]);
});

Deno.test("anUnreviewedCsvPublishesNothing", () => {
  const csv = ["source,source_label,tag_name,tag_id,weight,reviewed,note", "ann,Action,Action,1,1,no,", "ann,Comedy,Comedy,2,1,,"].join("\n");
  assert.deepEqual(parseTagMapCsv(csv), []);
  assert.deepEqual(assignTags([{ source: "ann", label: "Action" }], parseTagMapCsv(csv)), []);
});
