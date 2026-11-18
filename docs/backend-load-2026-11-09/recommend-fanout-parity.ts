// Offline comparison against a source-only saved baseline. No live requests or provider calls.
// args: baseline Supabase root, current Supabase root, frozen public config JSON, output JSON.
import { assertEquals } from "jsr:@std/assert@1";
import { pathToFileURL } from "node:url";
import { queryFake } from "../../supabase/functions/_shared/test_query_fake.ts";
import type { RecommendPlatform } from "../../supabase/functions/concierge-recommend/handler.ts";
const [oldRoot, newRoot, configPath, output] = Deno.args;
if (!oldRoot || !newRoot || !configPath || !output) throw new Error("Four explicit local paths required");
const oldHandle = (await import(pathToFileURL(oldRoot + "/functions/concierge-recommend/handler.ts").href)).handleRecommend;
const newHandle = (await import(pathToFileURL(newRoot + "/functions/concierge-recommend/handler.ts").href)).handleRecommend;
const config = JSON.parse(await Deno.readTextFile(configPath));
const user = "6f1c1b0e-0000-4000-8000-000000000002";
const genres = [["Slice of Life", "Comedy"], ["Drama", "Romance"], ["Action"], ["Mystery", "Thriller"], ["Fantasy", "Adventure"]];
const anime = Array.from({ length: 2300 }, (_, i) => ({ id: i + 1, title_english: `Anime ${i + 1}`,
  average_score: 80 + i % 15, popularity: 100000 + i * 1000, start_date_year: 1990 + i % 35,
  format: "TV", status: "FINISHED", is_adult: false, genres: genres[i % genres.length], episodes: 12 }));
const manga = anime.map(({ episodes: _episodes, ...row }) => ({ ...row, title_english: `Manga ${row.id}`, format: "MANGA", chapters: 24 }));
function world(size: number) {
  const a = new Set(Array.from({ length: Math.floor(size * .7) }, (_, i) => i + 1));
  const m = new Set(Array.from({ length: size - a.size }, (_, i) => i + 1));
  return queryFake({ user: { id: user }, tables: { anime, manga,
    user_lists: [...a].map((id) => ({ user_id: user, media_type: "anime", media_id: id }))
      .concat([...m].map((id) => ({ user_id: user, media_type: "manga", media_id: id }))) }, rpc: {
    check_concierge_rate_limit: { data: { allowed: true }, error: null },
    get_concierge_config: { data: structuredClone(config), error: null },
    search_titles: { data: [], error: null }, curated_rail_cards: { data: [], error: null },
    recommend_ids_premium: (args) => {
      const rows = args.p_media_type === "ANIME" ? anime : manga;
      const owned = args.p_media_type === "ANIME" ? a : m;
      const matches = Array.isArray(args.p_categories) ? args.p_categories.length : 0;
      return { data: rows.filter((r) => !owned.has(r.id)).slice(0, 50)
        .map((r) => ({ media_id: r.id, match_count: matches, score: r.average_score / 100 + matches })), error: null };
    },
  } });
}
async function run(handle: typeof newHandle, text: string, scope: string, size: number) {
  const fake = world(size);
  const platform: RecommendPlatform = { client: () => fake.client, globalBudgetClient: () => fake.client,
    env: (k) => k === "SUPABASE_URL" ? "https://fixture.invalid" : undefined,
    fetch: () => { throw new Error("External provider request forbidden"); }, now: () => Date.UTC(2026, 10, 9, 11) };
  const res = await handle(new Request("http://local/recommend", { method: "POST",
    headers: { Authorization: "Bearer fixture", "Content-Type": "application/json" },
    body: JSON.stringify({ text, scope, limit: 8, narrate: false }) }), platform);
  assertEquals(res.status, 200);
  return { body: await res.json(), premiumCalls: fake.rpcCalls("recommend_ids_premium").length,
    hydrationReads: fake.reads("anime") + fake.reads("manga") };
}
const cases = [];
for (const size of [0, 2000]) for (const scope of ["anime", "manga", "both"]) {
  for (const text of ["something cozy", "premium action anime", "sad but hopeful", "classics without horror", "short sci-fi under 20 episodes", "something without romance"]) {
    const before = await run(oldHandle, text, scope, size); const after = await run(newHandle, text, scope, size);
    assertEquals(after.body, before.body, `${text}/${scope}/${size}`);
    cases.push({ text, scope, librarySize: size, identical: true, beforePremiumCalls: before.premiumCalls,
      afterPremiumCalls: after.premiumCalls, beforeHydrationReads: before.hydrationReads, afterHydrationReads: after.hydrationReads });
  }
}
await Deno.writeTextFile(output, JSON.stringify({ scope: "Frozen public config and synthetic responses; offline, not hosted capacity proof", comparisons: cases.length,
  beforePremiumCalls: cases.reduce((n, x) => n + x.beforePremiumCalls, 0), afterPremiumCalls: cases.reduce((n, x) => n + x.afterPremiumCalls, 0), cases }, null, 2) + "\n");
console.log(`${cases.length} complete handler responses identical`);
