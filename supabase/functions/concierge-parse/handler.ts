/**
 * Request handling and the per-line run of `concierge-parse` (F51, 2026-10-05), separated from index.ts
 * so the production flow runs against an injected Supabase-shaped client in Deno tests.
 *
 * Contract (unchanged unless marked):
 *   POST only (405); `?warmup=true` answers `{ ok: true }` before any auth/limiter work. Body
 *   `{ text (<= 5000 chars, else 400), scope?: "anime"|"manga"|"both", limitPerItem?: 3..15 (default 10, also for a non-finite value, F76),
 *   clarification?: {kind: answer} }`. No parsed lines -> `{ success: true, items: [] }` without a limiter
 *   call. Response `{ success: true, userId, items: [{ raw, normalized, parsed{...}, ambiguity, candidates,
 *   candidateError, aliasNorm, existing_entry }] }`; one line's failure never aborts the others.
 *   CHANGED (F32): the rate limiter (`check_concierge_rate_limit`, kind `parse`) is a required gate read
 *   through _shared/rate_limit_gate.ts: denial 429 + Retry-After; an error, missing or unrecognised
 *   result (or a rejected limiter call) 503 + Retry-After, with no search/alias/list work. A rejected
 *   auth.getUser() is not caught (500, as before): it must not degrade a signed-in caller to anonymous.
 *   CHANGED (F31): the alias lookup reads `aliasLookupKeys(raw)` (strong key, then the legacy Apply key).
 * Anonymous callers (public parse, explicit contract): identity only from `auth.getUser()`, never the
 *   body. Without a verified user the run does no user-scoped read or write (no title_aliases, list
 *   tables, parse feedback or run log); `userId` and `aliasNorm` are null; the limiter keys on the IP.
 * No remote imports here (index.ts owns supabase-js and env).
 */
import { aliasLookupKeys, normalizeAliasKey } from "../_shared/alias_normalization.ts";
import { interpretRateLimit, rateLimitBlockedResponse } from "../_shared/rate_limit_gate.ts";
import { type ExistingEntry, type ParseRepository, type SupabaseLike, supabaseParseRepository } from "./parse_repository.ts";
import { type ParsedItem, parseClarificationMap, parseLine, splitItems } from "./rules.ts";
import {
  type AliasTarget,
  type Candidate,
  existingEntryTarget,
  feedbackLogFor,
  feedbackSettings,
  lineMediaType,
  mergeCandidate,
  planDenoisedQueries,
  planInitialQueries,
  rankCandidates,
  scoreDenoisedRow,
  scoreInitialRow,
  searchLimit,
} from "./search_plan.ts";

export interface ParsePlatform {
  /** Client for this caller, or null when SUPABASE_URL / an API key env var is missing. */
  client(authHeader: string): SupabaseLike | null;
}

function json(res: unknown, init: ResponseInit = {}) {
  return new Response(JSON.stringify(res), {
    ...init,
    headers: { "Content-Type": "application/json", ...(init.headers ?? {}) },
  });
}

function clientIp(req: Request): string | null {
  const xf = req.headers.get("x-forwarded-for");
  if (xf) {
    const first = xf.split(",")[0]?.trim();
    if (first) return first;
  }
  const real = req.headers.get("x-real-ip")?.trim();
  if (real) return real;
  const cf = req.headers.get("cf-connecting-ip")?.trim();
  if (cf) return cf;
  return null;
}

/** The response's `parsed` block for a line. */
function projectParsed(item: ParsedItem) {
  return {
    mediaTypeHint: item.mediaTypeHint ?? null,
    status: item.status ?? null,
    progressEpisodes: item.progressEpisodes ?? null,
    progressChapters: item.progressChapters ?? null,
    progressVolumes: item.progressVolumes ?? null,
    progressTotal: item.progressTotal ?? null,
    progressUnit: item.progressUnit ?? null,
    seasonNumber: item.seasonNumber ?? null,
    episodeInSeason: item.episodeInSeason ?? null,
    caughtUp: item.caughtUp ?? null,
    lastEpisode: item.lastEpisode ?? null,
    completed: item.completed ?? null,
    yearMention: item.yearMention ?? null,
    rating: item.rating ?? null,
  };
}

type LineContext = {
  repo: ParseRepository;
  userId: string | null;
  scope: unknown;
  limitPerItem: number;
  feedback: { enabled: boolean; lowScore: number };
};

/** One parsed line: alias lookup, title search (+ denoised pass), feedback, existing-entry read. */
async function runLine(item: ParsedItem, ctx: LineContext) {
  const { repo, userId, limitPerItem } = ctx;
  try {
    const mediaType = lineMediaType(ctx.scope, item);

    let aliasTarget: AliasTarget | null = null;
    if (userId && item.normalized) {
      const keys = aliasLookupKeys(item.raw);
      if (keys.length > 0) aliasTarget = await repo.findAlias(userId, keys, mediaType ?? null);
    }

    const merged = new Map<string, Candidate>();
    let candidateError: string | null = null;
    const limit = searchLimit(limitPerItem);

    // All initial search queries for this line run in parallel.
    const planned = planInitialQueries(item, mediaType);
    const initial = await Promise.all(planned.map((q) => repo.searchTitles(q.q, mediaType, limit)));
    initial.forEach((result, i) => {
      if (result.error) {
        candidateError = candidateError ?? result.error;
        return;
      }
      for (const c of result.rows) mergeCandidate(merged, c, scoreInitialRow(item, c, planned[i].seasonBoost, aliasTarget));
    });

    // Second pass: if confidence is low, try denoised keyword queries in parallel (errors ignored).
    const denoised = planDenoisedQueries(item, rankCandidates(merged, limitPerItem));
    if (denoised.length > 0) {
      const extra = await Promise.all(denoised.map((q) => repo.searchTitles(q, mediaType, limit)));
      for (const result of extra) {
        if (result.error) continue;
        for (const c of result.rows) mergeCandidate(merged, c, scoreDenoisedRow(item, c));
      }
    }

    const finalCandidates = rankCandidates(merged, limitPerItem);

    if (ctx.feedback.enabled) {
      const log = feedbackLogFor(finalCandidates, ctx.feedback.lowScore);
      if (log) {
        await repo.logParseFeedback({
          raw: item.raw,
          normalized: item.normalized,
          aliasNorm: normalizeAliasKey(item.raw),
          bestScore: log.bestScore,
          candidatesCount: finalCandidates.length,
          topMediaType: log.top?.media_type ?? null,
          topMediaId: log.top?.media_id ?? null,
        });
      }
    }

    // Import reconciliation: the caller's existing list entry for a confident top candidate.
    let existingEntry: ExistingEntry | null = null;
    const target = existingEntryTarget(finalCandidates);
    if (userId && target) {
      existingEntry = await repo.existingEntry(userId, target.media_type, Number(target.media_id));
    }

    return {
      raw: item.raw,
      normalized: item.normalized,
      parsed: projectParsed(item),
      ambiguity: item.ambiguity ?? null,
      candidates: finalCandidates,
      candidateError,
      aliasNorm: userId ? normalizeAliasKey(item.raw) : null,
      existing_entry: existingEntry,
    };
  } catch (err) {
    // Per-item error handling: don't let one item's failure abort others.
    return {
      raw: item.raw,
      normalized: item.normalized,
      parsed: projectParsed(item),
      ambiguity: item.ambiguity ?? null,
      candidates: [],
      candidateError: err instanceof Error ? err.message : "unknown error",
      aliasNorm: userId ? normalizeAliasKey(item.raw) : null,
      existing_entry: null,
    };
  }
}

export async function handleParse(req: Request, platform: ParsePlatform): Promise<Response> {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, { status: 405 });

  // Warmup: short-circuit before auth/rate-limit to warm the Deno isolate
  const url = new URL(req.url);
  if (url.searchParams.get("warmup") === "true") {
    return json({ ok: true });
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const client = platform.client(authHeader);
  if (!client) {
    return json({ error: "Missing SUPABASE_URL or a Supabase API key env (SUPABASE_ANON_KEY or SUPABASE_SERVICE_ROLE_KEY)" }, { status: 500 });
  }

  const body = await req.json().catch(() => ({}));
  const text: string = String(body?.text ?? "");
  if (typeof text !== "string" || text.length > 5000) {
    return json({ error: "Text too long (max 5000 chars)" }, { status: 400 });
  }
  const scope: "anime" | "manga" | "both" = body?.scope ?? "both";
  // F76: a limitPerItem that is not a finite number is the default 10 (before: NaN, no candidates).
  const limitPerItem = Number.isFinite(Number(body?.limitPerItem ?? 10)) ? Math.max(3, Math.min(15, Number(body?.limitPerItem ?? 10))) : 10;
  const clarification = parseClarificationMap(body?.clarification);

  const itemsRaw = splitItems(text);
  if (itemsRaw.length === 0) {
    return json({ success: true, items: [] });
  }

  // Rate-limit check and auth verification run in parallel (they are independent).
  const ip = clientIp(req);
  const [rlResult, userResult] = await Promise.all([
    Promise.resolve(
      client.rpc("check_concierge_rate_limit", {
        p_kind: "parse",
        p_ip: ip,
        p_window_seconds: null,
        p_max_user: null,
        p_max_ip: null,
      }),
    ).catch((error: unknown) => ({ data: null, error })),
    // Not caught: a rejected getUser() is an infrastructure failure for a caller who may hold a valid JWT;
    // it must not degrade to an anonymous parse (no existing_entry -> reconciler would "add" over a row).
    client.auth.getUser(),
  ]);

  const blocked = rateLimitBlockedResponse(interpretRateLimit(rlResult), json);
  if (blocked) return blocked;

  const userId: string | null = userResult?.data?.user?.id ?? null;
  const repo = supabaseParseRepository(client);

  // Optional: feedback logging threshold (single DB roundtrip per request, signed-in only).
  const feedback = userId ? feedbackSettings(await repo.feedbackConfig(), true) : { enabled: false, lowScore: 0.55 };

  const parsed: ParsedItem[] = itemsRaw.map((raw) => parseLine(raw, clarification));

  // Lines are independent (each searches a different title), so they run in parallel.
  const outItems = await Promise.all(parsed.map((item) => runLine(item, { repo, userId, scope, limitPerItem, feedback })));

  // Lightweight run logging (best-effort; table is RLS-deny by default for users).
  if (userId) await repo.logRun(text.length, outItems.length);

  return json({ success: true, userId, items: outItems });
}
