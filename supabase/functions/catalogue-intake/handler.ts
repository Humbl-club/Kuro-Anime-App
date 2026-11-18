// catalogue-intake run orchestration (prepared, NOT deployed, NOT scheduled).
// index.ts reads the environment and builds clients; everything else is injected so a run is
// testable offline. Auth is the shared IMPORT_SECRET header, like bulk-import (pg_cron cannot
// send JWTs): a missing server secret is 500, a wrong or absent header is 401.
//
// Payload: { handler, medium?, limit?, timeBudgetMs? }
//   handler  'wikidata' | 'ann' | 'mangaupdates' | 'pageviews' | 'compose' | 'publish'
//   medium   'anime' | 'manga' (required; ann is anime only, mangaupdates is manga only)
//   limit    per-run work cap, each handler clamps it
//   timeBudgetMs  default 50_000 (5_000..140_000)
// compose (Task 7) is local-DB only. publish (Task 15) writes the field groups whose mode is 'new'
// (publish.ts). restore (Task 15) is the rollback of one group, payload { handler: 'restore', group },
// medium not needed; it refuses a group that is still 'new' (restore.ts).
// Lock: acquire_import_lock('catalogue-intake:<handler>', 900), released only when acquired.
// Bookkeeping: import_runs (run_type 'catalogue_intake_<handler>'). Cursors: import_track_state
// `catalogue-intake:<handler>:<medium>`, owned by each handler.
import { acquireImportLock, finishImportRun, releaseImportLock, startImportRun } from "./../_shared/catalogue/intake_persistence.ts";
import type { HandlerOutcome, IntakeDeps, RunContext } from "./context.ts";
import { clampInt, type Medium } from "./store.ts";
import { runAnn } from "./ann.ts";
import { runCompose } from "./compose.ts";
import { runMangaUpdates } from "./mangaupdates.ts";
import { inMangaUpdatesQuietWindow } from "./cron_schedule.ts";
import { runPageviews } from "./pageviews.ts";
import { runPublish } from "./publish.ts";
import { restore } from "./restore.ts";
import type { FieldGroup } from "../_shared/catalogue/field_groups.ts";
import { runWikidata } from "./wikidata.ts";

export type { IntakeDeps } from "./context.ts";

export const HANDLER_NAMES = ["wikidata", "ann", "mangaupdates", "pageviews", "compose", "publish", "restore"] as const;
export type HandlerName = (typeof HANDLER_NAMES)[number];

/** Handlers with an implementation. Later tasks register theirs here. */
export const HANDLERS: Partial<Record<HandlerName, (ctx: RunContext) => Promise<HandlerOutcome>>> = {
  wikidata: runWikidata,
  ann: runAnn,
  mangaupdates: runMangaUpdates,
  pageviews: runPageviews,
  compose: runCompose,
  publish: runPublish,
};

/** Which media each handler serves; absent means both. */
const MEDIA_FOR: Partial<Record<HandlerName, Medium[]>> = { ann: ["anime"], mangaupdates: ["manga"] };

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

export async function handleRequest(
  req: Request,
  opts: { secret: string | undefined; buildDeps: () => IntakeDeps },
): Promise<Response> {
  if (!opts.secret) return json({ error: "Server misconfigured" }, 500);
  if (req.headers.get("x-import-secret") !== opts.secret) return json({ error: "Unauthorized" }, 401);
  // deno-lint-ignore no-explicit-any
  const payload = await req.json().catch(() => ({} as any));
  return run(payload, opts.buildDeps());
}

// deno-lint-ignore no-explicit-any
export async function run(payload: any, deps: IntakeDeps): Promise<Response> {
  const handler = String(payload?.handler ?? "").trim().toLowerCase() as HandlerName;
  if (!HANDLER_NAMES.includes(handler)) return json({ success: false, error: `handler must be one of ${HANDLER_NAMES.join(", ")}` }, 400);
  if (handler === "restore") return runRestore(payload, deps);
  const medium = String(payload?.medium ?? "").trim().toLowerCase();
  if (medium !== "anime" && medium !== "manga") return json({ success: false, error: "medium must be 'anime' or 'manga'" }, 400);
  const allowed = MEDIA_FOR[handler];
  if (allowed && !allowed.includes(medium)) return json({ success: false, error: `${handler} serves ${allowed.join(", ")} only` }, 400);
  const impl = HANDLERS[handler];
  if (!impl) return json({ success: false, error: `handler '${handler}' is not available yet` }, 501);

  const now = deps.now ?? Date.now;
  // MangaUpdates never overlaps release-intake's manga run (03:50 UTC): the cron expressions skip 03:30-04:20 and
  // this guard backs them up for a manual or late-fired call. No lock, no run row, no request.
  if (handler === "mangaupdates" && inMangaUpdatesQuietWindow(now())) {
    return json({ success: true, skipped: true, reason: "release_intake_window" });
  }
  const supabase = deps.supabase;
  const startedMs = now();
  const deadlineMs = startedMs + clampInt(payload?.timeBudgetMs, 50_000, 5_000, 140_000);
  const lockKey = `catalogue-intake:${handler}`;
  const runId = await startImportRun(supabase, medium.toUpperCase(), `catalogue_intake_${handler}`, payload);

  const lock = await acquireImportLock(supabase, lockKey, 900);
  if (lock.status !== "acquired") {
    const unavailable = lock.status === "unavailable";
    const message = unavailable ? lock.reason : "locked";
    await finishImportRun(supabase, runId, unavailable ? "error" : "skipped", {}, message, startedMs);
    return json(
      unavailable
        ? { success: false, skipped: true, reason: "lock_unavailable", error: message }
        : { success: true, skipped: true, reason: "locked" },
      unavailable ? 500 : 200,
    );
  }

  try {
    const outcome = await impl({
      supabase,
      clients: deps.clients,
      medium,
      limit: payload?.limit === undefined ? undefined : Number(payload.limit),
      deadlineMs,
      now,
    });
    await finishImportRun(supabase, runId, "success", outcome.results, outcome.stoppedEarly ? `stopped_early:${outcome.stoppedEarly}` : null, startedMs);
    return json({ success: true, handler, medium, results: outcome.results, ...(outcome.stoppedEarly ? { stoppedEarly: outcome.stoppedEarly } : {}) });
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    await finishImportRun(supabase, runId, "error", {}, message, startedMs);
    return json({ success: false, handler, medium, error: message }, 500);
  } finally {
    await releaseImportLock(supabase, lockKey);
  }
}

/** Rollback of one group (both media). Same lock family and bookkeeping as the other handlers; restore.ts records its own import_runs row with the duration. */
// deno-lint-ignore no-explicit-any
async function runRestore(payload: any, deps: IntakeDeps): Promise<Response> {
  const group = String(payload?.group ?? "").trim().toLowerCase() as FieldGroup;
  const lockKey = "catalogue-intake:restore";
  const lock = await acquireImportLock(deps.supabase, lockKey, 900);
  if (lock.status !== "acquired") {
    return lock.status === "unavailable"
      ? json({ success: false, skipped: true, reason: "lock_unavailable", error: lock.reason }, 500)
      : json({ success: true, skipped: true, reason: "locked" });
  }
  try {
    const r = await restore({ supabase: deps.supabase, now: deps.now }, group);
    return json({ success: true, handler: "restore", results: r });
  } catch (e) {
    return json({ success: false, handler: "restore", error: e instanceof Error ? e.message : String(e) }, 500);
  } finally {
    await releaseImportLock(deps.supabase, lockKey);
  }
}
