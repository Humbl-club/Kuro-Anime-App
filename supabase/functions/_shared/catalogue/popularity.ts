// Kuro popularity index (catalogue Task 10, spec section 3). Pure. Built only from inputs Kuro may
// use: Wikipedia pageviews, the vote counts of ANN / MangaUpdates, and Kuro's own list adds.
//
// The coefficients are STARTING VALUES. They were not calibrated: calibration against AniList's
// `popularity` needs gate L4(c), which is not granted (plan Task 10 Step 4 is skipped). The owner's
// Discover top-100 review decides whether they change.

/** Largest value a Postgres `integer` column holds. */
export const INT32_MAX = 2_147_483_647;

export const POPULARITY_COEFFICIENTS = { viewsPerMonth: 0.02, vote: 1, libraryAdd: 50 } as const;
/** Fewer combined ANN + MangaUpdates votes than this give no score. */
export const MIN_SCORE_VOTES = 20;

const finite = (n: number): number => (Number.isFinite(n) ? n : 0);

/** Non-negative integer that fits the column; NaN and negatives become 0, infinity and overflow clamp. */
function toColumn(n: number): number {
  if (Number.isNaN(n) || n <= 0) return 0;
  if (n >= INT32_MAX) return INT32_MAX;
  return Math.round(n);
}

/** `round(views12m/12 * 0.02 + votes * 1 + libraryAdds * 50)` on the scale of the `popularity` column. */
export function popularityIndex(input: { views12m: number; votes: number; libraryAdds: number }): number {
  const c = POPULARITY_COEFFICIENTS;
  const views = Math.max(0, finite(input.views12m));
  const votes = Math.max(0, finite(input.votes));
  const adds = Math.max(0, finite(input.libraryAdds));
  // An infinite input is treated as the column maximum rather than 0.
  const big = [input.views12m, input.votes, input.libraryAdds].some((v) => v === Number.POSITIVE_INFINITY);
  if (big) return INT32_MAX;
  return toColumn((views / 12) * c.viewsPerMonth + votes * c.vote + adds * c.libraryAdd);
}

/** Rise of the last 30 days over the 30 before, scaled down; never negative. */
export function trendingIndex(last30: number, prev30: number): number {
  return toColumn(Math.max(0, finite(last30) - finite(prev30)) / 100);
}

/** 0-100 vote-weighted blend of ANN (weighted, 0-10) and MangaUpdates (bayesian, 0-10); null below 20 combined votes. */
export function scoreIndex(ann?: { weighted: number; votes: number }, mu?: { bayesian: number; votes: number }): number | null {
  const parts = [ann ? { score: ann.weighted, votes: ann.votes } : null, mu ? { score: mu.bayesian, votes: mu.votes } : null]
    .filter((p): p is { score: number; votes: number } => p !== null && Number.isFinite(p.score) && Number.isFinite(p.votes) && p.votes > 0);
  const votes = parts.reduce((s, p) => s + p.votes, 0);
  if (votes < MIN_SCORE_VOTES) return null;
  const blended = parts.reduce((s, p) => s + p.score * 10 * p.votes, 0) / votes;
  return Math.min(100, Math.max(0, Math.round(blended)));
}
