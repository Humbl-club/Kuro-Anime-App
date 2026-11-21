// Offline tests for Syoboi Calendar airing intake (zero network, zero DB).
// Verifies parseSyoboiProgItems, valid 'publisher' row generation matching
// upsert_release_events_v1 constraints, and cutover gating when episodes='new'.
import { strict as assert } from "node:assert";
import { AniListLimiter, createAniListClient } from "../_shared/anilist_client.ts";
import { FIELD_GROUP_NAMES } from "../_shared/catalogue/field_groups.ts";
import { createPoliteClient, PoliteLimiter } from "../_shared/polite_fetch.ts";
import { queryFake as baseQueryFake, type FakeOptions } from "../_shared/test_query_fake.ts";
import type { ReleaseEventRow } from "./contract.ts";
import { run } from "./handler.ts";
import { parseSyoboiCalChkXml, parseSyoboiProgItems, parseSyoboiTitleMedium } from "./syoboi.ts";

const NOW = Date.parse("2026-11-01T10:00:00Z");
const NOW_S = Math.floor(NOW / 1000);

function cutoverRows(modes: Record<string, string> = {}) {
  return FIELD_GROUP_NAMES.map((g) => ({ field_group: g, mode: modes[g] ?? "anilist" }));
}

function queryFake(opts: FakeOptions & { modes?: Record<string, string> } = {}) {
  const { modes, ...rest } = opts;
  return baseQueryFake({
    ...rest,
    tables: { catalogue_cutover: cutoverRows(modes), ...(rest.tables ?? {}) },
  });
}

function lockRpc(state: { held: Set<string> }) {
  return {
    acquire_import_lock: (args: Record<string, unknown>) => {
      const key = String(args.p_key);
      if (state.held.has(key)) return { data: false, error: null };
      state.held.add(key);
      return { data: true, error: null };
    },
    release_import_lock: (args: Record<string, unknown>) => {
      state.held.delete(String(args.p_key));
      return { data: null, error: null };
    },
  };
}

function noopClients() {
  return {
    anilist: createAniListClient({
      limiter: new AniListLimiter(0),
      sleep: () => Promise.resolve(),
      now: () => NOW,
      random: () => 0,
      fetch: () => Promise.reject(new Error("AniList must not be called in syoboi mode")),
    }),
    mangaUpdates: createPoliteClient({
      limiter: new PoliteLimiter(0),
      sleep: () => Promise.resolve(),
      now: () => NOW,
      random: () => 0,
      fetch: () => Promise.reject(new Error("MangaUpdates must not be called in syoboi mode")),
    }),
    readMangaDexLinks: () => Promise.resolve(null),
    now: () => NOW,
  };
}

Deno.test("parseSyoboiProgItems parses Programs and ProgItems while filtering invalid/deleted entries", () => {
  const parsed = parseSyoboiProgItems({
    Programs: {
      "101": { TID: "7001", PID: "101", Count: "5", StTime: String(NOW_S + 3600), Deleted: "0" },
      "102": { TID: "7001", PID: "102", Count: "6", StTime: String(NOW_S + 7200), Deleted: "1" },
      "103": { TID: "7002", PID: "103", Count: "0", StTime: String(NOW_S + 3600) },
    },
  });
  assert.deepEqual(parsed, [{ tid: "7001", pid: "101", episode: 5, stTimeSeconds: NOW_S + 3600 }]);

  const arrayVariant = parseSyoboiProgItems({
    ProgItems: [{ TID: 7009, PID: 201, Count: 12, StTime: NOW_S + 86400 }],
  });
  assert.deepEqual(arrayVariant, [{ tid: "7009", pid: "201", episode: 12, stTimeSeconds: NOW_S + 86400 }]);
});

Deno.test("syoboi mode maps TID -> anime_id, picks earliest channel broadcast, and satisfies writer constraints", async () => {
  const locks = { held: new Set<string>() };
  const fake = queryFake({
    tables: {
      anime: [{ id: 42, next_episode_number: 4, next_airing_at: new Date((NOW_S - 3600) * 1000).toISOString() }],
      catalogue_id_links: [
        { kind: "anime", kuro_id: 42, source: "syoboi", source_key: "7001", status: "accepted" },
        { kind: "anime", kuro_id: 99, source: "syoboi", source_key: "7002", status: "proposed" },
      ],
    },
    rpc: lockRpc(locks),
  });

  const syoboiUrls: string[] = [];
  const syoboiFetch: typeof fetch = (input) => {
    syoboiUrls.push(String(input));
    return Promise.resolve(
      new Response(
        JSON.stringify({
          ProgItems: {
            "501": { TID: "7001", PID: "501", Count: "5", StTime: String(NOW_S + 7200) },
            "502": { TID: "7001", PID: "502", Count: "5", StTime: String(NOW_S + 3600) },
            "503": { TID: "7001", PID: "503", Count: "4", StTime: String(NOW_S - 1800) },
          },
        }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      ),
    );
  };

  const res = await run({ mode: "syoboi" }, { supabase: fake.client, ...noopClients(), syoboiFetch });
  const out = await res.json();
  assert.equal(res.status, 200, JSON.stringify(out));
  assert.equal(syoboiUrls.length, 1);
  assert.ok(syoboiUrls[0].includes("TID=7001") && !syoboiUrls[0].includes("7002"));

  const rows = fake.rpcCalls("upsert_release_events_v1").flatMap((c) => c.p_rows as ReleaseEventRow[]);
  assert.equal(rows.length, 2);
  for (const r of rows) {
    assert.equal(r.source, "publisher");
    assert.equal(r.source_url, null);
    assert.equal(r.basis, "confirmed");
    assert.equal(r.precision, "instant");
    assert.equal(r.medium, "anime");
    assert.equal(r.unit_kind, "episode");
  }
  const ep5 = rows.find((r) => r.unit_number === 5)!;
  assert.equal(ep5.external_id, "syoboi:7001:502");
  assert.equal(ep5.status, "scheduled");
  assert.equal(ep5.release_at, new Date((NOW_S + 3600) * 1000).toISOString());

  const ep4 = rows.find((r) => r.unit_number === 4)!;
  assert.equal(ep4.status, "released");
  assert.equal(fake.tables.anime[0].next_episode_number, 5);
  assert.equal(locks.held.size, 0);
});

Deno.test("syoboi mode skips anime.next_* writes when episodes group is switched to new", async () => {
  const locks = { held: new Set<string>() };
  const fake = queryFake({
    modes: { episodes: "new" },
    tables: {
      anime: [{ id: 42, next_episode_number: 4, next_airing_at: null }],
      catalogue_id_links: [
        { kind: "anime", kuro_id: 42, source: "syoboi", source_key: "7001", status: "accepted" },
      ],
    },
    rpc: lockRpc(locks),
  });

  const syoboiFetch: typeof fetch = () =>
    Promise.resolve(
      new Response(
        JSON.stringify({
          Programs: {
            "502": { TID: "7001", PID: "502", Count: "5", StTime: String(NOW_S + 3600) },
          },
        }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      ),
    );

  const res = await run({ mode: "syoboi" }, { supabase: fake.client, ...noopClients(), syoboiFetch });
  const out = await res.json();
  assert.equal(res.status, 200, JSON.stringify(out));
  assert.equal(out.results.events, 1);
  assert.equal(out.results.animePatched, 0);
  assert.equal(fake.calls.filter((c) => c.kind === "update" && c.table === "anime").length, 0);
});

Deno.test("syoboi mode stops cleanly with rate_limited on HTTP 429 and releases lock", async () => {
  const locks = { held: new Set<string>() };
  const fake = queryFake({
    tables: {
      catalogue_id_links: [
        { kind: "anime", kuro_id: 42, source: "syoboi", source_key: "7001", status: "accepted" },
      ],
    },
    rpc: lockRpc(locks),
  });

  const syoboiFetch: typeof fetch = () =>
    Promise.resolve(new Response(null, { status: 429, headers: { "Retry-After": "12" } }));

  const res = await run({ mode: "syoboi" }, { supabase: fake.client, ...noopClients(), syoboiFetch });
  const out = await res.json();
  assert.equal(res.status, 200, JSON.stringify(out));
  assert.equal(out.results.stoppedEarly, "rate_limited");
  assert.equal(out.results.events, 0);
  assert.equal(locks.held.size, 0);
});

Deno.test("syoboi cal_chk.php XML parses JST StTime, filters rerun marathons, and auto-links RELEASING anime", async () => {
  const xml = `<?xml version="1.0" encoding="UTF-8"?>
<syobocal>
<ProgItems>
<ProgItem PID="10" TID="8001" StTime="20261102003000" Count="8" Title="テストアニメ(2026)"/>
<ProgItem PID="11" TID="8001" StTime="20261102010000" Count="8" Title="テストアニメ(2026)"/>
<ProgItem PID="12" TID="8002" StTime="20261102020000" Count="" Title="Re-run Marathon"/>
<ProgItem PID="13" TID="8001" StTime="20261102030000" Count="9" Deleted="1" Title="テストアニメ(2026)"/>
</ProgItems>
</syobocal>`;
  const parsedXml = parseSyoboiCalChkXml(xml);
  assert.equal(parsedXml.length, 2);
  assert.equal(parsedXml[0].tid, "8001");
  assert.equal(parsedXml[0].episode, 8);
  // 2026-11-02 00:30:00 JST = 2026-11-01 15:30:00 UTC
  assert.equal(parsedXml[0].stTimeSeconds, Math.floor(Date.parse("2026-11-01T15:30:00Z") / 1000));

  const titleMeta = parseSyoboiTitleMedium({
    Titles: { "8001": { TID: "8001", Title: "テストアニメ", TitleEN: "Test Anime", FirstYear: "2026" } },
  });
  assert.equal(titleMeta.get("8001")?.firstYear, 2026);

  const locks = { held: new Set<string>() };
  const fake = queryFake({
    tables: {
      anime: [{ id: 500, status: "RELEASING", title_native: "テストアニメ", start_date_year: 2026, next_episode_number: 7, next_airing_at: null }],
      catalogue_id_links: [],
    },
    rpc: {
      ...lockRpc(locks),
      catalogue_find_title_candidates_v1: () => ({
        data: [{ id: 500, title_native: "テストアニメ", title_english: "Test Anime", start_date_year: 2026 }],
        error: null,
      }),
    },
  });

  const syoboiFetch: typeof fetch = (input) => {
    const url = String(input);
    if (url.includes("cal_chk.php")) {
      return Promise.resolve(new Response(xml, { status: 200 }));
    }
    return Promise.resolve(new Response(JSON.stringify({
      Titles: { "8001": { TID: "8001", Title: "テストアニメ", TitleEN: "Test Anime", FirstYear: "2026" } },
    }), { status: 200 }));
  };

  const res = await run({ mode: "syoboi", discover: true }, { supabase: fake.client, ...noopClients(), syoboiFetch });
  const out = await res.json();
  assert.equal(res.status, 200, JSON.stringify(out));
  assert.equal(out.results.discoveredTids, 1);
  assert.equal(out.results.linked, 1);
  assert.equal(out.results.events, 1);
  assert.equal(out.results.animePatched, 1);
  assert.equal(fake.tables.anime[0].next_episode_number, 8);
  assert.equal(fake.tables.anime[0].next_airing_at, "2026-11-01T15:30:00.000Z");
  assert.equal(fake.tables.catalogue_id_links.length, 1);
  assert.equal(fake.tables.catalogue_id_links[0].source_key, "8001");
});
