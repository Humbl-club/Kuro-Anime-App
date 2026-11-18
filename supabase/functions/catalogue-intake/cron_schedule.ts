// Prepared cron schedule of catalogue-intake (catalogue Task 15 Step 7; spec section 3.1). NOT applied.
// This module is the single source of the schedule: docs/catalogue-sources-2026-11/cron-prepared.sql is
// generated from it (`deno run supabase/functions/catalogue-intake/cron_schedule.ts`), and
// cron_schedule_test.ts checks the schedule against the spec's throughput table. pg_cron runs in UTC.
// Nothing here talks to a database or a source.

export type CronJob = {
  name: string;
  schedule: string;
  handler: "wikidata" | "ann" | "mangaupdates" | "mangaupdates_new" | "pageviews" | "compose" | "publish" | "create";
  medium: "anime" | "manga";
  /** Extra payload fields (timeBudgetMs etc.). */
  extra?: Record<string, unknown>;
  /** Initial-pass jobs are unscheduled once the first full pass is done and the refresh job takes over. */
  phase?: "initial" | "refresh";
};

/** release-intake's manga job (`kuro-release-intake-manga-daily`, job 117): 03:50 UTC, budget 120 s. */
export const RELEASE_INTAKE_MANGA = { name: "kuro-release-intake-manga-daily", schedule: "50 3 * * *", budgetMs: 120_000 } as const;

/** MangaUpdates must not run from 03:30 to 04:20 UTC (inclusive): around release-intake's 03:50 run. */
export const MU_QUIET_WINDOW = { startMinute: 3 * 60 + 30, endMinute: 4 * 60 + 20 } as const;

/** The handler-side guard that backs the cron expressions: true inside the quiet window (UTC). */
export function inMangaUpdatesQuietWindow(nowMs: number): boolean {
  const d = new Date(nowMs);
  const minute = d.getUTCHours() * 60 + d.getUTCMinutes();
  return minute >= MU_QUIET_WINDOW.startMinute && minute <= MU_QUIET_WINDOW.endMinute;
}

export const CRON_JOBS: readonly CronJob[] = [
  // Wikidata: 4 queries per run; anime and manga alternate every 15 min (384 queries/day in total).
  { name: "catalogue-intake-wikidata-anime", schedule: "0,30 * * * *", handler: "wikidata", medium: "anime" },
  { name: "catalogue-intake-wikidata-manga", schedule: "15,45 * * * *", handler: "wikidata", medium: "manga" },
  // ANN (anime only): every 30 min.
  { name: "catalogue-intake-ann-anime", schedule: "10,40 * * * *", handler: "ann", medium: "anime" },
  // MangaUpdates (manga only): every 2 min except 03:30-04:20, as three expressions (cron cannot express the gap
  // in one) plus the handler guard above.
  { name: "catalogue-intake-mangaupdates-a", schedule: "*/2 0-2,5-23 * * *", handler: "mangaupdates", medium: "manga" },
  { name: "catalogue-intake-mangaupdates-b", schedule: "0-28/2 3 * * *", handler: "mangaupdates", medium: "manga" },
  { name: "catalogue-intake-mangaupdates-c", schedule: "22-58/2 4 * * *", handler: "mangaupdates", medium: "manga" },
  // MangaUpdates new series (Task 15c): twice an hour on ODD minutes, so it never shares a minute with the matcher (even
  // minutes, each run ends within 50 s) and never runs in 03:30-04:20 (release-intake): :07 and :37 except 03:37 and 04:07.
  { name: "catalogue-intake-mangaupdates-new-a", schedule: "7,37 0-2,5-23 * * *", handler: "mangaupdates_new", medium: "manga" },
  { name: "catalogue-intake-mangaupdates-new-b", schedule: "7 3 * * *", handler: "mangaupdates_new", medium: "manga" },
  { name: "catalogue-intake-mangaupdates-new-c", schedule: "37 4 * * *", handler: "mangaupdates_new", medium: "manga" },
  // create (Task 15c), manga, REPORT mode (the payload has no mode, so the default applies; insert mode is the separate,
  // owner-approved Task 17 Step 2b change). DB only, no source request: it reads the records mangaupdates_new stored.
  { name: "catalogue-intake-create-manga", schedule: "20 * * * *", handler: "create", medium: "manga" },
  // Pageviews: about 200 serial calls per 50 s run. Initial pass: both media every 10 min (offset 5 min),
  // i.e. one run every 5 min. Refresh: Sunday 00:00-12:00 on the same grid.
  { name: "catalogue-intake-pageviews-anime-initial", schedule: "0-50/10 * * * *", handler: "pageviews", medium: "anime", phase: "initial" },
  { name: "catalogue-intake-pageviews-manga-initial", schedule: "5-55/10 * * * *", handler: "pageviews", medium: "manga", phase: "initial" },
  { name: "catalogue-intake-pageviews-anime-weekly", schedule: "0-50/10 0-11 * * 0", handler: "pageviews", medium: "anime", phase: "refresh" },
  { name: "catalogue-intake-pageviews-manga-weekly", schedule: "5-55/10 0-11 * * 0", handler: "pageviews", medium: "manga", phase: "refresh" },
  // compose hourly at :55 and publish hourly at :58 (the second medium one minute later: one lock per handler).
  { name: "catalogue-intake-compose-anime", schedule: "55 * * * *", handler: "compose", medium: "anime" },
  { name: "catalogue-intake-compose-manga", schedule: "56 * * * *", handler: "compose", medium: "manga" },
  { name: "catalogue-intake-publish-anime", schedule: "58 * * * *", handler: "publish", medium: "anime" },
  { name: "catalogue-intake-publish-manga", schedule: "59 * * * *", handler: "publish", medium: "manga" },
];

// ---------------------------------------------------------------------------------------------
// A small cron evaluator (minute hour dom month dow; `*`, `n`, `a-b`, `*/n`, `a-b/n`, lists)

function expand(field: string, min: number, max: number): Set<number> {
  const out = new Set<number>();
  for (const part of field.split(",")) {
    const [range, stepRaw] = part.split("/");
    const step = stepRaw === undefined ? 1 : Number(stepRaw);
    let lo = min;
    let hi = max;
    if (range !== "*") {
      const [a, b] = range.split("-");
      lo = Number(a);
      hi = b === undefined ? (stepRaw === undefined ? lo : max) : Number(b);
    }
    if (!Number.isInteger(lo) || !Number.isInteger(hi) || !Number.isInteger(step) || step < 1 || lo < min || hi > max || lo > hi) {
      throw new Error(`bad cron field "${field}"`);
    }
    for (let v = lo; v <= hi; v += step) out.add(v);
  }
  return out;
}

export type ParsedCron = { minutes: Set<number>; hours: Set<number>; dows: Set<number> | null };

export function parseCron(expr: string): ParsedCron {
  const f = expr.trim().split(/\s+/);
  if (f.length !== 5) throw new Error(`cron needs 5 fields: "${expr}"`);
  if (f[2] !== "*" || f[3] !== "*") throw new Error(`day-of-month and month are not used here: "${expr}"`);
  return { minutes: expand(f[0], 0, 59), hours: expand(f[1], 0, 23), dows: f[4] === "*" ? null : expand(f[4], 0, 6) };
}

/** Minutes of a day (0..1439) at which the expression fires; `dow` selects the weekday (0 = Sunday). */
export function firingMinutes(expr: string, dow = 0): number[] {
  const c = parseCron(expr);
  if (c.dows && !c.dows.has(dow)) return [];
  const out: number[] = [];
  for (const h of [...c.hours].sort((a, b) => a - b)) for (const m of [...c.minutes].sort((a, b) => a - b)) out.push(h * 60 + m);
  return out;
}

/** Union of the firing minutes of a set of jobs on one weekday. */
export function jobMinutes(jobs: readonly CronJob[], dow = 1): Set<number> {
  const s = new Set<number>();
  for (const j of jobs) for (const m of firingMinutes(j.schedule, dow)) s.add(m);
  return s;
}

// ---------------------------------------------------------------------------------------------
// SQL rendering. Secrets are never written here: psql variables carry them (:'import_secret' and friends),
// copied from the command of an existing import job at apply time.

function payloadFor(job: CronJob): string {
  return JSON.stringify({ handler: job.handler, medium: job.medium, ...(job.extra ?? {}) });
}

export function renderCronSql(jobs: readonly CronJob[] = CRON_JOBS): string {
  const lines: string[] = [
    "-- Catalogue-intake cron jobs. PREPARED, NOT APPLIED (catalogue Task 15 Step 7; spec section 3.1).",
    "-- Generated from supabase/functions/catalogue-intake/cron_schedule.ts: edit that file, then regenerate with",
    "--   deno run supabase/functions/catalogue-intake/cron_schedule.ts > docs/catalogue-sources-2026-11/cron-prepared.sql",
    "-- Applying this file is a hosted change and needs the owner's explicit approval, after catalogue-intake is deployed.",
    "-- pg_cron runs in UTC. Run it with psql variables copied from an existing import job's command (never committed):",
    "--   \\set project_url '...' \\set import_secret '...' \\set service_jwt '...'",
    "-- Schedule only after the matching migrations are applied and the function is deployed (--no-verify-jwt).",
    "-- A job name that already exists is replaced by cron.schedule(name, ...).",
    "",
  ];
  for (const j of jobs) {
    lines.push(`-- ${j.handler} ${j.medium}${j.phase ? ` (${j.phase})` : ""}`);
    // psql does not interpolate variables inside dollar-quoted text, so the command is built with format()
    // from the variables passed as arguments (outside the quotes): the secret ends up in the stored command
    // exactly like the existing import jobs.
    lines.push(
      `select cron.schedule('${j.name}', '${j.schedule}', format(`,
      "  $cmd$select net.http_post(url := %L || '/functions/v1/catalogue-intake',",
      "    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || %L, 'x-import-secret', %L),",
      "    body := %L::jsonb)$cmd$,",
      `  :'project_url', :'service_jwt', :'import_secret', '${payloadFor(j)}'));`,
      "",
    );
  }
  lines.push(
    "-- After the initial pageviews pass has covered every title (spec 3.1: about 12 h), drop the initial jobs:",
    "--   select cron.unschedule('catalogue-intake-pageviews-anime-initial');",
    "--   select cron.unschedule('catalogue-intake-pageviews-manga-initial');",
    "",
  );
  return lines.join("\n");
}

if (import.meta.main) console.log(renderCronSql());
