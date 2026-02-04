/*
  Evaluate concierge-parse against a synthetic corpus (JSONL).

  Usage:
    node scripts/concierge_corpus_generate.js > /tmp/concierge_corpus.jsonl
    node scripts/concierge_eval_parse.js /tmp/concierge_corpus.jsonl
*/

const fs = require("fs");
const path = require("path");
const { createClient } = require("@supabase/supabase-js");

function extractSupabaseConfigFromSwift() {
  const swiftPath = path.join(__dirname, "..", "Kuro", "Services", "SupabaseService.swift");
  const text = fs.readFileSync(swiftPath, "utf8");
  const urlMatch = text.match(/fallbackURL\s*=\s*URL\(string:\s*"([^"]+)"\)/);
  const keyMatch = text.match(/fallbackKey\s*=\s*"([^"]+)"/);
  const url = urlMatch?.[1];
  const anonKey = keyMatch?.[1];
  if (!url || !anonKey) throw new Error("Could not extract Supabase URL/key from SupabaseService.swift");
  return { url, anonKey };
}

async function callFn(url, anonKey, accessToken, name, payload) {
  const res = await fetch(`${url}/functions/v1/${name}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${accessToken}`, apikey: anonKey },
    body: JSON.stringify(payload),
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`${name} failed (${res.status}): ${JSON.stringify(json)}`);
  return json;
}

async function resolveExpectedIds(url, anonKey, accessToken, expectedItems) {
  const resolved = [];

  const norm = (s) =>
    String(s || "")
      .toLowerCase()
      .replace(/[^\p{L}\p{N}\s]+/gu, " ")
      .replace(/\s+/g, " ")
      .trim();

  const cache = resolveExpectedIds._cache || (resolveExpectedIds._cache = new Map());

  async function resolveOne(mt, query) {
    const key = `${mt}|${query}`;
    const cached = cache.get(key);
    if (cached) return cached;

    // Try exact title_norm match first (reduces ambiguity for e.g. Naruto).
    const titleNorm = norm(query);
    const exactUrl =
      `${url}/rest/v1/title_search?select=media_id,title_raw,variant_type,popularity` +
      `&media_type=eq.${encodeURIComponent(mt)}` +
      `&title_norm=eq.${encodeURIComponent(titleNorm)}` +
      `&variant_type=in.(${encodeURIComponent("english")},${encodeURIComponent("romaji")},${encodeURIComponent("native")})` +
      `&order=popularity.desc.nullslast&limit=5`;
    const exactRes = await fetch(exactUrl, {
      headers: { Authorization: `Bearer ${accessToken}`, apikey: anonKey },
    });
    const exactJson = await exactRes.json().catch(() => []);
    if (Array.isArray(exactJson) && exactJson.length > 0 && exactJson[0]?.media_id) {
      const out = { media_id: exactJson[0].media_id, title_raw: exactJson[0].title_raw, score: 1 };
      cache.set(key, out);
      return out;
    }

    // Fallback to fuzzy search.
    const res = await fetch(`${url}/rest/v1/rpc/search_titles`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${accessToken}`,
        apikey: anonKey,
      },
      body: JSON.stringify({ p_query: query, p_media_type: mt, p_limit: 8 }),
    });
    const json = await res.json().catch(() => []);
    const top = Array.isArray(json) ? json[0] : null;
    // If the query was a season-variant that doesn't exist, fall back to the base title.
    if ((!top?.media_id) && /\bseason\s+\d+\b/i.test(query)) {
      const base = query.replace(/\bseason\s+\d+\b/gi, "").replace(/\s+/g, " ").trim();
      if (base && base !== query) {
        const fallback = await resolveOne(mt, base);
        cache.set(key, fallback);
        return fallback;
      }
    }

    const out = { media_id: top?.media_id ?? null, title_raw: top?.title_raw ?? null, score: top?.score ?? null };
    cache.set(key, out);
    return out;
  }

  for (const e of expectedItems) {
    const mt = e.kind === "ANIME" ? "ANIME" : "MANGA";
    const query = String(e.query || "");
    const top = await resolveOne(mt, query);
    resolved.push({
      ...e,
      expected_media_type: mt,
      expected_media_id: top.media_id,
      expected_title_raw: top.title_raw,
      expected_score: top.score,
    });
  }

  return resolved;
}

function scoreAutoApply(parsedItem) {
  const cands = Array.isArray(parsedItem?.candidates) ? parsedItem.candidates : [];
  const top = cands[0];
  const second = cands[1];
  const topScore = typeof top?.score === "number" ? top.score : 0;
  const secondScore = typeof second?.score === "number" ? second.score : 0;
  const margin = topScore - secondScore;
  const confident = (topScore >= 1.1 && margin >= 0.1) || (topScore >= 1.0 && margin >= 0.22);

  const stop = new Set([
    "the",
    "a",
    "an",
    "of",
    "and",
    "or",
    "to",
    "in",
    "on",
    "for",
    "with",
    "der",
    "die",
    "das",
    "ein",
    "eine",
    "einer",
    "eines",
    "und",
    "oder",
    "zu",
    "im",
    "am",
    "auf",
    "mit",
  ]);

  function tokens(s) {
    return String(s || "")
      .toLowerCase()
      .replace(/[^\p{L}\p{N}\s]+/gu, " ")
      .replace(/\s+/g, " ")
      .trim()
      .split(" ")
      .filter(Boolean)
      .filter((t) => !stop.has(t));
  }

  const q = tokens(parsedItem?.normalized || "");
  const c = tokens(top?.title_raw || "");
  let titleSafe = false;
  if (q.length > 0 && c.length > 0) {
    if (q.length === 1) {
      const season = Number(parsedItem?.parsed?.seasonNumber ?? 0);
      if (season >= 2) {
        titleSafe = false;
      } else {
      titleSafe = c.length === 1 && c[0] === q[0];
      }
    } else {
      const qSet = new Set(q);
      const cSet = new Set(c);
      let inter = 0;
      for (const t of qSet) if (cSet.has(t)) inter++;
      const overlap = inter / qSet.size;
      titleSafe = overlap >= 0.75 && (c.length - q.length < 4);
    }
  }

  const eligible = confident && titleSafe;
  return { topScore, margin, confident, titleSafe, eligible };
}

function eqNum(a, b) {
  if (a == null && b == null) return true;
  return Number(a) === Number(b);
}

function eqStr(a, b) {
  if (a == null && b == null) return true;
  return String(a) === String(b);
}

async function main() {
  const corpusPath = process.argv[2];
  if (!corpusPath) throw new Error("Missing corpus JSONL path argument.");
  const raw = fs.readFileSync(corpusPath, "utf8");
  const lines = raw.split("\n").map((l) => l.trim()).filter(Boolean);
  const corpus = lines.map((l) => JSON.parse(l));

  const { url, anonKey } = extractSupabaseConfigFromSwift();
  const supabase = createClient(url, anonKey, { auth: { persistSession: false } });
  const { data: authData, error: authErr } = await supabase.auth.signInAnonymously();
  if (authErr) throw new Error(`Anonymous sign-in failed: ${authErr.message}`);
  const token = authData?.session?.access_token;
  if (!token) throw new Error("Missing access token");

  let caseCount = 0;
  let itemCount = 0;
  let splitExact = 0;
  let top1Exact = 0;
  let expectedInTopK = 0;
  let statusExact = 0;
  let progressExact = 0;
  let autoApplyEligible = 0;
  let autoApplyEligibleCorrect = 0;
  const debug = process.env.DEBUG_FAILS === "1";
  const progressFailures = [];
  const autoApplyFailures = [];
  let hardFailures = 0;

  for (const row of corpus) {
    caseCount++;
    const expected = await resolveExpectedIds(url, anonKey, token, row.expected || []);

    let parsed;
    try {
      parsed = await callFn(url, anonKey, token, "concierge-parse", { text: row.text, scope: "both", limitPerItem: 10 });
    } catch (e) {
      hardFailures++;
      continue;
    }

    const items = Array.isArray(parsed?.items) ? parsed.items : [];
    if (items.length === expected.length) splitExact++;

    const n = Math.min(items.length, expected.length);
    for (let i = 0; i < n; i++) {
      itemCount++;
      const it = items[i];
      const exp = expected[i];
      const cands = Array.isArray(it?.candidates) ? it.candidates : [];
      const top = cands[0];

      const { eligible } = scoreAutoApply(it);
      if (eligible) autoApplyEligible++;

      if (eqStr(it?.parsed?.status, exp.status)) statusExact++;

      const expId = exp.expected_media_id;
      const topOk = expId != null && Number(top?.media_id) === Number(expId) && String(top?.media_type) === exp.expected_media_type;
      if (topOk) top1Exact++;
      const inK = expId != null && cands.some((c) => Number(c.media_id) === Number(expId) && String(c.media_type) === exp.expected_media_type);
      if (inK) expectedInTopK++;

      if (eligible && topOk) autoApplyEligibleCorrect++;

      // progress checks (only when expected has them)
      const expSeason = exp.seasonNumber ?? null;
      const expEpInSeason = exp.episodeInSeason ?? null;
      const expEp = exp.progressEpisodes ?? null;
      const gotSeason = it?.parsed?.seasonNumber ?? null;
      const gotEpInSeason = it?.parsed?.episodeInSeason ?? null;
      const gotEp = it?.parsed?.progressEpisodes ?? null;

      const needsProgress = expSeason != null || expEpInSeason != null || expEp != null;
      if (needsProgress) {
        const ok =
          (expSeason == null || eqNum(gotSeason, expSeason)) &&
          (expEpInSeason == null || eqNum(gotEpInSeason, expEpInSeason)) &&
          (expEp == null || eqNum(gotEp, expEp));
        if (ok) progressExact++;
        else if (debug && progressFailures.length < 12) {
          progressFailures.push({
            text: row.text,
            expected: { seasonNumber: expSeason, episodeInSeason: expEpInSeason, progressEpisodes: expEp },
            got: { seasonNumber: gotSeason, episodeInSeason: gotEpInSeason, progressEpisodes: gotEp },
            raw: it?.raw,
            normalized: it?.normalized,
          });
        }
      } else {
        progressExact++;
      }

      if (eligible && !topOk && debug && autoApplyFailures.length < 8) {
        autoApplyFailures.push({
          text: row.text,
          raw: it?.raw,
          normalized: it?.normalized,
          top: top ? { media_type: top.media_type, media_id: top.media_id, title_raw: top.title_raw, score: top.score } : null,
          expected: { media_type: exp.expected_media_type, media_id: exp.expected_media_id, title_raw: exp.expected_title_raw, score: exp.expected_score },
        });
      }
    }
  }

  const pct = (a, b) => (b === 0 ? "0.0%" : `${((a / b) * 100).toFixed(1)}%`);

  console.log("CONCIERGE PARSE EVAL");
  console.log(`cases=${caseCount} items=${itemCount} hard_failures=${hardFailures}`);
  console.log(`split_exact=${splitExact}/${caseCount} (${pct(splitExact, caseCount)})`);
  console.log(`top1_exact=${top1Exact}/${itemCount} (${pct(top1Exact, itemCount)})`);
  console.log(`expected_in_topK=${expectedInTopK}/${itemCount} (${pct(expectedInTopK, itemCount)})`);
  console.log(`status_exact=${statusExact}/${itemCount} (${pct(statusExact, itemCount)})`);
  console.log(`progress_exact=${progressExact}/${itemCount} (${pct(progressExact, itemCount)})`);
  console.log(`auto_apply_eligible=${autoApplyEligible}/${itemCount} (${pct(autoApplyEligible, itemCount)})`);
  console.log(`auto_apply_precision=${autoApplyEligibleCorrect}/${autoApplyEligible} (${pct(autoApplyEligibleCorrect, autoApplyEligible)})`);

  if (debug) {
    if (progressFailures.length) {
      console.log("\nPROGRESS FAILURES (sample)");
      for (const f of progressFailures) console.log(JSON.stringify(f));
    }
    if (autoApplyFailures.length) {
      console.log("\nAUTO-APPLY FAILURES (sample)");
      for (const f of autoApplyFailures) console.log(JSON.stringify(f));
    }
  }
}

main().catch((e) => {
  console.error(e?.message || String(e));
  process.exit(1);
});
