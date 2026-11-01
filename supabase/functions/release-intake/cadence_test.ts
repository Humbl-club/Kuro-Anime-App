// Offline tests for the chapter cadence estimate. Pure; no network.
// Run: deno test --no-prompt supabase/functions/release-intake/cadence_test.ts
import { strict as assert } from "node:assert";
import { estimateNextChapter, isEstimate } from "./cadence.ts";

const NOW = Date.parse("2026-11-01T10:00:00Z");

function weekly(lastDate: string, count: number, startNumber: number, skipIndex: number | null = null) {
  const out = [];
  let t = Date.parse(`${lastDate}T00:00:00Z`);
  let n = startNumber;
  for (let i = 0; i < count; i++) {
    out.push({ number: n, date: new Date(t).toISOString().slice(0, 10) });
    n--;
    t -= (i === skipIndex ? 14 : 7) * 86_400_000;
  }
  return out;
}

Deno.test("a regular weekly series gets an estimate one week after the last release", () => {
  const e = estimateNextChapter(weekly("2026-10-25", 10, 1196), NOW);
  assert.ok(isEstimate(e));
  if (!isEstimate(e)) return;
  assert.equal(e.nextDate, "2026-11-01");
  assert.equal(e.nextNumber, 1197);
  assert.equal(e.medianDays, 7);
  assert.equal(e.confidence, 1);
});

Deno.test("one skipped week keeps the estimate (IQR stays 0)", () => {
  const e = estimateNextChapter(weekly("2026-10-25", 8, 1196, 2), NOW);
  assert.ok(isEstimate(e));
  if (isEstimate(e)) assert.ok(e.confidence >= 0.7);
});

Deno.test("fewer than 6 distinct release dates gives no estimate", () => {
  const e = estimateNextChapter(weekly("2026-10-25", 5, 100), NOW);
  assert.deepEqual(e, { reason: "too_few_dates" });
  // Several chapters on one day count as one release date.
  const sameDay = [1, 2, 3, 4, 5, 6, 7].map((n) => ({ number: n, date: "2026-10-25" }));
  assert.deepEqual(estimateNextChapter(sameDay, NOW), { reason: "too_few_dates" });
});

Deno.test("an irregular cadence is rejected below confidence 0.7", () => {
  const dates = ["2026-10-28", "2026-10-21", "2026-10-02", "2026-09-29", "2026-09-05", "2026-08-30", "2026-08-02"];
  const e = estimateNextChapter(dates.map((date, i) => ({ number: 50 - i, date })), NOW);
  assert.deepEqual(e, { reason: "irregular" });
});

Deno.test("a series on a long break (last release > 3x median ago) gets no estimate", () => {
  const e = estimateNextChapter(weekly("2026-09-20", 10, 300), NOW);
  assert.deepEqual(e, { reason: "stale" });
});

Deno.test("an estimate whose date is already past is not rolled forward", () => {
  const e = estimateNextChapter(weekly("2026-10-18", 10, 300), NOW);
  assert.deepEqual(e, { reason: "past" });
});

Deno.test("a fractional latest chapter predicts the next whole chapter", () => {
  const list = weekly("2026-10-25", 8, 40);
  list[0] = { number: 40.5, date: "2026-10-25" };
  const e = estimateNextChapter(list, NOW);
  assert.ok(isEstimate(e));
  if (isEstimate(e)) assert.equal(e.nextNumber, 41);
});

Deno.test("invalid dates are ignored", () => {
  const list = [...weekly("2026-10-25", 6, 20), { number: 21, date: "soon" }];
  const e = estimateNextChapter(list, NOW);
  assert.ok(isEstimate(e));
  if (isEstimate(e)) assert.equal(e.nextNumber, 21);
});
