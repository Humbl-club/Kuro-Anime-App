// Pure title-search policy of concierge-parse: which `search_titles` queries a parsed line issues and
// how the returned rows are scored, merged and ranked (moved verbatim from the former index.ts
// per-item closure, 2026-10-05, F51). No I/O: handler.ts runs the queries through the repository.
//
// Fan-out per line (unchanged): the normalized title, its abbreviation expansion (when different) and,
// for an anime season line, six season-suffixed queries; then, only when the best score is < 0.55 and
// the title has >= 8 chars, up to five denoised keyword queries. Each query asks for
// `searchLimit(limitPerItem)` rows; the merged result keeps the best score per (media_type, media_id).
import {
  buildDenoisedQueries,
  buildSeasonQueries,
  expandCommonAbbreviations,
  type MediaType,
  type ParsedItem,
  seasonMatchBoost,
  tokenOverlapBoost,
  variantPenalty,
} from "./rules.ts";

/** One `search_titles` row (other columns pass through to the response unchanged). */
export type SearchRow = {
  media_type: string;
  media_id: number;
  title_raw?: string | null;
  variant_type?: string | null;
  score?: number | null;
  year?: number | null;
  [column: string]: unknown;
};

/** A row with its adjusted score; this is the response's `candidates[]` element. */
export type Candidate = SearchRow & { score: number };

/** The caller's alias row for this line (from title_aliases), used only for the alias boost. */
export type AliasTarget = { media_type: string; media_id: number; title_raw?: string | null };

export type PlannedQuery = { q: string; seasonBoost: boolean };

/** Score below which a low-confidence line gets the denoised keyword pass. */
export const DENOISE_BELOW_SCORE = 0.55;
/** Minimum top score for the existing-entry read (import reconciliation). */
export const EXISTING_ENTRY_MIN_SCORE = 0.60;

/** The media type searched for a line: the request scope wins, else the line's own hint. */
export function lineMediaType(scope: unknown, item: ParsedItem): MediaType | null {
  return scope === "anime" ? "ANIME" : scope === "manga" ? "MANGA" : item.mediaTypeHint ?? null;
}

/** Rows asked per `search_titles` call. */
export function searchLimit(limitPerItem: number): number {
  return Math.max(5, Math.min(limitPerItem, 12));
}

export function planInitialQueries(item: ParsedItem, mediaType: MediaType | null): PlannedQuery[] {
  const queries: PlannedQuery[] = [{ q: item.normalized, seasonBoost: false }];
  const expanded = expandCommonAbbreviations(item.normalized);
  if (expanded && expanded !== item.normalized) {
    // Treat the expanded form as an alternate query; it tends to help new users on acronyms (AoT/JJK/etc).
    queries.push({ q: expanded, seasonBoost: false });
  }
  if (item.seasonNumber && item.normalized && (mediaType === "ANIME" || item.mediaTypeHint === "ANIME")) {
    for (const q of buildSeasonQueries(item.normalized, item.seasonNumber)) {
      queries.push({ q, seasonBoost: true });
    }
  }
  return queries;
}

/** Adjusted score of a row from an initial query (season, token overlap, alias, year boosts; variant penalty). */
export function scoreInitialRow(item: ParsedItem, c: SearchRow, seasonBoostQuery: boolean, aliasTarget: AliasTarget | null): number {
  const baseScore = typeof c.score === "number" ? c.score : 0;
  const seasonBoost = seasonBoostQuery && item.seasonNumber ? seasonMatchBoost(String(c.title_raw ?? ""), item.seasonNumber) : 0;
  const overlapBoost = tokenOverlapBoost(item.normalized, String(c.title_raw ?? ""));
  const penalty = variantPenalty(item.raw, { title_raw: c.title_raw ?? undefined, variant_type: c.variant_type ?? undefined });
  const aliasBoost =
    aliasTarget && aliasTarget.media_type === c.media_type && Number(aliasTarget.media_id) === Number(c.media_id) ? 0.80 : 0;
  const yearBoost = item.yearMention && typeof c.year === "number" && c.year === item.yearMention ? 0.25 : 0;
  // Allow a tiny score > 1 so "Season 2" variants can beat the base title when both match at 1.0.
  return Math.max(0, Math.min(1.25, baseScore + seasonBoost + overlapBoost + aliasBoost + yearBoost - penalty));
}

/** Adjusted score of a row from a denoised keyword query (token overlap and variant penalty only). */
export function scoreDenoisedRow(item: ParsedItem, c: SearchRow): number {
  const baseScore = typeof c.score === "number" ? c.score : 0;
  const penalty = variantPenalty(item.raw, { title_raw: c.title_raw ?? undefined, variant_type: c.variant_type ?? undefined });
  return Math.max(0, Math.min(1.25, baseScore + tokenOverlapBoost(item.normalized, String(c.title_raw ?? "")) - penalty));
}

/** Keeps the best adjusted score per (media_type, media_id); first-seen order is kept for ties. */
export function mergeCandidate(merged: Map<string, Candidate>, c: SearchRow, adjusted: number): void {
  const key = `${c.media_type}:${c.media_id}`;
  const existing = merged.get(key);
  if (!existing || (existing.score ?? 0) < adjusted) {
    merged.set(key, { ...c, score: adjusted });
  }
}

/** Best-first, at most `limitPerItem` candidates. */
export function rankCandidates(merged: Map<string, Candidate>, limitPerItem: number): Candidate[] {
  return Array.from(merged.values())
    .sort((a, b) => (b.score ?? 0) - (a.score ?? 0))
    .slice(0, limitPerItem);
}

/** Whether the low-confidence denoised keyword pass runs, and its queries. */
export function planDenoisedQueries(item: ParsedItem, ranked: Candidate[]): string[] {
  const bestScore = typeof ranked[0]?.score === "number" ? ranked[0].score : 0;
  if (bestScore < DENOISE_BELOW_SCORE && item.normalized.length >= 8) return buildDenoisedQueries(item.normalized);
  return [];
}

/** Low-confidence or no-match lines are logged for parser feedback (only those, to avoid latency). */
export function feedbackLogFor(ranked: Candidate[], lowScore: number): { bestScore: number | null; top: Candidate | null } | null {
  const top = ranked[0] ?? null;
  const bestScore = typeof top?.score === "number" ? top.score : null;
  if (bestScore == null || bestScore < lowScore || ranked.length === 0) return { bestScore, top };
  return null;
}

/** The candidate whose existing list entry is read for reconciliation, if confident enough. */
export function existingEntryTarget(ranked: Candidate[]): Candidate | null {
  const top = ranked[0] ?? null;
  const topScore = typeof top?.score === "number" ? top.score : 0;
  return top && topScore >= EXISTING_ENTRY_MIN_SCORE ? top : null;
}

/** The parse feedback config (`get_concierge_config().parse_feedback`), with the defaults it overrides. */
export function feedbackSettings(cfg: unknown, signedIn: boolean): { enabled: boolean; lowScore: number } {
  let enabled = signedIn;
  let lowScore = 0.55;
  // deno-lint-ignore no-explicit-any
  const c = cfg as any;
  const pf = c?.parse_feedback ?? c?.parseFeedback ?? null;
  if (pf && typeof pf === "object") {
    if (typeof pf.enabled === "boolean") enabled = pf.enabled;
    const v = Number(pf.low_confidence_score ?? pf.lowConfidenceScore ?? lowScore);
    if (Number.isFinite(v) && v >= 0 && v <= 1.5) lowScore = v;
  }
  return { enabled, lowScore };
}
