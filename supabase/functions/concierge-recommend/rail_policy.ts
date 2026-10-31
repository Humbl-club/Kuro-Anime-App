// Rail selection policy of concierge-recommend (F51, 2026-10-05): pure functions moved from the former
// ~1,300-line `serve` closure of index.ts with their logic unchanged; values the closure captured
// (quality floor, constraints, media type, user top genres, mode table) are now parameters. No I/O:
// handler.ts runs the reads through catalog_repository.ts and calls these rules.
//
//   - item building:      buildItemsFromRows (quality/format/year/episode gates, genre preference tiers,
//                         top-genre diversification, classic boost), compileQuality, curated-row mapping,
//                         constraint post-filter, alternating ANIME/MANGA merge;
//   - secondary ranking:  rankSecondaryCandidates (mode score minus genre/family/top-genre overlap,
//                         classics only on explicit intent) and decisionFromRanking (the router decision);
//   - secondary choice:   railTotals, preferredSecondaryIds, evaluateSecondary, chooseSecondary
//                         (acceptable > score > overlap > size > priority; classics guardrail; stable
//                         rotation within a close band keyed by the normalized prompt).
// Response field names and rail/mode ids are unchanged.
import {
  type ConciergeMode,
  isClassicIntent,
  type MediaType,
  safeStringArray,
  scoreMode,
  uniq,
  type UserConstraints,
} from "./router.ts";

export type ModePick = { id: string; title: string; confidence: number; reason: string };

export type CandidateRow = { media_id: number; match_count?: number | null; score?: number | null };

// deno-lint-ignore no-explicit-any
type Media = any;
// deno-lint-ignore no-explicit-any
export type RailItem = any;

export type MediaContext = {
  byId: Map<number, Media>;
  boostById: Map<number, Media>;
  boostedReasonsById: Map<number, string[]>;
};

export function emptyMediaContext(): MediaContext {
  return { byId: new Map(), boostById: new Map(), boostedReasonsById: new Map() };
}

export type QualityFloor = { minScore: number; minPopularity: number; excludeFormats: Set<string> };
export type CompiledQuality = { minScore: number; minPopularity: number; maxPopularity: number | null; excludeFormats: Set<string> };

export type RouterDecision = {
  primaryId: string;
  secondaryId: string;
  secondaryCandidates: string[];
  primaryConfidence: number;
  primaryReason: string;
  usedLLM: boolean;
  topScore: number;
};

export type BuiltRail = { title: string; items: RailItem[] };

export function stableBucket(input: string): number {
  // djb2-style deterministic hash, then map into [0, 99].
  let hash = 5381;
  for (let i = 0; i < input.length; i++) {
    hash = ((hash << 5) + hash) + input.charCodeAt(i);
    hash |= 0;
  }
  return Math.abs(hash) % 100;
}

export function mergeAlternating<T>(a: T[], b: T[], max: number): T[] {
  const out: T[] = [];
  let i = 0;
  while (out.length < max && (i < a.length || i < b.length)) {
    if (i < a.length) out.push(a[i]);
    if (out.length >= max) break;
    if (i < b.length) out.push(b[i]);
    i++;
  }
  return out;
}

/** Per-medium share of a rail: half (min 3) when both media are shown. */
export function perTypeLimit(mediaType: MediaType | "BOTH", total: number): number {
  return mediaType === "BOTH" ? Math.max(3, Math.ceil(total / 2)) : total;
}

/** The two media lists of a rail merged: alternating for BOTH, else concatenated, capped at `total`. */
export function mergeRail(mediaType: MediaType | "BOTH", a: RailItem[], m: RailItem[], total: number): RailItem[] {
  return mediaType === "BOTH" ? mergeAlternating(a, m, total) : [...a, ...m].slice(0, total);
}

export function compileQuality(quality: QualityFloor, mode: ConciergeMode | null): CompiledQuality {
  const minScore = Math.max(quality.minScore, Number(mode?.min_score ?? 0) || 0);
  const minPopularity = Math.max(quality.minPopularity, Number(mode?.min_popularity ?? 0) || 0);
  const maxPopularityRaw = mode?.max_popularity;
  const maxPopularity = Number.isFinite(Number(maxPopularityRaw)) ? Number(maxPopularityRaw) : null;
  const excludeFormats = new Set<string>(Array.from(quality.excludeFormats));
  for (const f of safeStringArray(mode?.exclude_formats)) {
    excludeFormats.add(String(f).toUpperCase());
  }
  return { minScore, minPopularity, maxPopularity, excludeFormats };
}

export function buildItemsFromRows(mt: MediaType, rows: CandidateRow[], ctx: MediaContext, opts: {
  limit: number;
  requiredGenres: string[];
  excludeGenres: string[];
  avoidGenres?: string[];
  classicYearMax?: number;
  quality: CompiledQuality;
  prioritizeClassicBoost?: boolean;
  constraints?: UserConstraints;
}): RailItem[] {
  const hasGenres = (m: Media, required: string[]) => {
    if (!required.length) return true;
    const gs = Array.isArray(m?.genres) ? m.genres.map((x: unknown) => String(x)) : [];
    if (!gs.length) return false;
    // Require at least one requested genre to match.
    return required.some((g) => gs.includes(g));
  };

  const hasExcludedGenres = (m: Media, excluded: string[]) => {
    if (!excluded.length) return false;
    const gs = Array.isArray(m?.genres) ? m.genres.map((x: unknown) => String(x)) : [];
    if (!gs.length) return false;
    return excluded.some((g) => gs.includes(g));
  };

  const uc = opts.constraints;

  const passes = (m: Media) => {
    if (!m) return false;
    if (m.is_adult === true) return false;
    const fmt = String(m.format ?? "").toUpperCase();

    // Format constraint: if user wants MOVIE, only allow MOVIE format.
    if (uc?.format === "MOVIE" && fmt !== "MOVIE") return false;
    // Short-form: allow ONA, OVA, SPECIAL only.
    if (uc?.format === "SHORT_FORM" && !["ONA", "OVA", "SPECIAL"].includes(fmt)) return false;
    if (uc?.format === "OVA" && fmt !== "OVA") return false;
    if (uc?.format === "ONA" && fmt !== "ONA") return false;

    // Default format exclusions (unless overridden by constraint).
    if (!uc?.format && opts.quality.excludeFormats.has(fmt)) return false;
    if (hasExcludedGenres(m, opts.excludeGenres)) return false;

    const year = Number(m.start_date_year ?? 0);
    if (opts.classicYearMax && year > 0 && year > opts.classicYearMax) return false;
    // Year constraints from user.
    if (uc?.year_min != null && year > 0 && year < uc.year_min) return false;
    if (uc?.year_max != null && year > 0 && year > uc.year_max) return false;

    const score = Number(m.average_score ?? 0);
    const pop = Number(m.popularity ?? 0);
    if (opts.quality.minScore > 0 && score > 0 && score < opts.quality.minScore) return false;
    if (opts.quality.minPopularity > 0 && pop > 0 && pop < opts.quality.minPopularity) return false;
    if (opts.quality.maxPopularity != null && pop > 0 && pop > opts.quality.maxPopularity) return false;

    // Episode count constraints (anime only; manga uses chapters).
    if (mt === "ANIME") {
      const eps = Number(m.episodes ?? 0);
      if (uc?.max_episodes != null && eps > 0 && eps > uc.max_episodes) return false;
      if (uc?.min_episodes != null && eps > 0 && eps < uc.min_episodes) return false;
    }

    return true;
  };

  const avoid = Array.isArray(opts.avoidGenres) ? opts.avoidGenres.map((g) => String(g)).filter(Boolean) : [];
  const shouldDiversify = avoid.length > 0 && opts.requiredGenres.length === 0;

  const overlapCount = (m: Media): number => {
    if (!shouldDiversify) return 0;
    const gs = Array.isArray(m?.genres) ? m.genres.map((x: unknown) => String(x)) : [];
    if (!gs.length) return 0;
    let n = 0;
    for (const g of avoid) {
      if (gs.includes(g)) n++;
    }
    return n;
  };

  const stableDiversify = (arr: CandidateRow[]): CandidateRow[] => {
    if (!shouldDiversify || arr.length <= 1) return arr;
    return arr
      .map((r, idx) => ({ r, idx }))
      .sort((a, b) => {
        const ma = ctx.byId.get(a.r.media_id);
        const mb = ctx.byId.get(b.r.media_id);
        const oa = overlapCount(ma);
        const ob = overlapCount(mb);
        if (oa !== ob) return oa - ob; // prefer less overlap with top genres
        return a.idx - b.idx; // stable tie-break
      })
      .map((x) => x.r);
  };

  // Prefer: genre match + quality; then quality; then anything (no hard failures).
  let primary: CandidateRow[] = [];
  let secondary: CandidateRow[] = [];
  let tertiary: CandidateRow[] = [];

  for (const r of rows) {
    const m = ctx.byId.get(r.media_id);
    if (!m) continue;
    if (passes(m) && hasGenres(m, opts.requiredGenres)) primary.push(r);
    else if (passes(m)) secondary.push(r);
    else tertiary.push(r);
  }

  primary = stableDiversify(primary);
  secondary = stableDiversify(secondary);
  tertiary = stableDiversify(tertiary);

  let ordered = [...primary, ...secondary, ...tertiary];
  if (opts.prioritizeClassicBoost) {
    const boosted: CandidateRow[] = [];
    const rest: CandidateRow[] = [];
    for (const r of ordered) {
      const b = ctx.boostById.get(r.media_id);
      if (b?.label === "classic") boosted.push(r);
      else rest.push(r);
    }
    ordered = [...boosted, ...rest];
  }
  ordered = ordered.slice(0, opts.limit);

  const out: RailItem[] = [];
  for (const r of ordered) {
    const m = ctx.byId.get(r.media_id);
    if (!m) continue;
    const signals: string[] = [];
    const b = ctx.boostById.get(r.media_id);
    if (b?.label === "classic") signals.push("CLASSIC");
    const reasons = ctx.boostedReasonsById.get(r.media_id) ?? [];
    for (const x of reasons.slice(0, 3)) signals.push(String(x).toUpperCase());
    if ((r.match_count ?? 0) >= 2) signals.push("MATCH");

    out.push({
      mediaType: mt,
      mediaId: r.media_id,
      matchCount: r.match_count ?? 0,
      score: r.score ?? null,
      title: m.title_english ?? m.title_romaji ?? m.title_native ?? "Unknown",
      coverImageMedium: m.cover_image_medium ?? null,
      averageScore: m.average_score ?? null,
      year: m.start_date_year ?? null,
      format: m.format ?? null,
      status: m.status ?? null,
      siteUrl: m.site_url ?? null,
      signals,
      genres: Array.isArray(m.genres) ? m.genres : null,
    });
  }
  return out;
}

// deno-lint-ignore no-explicit-any
export function mapCuratedRowToItem(row: any): RailItem {
  const mt = String(row?.media_type ?? row?.mediaType ?? "").toUpperCase();
  const mediaTypeOut = mt === "MANGA" ? "MANGA" : "ANIME";
  const mediaId = Number(row?.media_id ?? row?.mediaId ?? 0);
  const title = row?.title_english ?? row?.title_romaji ?? row?.title_native ?? "Unknown";
  return {
    mediaType: mediaTypeOut,
    mediaId,
    matchCount: null,
    score: null,
    title,
    coverImageMedium: row?.cover_image_medium ?? row?.coverImageMedium ?? null,
    averageScore: row?.average_score ?? row?.averageScore ?? null,
    year: row?.year ?? null,
    format: row?.format ?? null,
    status: row?.status ?? null,
    siteUrl: row?.site_url ?? row?.siteUrl ?? null,
    signals: Array.isArray(row?.signals) ? row.signals : [],
    genres: Array.isArray(row?.genres) ? row.genres : null,
  };
}

export function railIdFor(mode: ConciergeMode | null, mt: MediaType): string | null {
  if (!mode?.rail_id) return null;
  if (typeof mode.rail_id === "string") return mode.rail_id;
  const both = mode.rail_id.both;
  if (both) return both;
  return mt === "ANIME" ? (mode.rail_id.anime ?? null) : (mode.rail_id.manga ?? null);
}

/** Post-filter of curated rail cards by the prompt's constraints (genre exclusion, format, years). */
export function filterByConstraints(items: RailItem[], constraints: UserConstraints): RailItem[] {
  const userExcludedGenres = constraints.excluded_genres;
  return items.filter((it) => {
    // Genre exclusion.
    if (userExcludedGenres.length) {
      const gs = Array.isArray(it.genres) ? it.genres.map((g: unknown) => String(g)) : [];
      if (userExcludedGenres.some((eg) => gs.includes(eg))) return false;
    }
    // Format constraint.
    const fmt = String(it.format ?? "").toUpperCase();
    if (constraints.format === "MOVIE" && fmt !== "MOVIE") return false;
    if (constraints.format === "SHORT_FORM" && !["ONA", "OVA", "SPECIAL"].includes(fmt)) return false;
    if (constraints.format === "OVA" && fmt !== "OVA") return false;
    if (constraints.format === "ONA" && fmt !== "ONA") return false;
    // Year constraints.
    const year = Number(it.year ?? 0);
    if (constraints.year_min != null && year > 0 && year < constraints.year_min) return false;
    if (constraints.year_max != null && year > 0 && year > constraints.year_max) return false;
    return true;
  });
}

/** Stable reorder of curated items: less overlap with the user's top genres first. */
export function diversifyItems(arr: RailItem[], avoidGenres: string[]): RailItem[] {
  if (!Array.isArray(arr) || arr.length <= 1) return arr;
  if (!avoidGenres.length) return arr;
  const overlap = (it: RailItem) => {
    const gs = Array.isArray(it?.genres) ? it.genres.map((g: unknown) => String(g)) : [];
    if (!gs.length) return 0;
    let n = 0;
    for (const g of avoidGenres) if (gs.includes(g)) n++;
    return n;
  };
  return arr
    .map((it, idx) => ({ it, idx }))
    .sort((a, b) => {
      const oa = overlap(a.it);
      const ob = overlap(b.it);
      if (oa !== ob) return oa - ob;
      return a.idx - b.idx;
    })
    .map((x) => x.it);
}

/** Curated cards are over-fetched by 20 when a constraint post-filter may drop some. */
export function curatedFetchLimit(total: number, constraints: UserConstraints): number {
  const hasActiveConstraints = constraints.excluded_genres.length > 0 || constraints.format != null || constraints.year_min != null ||
    constraints.year_max != null;
  return hasActiveConstraints ? total + 20 : total;
}

export function modeFamily(modeId: string): string {
  if (modeId.startsWith("premium_")) return "premium";
  if (modeId.startsWith("classics")) return "classics";
  if (modeId === "romcom" || modeId.startsWith("romance_")) return "romance";
  if (modeId === "similar_to_seed") return "seed";
  return modeId.split("_")[0] ?? modeId;
}

function arrayOverlapCount(a: string[], b: string[]): number {
  if (!a.length || !b.length) return 0;
  const right = new Set(b.map((x) => x.toLowerCase()));
  let n = 0;
  for (const item of a) if (right.has(item.toLowerCase())) n++;
  return n;
}

export type SecondaryRankingInput = {
  text: string;
  primaryId: string;
  modeById: Map<string, ConciergeMode>;
  classicsId: string;
  requiredGenres: string[];
  userExcludedGenres: string[];
  constraints: UserConstraints;
  /** The caller's top list genres (user_lists), most frequent first. */
  topGenres: string[];
};

/** Every mode except the primary and similar_to_seed, best secondary candidate first. */
export function rankSecondaryCandidates(input: SecondaryRankingInput): Array<{ id: string; score: number; reason: string }> {
  const { text, primaryId, modeById, classicsId, requiredGenres, userExcludedGenres, constraints, topGenres } = input;
  const primary = modeById.get(primaryId) ?? null;
  const primaryReq = safeStringArray(primary?.required_genres);
  const wantsClassic = isClassicIntent(text);

  const all = Array.from(modeById.values())
    .filter((m) => m.id !== primaryId && m.id !== "similar_to_seed")
    .map((m) => {
      const s = scoreMode(text, m, requiredGenres, userExcludedGenres, constraints);
      let score = s.score;
      const reasons: string[] = [];

      const req = safeStringArray(m.required_genres);
      const genreOverlap = arrayOverlapCount(primaryReq, req);
      if (genreOverlap > 0) {
        score -= Math.min(4, genreOverlap * 1.6);
        reasons.push("genre-overlap");
      }

      if (modeFamily(primaryId) === modeFamily(m.id)) {
        score -= 2.2;
        reasons.push("same-family");
      }

      // Keep classics available, but no longer hardwire it as the default second rail.
      if (m.id === classicsId) {
        if (wantsClassic) {
          score += 2.5;
          reasons.push("explicit-classic");
        } else {
          score -= 3.2;
          reasons.push("avoid-default-classic");
        }
      }

      // Prefer less saturated taste pockets for secondary rails.
      const topGenreOverlap = arrayOverlapCount(req, topGenres);
      if (topGenreOverlap > 0) {
        score -= Math.min(3, topGenreOverlap * 1.1);
        reasons.push("top-genre-overlap");
      }

      // Slightly prefer curated rails (when quality is present) to keep selection deterministic.
      if (m.rail_id) {
        score += 0.4;
      }

      return {
        id: m.id,
        score,
        reason: reasons.length > 0 ? reasons.join(",") : (s.reason || "scored"),
      };
    })
    .sort((a, b) => b.score - a.score);

  return all;
}

/** The router decision for a primary route: best-ranked secondary, else premium (or classics). */
export function decisionFromRanking(
  route: { primaryId: string; primaryConfidence: number; primaryReason: string; usedLLM: boolean; topScore: number },
  ranked: Array<{ id: string }>,
  anchors: { classicsId: string; premiumId: string | undefined },
): RouterDecision {
  const { primaryId } = route;
  const fallbackSecondary = primaryId === anchors.classicsId
    ? (anchors.premiumId ?? "premium_picks")
    : (anchors.premiumId ?? anchors.classicsId);
  const secondaryId = ranked[0]?.id ?? fallbackSecondary;
  return {
    primaryId,
    secondaryId,
    secondaryCandidates: uniq([secondaryId, ...ranked.map((r) => r.id)]).slice(0, 8),
    primaryConfidence: route.primaryConfidence,
    primaryReason: route.primaryReason,
    usedLLM: route.usedLLM,
    topScore: route.topScore,
  };
}

export function mkPick(id: string, title: string, confidence: number, reason: string): ModePick {
  return {
    id,
    title,
    confidence: Math.max(0, Math.min(1, confidence)),
    reason,
  };
}

/** Exactly 2 rails: primary + diversified secondary (no hard classics anchor). */
export function railTotals(limit: number): { primaryTotal: number; secondaryTotal: number; minSecondaryItems: number } {
  const primaryTotal = limit;
  const secondaryTotal = Math.max(10, Math.min(16, limit + 2));
  const minSecondaryItems = Math.max(8, Math.min(secondaryTotal, 12));
  return { primaryTotal, secondaryTotal, minSecondaryItems };
}

/** Secondary modes built and compared (at most 5): the decision's candidates, premium, classics on intent. */
export function preferredSecondaryIds(
  decision: RouterDecision,
  anchors: { classicsId: string; premiumId: string | undefined },
  explicitClassicIntent: boolean,
): string[] {
  return uniq([
    decision.secondaryId,
    ...decision.secondaryCandidates,
    anchors.premiumId ?? "premium_picks",
    ...(explicitClassicIntent ? [anchors.classicsId] : []),
  ])
    .filter((id) => !!id && id !== decision.primaryId)
    .slice(0, 5);
}

export type SecondaryEvaluation = { score: number; acceptable: boolean; overlapRatio: number; overlapCount: number };
export type SecondaryCandidateEvaluation = { modeId: string; built: BuiltRail; eval: SecondaryEvaluation };

export type SecondaryContext = {
  primaryId: string;
  primaryItemKeys: Set<string>;
  /** Higher = earlier in preferredSecondaryIds. */
  secondaryPriority: Map<string, number>;
  secondaryTotal: number;
  minSecondaryItems: number;
  classicsId: string;
  explicitClassicIntent: boolean;
};

export function secondaryContext(
  primaryId: string,
  primaryItems: RailItem[],
  preferred: string[],
  totals: { secondaryTotal: number; minSecondaryItems: number },
  classicsId: string,
  explicitClassicIntent: boolean,
): SecondaryContext {
  const secondaryPriority = new Map<string, number>();
  preferred.forEach((id, idx) => secondaryPriority.set(id, preferred.length - idx));
  return {
    primaryId,
    primaryItemKeys: new Set(primaryItems.map((it: RailItem) => `${it.mediaType}|${it.mediaId}`)),
    secondaryPriority,
    secondaryTotal: totals.secondaryTotal,
    minSecondaryItems: totals.minSecondaryItems,
    classicsId,
    explicitClassicIntent,
  };
}

export function evaluateSecondary(modeId: string, built: BuiltRail, ctx: SecondaryContext): SecondaryEvaluation {
  const itemKeys = built.items.map((it: RailItem) => `${it.mediaType}|${it.mediaId}`);
  const overlapCount = itemKeys.filter((k) => ctx.primaryItemKeys.has(k)).length;
  const overlapRatio = built.items.length > 0 ? overlapCount / built.items.length : 1;
  const itemCoverage = Math.min(1, built.items.length / Math.max(1, ctx.secondaryTotal));
  let score = 0;
  score += (ctx.secondaryPriority.get(modeId) ?? 0) * 1.1;
  score += itemCoverage * 2.0;
  score -= overlapRatio * 5.0;
  if (built.items.length < ctx.minSecondaryItems) score -= 2.8;
  if (modeId === ctx.classicsId && !ctx.explicitClassicIntent) score -= 3.2;
  if (modeFamily(modeId) === modeFamily(ctx.primaryId)) score -= 1.2;
  const acceptable = built.items.length >= ctx.minSecondaryItems && overlapRatio <= 0.45;
  return {
    score,
    acceptable,
    overlapRatio,
    overlapCount,
  };
}

/** A candidate whose build threw: never preferred. */
export function failedSecondary(modeId: string): SecondaryCandidateEvaluation {
  return {
    modeId,
    built: { title: modeId, items: [] },
    eval: { score: Number.NEGATIVE_INFINITY, acceptable: false, overlapRatio: 1, overlapCount: 0 },
  };
}

/**
 * The secondary rail among the built candidates (the caller passes the fallback build when there is
 * no candidate, F73): acceptable first, then score, lower overlap, more items, earlier preference;
 * then the classics guardrail and the deterministic rotation within the close band (keyed by
 * `promptNorm`). With a single candidate the guardrail and rotation cannot change the choice.
 */
export function chooseSecondary(
  candidates: SecondaryCandidateEvaluation[],
  ctx: SecondaryContext,
  promptNorm: string,
): SecondaryCandidateEvaluation {
  const chooseBetterSecondary = (a: SecondaryCandidateEvaluation, b: SecondaryCandidateEvaluation) => {
    if (a.eval.acceptable !== b.eval.acceptable) {
      return a.eval.acceptable ? -1 : 1;
    }
    if (a.eval.score !== b.eval.score) {
      return b.eval.score - a.eval.score;
    }
    if (a.eval.overlapRatio !== b.eval.overlapRatio) {
      return a.eval.overlapRatio - b.eval.overlapRatio;
    }
    if (a.built.items.length !== b.built.items.length) {
      return b.built.items.length - a.built.items.length;
    }
    const ap = ctx.secondaryPriority.get(a.modeId) ?? 0;
    const bp = ctx.secondaryPriority.get(b.modeId) ?? 0;
    return bp - ap;
  };

  const sortedSecondaryCandidates = candidates
    .slice()
    .sort(chooseBetterSecondary);

  let chosenSecondary = sortedSecondaryCandidates[0];
  if (!chosenSecondary) throw new Error("no secondary rail candidate");

  // Guardrail: if classics wins by default, prefer a close non-classics candidate
  // unless the user explicitly asked for classics.
  if (!ctx.explicitClassicIntent && chosenSecondary.modeId === ctx.classicsId) {
    const bestNonClassic = sortedSecondaryCandidates.find((c) => c.modeId !== ctx.classicsId && c.eval.acceptable);
    if (bestNonClassic && bestNonClassic.eval.score >= (chosenSecondary.eval.score - 0.9)) {
      chosenSecondary = bestNonClassic;
    }
  }

  // Diversity stabilizer: rotate within the top close alternatives so the second rail
  // does not collapse into the same mode for broad prompts.
  if (!ctx.explicitClassicIntent) {
    const nonClassicAcceptable = sortedSecondaryCandidates.filter((c) => c.modeId !== ctx.classicsId && c.eval.acceptable);
    if (nonClassicAcceptable.length >= 2) {
      const topScore = nonClassicAcceptable[0].eval.score;
      const closeBand = nonClassicAcceptable
        .filter((c) => (topScore - c.eval.score) <= 0.8)
        .slice(0, 3);
      if (closeBand.length >= 2) {
        const pickIndex = stableBucket(`${promptNorm}|${ctx.primaryId}|secondary`) % closeBand.length;
        chosenSecondary = closeBand[pickIndex];
      }
    }
  }

  return chosenSecondary;
}
