import { assertEquals } from "jsr:@std/assert@1";
import { queryFake } from "../_shared/test_query_fake.ts";
import {
  type RagSeedQuery,
  supabaseCatalogRepository,
} from "./catalog_repository.ts";

Deno.test("ragSeed rejects wrong-medium answers and preserves matching or unscoped identity", async () => {
  let medium = "MANGA";
  const requests: Record<string, unknown>[] = [];
  const repo = supabaseCatalogRepository({
    client: {},
    supabaseUrl: "https://fixture.invalid",
    authHeader: "Bearer fixture",
    now: () => 0,
    fetch: (_url, init) => {
      requests.push(JSON.parse(String(init.body)));
      return Promise.resolve(Response.json({
        entity_candidates: [{
          media_type: medium,
          anilist_id: 7,
          entity_id: "entity-7",
          title: "Title",
          score: 0.9,
        }],
      }));
    },
  });
  const query: RagSeedQuery = {
    query: "Title",
    locale: "en",
    mediaType: "ANIME",
    excludedGenres: [],
    format: null,
    yearMin: null,
    yearMax: null,
  };
  assertEquals(await repo.ragSeed(query), null);
  medium = "ANIME";
  assertEquals(await repo.ragSeed(query), {
    mt: "ANIME",
    mediaId: 7,
    title: "Title",
    entityId: "entity-7",
  });
  medium = "MANGA";
  assertEquals(await repo.ragSeed({ ...query, mediaType: null }), {
    mt: "MANGA",
    mediaId: 7,
    title: "Title",
    entityId: "entity-7",
  });
  assertEquals(requests.map((request) => request.media_type), [
    "ANIME",
    "ANIME",
    null,
  ]);
});

Deno.test("ragSeed rejects malformed confidence and fractional identity instead of bypassing the threshold", async () => {
  let candidate: Record<string, unknown> = {};
  const repo = supabaseCatalogRepository({
    client: {}, supabaseUrl: "https://fixture.invalid", authHeader: "Bearer fixture", now: () => 0,
    fetch: () => Promise.resolve(Response.json({ entity_candidates: [candidate] })),
  });
  const query: RagSeedQuery = { query: "Title", locale: "en", mediaType: "ANIME",
    excludedGenres: [], format: null, yearMin: null, yearMax: null };
  for (const score of ["not-a-score", "Infinity", -1, 0.44]) {
    candidate = { media_type: "ANIME", anilist_id: 7, score, title: "Title" };
    assertEquals(await repo.ragSeed(query), null);
  }
  candidate = { media_type: "ANIME", anilist_id: 7.5, score: 0.9, title: "Title" };
  assertEquals(await repo.ragSeed(query), null);
  candidate = { media_type: "ANIME", anilist_id: 7, score: 0.9, title: "Title" };
  assertEquals(await repo.ragSeed(query), { mt: "ANIME", mediaId: 7, title: "Title", entityId: null });
});

function candidateRepo(fake: ReturnType<typeof queryFake>) {
  return supabaseCatalogRepository({
    client: fake.client, supabaseUrl: "https://fixture.invalid", authHeader: "Bearer fixture", now: () => 0,
    fetch: () => { throw new Error("Unexpected external transport"); },
  });
}

Deno.test("candidate rails share concurrent and completed successful reads, with independent returned rows", async () => {
  const fake = queryFake({ rpc: { recommend_ids_premium: async () => {
    await Promise.resolve();
    return { data: [{ media_id: 7, overlap_count: 2 }], error: null };
  } } });
  const repo = candidateRepo(fake);
  const first = repo.premiumCandidates("ANIME", null, false, []);
  const second = repo.premiumCandidates("ANIME", null, false, []);
  assertEquals(fake.rpcCalls("recommend_ids_premium").length, 1);
  const [a, b] = await Promise.all([first, second]);
  const expected = [{ media_id: 7, match_count: 2, score: null }];
  assertEquals(a, expected); assertEquals(b, expected);
  a[0].match_count = 999; a.length = 0;
  assertEquals(b, expected);
  assertEquals(await repo.premiumCandidates("ANIME", null, false, []), expected);
  assertEquals(fake.rpcCalls("recommend_ids_premium").length, 1);
});

Deno.test("candidate read keys distinguish every RPC filter and retain empty-result semantics", async () => {
  const fake = queryFake({ rpc: { recommend_ids_premium: { data: [], error: null } } });
  const repo = candidateRepo(fake);
  for (const [mt, categories, gimmicks, focus] of [
    ["ANIME", [], false, []], ["ANIME", null, false, []], ["MANGA", null, false, []],
    ["ANIME", ["Theme"], false, []], ["ANIME", null, true, []], ["ANIME", null, false, [9]],
  ] as const) {
    assertEquals(await repo.premiumCandidates(mt, categories ? [...categories] : null, gimmicks, [...focus]), []);
  }
  assertEquals(fake.rpcCalls("recommend_ids_premium").length, 5);
});

Deno.test("candidate caches cannot cross requests or callers", async () => {
  const a = queryFake({ rpc: { recommend_ids_premium: { data: [{ media_id: 7 }], error: null } } });
  const b = queryFake({ rpc: { recommend_ids_premium: { data: [{ media_id: 8 }], error: null } } });
  assertEquals((await candidateRepo(a).premiumCandidates("ANIME", null, false, []))[0].media_id, 7);
  assertEquals((await candidateRepo(a).premiumCandidates("ANIME", null, false, []))[0].media_id, 7);
  assertEquals((await candidateRepo(b).premiumCandidates("ANIME", null, false, []))[0].media_id, 8);
  assertEquals(a.rpcCalls("recommend_ids_premium").length, 2);
  assertEquals(b.rpcCalls("recommend_ids_premium").length, 1);
});

Deno.test("a failed candidate read is not cached and a later independent read can succeed", async () => {
  let attempts = 0;
  const fake = queryFake({ rpc: { recommend_ids_premium: () => ++attempts === 1
    ? { data: null, error: { message: "temporary" } }
    : { data: [{ media_id: 7 }], error: null } } });
  const repo = candidateRepo(fake);
  const first = await Promise.allSettled([repo.premiumCandidates("ANIME", null, false, [])]);
  assertEquals(first[0].status, "rejected");
  assertEquals((await repo.premiumCandidates("ANIME", null, false, []))[0].media_id, 7);
  await repo.premiumCandidates("ANIME", null, false, []);
  assertEquals(attempts, 2);
});

Deno.test("a secondary consumer retains its own attempt when the shared read fails", async () => {
  let attempts = 0;
  const fake = queryFake({ rpc: { recommend_ids_premium: async () => {
    const n = ++attempts; await Promise.resolve();
    return n === 1 ? { data: null, error: { message: "temporary" } } : { data: [{ media_id: 7 }], error: null };
  } } });
  const repo = candidateRepo(fake);
  const results = await Promise.allSettled([
    repo.premiumCandidates("ANIME", null, false, []), repo.premiumCandidates("ANIME", null, false, []),
  ]);
  assertEquals(results.map((x) => x.status), ["rejected", "fulfilled"]);
  if (results[1].status === "fulfilled") assertEquals(results[1].value[0].media_id, 7);
  assertEquals(attempts, 2);
});
