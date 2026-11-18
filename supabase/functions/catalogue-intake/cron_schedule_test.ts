// Schedule tests (catalogue Task 15 Step 7). Run: cd supabase/functions/catalogue-intake && deno test --no-prompt
import { strict as assert } from "node:assert";
import { ANN_BATCH } from "./ann.ts";
import { WIKIDATA_BATCH } from "./wikidata.ts";
import { fakeSupabase } from "./fake_supabase.ts";
import { handleRequest, type IntakeDeps } from "./handler.ts";
import {
  CRON_JOBS,
  firingMinutes,
  inMangaUpdatesQuietWindow,
  jobMinutes,
  MU_QUIET_WINDOW,
  parseCron,
  RELEASE_INTAKE_MANGA,
  renderCronSql,
} from "./cron_schedule.ts";

const MU_JOBS = CRON_JOBS.filter((j) => j.handler === "mangaupdates");
const at = (h: number, m: number) => Date.UTC(2026, 10, 18, h, m, 0);

Deno.test("muNeverOverlapsReleaseIntake: no MangaUpdates run fires from 03:30 to 04:20, the handler guard agrees", () => {
  const riMinute = firingMinutes(RELEASE_INTAKE_MANGA.schedule)[0];
  assert.equal(riMinute, 3 * 60 + 50);
  assert.ok(riMinute >= MU_QUIET_WINDOW.startMinute && riMinute + RELEASE_INTAKE_MANGA.budgetMs / 60_000 < MU_QUIET_WINDOW.endMinute, "release-intake and its 120 s budget sit inside the window");
  for (const dow of [0, 1, 6]) {
    for (const m of jobMinutes(MU_JOBS, dow)) {
      assert.ok(m < MU_QUIET_WINDOW.startMinute || m > MU_QUIET_WINDOW.endMinute, `MangaUpdates fires at minute ${m} inside the quiet window`);
    }
  }
  // the window is the only gap: every other even minute of the day fires
  const fires = jobMinutes(MU_JOBS);
  for (let m = 0; m < 1440; m += 2) {
    const inWindow = m >= MU_QUIET_WINDOW.startMinute && m <= MU_QUIET_WINDOW.endMinute;
    assert.equal(fires.has(m), !inWindow, `minute ${m}`);
  }
  // the guard inside the handler
  assert.equal(inMangaUpdatesQuietWindow(at(3, 29)), false);
  assert.equal(inMangaUpdatesQuietWindow(at(3, 30)), true);
  assert.equal(inMangaUpdatesQuietWindow(at(3, 50)), true);
  assert.equal(inMangaUpdatesQuietWindow(at(4, 20)), true);
  assert.equal(inMangaUpdatesQuietWindow(at(4, 21)), false);
});

Deno.test("muNeverOverlapsReleaseIntake: the handler skips a MangaUpdates run inside the window without taking the lock", async () => {
  const db = fakeSupabase();
  const deps = { supabase: db.client, clients: {} as never, now: () => at(3, 50) } as IntakeDeps;
  const res = await handleRequest(
    new Request("https://x.test/", { method: "POST", headers: { "x-import-secret": "s" }, body: JSON.stringify({ handler: "mangaupdates", medium: "manga" }) }),
    { secret: "s", buildDeps: () => deps },
  );
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.deepEqual({ skipped: body.skipped, reason: body.reason }, { skipped: true, reason: "release_intake_window" });
  assert.equal(db.rpcs.length, 0);
});

Deno.test("cron expressions parse and the staggered handlers never share a minute (one lock per handler)", () => {
  for (const j of CRON_JOBS) parseCron(j.schedule);
  const byHandler = new Map<string, Set<number>[]>();
  for (const j of CRON_JOBS.filter((x) => x.phase !== "initial")) {
    const list = byHandler.get(j.handler) ?? [];
    list.push(jobMinutes([j], 0));
    byHandler.set(j.handler, list);
  }
  for (const [handler, sets] of byHandler) {
    const all = new Set<number>();
    for (const s of sets) for (const m of s) {
      assert.ok(!all.has(m), `${handler} has two jobs firing at minute ${m}`);
      all.add(m);
    }
  }
  assert.throws(() => parseCron("* * 1 * *"));
});

// Counts from the 2026-11-09 inventory (spec section 3.1) and the figures of the spec's throughput table.
const COUNTS = { anime: 21_867, manga: 41_899, annAnimeRecords: 20_000, muRequests: 80_000, pageviewsCalls: 28_800 };
const PER_RUN = { wikidataQueries: 4, annRequests: 45, muRequests: 45, pageviewsCalls: 200, composeTitles: 5_000 };
const SPEC = { wikidataInitialHours: 8, annInitialHours: 4.5, muInitialDays: 2.6, muRunsPerDay: 695, pageviewsInitialHours: 12, pageviewsRefreshRuns: 144, composeFirstRuns: 13, wikidataQueriesPerDay: 384 };
const within = (actual: number, spec: number) => Math.abs(actual - spec) / spec <= 0.1;

Deno.test("passLengthsMatchSpecTable: initial pass and refresh recomputed from the constants stay within 10% of spec section 3.1", () => {
  const runsPerDay = (jobs: typeof CRON_JOBS) => jobMinutes(jobs, 1).size;
  const jobs = (h: string, medium?: string, phase?: string) => CRON_JOBS.filter((j) => j.handler === h && (!medium || j.medium === medium) && (!phase || j.phase === phase));

  // Wikidata: 128 queries, 4 per run, one run per medium every 30 min (each medium 48 runs a day)
  const wdQueries = Math.ceil(COUNTS.anime / WIKIDATA_BATCH) + Math.ceil(COUNTS.manga / WIKIDATA_BATCH);
  assert.equal(wdQueries, 128);
  const wdRuns = Math.ceil(wdQueries / PER_RUN.wikidataQueries);
  const wdRunsPerDay = runsPerDay(jobs("wikidata"));
  const wdHours = (wdRuns / wdRunsPerDay) * 24;
  assert.ok(within(wdHours, SPEC.wikidataInitialHours), `wikidata initial pass ${wdHours} h vs ${SPEC.wikidataInitialHours}`);
  assert.ok(within(wdRunsPerDay * PER_RUN.wikidataQueries, SPEC.wikidataQueriesPerDay), "wikidata queries per day");
  assert.ok(wdQueries <= wdRunsPerDay * PER_RUN.wikidataQueries, "a daily refresh fits in a day");

  // ANN records: 20,000 / 50 = 400 requests
  const annRequests = Math.ceil(COUNTS.annAnimeRecords / ANN_BATCH);
  assert.equal(annRequests, 400);
  const annHours = (Math.ceil(annRequests / PER_RUN.annRequests) / runsPerDay(jobs("ann"))) * 24;
  assert.ok(within(annHours, SPEC.annInitialHours), `ann initial pass ${annHours} h vs ${SPEC.annInitialHours}`);

  // MangaUpdates: ~80,000 requests, 45 per run
  const muPerDay = runsPerDay(MU_JOBS);
  assert.ok(within(muPerDay, SPEC.muRunsPerDay), `mangaupdates runs per day ${muPerDay} vs ${SPEC.muRunsPerDay}`);
  const muDays = Math.ceil(COUNTS.muRequests / PER_RUN.muRequests) / muPerDay;
  assert.ok(within(muDays, SPEC.muInitialDays), `mangaupdates initial pass ${muDays} d vs ${SPEC.muInitialDays}`);

  // Pageviews: 28,800 calls, ~200 per serial 50 s run; one run every 5 min across the two media
  const pvRuns = Math.ceil(COUNTS.pageviewsCalls / PER_RUN.pageviewsCalls);
  const pvInitialHours = (pvRuns / runsPerDay(jobs("pageviews", undefined, "initial"))) * 24;
  assert.ok(within(pvInitialHours, SPEC.pageviewsInitialHours), `pageviews initial pass ${pvInitialHours} h vs ${SPEC.pageviewsInitialHours}`);
  const weekly = jobs("pageviews", undefined, "refresh");
  const weeklyRuns = jobMinutes(weekly, 0).size; // Sunday only
  assert.ok(within(weeklyRuns, SPEC.pageviewsRefreshRuns), `pageviews weekly runs ${weeklyRuns} vs ${SPEC.pageviewsRefreshRuns}`);
  assert.ok(weeklyRuns * PER_RUN.pageviewsCalls >= COUNTS.pageviewsCalls, "the Sunday window covers a full weekly refresh");
  assert.equal(jobMinutes(weekly, 1).size, 0, "the weekly refresh does not run on other days");

  // compose / publish: <= 5,000 titles an hour; ~64,000 titles for the first full compose
  const composeRuns = Math.ceil((COUNTS.anime + COUNTS.manga) / PER_RUN.composeTitles);
  assert.ok(within(composeRuns, SPEC.composeFirstRuns), `compose first full pass ${composeRuns} runs vs ${SPEC.composeFirstRuns}`);
  const minuteOfHour = (h: string) => [...new Set([...jobMinutes(jobs(h, "anime"), 1)].map((m) => m % 60))];
  assert.deepEqual(minuteOfHour("compose"), [55]);
  assert.deepEqual(minuteOfHour("publish"), [58]);
  assert.equal(jobMinutes(jobs("compose", "anime"), 1).size, 24, "hourly");
});

Deno.test("passLengthsMatchSpecTable: a slower run would fail the check (the guard is live)", () => {
  // 100 pageviews calls per run would double the initial pass to ~24 h, outside the 10% band
  const hours = (Math.ceil(COUNTS.pageviewsCalls / 100) / 288) * 24;
  assert.equal(within(hours, SPEC.pageviewsInitialHours), false);
});

Deno.test("renderCronSql: every job is scheduled once with its payload, no secret literal", () => {
  const sql = renderCronSql();
  for (const j of CRON_JOBS) {
    assert.equal(sql.split(`cron.schedule('${j.name}'`).length - 1, 1, j.name);
    assert.ok(sql.includes(`'${j.schedule}'`));
    assert.ok(sql.includes(JSON.stringify({ handler: j.handler, medium: j.medium })));
  }
  assert.ok(sql.includes(":'import_secret'") && sql.includes(":'service_jwt'"));
  assert.equal(/eyJ[A-Za-z0-9_-]{20,}/.test(sql), false, "no JWT literal");
});
