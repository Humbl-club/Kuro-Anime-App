import { strict as assert } from "node:assert";
import { buildContinuityCandidates } from "./continuity_candidates.ts";
import { parseMuAnimeSpan } from "./map_mangaupdates.ts";

const assertEquals = <T>(actual: T, expected: T) => assert.deepStrictEqual(actual, expected);

Deno.test("buildContinuityCandidates builds linear auto-approvable main spine and adaptation span", () => {
  const span = parseMuAnimeSpan("Vol 1, Chap 1", "Vol 8, Chap 63");
  const rows = buildContinuityCandidates({
    rootMediaType: "anime",
    rootMediaId: 100,
    adaptationSpan: span,
    relations: [
      {
        relationType: "PREQUEL",
        sourceMediaType: "anime",
        sourceMediaId: 100,
        targetMediaType: "anime",
        targetMediaId: 99,
        year: 2020,
      },
      {
        relationType: "SEQUEL",
        sourceMediaType: "anime",
        sourceMediaId: 100,
        targetMediaType: "anime",
        targetMediaId: 101,
        year: 2022,
      },
      {
        relationType: "SEQUEL",
        sourceMediaType: "anime",
        sourceMediaId: 101,
        targetMediaType: "anime",
        targetMediaId: 102,
        year: 2024,
      },
      {
        relationType: "SIDE_STORY",
        targetMediaType: "anime",
        targetMediaId: 200,
        format: "OVA",
        year: 2023,
      },
      {
        relationType: "SOURCE",
        targetMediaType: "manga",
        targetMediaId: 500,
        year: 2018,
      },
    ],
  });

  assertEquals(rows.length, 5);
  assertEquals(rows[0].section_kind, "main");
  assertEquals(rows[0].member_media_id, 99);
  assertEquals(rows[0].ordinal, 1);
  assertEquals(rows[0].auto_approvable, true);

  assertEquals(rows[1].member_media_id, 101);
  assertEquals(rows[1].ordinal, 2);
  assertEquals(rows[2].member_media_id, 102);
  assertEquals(rows[2].ordinal, 3);
  assertEquals(rows[2].auto_approvable, true);

  assertEquals(rows[3].section_kind, "side");
  assertEquals(rows[3].member_media_id, 200);
  assertEquals(rows[3].auto_approvable, false);

  assertEquals(rows[4].section_kind, "adaptation");
  assertEquals(rows[4].member_media_type, "manga");
  assertEquals(rows[4].member_media_id, 500);
  assertEquals(rows[4].source_start_unit, 1);
  assertEquals(rows[4].source_end_unit, 63);
  assertEquals(rows[4].source_volume, 8);
  assertEquals(rows[4].raw_note, "Vol 1, Chap 1 -> Vol 8, Chap 63");
  assertEquals(rows[4].auto_approvable, true);
});

Deno.test("buildContinuityCandidates marks branching main spines and ambiguous adaptations non-auto-approvable", () => {
  const rows = buildContinuityCandidates({
    rootMediaType: "anime",
    rootMediaId: 10,
    relations: [
      {
        relationType: "SEQUEL",
        sourceMediaType: "anime",
        sourceMediaId: 10,
        targetMediaType: "anime",
        targetMediaId: 11,
        year: 2021,
      },
      {
        relationType: "SEQUEL",
        sourceMediaType: "anime",
        sourceMediaId: 10,
        targetMediaType: "anime",
        targetMediaId: 12,
        year: 2022,
      },
      {
        relationType: "ADAPTATION",
        targetMediaType: "manga",
        targetMediaId: 701,
      },
      {
        relationType: "ADAPTATION",
        targetMediaType: "manga",
        targetMediaId: 702,
      },
      {
        // Duplicate of 701 must be deduplicated cleanly
        relationType: "SOURCE",
        targetMediaType: "manga",
        targetMediaId: 701,
      },
    ],
  });

  const mainRows = rows.filter((r) => r.section_kind === "main");
  assertEquals(mainRows.length, 2);
  assertEquals(mainRows.every((r) => !r.auto_approvable), true);

  const adaptRows = rows.filter((r) => r.section_kind === "adaptation");
  assertEquals(adaptRows.length, 2);
  assertEquals(adaptRows.every((r) => !r.auto_approvable), true);
});
