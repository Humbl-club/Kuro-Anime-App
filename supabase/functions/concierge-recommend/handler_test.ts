// concierge-recommend production handler (handler.ts + catalog_repository.ts + rail_policy.ts +
// narration.ts + router.ts) against a controlled client, fetch and clock. One test per boundary
// outcome: limiter denial, limiter failure, mode-cache outcome, narration failure keeping the
// deterministic recommendations, and budget reservation accounting on every narration path.
import { assertEquals } from "jsr:@std/assert@1";
import { type FakeOptions, queryFake, type RpcReply } from "../_shared/test_query_fake.ts";
import { handleRecommend } from "./handler.ts";
import { groqNarrate, narrateWithBudget, supabaseNarrationBudget } from "./narration.ts";

const USER = "6f1c1b0e-0000-4000-8000-000000000002";
const NOW = Date.UTC(2026, 9, 5, 12, 0, 0);
const DAY = 86_400_000;
const PROMPT = "cozy anime for a rainy day"; // strong genre -> cozy_comfort; > 5 words, so no bare-title search

// deno-lint-ignore no-explicit-any
type Json = any;

const GENRES = [["Slice of Life", "Comedy"], ["Drama", "Romance"], ["Action"], ["Mystery", "Thriller"], ["Slice of Life"], ["Fantasy", "Adventure"]];
const ANIME = Array.from({ length: 36 }, (_, i) => ({
  id: 100 + i,
  title_english: `Anime ${100 + i}`,
  average_score: 72 + (i % 20),
  popularity: 3_000 + i * 1_000,
  start_date_year: 1995 + (i % 28),
  format: "TV",
  status: "FINISHED",
  is_adult: false,
  genres: GENRES[i % GENRES.length],
  episodes: 12,
}));

function world(over: { rpc?: Record<string, RpcReply>; tables?: FakeOptions["tables"] } = {}) {
  return queryFake({
    user: { id: USER },
    tables: { anime: ANIME, ...over.tables },
    rpc: {
      check_concierge_rate_limit: { data: { allowed: true }, error: null },
      get_concierge_config: { data: { router_llm: { cache_ttl_days: 30 } }, error: null }, // modes: defaultModes()
      recommend_ids_premium: (a) => ({
        data: a.p_media_type === "ANIME" ? ANIME.map((m) => ({ media_id: m.id, match_count: 1, score: m.average_score / 100 })) : [],
        error: null,
      }),
      is_flag_enabled: { data: true, error: null },
      llm_budget_reserve: { data: { allowed: true }, error: null },
      llm_global_budget_reserve: { data: { allowed: true }, error: null },
      ...over.rpc,
    },
  });
}

type Net = { urls: string[]; fetch: (url: string, init: RequestInit) => Promise<Response> };
function groq(outcome: "ok" | "fail"): Net {
  const urls: string[] = [];
  return {
    urls,
    fetch(url, init) {
      urls.push(url);
      if (outcome === "fail") return Promise.resolve(new Response(JSON.stringify({ error: "overloaded" }), { status: 503 }));
      const ids = [...String(JSON.parse(String(init.body)).messages[1].content).matchAll(/- ((?:ANIME|MANGA)\|\d+):/g)].map((m) => m[1]);
      const blurbs = Object.fromEntries(ids.map((id) => [id, `A quiet pick for ${id}.`]));
      return Promise.resolve(
        new Response(JSON.stringify({ choices: [{ message: { content: JSON.stringify({ blurbs }) } }], usage: { total_tokens: 321 } }), { status: 200 }),
      );
    },
  };
}

async function recommend(fake: ReturnType<typeof queryFake>, body: Record<string, unknown>, net: Net = groq("ok")) {
  const env: Record<string, string> = { SUPABASE_URL: "https://project.supabase.co", GROQ_API_KEY: "test-key" };
  const res = await handleRecommend(
    new Request("http://local/concierge-recommend", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: "Bearer test", "x-forwarded-for": "203.0.113.9" },
      body: JSON.stringify(body),
    }),
    { client: () => fake.client, env: (k) => env[k], fetch: net.fetch, now: () => NOW },
  );
  return { res, body: (await res.json()) as Json };
}

const onlyLimiterCalled = (fake: ReturnType<typeof queryFake>) =>
  assertEquals(fake.calls.filter((c) => c.kind !== "rpc" || c.name !== "check_concierge_rate_limit"), []);

Deno.test("actual narration transport bounds held headers and body, then releases only its two reservations", async () => {
  for (const phase of ["headers", "body"] as const) {
    const fake = world();
    let signal: AbortSignal | null | undefined;
    let release!: () => void;
    const held = new Promise<void>((resolve) => { release = resolve; });
    const fetchImpl = async (_url: string, init: RequestInit) => {
      signal = init.signal;
      if (phase === "headers") await held;
      const response = Response.json({});
      if (phase === "body") response.json = async () => { await held; return {}; };
      return response;
    };
    try {
      const result = await narrateWithBudget({
        requested: true, debug: true, apiKey: "test", model: "test", lang: "en", userText: PROMPT, globalBudgetConfig: {},
      }, [{ id: "ANIME|7", title: "Fixture", signals: [] }], supabaseNarrationBudget(fake.client),
        (opts) => groqNarrate({ ...opts, fetch: fetchImpl, timeoutMs: 10 }));
      assertEquals(result.narrated, true);
      assertEquals(result.blurbs, {});
      assertEquals(result.error, "Groq narration timed out");
      assertEquals(signal?.aborted, true);
      const finalizers = fake.calls.flatMap((c) => c.kind === "rpc" && c.name.endsWith("_finalize") ? [c] : []);
      assertEquals(finalizers.map((c) => c.name), ["llm_budget_finalize", "llm_global_budget_finalize"]);
      assertEquals(finalizers.map((c) => c.args.p_actual_tokens), [0, 0]);
    } finally {
      release();
    }
    await new Promise((resolve) => setTimeout(resolve, 0));
    assertEquals(fake.calls.filter((c) => c.kind === "rpc" && c.name.endsWith("_finalize")).length, 2);
  }
});

Deno.test("explicit rate denial is 429 with Retry-After and no catalog, cache or narration work", async () => {
  const fake = world({ rpc: { check_concierge_rate_limit: { data: { allowed: false, retry_after_s: 7 }, error: null } } });
  const net = groq("ok");
  const { res, body } = await recommend(fake, { text: PROMPT, narrate: true }, net);
  assertEquals([res.status, res.headers.get("Retry-After"), body], [429, "7", { error: "Rate limited", retry_after_s: 7 }]);
  onlyLimiterCalled(fake);
  assertEquals(net.urls, []);
});

Deno.test("F32: a limiter error fails closed as a retryable 503 with no catalog, search or paid narration call", async () => {
  const fake = world({ rpc: { check_concierge_rate_limit: { data: null, error: { message: "rate_limit_hit failed" } } } });
  const net = groq("ok");
  const { res, body } = await recommend(fake, { text: "something like Attack on Titan", narrate: true }, net);
  assertEquals([res.status, res.headers.get("Retry-After"), body], [503, "30", { error: "Rate limiter unavailable", retry_after_s: 30 }]);
  onlyLimiterCalled(fake);
  assertEquals(net.urls, []);
});

Deno.test("mode cache: a fresh entry decides the primary rail; a stale one is re-routed and overwritten", async () => {
  const cacheRow = (ageDays: number) => ({
    concierge_mode_cache: [{
      user_id: USER,
      prompt_norm: PROMPT,
      primary_mode_id: "hidden_gems",
      secondary_mode_id: "premium_picks",
      used_llm: false,
      updated_at: new Date(NOW - ageDays * DAY).toISOString(),
    }],
  });

  const fresh = world({ tables: cacheRow(2) });
  const hit = await recommend(fresh, { text: PROMPT });
  assertEquals([hit.res.status, hit.body.modes[0].id, hit.body.modes[0].reason], [200, "hidden_gems", "cache"]);
  assertEquals(hit.body.sets[0].items.length, 8);

  const stale = world({ tables: cacheRow(40) });
  const miss = await recommend(stale, { text: PROMPT });
  assertEquals([miss.body.modes[0].id, miss.body.modes[0].reason], ["cozy_comfort", "strong genre signal"]);
  assertEquals(stale.tables.concierge_mode_cache[0].primary_mode_id, "cozy_comfort");
  // Every primary item passes the cozy rail's genre gate (Slice of Life first).
  assertEquals(miss.body.sets[0].items.every((it: Json) => it.genres.includes("Slice of Life")), true);
});

Deno.test("F73: each rail is built once: the primary plus each secondary candidate, no duplicate fallback build", async () => {
  const fake = world();
  const { res } = await recommend(fake, { text: PROMPT });
  assertEquals(res.status, 200);
  const telemetry = fake.rpcCalls("log_concierge_run").find((a) => a.p_kind === "recommend_router_v2");
  const candidates = JSON.parse(String(telemetry?.p_error)).secondary_candidates_count;
  assertEquals(candidates > 0, true);
  // Anime-only prompt, no curated cards: every rail build is exactly one recommend_ids_premium call.
  assertEquals(fake.rpcCalls("recommend_ids_premium").length, 1 + candidates);
});

Deno.test("F76: a non-numeric limit falls back to the default 8; a numeric one is still clamped and honored", async () => {
  const bad = await recommend(world(), { text: PROMPT, limit: "lots" });
  assertEquals([bad.res.status, bad.body.sets[0].items.length], [200, 8]);
  const five = await recommend(world(), { text: PROMPT, limit: 5 });
  assertEquals(five.body.sets[0].items.length, 5);
});

Deno.test("narration failure keeps the deterministic recommendations unchanged (no blurbs, error only under debug)", async () => {
  const plain = await recommend(world(), { text: PROMPT, narrate: false });
  const failed = await recommend(world(), { text: PROMPT, narrate: true, debugNarration: true }, groq("fail"));
  assertEquals(failed.res.status, 200);
  assertEquals(failed.body.sets, plain.body.sets);
  assertEquals(failed.body.items, plain.body.items);
  assertEquals(failed.body.items.some((it: Json) => "blurb" in it), false);
  assertEquals([failed.body.narrated, String(failed.body.narrationError).startsWith("Groq error: 503")], [true, true]);

  const narrated = await recommend(world(), { text: PROMPT, narrate: true });
  assertEquals(narrated.body.sets.map((s: Json) => s.items.map((it: Json) => it.mediaId)), plain.body.sets.map((s: Json) => s.items.map((it: Json) => it.mediaId)));
  assertEquals(narrated.body.items.filter((it: Json) => it.blurb).length, 8);
  assertEquals("narrationError" in narrated.body, false);
});

Deno.test("budget accounting: a held reservation is released exactly once, with 0 tokens when the provider fails", async () => {
  for (const [outcome, actual] of [["fail", 0], ["ok", 321]] as const) {
    const fake = world();
    await recommend(fake, { text: PROMPT, narrate: true }, groq(outcome));
    const [reserved] = fake.rpcCalls("llm_budget_reserve");
    const tokens = reserved.p_reserved_tokens;
    assertEquals(fake.rpcCalls("llm_budget_finalize"), [{ p_reserved_tokens: tokens, p_actual_tokens: actual, p_model: "openai/gpt-oss-20b" }], outcome);
    assertEquals(fake.rpcCalls("llm_global_budget_finalize"), [{ p_reserved_tokens: tokens, p_actual_tokens: actual }], outcome);
  }
});

Deno.test("budget denial or error never calls the provider and releases only the reservation actually taken", async () => {
  const denied = { data: { allowed: false, reason: "daily_limit" }, error: null };
  const failed = { data: null, error: { message: "llm_daily_usage locked" } };
  const cases: Array<{ name: string; rpc: Record<string, RpcReply>; userReleases: number; globalReserves: number }> = [
    { name: "kill switch unreadable", rpc: { is_flag_enabled: failed }, userReleases: 0, globalReserves: 0 },
    { name: "kill switch off", rpc: { is_flag_enabled: { data: false, error: null } }, userReleases: 0, globalReserves: 0 },
    { name: "user budget denied", rpc: { llm_budget_reserve: denied }, userReleases: 0, globalReserves: 0 },
    { name: "user budget error", rpc: { llm_budget_reserve: failed }, userReleases: 0, globalReserves: 0 },
    { name: "global budget denied", rpc: { llm_global_budget_reserve: denied }, userReleases: 1, globalReserves: 1 },
    { name: "global budget error", rpc: { llm_global_budget_reserve: failed }, userReleases: 1, globalReserves: 1 },
  ];
  for (const c of cases) {
    const fake = world({ rpc: c.rpc });
    const net = groq("ok");
    const { res, body } = await recommend(fake, { text: PROMPT, narrate: true }, net);
    assertEquals([res.status, body.narrated, net.urls.length], [200, false, 0], c.name);
    assertEquals(fake.rpcCalls("llm_global_budget_reserve").length, c.globalReserves, c.name);
    assertEquals(fake.rpcCalls("llm_budget_finalize").map((a) => a.p_actual_tokens), Array(c.userReleases).fill(0), c.name);
    assertEquals(fake.rpcCalls("llm_global_budget_finalize").length, 0, c.name);
    assertEquals(body.items.length > 0, true, c.name);
  }
});
