// F31 closure through the REAL handlers (review A6): an alias recorded by concierge-apply's handler is
// found by concierge-parse's handler, and an alias recorded with the legacy Apply key (what deployed Apply
// wrote before the switch to the shared module) is still found. One controlled store (test_query_fake.ts)
// is shared by both handlers, so the title_aliases row Apply writes is the row Parse reads. Fakes only:
// the list write itself is the `apply_import_session` transaction, answered here by a stub service client.
import { assertEquals } from "jsr:@std/assert@1";
import { handleApply } from "../concierge-apply/handler.ts";
import { handleParse } from "../concierge-parse/handler.ts";
import { legacyApplyAliasKey, normalizeAliasKey } from "./alias_normalization.ts";
import { queryFake } from "./test_query_fake.ts";

const USER = "6f1c1b0e-0000-4000-8000-000000000003";
const LEGACY_LINE = "I watched Kämpfer 8/10";
// deno-lint-ignore no-explicit-any
type Json = any;

const CATALOG = [
  { media_type: "ANIME", media_id: 16498, title_raw: "Attack on Titan", score: 0.2 },
  { media_type: "ANIME", media_id: 99147, title_raw: "Attack on Titan: Junior High", score: 0.6 },
  { media_type: "ANIME", media_id: 7001, title_raw: "Kämpfer", score: 0.3 },
  { media_type: "ANIME", media_id: 7099, title_raw: "Kämpfer für die Liebe", score: 0.7 },
];

function store() {
  return queryFake({
    user: { id: USER },
    tables: {
      // Written by the OLD deployed Apply (weaker key, no umlaut folding, rating kept) for the line
      // "I watched Kämpfer 8/10" (the parse raw of that line is the line itself, asserted below).
      title_aliases: [{ user_id: USER, alias_norm: legacyApplyAliasKey(LEGACY_LINE), media_type: "ANIME", media_id: 7001, title_raw: "Kämpfer", hits: 2 }],
    },
    rpc: {
      check_concierge_rate_limit: { data: { allowed: true }, error: null },
      search_titles: (a) => {
        const words = String(a.p_query ?? "").toLowerCase().split(/\s+/).filter((w) => w.length >= 3);
        return { data: CATALOG.filter((r) => (a.p_media_type == null || r.media_type === a.p_media_type) && words.some((w) => r.title_raw.toLowerCase().includes(w))), error: null };
      },
    },
  });
}

const post = (body: unknown) =>
  new Request("http://local/fn", { method: "POST", headers: { "Content-Type": "application/json", Authorization: "Bearer test" }, body: JSON.stringify(body) });

async function parse(db: ReturnType<typeof queryFake>, text: string) {
  const res = await handleParse(post({ text }), { client: () => db.client });
  return ((await res.json()) as Json).items[0];
}

Deno.test("record then look up: Apply's alias (strong key) and a legacy-key alias both steer the next Parse", async () => {
  const db = store();

  // 1. First import: without an alias the better-scoring variant ranks first.
  const before = await parse(db, "I watched Attack on Titan 9/10");
  assertEquals(before.candidates[0].media_id, 99147);

  // 2. The user picks "Attack on Titan" and applies (the line's raw comes from the parse response).
  const service = queryFake({
    rpc: {
      apply_import_session: () => ({
        data: { session_id: "s-1", applied: [{ mediaType: "ANIME", mediaId: 16498 }], skipped: [], conflicts: [], errors: [], undoable: true, replayed: false },
        error: null,
      }),
    },
  });
  const applied = await handleApply(
    post({ items: [{ raw: before.raw, normalized: before.normalized, mediaType: "ANIME", mediaId: 16498, status: "WATCHING", action: "add", progressEpisodes: 3 }] }),
    { client: () => db.client, serviceClient: () => service.client },
  );
  assertEquals(applied.status, 200);
  const recorded = db.tables.title_aliases.find((r) => r.media_id === 16498);
  assertEquals(recorded?.alias_norm, normalizeAliasKey(before.raw));

  // 3. Next import of the same line: Parse finds Apply's alias and the chosen title ranks first.
  const after = await parse(db, "I watched Attack on Titan 9/10");
  assertEquals(after.candidates[0].media_id, 16498);

  // 4. The legacy-key alias written by the old Apply is found too ("kaempfer" vs "kämpfer 8 10").
  assertEquals([normalizeAliasKey(LEGACY_LINE), legacyApplyAliasKey(LEGACY_LINE)], ["kaempfer", "kämpfer 8 10"]);
  const legacy = await parse(db, LEGACY_LINE);
  assertEquals(legacy.raw, LEGACY_LINE);
  assertEquals(legacy.candidates[0].media_id, 7001);
});
