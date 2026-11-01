// Chapter cadence estimate (release certainty model D10: an estimate is shown only when
// confidence >= 0.7, as "expected around", never as a countdown).
//
// Rules (all must hold, otherwise no estimate):
//   - at least MIN_DATED_RELEASES distinct release DATES (several chapters on one day are one
//     release); the newest MAX_DATED_RELEASES dates are used;
//   - median interval between consecutive dates within [1, MAX_MEDIAN_DAYS] days;
//   - the last release is not older than STALE_FACTOR x the median (a series on break gets none);
//   - next = last date + median, and next must not already be past (no rolling a stale
//     estimate forward);
//   - confidence = clamp(1 - IQR / median) x (0.9 when fewer than 8 intervals), rounded to 2 dp;
//     a weekly series with one skipped week keeps IQR 0, an irregular one falls below 0.7.
// Pure: the clock is a parameter.

export const MIN_DATED_RELEASES = 6;
export const MAX_DATED_RELEASES = 10;
export const MIN_CONFIDENCE = 0.7;
export const MAX_MEDIAN_DAYS = 70;
export const STALE_FACTOR = 3;

const DAY_MS = 86_400_000;

export type DatedChapter = { number: number; date: string /* YYYY-MM-DD */ };

export type CadenceEstimate = {
  nextNumber: number;
  /** YYYY-MM-DD (day precision). */
  nextDate: string;
  medianDays: number;
  confidence: number;
  datesUsed: number;
};

export type CadenceRejection = { reason: "too_few_dates" | "irregular" | "stale" | "past" | "out_of_range" };

function dayIndex(date: string): number | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return null;
  const t = Date.parse(`${date}T00:00:00Z`);
  return Number.isFinite(t) ? Math.round(t / DAY_MS) : null;
}

function quantile(sorted: number[], q: number): number {
  if (sorted.length === 1) return sorted[0];
  const pos = (sorted.length - 1) * q;
  const lo = Math.floor(pos);
  const hi = Math.ceil(pos);
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo);
}

export function estimateNextChapter(chapters: DatedChapter[], nowMs: number): CadenceEstimate | CadenceRejection {
  const days = new Set<number>();
  let maxNumber = -Infinity;
  for (const c of chapters) {
    const d = dayIndex(c.date);
    if (d === null || !Number.isFinite(c.number)) continue;
    days.add(d);
    if (c.number > maxNumber) maxNumber = c.number;
  }
  const dates = [...days].sort((a, b) => b - a).slice(0, MAX_DATED_RELEASES);
  if (dates.length < MIN_DATED_RELEASES) return { reason: "too_few_dates" };

  const intervals: number[] = [];
  for (let i = 0; i < dates.length - 1; i++) intervals.push(dates[i] - dates[i + 1]);
  const sorted = [...intervals].sort((a, b) => a - b);
  const median = quantile(sorted, 0.5);
  if (median < 1 || median > MAX_MEDIAN_DAYS) return { reason: "out_of_range" };
  const iqr = quantile(sorted, 0.75) - quantile(sorted, 0.25);
  const base = Math.max(0, Math.min(1, 1 - iqr / median));
  const confidence = Math.round(base * (intervals.length >= 8 ? 1 : 0.9) * 100) / 100;
  if (confidence < MIN_CONFIDENCE) return { reason: "irregular" };

  const today = Math.floor(nowMs / DAY_MS);
  const last = dates[0];
  if (today - last > STALE_FACTOR * median) return { reason: "stale" };
  const next = last + Math.round(median);
  if (next < today) return { reason: "past" };

  return {
    nextNumber: Math.floor(maxNumber) + 1,
    nextDate: new Date(next * DAY_MS).toISOString().slice(0, 10),
    medianDays: median,
    confidence,
    datesUsed: dates.length,
  };
}

export function isEstimate(value: CadenceEstimate | CadenceRejection): value is CadenceEstimate {
  return (value as CadenceEstimate).nextDate !== undefined;
}
