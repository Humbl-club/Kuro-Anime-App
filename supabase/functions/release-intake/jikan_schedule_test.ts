// Offline unit and handler tests for Jikan v4 seasonal broadcast fallback.
import { strict as assert } from "node:assert";
import { createAniListClient, AniListLimiter } from "../_shared/anilist_client.ts";
import { createPoliteClient, PoliteLimiter } from "../_shared/polite_fetch.ts";
import { queryFake as baseQueryFake, type FakeOptions } from "../_shared/test_query_fake.ts";
import { FIELD_GROUP_NAMES } from "../_shared/catalogue/field_groups.ts";
import { run } from "./handler.ts";
import { computeNextJstBroadcastMs, estimateEpisodeNumber, parseJikanBroadcast } from "./jikan_schedule.ts";
import type { ReleaseEventRow } from "./contract.ts";

function cutoverRows(modes: Record<string, string> = {}) {
  return FIELD_GROUP_NAMES.map((g) => ({ field_group: g, mode: modes[g] ?? "anilist" }));
}

function queryFake(opts: FakeOptions & { modes?: Record<string, string> } = {}) {
  const { modes, ...rest } = opts;
  return baseQueryFake({ ...rest, tables: { catalogue_cutover: cutoverRows(modes), ...(rest.tables ?? {}) } });
}

function lockRpc(held: Set<string>) {
  return {
    acquire_import_lock: (args: Record<string, unknown>) => {
      const k = String(args.p_key);
      if (held.has(k)) return { data: false, error: null };
      held.add(k);
      return { data: true, error: null };
    },
    release_import_lock: (args: Record<string, unknown>) => {
      held.delete(String(args.p_key));
      return { data: null, error: null };
    },
  };
}

Deno.test("jikan helpers: parse broadcast, compute JST next slot, estimate episode", () => {
  const bc = parseJikanBroadcast({ day: "Sundays", time: "23:30", timezone: "Asia/Tokyo" });
  assert.deepEqual(bc, { weekday: 0, hour: 23, minute: 30 });
  assert.equal(parseJikanBroadcast({ day: "Unknown", time: "23:30", timezone: "Asia/Tokyo" }), null);
  assert.equal(parseJikanBroadcast({ day: "Sundays", time: "10:00", timezone: "America/New_York" }), null);

  // Sunday 2026-11-22 10:00:00 UTC = Sunday 19:00 JST -> 23:30 JST is 14:30 UTC same day
  const nowMs = Date.parse("2026-11-22T10:00:00Z");
  assert.ok(bc != null);
  const nextMs = computeNextJstBroadcastMs(bc, nowMs);
  assert.equal(new Date(nextMs).toISOString(), "2026-11-22T14:30:00.000Z");

  // Past 23:30 JST -> rolls forward 7 days
  const lateMs = Date.parse("2026-11-22T15:00:00Z");
  assert.equal(new Date(computeNextJstBroadcastMs(bc, lateMs)).toISOString(), "2026-11-29T14:30:00.000Z");

  // Aired from 2026-10-04 -> 7 weeks later is episode 8
  assert.equal(estimateEpisodeNumber("2026-10-04T00:00:00+00:00", nextMs, 12), 8);
  assert.equal(estimateEpisodeNumber("2026-10-04T00:00:00+00:00", nextMs, 5), null);
});

Deno.test("jikan handler: fills missing/stale RELEASING anime without overwriting fresh future instants", async () => {
  const NOW = Date.parse("2026-11-22T10:00:00Z");
  const existingFuture = "2026-11-24T12:00:00.000Z";
  const locks = new Set<string>();
  const fake = queryFake({
    tables: {
      anime: [
        { id: 101, mal_id: 50001, status: "RELEASING", episodes: 12, next_episode_number: null, next_airing_at: null },
        { id: 102, mal_id: 50002, status: "RELEASING", episodes: 24, next_episode_number: 8, next_airing_at: existingFuture },
      ],
    },
    rpc: lockRpc(locks),
  });

  const jikanFetch: typeof fetch = () =>
    Promise.resolve(
      new Response(
        JSON.stringify({
          pagination: { has_next_page: false },
          data: [
            {
              mal_id: 50001,
              episodes: 12,
              aired: { from: "2026-10-04T00:00:00+00:00" },
              broadcast: { day: "Sundays", time: "23:30", timezone: "Asia/Tokyo" },
            },
            {
              mal_id: 50002,
              episodes: 24,
              aired: { from: "2026-10-04T00:00:00+00:00" },
              broadcast: { day: "Mondays", time: "01:00", timezone: "Asia/Tokyo" },
            },
          ],
        }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      ),
    );

  const res = await run(
    { mode: "jikan", maxPages: 2 },
    {
      supabase: fake.client,
      anilist: createAniListClient({ limiter: new AniListLimiter(0), fetch: () => Promise.reject(new Error("unused")) }),
      mangaUpdates: createPoliteClient({ limiter: new PoliteLimiter(0), fetch: () => Promise.reject(new Error("unused")) }),
      readMangaDexLinks: () => Promise.resolve(null),
      jikanFetch,
      now: () => NOW,
    },
  );

  const out = await res.json();
  assert.equal(res.status, 200, JSON.stringify(out));
  assert.equal(out.results.candidates, 1);
  assert.equal(out.results.skippedExistingFuture, 1);
  assert.equal(out.results.matched, 1);
  assert.equal(out.results.events, 1);
  assert.equal(out.results.animePatched, 1);
  assert.equal(fake.tables.anime[0].next_episode_number, 8);
  assert.equal(fake.tables.anime[0].next_airing_at, "2026-11-22T14:30:00.000Z");
  assert.equal(fake.tables.anime[1].next_airing_at, existingFuture);

  const calls = fake.rpcCalls("upsert_release_events_v1");
  const rows = calls.flatMap((c) => c.p_rows as ReleaseEventRow[]);
  assert.equal(rows.length, 1);
  assert.equal(rows[0].source, "publisher");
  assert.equal(rows[0].basis, "announced");
  assert.equal(rows[0].source_url, null);
  assert.equal(rows[0].precision, "instant");
  assert.equal(rows[0].unit_label, "Ep. 8");
});
