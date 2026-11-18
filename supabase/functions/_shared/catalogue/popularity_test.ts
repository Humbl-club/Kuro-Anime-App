// Offline tests for the Kuro popularity index (catalogue Task 10). Pure functions, no I/O.
import { strict as assert } from "node:assert";
import { INT32_MAX, popularityIndex, scoreIndex, trendingIndex } from "./popularity.ts";

Deno.test("monotonicInViews", () => {
  let prev = -1;
  for (const views12m of [0, 1_000, 50_000, 1_000_000, 40_000_000]) {
    const v = popularityIndex({ views12m, votes: 10, libraryAdds: 2 });
    assert.ok(v >= prev, `${views12m} views gave ${v}, below ${prev}`);
    prev = v;
  }
  assert.ok(popularityIndex({ views12m: 2_000_000, votes: 0, libraryAdds: 0 }) > popularityIndex({ views12m: 1_000_000, votes: 0, libraryAdds: 0 }));
});

Deno.test("startingCoefficients", () => {
  // round(views12m/12 * 0.02 + votes * 1 + libraryAdds * 50)
  assert.equal(popularityIndex({ views12m: 120_000, votes: 7, libraryAdds: 3 }), 200 + 7 + 150);
  assert.equal(popularityIndex({ views12m: 0, votes: 0, libraryAdds: 0 }), 0);
});

Deno.test("nullScoreUnder20Votes", () => {
  assert.equal(scoreIndex(undefined, undefined), null);
  assert.equal(scoreIndex({ weighted: 8, votes: 19 }, undefined), null);
  assert.equal(scoreIndex({ weighted: 8, votes: 10 }, { bayesian: 7, votes: 9 }), null);
  assert.equal(scoreIndex({ weighted: 8, votes: 20 }, undefined), 80);
  assert.equal(scoreIndex(undefined, { bayesian: 7.5, votes: 20 }), 75);
});

Deno.test("scoreBlendIsVoteWeighted", () => {
  // (8*10*30 + 6*10*10) / 40 = 75
  assert.equal(scoreIndex({ weighted: 8, votes: 30 }, { bayesian: 6, votes: 10 }), 75);
  assert.equal(scoreIndex({ weighted: 10, votes: 100 }, undefined), 100);
  const s = scoreIndex({ weighted: 99, votes: 100 }, undefined);
  assert.equal(s, 100, "clamped to the 0-100 scale");
});

Deno.test("trendingNeverNegative", () => {
  assert.equal(trendingIndex(10, 5_000), 0);
  assert.equal(trendingIndex(0, 0), 0);
  assert.equal(trendingIndex(5_100, 100), 50);
  assert.ok(trendingIndex(-5, 3) >= 0);
});

Deno.test("scalesToIntegerColumn", () => {
  const values = [
    popularityIndex({ views12m: 1.5e6, votes: 33, libraryAdds: 1 }),
    popularityIndex({ views12m: 9e15, votes: 9e9, libraryAdds: 9e9 }),
    popularityIndex({ views12m: Number.NaN, votes: -4, libraryAdds: Number.POSITIVE_INFINITY }),
    trendingIndex(9e15, 0),
  ];
  for (const v of values) {
    assert.ok(Number.isInteger(v), `${v} is not an integer`);
    assert.ok(v >= 0 && v <= INT32_MAX, `${v} does not fit a Postgres integer`);
  }
});
