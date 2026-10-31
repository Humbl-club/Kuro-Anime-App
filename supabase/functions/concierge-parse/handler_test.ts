// concierge-parse production handler (handler.ts + parse_repository.ts + search_plan.ts + rules.ts)
// against a controlled client (_shared/test_query_fake.ts). One test per boundary outcome: anonymous
// caller, limiter denial, limiter failure, search failure, ambiguous line, existing-entry projection,
// and the F31 alias compatibility path.
import { assertEquals } from "jsr:@std/assert@1";
import { legacyApplyAliasKey, normalizeAliasKey } from "../_shared/alias_normalization.ts";
import { type FakeOptions, queryFake } from "../_shared/test_query_fake.ts";
import { handleParse } from "./handler.ts";

const USER = "6f1c1b0e-0000-4000-8000-000000000001";
const ALLOWED = { data: { allowed: true }, error: null };

// deno-lint-ignore no-explicit-any
type Json = any;

function catalog(rows: Array<Record<string, unknown>>) {
  // search_titles: every row whose title shares a word with the query (case-insensitive).
  return (args: Record<string, unknown>) => {
    const words = String(args.p_query ?? "").toLowerCase().split(/[^a-z0-9;]+/).filter((w) => w.length >= 3);
    const data = rows.filter((r) =>
      (args.p_media_type == null || r.media_type === args.p_media_type) &&
      words.some((w) => String(r.title_raw).toLowerCase().includes(w))
    );
    return { data, error: null };
  };
}

async function parse(opts: FakeOptions, body: Record<string, unknown>) {
  const fake = queryFake(opts);
  const res = await handleParse(
    new Request("http://local/concierge-parse", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: "Bearer test", "x-forwarded-for": "203.0.113.7" },
      body: JSON.stringify(body),
    }),
    { client: () => fake.client },
  );
  return { fake, res, body: (await res.json()) as Json };
}

const searchCalls = (fake: ReturnType<typeof queryFake>) => fake.rpcCalls("search_titles");

Deno.test("auth error: the parse runs anonymously and does no user-scoped read or write", async () => {
  const { fake, res, body } = await parse(
    { user: null, rpc: { check_concierge_rate_limit: ALLOWED, search_titles: catalog([{ media_type: "ANIME", media_id: 154587, title_raw: "Frieren", score: 1 }]) } },
    { text: "Frieren completed" },
  );
  assertEquals(res.status, 200);
  assertEquals(body.userId, null);
  assertEquals(body.items[0].candidates.map((c: Json) => c.media_id), [154587]);
  assertEquals([body.items[0].aliasNorm, body.items[0].existing_entry], [null, null]);
  for (const table of ["title_aliases", "anime_user_lists", "manga_user_lists"]) assertEquals(fake.reads(table), 0, table);
  for (const rpc of ["get_concierge_config", "log_concierge_parse_feedback", "log_concierge_run"]) assertEquals(fake.rpcCalls(rpc).length, 0, rpc);
  assertEquals(fake.rpcCalls("check_concierge_rate_limit")[0].p_ip, "203.0.113.7");
});

Deno.test("explicit rate denial is 429 with Retry-After and no search or list work", async () => {
  const { fake, res, body } = await parse(
    { user: { id: USER }, rpc: { check_concierge_rate_limit: { data: { allowed: false, retry_after_s: 12 }, error: null } } },
    { text: "Frieren completed" },
  );
  assertEquals(res.status, 429);
  assertEquals(res.headers.get("Retry-After"), "12");
  assertEquals(body, { error: "Rate limited", retry_after_s: 12 });
  assertEquals(searchCalls(fake).length, 0);
  assertEquals(fake.calls.filter((c) => c.kind !== "rpc" || c.name !== "check_concierge_rate_limit").length, 0);
});

Deno.test("F32: a limiter error fails closed as a retryable 503 with no search, alias or list work", async () => {
  const { fake, res, body } = await parse(
    { user: { id: USER }, rpc: { check_concierge_rate_limit: { data: null, error: { message: "rate_limit_buckets unavailable" } } } },
    { text: "Frieren completed" },
  );
  assertEquals(res.status, 503);
  assertEquals(res.headers.get("Retry-After"), "30");
  assertEquals(body, { error: "Rate limiter unavailable", retry_after_s: 30 });
  assertEquals(fake.calls.filter((c) => c.kind !== "rpc" || c.name !== "check_concierge_rate_limit").length, 0);
});

Deno.test("a search failure is reported on its line only; the other line still gets candidates", async () => {
  const rows = catalog([{ media_type: "ANIME", media_id: 269, title_raw: "Bleach", score: 1 }]);
  const { fake, res, body } = await parse(
    {
      user: { id: USER },
      rpc: {
        check_concierge_rate_limit: ALLOWED,
        search_titles: (args) => String(args.p_query).includes("Naruto") ? { data: null, error: { message: "statement timeout" } } : rows(args),
      },
    },
    { text: "Naruto completed\nBleach completed" },
  );
  assertEquals(res.status, 200);
  assertEquals([body.items[0].candidates, body.items[0].candidateError, body.items[0].existing_entry], [[], "statement timeout", null]);
  assertEquals([body.items[1].candidates.map((c: Json) => c.media_id), body.items[1].candidateError], [[269], null]);
  // Only the confident Bleach line reads its list entry.
  assertEquals(fake.reads("anime_user_lists"), 1);
});

Deno.test("an ambiguous line returns the parser's clarification through the handler", async () => {
  const { body } = await parse(
    { user: { id: USER }, rpc: { check_concierge_rate_limit: ALLOWED, search_titles: catalog([{ media_type: "ANIME", media_id: 1535, title_raw: "Death Note", score: 1 }]) } },
    { text: "I watched Death Note" },
  );
  const item = body.items[0];
  assertEquals([item.parsed.status, item.ambiguity?.kind, item.ambiguity?.options], ["WATCHING", "status_unclear", ["COMPLETED", "WATCHING"]]);
  assertEquals(item.candidates[0].media_id, 1535);
});

Deno.test("existing-entry projection: the caller's anime and manga rows, never another user's (F27 import example)", async () => {
  const { fake, body } = await parse(
    {
      user: { id: USER },
      tables: {
        anime_user_lists: [
          { user_id: "someone-else", anime_id: 9253, list_type: "COMPLETED", progress: 24, rating: 10, updated_at: "2026-01-01T00:00:00Z" },
          { user_id: USER, anime_id: 9253, list_type: "WATCHING", progress: 7, rating: 9, updated_at: "2026-10-01T00:00:00Z" },
        ],
        manga_user_lists: [{ user_id: USER, manga_id: 30002, list_type: "READING", progress: 120, rating: null, updated_at: "2026-09-01T00:00:00Z" }],
      },
      rpc: {
        check_concierge_rate_limit: ALLOWED,
        search_titles: catalog([
          { media_type: "ANIME", media_id: 9253, title_raw: "Steins;Gate", score: 1 },
          { media_type: "MANGA", media_id: 30002, title_raw: "Berserk", score: 0.9 },
        ]),
      },
    },
    { text: "I watched Steins;Gate to the end\nich habe Berserk Manga gelesen bis Kapitel 200" },
  );
  const [steins, berserk] = body.items;
  assertEquals(body.items.length, 2);
  assertEquals([steins.normalized, steins.parsed.status, steins.parsed.completed], ["Steins;Gate", "COMPLETED", true]);
  assertEquals(steins.existing_entry, {
    media_type: "ANIME", media_id: 9253, status: "WATCHING", progress_episodes: 7, progress_chapters: null, progress_volumes: null, rating: 9,
    updated_at: "2026-10-01T00:00:00Z",
  });
  assertEquals([berserk.parsed.status, berserk.parsed.progressChapters, berserk.parsed.mediaTypeHint, berserk.ambiguity], ["READING", 200, "MANGA", null]);
  assertEquals(berserk.existing_entry, {
    media_type: "MANGA", media_id: 30002, status: "READING", progress_episodes: null, progress_chapters: 120, progress_volumes: null, rating: null,
    updated_at: "2026-09-01T00:00:00Z",
  });
  // The Steins;Gate line searched its whole title once, never "Steins" / "Gate" as separate lines.
  assertEquals(searchCalls(fake)[0], { p_query: "Steins;Gate", p_media_type: "ANIME", p_limit: 10 });
  assertEquals(searchCalls(fake).some((a) => a.p_query === "Gate to the end"), false);
});

Deno.test("F76 (parse): a non-numeric limitPerItem falls back to the default 10; a numeric one is still clamped", async () => {
  const rpc = { check_concierge_rate_limit: ALLOWED, search_titles: catalog([{ media_type: "ANIME", media_id: 154587, title_raw: "Frieren", score: 1 }]) };
  const bad = await parse({ user: null, rpc }, { text: "Frieren completed", limitPerItem: "lots" });
  assertEquals(bad.body.items[0].candidates.map((c: Json) => c.media_id), [154587]);
  assertEquals(searchCalls(bad.fake)[0].p_limit, 10);
  const small = await parse({ user: null, rpc }, { text: "Frieren completed", limitPerItem: 1 });
  assertEquals(searchCalls(small.fake)[0].p_limit, 5); // clamped to 3, searched with the minimum 5
});

const AOT_LINE = "I watched Attack on Titan 9/10";
const AOT_ROWS = [
  { media_type: "ANIME", media_id: 16498, title_raw: "Attack on Titan", score: 0.6 },
  { media_type: "ANIME", media_id: 99147, title_raw: "Attack on Titan: Junior High", score: 0.3 },
  { media_type: "ANIME", media_id: 77001, title_raw: "Titan Picture Drama", score: 0.3 },
];

Deno.test("F31: an alias recorded with the legacy Apply key is found by the parse lookup and boosts its title", async () => {
  // Deployed concierge-apply recorded this alias with its old, weaker key ("attack on titan 9 10").
  const legacyKey = legacyApplyAliasKey(AOT_LINE);
  assertEquals(legacyKey === normalizeAliasKey(AOT_LINE), false);
  const { body } = await parse(
    {
      user: { id: USER },
      tables: { title_aliases: [{ user_id: USER, alias_norm: legacyKey, media_type: "ANIME", media_id: 99147, title_raw: "Attack on Titan: Junior High", hits: 3 }] },
      rpc: { check_concierge_rate_limit: ALLOWED, search_titles: catalog(AOT_ROWS) },
    },
    { text: AOT_LINE },
  );
  assertEquals(body.items[0].candidates[0].media_id, 99147);
  assertEquals(body.items[0].aliasNorm, "attack on titan");
});

Deno.test("F31: a strong-key alias wins over a legacy-key alias for the same line, regardless of hits", async () => {
  const { body } = await parse(
    {
      user: { id: USER },
      tables: {
        title_aliases: [
          { user_id: USER, alias_norm: legacyApplyAliasKey(AOT_LINE), media_type: "ANIME", media_id: 99147, title_raw: "Attack on Titan: Junior High", hits: 9 },
          { user_id: USER, alias_norm: normalizeAliasKey(AOT_LINE), media_type: "ANIME", media_id: 77001, title_raw: "Titan Picture Drama", hits: 1 },
          { user_id: "someone-else", alias_norm: normalizeAliasKey(AOT_LINE), media_type: "ANIME", media_id: 16498, title_raw: "x", hits: 50 },
        ],
      },
      rpc: { check_concierge_rate_limit: ALLOWED, search_titles: catalog(AOT_ROWS) },
    },
    { text: AOT_LINE },
  );
  assertEquals(body.items[0].candidates[0].media_id, 77001);
});
