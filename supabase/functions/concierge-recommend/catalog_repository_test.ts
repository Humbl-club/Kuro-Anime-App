import { assertEquals } from "jsr:@std/assert@1";
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
