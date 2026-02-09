/*
  Audit curated rails for quality + safety:
  - Ensures no Ecchi/Hentai genres
  - Ensures is_adult = false
  - Reports average score distribution + top "suspicious" items (low score, Kids genre, etc)
  - Cross-rail overlap detection (flags pairs > 15%)
  - Franchise duplication check (multiple entries from same series in a rail)
  - Classics year validation (flags items newer than 2014)
  - Rail size check (flags rails with > 80 items)
  - Score floor check per rail category

  Ship gates (hard failures, exit 1):
  - Any rail with adult/ecchi/hentai content
  - Any rail pair with overlap > 40%
  - Any rail with > 100 items
  - Any premium/gateway rail with items scoring < 70

  Warnings (exit 0):
  - Overlap 15-40% between rail pairs
  - Rail size 80-100
  - Franchise duplicates
  - Classics items newer than 2014

  Uses Supabase anon key (read-only) extracted from SupabaseService.swift.

  Usage:
    node scripts/audit_curated_rails_quality.js
    node scripts/audit_curated_rails_quality.js --json
*/

const fs = require("fs");
const path = require("path");
const { createClient } = require("@supabase/supabase-js");

const JSON_MODE = process.argv.includes("--json");

function getSupabaseConfig() {
  // Prefer explicit env vars (no coupling to app source)
  const envUrl = process.env.SUPABASE_URL;
  const envKey = process.env.SUPABASE_ANON_KEY;
  if (envUrl && envKey) {
    return { url: envUrl, anonKey: envKey };
  }

  // Fallback: extract from Swift source (legacy, for local dev convenience)
  const swiftPath = path.join(__dirname, "..", "Kuro", "Services", "SupabaseService.swift");
  if (!fs.existsSync(swiftPath)) {
    throw new Error("Set SUPABASE_URL and SUPABASE_ANON_KEY env vars, or run from the repo root.");
  }
  console.warn("WARNING: Extracting Supabase config from Swift source. Set SUPABASE_URL + SUPABASE_ANON_KEY env vars instead.");
  const text = fs.readFileSync(swiftPath, "utf8");
  const urlMatch = text.match(/fallbackURL\s*=\s*URL\(string:\s*"([^"]+)"\)/);
  const keyMatch = text.match(/fallbackKey\s*=\s*"([^"]+)"/);
  const urlFallback = text.match(new RegExp("https://[a-z0-9]+\\.supabase\\.co", "i"));
  const keyFallback = text.match(new RegExp("eyJhbGci[0-9A-Za-z._-]+"));
  const url = urlMatch?.[1] ?? (urlFallback ? urlFallback[0] : null);
  const anonKey = keyMatch?.[1] ?? (keyFallback ? keyFallback[0] : null);
  if (!url || !anonKey) throw new Error("Could not extract config. Set SUPABASE_URL + SUPABASE_ANON_KEY env vars.");
  return { url, anonKey };
}

function hasAny(genres, needle) {
  const gs = Array.isArray(genres) ? genres : [];
  return gs.includes(needle);
}

function pct(n, d) {
  if (!d) return "0%";
  return `${((n / d) * 100).toFixed(1)}%`;
}

// Score floor by rail category
function getScoreFloor(railId) {
  if (railId.startsWith("premium_picks") || railId.startsWith("gateway") || railId.startsWith("start_here")) return 78;
  if (railId.startsWith("isekai")) return 73;
  // Genre rails: dark_serious, cozy_comfort, premium_action, premium_comedy, hidden_gems, classics, movie_night
  return 74;
}

function getScoreFloorLabel(railId) {
  const floor = getScoreFloor(railId);
  if (floor === 78) return "premium/gateway";
  if (floor === 73) return "isekai";
  return "genre";
}

// Check if a rail is premium/gateway (hard failure threshold for score < 70)
function isPremiumOrGateway(railId) {
  return railId.startsWith("premium_picks") || railId.startsWith("gateway") || railId.startsWith("start_here");
}

// Detect franchise duplicates using title heuristics
function detectFranchiseDuplicates(items) {
  const groups = new Map(); // normalized prefix -> [items]

  for (const item of items) {
    const title = item.title_english || item.title_romaji || item.title_native || "";
    if (!title) continue;

    // Normalize: lowercase, strip punctuation for comparison
    const norm = title.toLowerCase().replace(/[^a-z0-9\s]/g, "").trim();
    const words = norm.split(/\s+/);

    // Use first 3 words as franchise key (if title has 3+ words)
    let key = words.length >= 3 ? words.slice(0, 3).join(" ") : norm;

    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(title);
  }

  // Also check containment: if title A is contained within title B
  const titles = items.map((it) => ({
    full: it.title_english || it.title_romaji || it.title_native || "",
    norm: (it.title_english || it.title_romaji || it.title_native || "").toLowerCase().replace(/[^a-z0-9\s]/g, "").trim(),
  }));

  // Merge groups where one title contains another
  for (let i = 0; i < titles.length; i++) {
    for (let j = i + 1; j < titles.length; j++) {
      if (!titles[i].norm || !titles[j].norm) continue;
      if (titles[i].norm.length < 5 || titles[j].norm.length < 5) continue;

      const shorter = titles[i].norm.length <= titles[j].norm.length ? titles[i] : titles[j];
      const longer = titles[i].norm.length <= titles[j].norm.length ? titles[j] : titles[i];

      if (longer.norm.includes(shorter.norm) && shorter.norm.length >= 8) {
        // Find which group shorter belongs to and add longer
        for (const [key, members] of groups) {
          if (members.includes(shorter.full) && !members.includes(longer.full)) {
            members.push(longer.full);
          }
        }
      }
    }
  }

  // Return only groups with 2+ entries
  const duplicates = [];
  const seen = new Set();
  for (const [key, members] of groups) {
    const unique = [...new Set(members)];
    if (unique.length >= 2) {
      const sig = unique.sort().join("|");
      if (!seen.has(sig)) {
        seen.add(sig);
        duplicates.push(unique);
      }
    }
  }
  return duplicates;
}

async function fetchAllRailItems(supabase, railId) {
  // Fetch from curated_rail_items directly (no 120 limit)
  const allItems = [];
  let offset = 0;
  const pageSize = 1000;
  while (true) {
    const { data, error } = await supabase
      .from("curated_rail_items")
      .select("rail_id,media_type,anilist_id,rank")
      .eq("rail_id", railId)
      .order("rank", { ascending: true })
      .range(offset, offset + pageSize - 1);
    if (error) throw new Error(`curated_rail_items query failed for ${railId}: ${error.message}`);
    if (!data || data.length === 0) break;
    allItems.push(...data);
    if (data.length < pageSize) break;
    offset += pageSize;
  }
  return allItems;
}

// Log helper: prints to stderr in JSON mode, stdout otherwise
function log(msg) {
  if (!JSON_MODE) {
    console.log(msg);
  }
}

async function main() {
  const { url, anonKey } = getSupabaseConfig();
  const supabase = createClient(url, anonKey, { auth: { persistSession: false } });

  const { data: rails, error: railErr } = await supabase
    .from("curated_rails")
    .select("id,title,media_type")
    .order("id", { ascending: true });
  if (railErr) throw new Error(`curated_rails query failed: ${railErr.message}`);

  const railIds = (rails || []).map((r) => r.id);
  if (railIds.length === 0) {
    log("No curated rails found.");
    return;
  }

  log(`# Curated Rails Audit`);
  log(`Rails: ${railIds.length}`);
  log(`Date: ${new Date().toISOString().slice(0, 10)}`);
  log("");

  let totalWarnings = 0;
  let totalFailures = 0;

  // Collect all issues for JSON output
  const failures = [];
  const warnings = [];

  // ── Per-rail checks ──────────────────────────────────────────────────
  // Collect anilist_id sets per rail for cross-rail overlap
  const railAnilistIds = new Map(); // railId -> Set<"ANIME:123" | "MANGA:456">

  for (const railId of railIds) {
    // Fetch via RPC (for detailed card info: scores, genres, titles, year)
    const { data: cards, error } = await supabase.rpc("curated_rail_cards", {
      p_rail_id: railId,
      p_limit: 120,
      p_exclude_seen: false,
    });
    if (error) {
      log(`- ${railId}: RPC error: ${error.message}`);
      continue;
    }
    const items = Array.isArray(cards) ? cards : [];

    // Fetch raw rail items (no limit) for accurate count and anilist_ids
    const rawItems = await fetchAllRailItems(supabase, railId);
    const idSet = new Set(rawItems.map((r) => `${r.media_type}:${r.anilist_id}`));
    railAnilistIds.set(railId, idSet);

    let ecchi = 0;
    let hentai = 0;
    let kids = 0;
    let adult = 0;
    let lowScore = 0;
    let scoreSum = 0;
    let scoreCount = 0;

    const suspicious = [];
    const scoreFloor = getScoreFloor(railId);
    const belowFloor = [];

    for (const it of items) {
      const gs = it.genres || [];
      if (hasAny(gs, "Ecchi")) ecchi++;
      if (hasAny(gs, "Hentai")) hentai++;
      if (hasAny(gs, "Kids")) kids++;
      if (it.is_adult === true) adult++;
      const s = typeof it.average_score === "number" ? it.average_score : null;
      if (typeof s === "number") {
        scoreSum += s;
        scoreCount++;
        if (s < 70) lowScore++;
        if (s < scoreFloor) {
          belowFloor.push({ title: it.title_english || it.title_romaji || "?", score: s });
        }
      }
      if (hasAny(gs, "Ecchi") || hasAny(gs, "Hentai") || hasAny(gs, "Kids") || (typeof s === "number" && s < 70)) {
        suspicious.push({ title: it.title_english || it.title_romaji || it.title_native || "?", s, gs });
      }
    }

    const avg = scoreCount ? (scoreSum / scoreCount).toFixed(1) : "?";
    log(`## ${railId}`);
    log(`items=${rawItems.length} (RPC returned ${items.length}) avg_score=${avg}`);
    log(`ecchi=${ecchi} hentai=${hentai} kids=${kids} adult=${adult} lowScore(<70)=${lowScore}`);

    if (suspicious.length) {
      log(`suspicious=${suspicious.length} (${pct(suspicious.length, items.length)})`);
      for (const s of suspicious.slice(0, 5)) {
        log(`  - ${s.title} score=${s.s ?? "?"} genres=${(s.gs || []).slice(0, 4).join(",")}`);
      }
    }

    // ── HARD FAILURE: adult content ────────────────────────────────────
    if (ecchi > 0 || hentai > 0 || adult > 0) {
      const msg = `FAIL: ${railId} contains adult content (ecchi=${ecchi} hentai=${hentai} is_adult=${adult})`;
      log(msg);
      failures.push({ check: "adult_content", rail: railId, ecchi, hentai, adult, message: msg });
      totalFailures++;
    }

    // ── HARD FAILURE: rail > 100 items ─────────────────────────────────
    if (rawItems.length > 100) {
      const msg = `FAIL: ${railId} has ${rawItems.length} items (hard limit: 100)`;
      log(msg);
      failures.push({ check: "rail_size_hard", rail: railId, count: rawItems.length, limit: 100, message: msg });
      totalFailures++;
    }
    // ── WARNING: rail 80-100 items ─────────────────────────────────────
    else if (rawItems.length > 80) {
      const msg = `WARNING: ${railId} has ${rawItems.length} items (target: <=80)`;
      log(msg);
      warnings.push({ check: "rail_size_warn", rail: railId, count: rawItems.length, message: msg });
      totalWarnings++;
    }

    // ── HARD FAILURE: premium/gateway items with score < 70 ────────────
    if (isPremiumOrGateway(railId) && lowScore > 0) {
      const lowItems = items.filter((it) => typeof it.average_score === "number" && it.average_score < 70);
      const msg = `FAIL: ${railId} (premium/gateway) has ${lowScore} items with score < 70`;
      log(msg);
      for (const li of lowItems.slice(0, 5)) {
        log(`  - ${li.title_english || li.title_romaji || "?"} (${li.average_score})`);
      }
      failures.push({
        check: "premium_score_floor",
        rail: railId,
        count: lowScore,
        items: lowItems.slice(0, 10).map((li) => ({
          title: li.title_english || li.title_romaji || "?",
          score: li.average_score,
        })),
        message: msg,
      });
      totalFailures++;
    }

    // ── WARNING: Score floor check ────────────────────────────────────
    if (belowFloor.length > 0) {
      const msg = `WARNING: ${belowFloor.length} items below ${getScoreFloorLabel(railId)} score floor (${scoreFloor})`;
      log(`${msg}:`);
      for (const bf of belowFloor.slice(0, 5)) {
        log(`  - ${bf.title} (${bf.score})`);
      }
      if (belowFloor.length > 5) log(`  ... and ${belowFloor.length - 5} more`);
      warnings.push({ check: "score_floor_warn", rail: railId, floor: scoreFloor, count: belowFloor.length, message: msg });
      totalWarnings++;
    }

    // ── WARNING: Classics year validation ─────────────────────────────
    if (railId.startsWith("classics")) {
      const tooNew = items.filter((it) => typeof it.year === "number" && it.year > 2014);
      if (tooNew.length > 0) {
        const msg = `WARNING: ${railId} contains ${tooNew.length} items from after 2014`;
        log(`${msg}:`);
        for (const t of tooNew.slice(0, 8)) {
          log(`  - ${t.title_english || t.title_romaji || "?"} (${t.year})`);
        }
        if (tooNew.length > 8) log(`  ... and ${tooNew.length - 8} more`);
        warnings.push({ check: "classics_year", rail: railId, count: tooNew.length, message: msg });
        totalWarnings++;
      }
    }

    // ── WARNING: Franchise duplication check ──────────────────────────
    const franchiseDupes = detectFranchiseDuplicates(items);
    if (franchiseDupes.length > 0) {
      for (const group of franchiseDupes) {
        const msg = `WARNING: ${railId} has ${group.length} entries from same franchise: ${JSON.stringify(group)}`;
        log(msg);
        warnings.push({ check: "franchise_dupe", rail: railId, titles: group, message: msg });
        totalWarnings++;
      }
    }

    log("");
  }

  // ── Cross-rail overlap detection ─────────────────────────────────────
  log(`## Cross-Rail Overlap Analysis`);
  log("");

  const railIdList = [...railAnilistIds.keys()];
  const overlapPairs = [];

  for (let i = 0; i < railIdList.length; i++) {
    for (let j = i + 1; j < railIdList.length; j++) {
      const railA = railIdList[i];
      const railB = railIdList[j];
      const setA = railAnilistIds.get(railA);
      const setB = railAnilistIds.get(railB);

      let shared = 0;
      for (const id of setA) {
        if (setB.has(id)) shared++;
      }

      const smaller = Math.min(setA.size, setB.size);
      if (smaller === 0) continue;
      const overlapPct = (shared / smaller) * 100;

      if (overlapPct > 15) {
        overlapPairs.push({ railA, railB, shared, sizeA: setA.size, sizeB: setB.size, overlapPct });
      }
    }
  }

  overlapPairs.sort((a, b) => b.overlapPct - a.overlapPct);

  if (overlapPairs.length === 0) {
    log("No rail pairs exceed 15% overlap. Good.");
  } else {
    log(`Found ${overlapPairs.length} rail pairs exceeding 15% overlap:`);
    log("");
    for (const p of overlapPairs) {
      // ── HARD FAILURE: overlap > 40% ──────────────────────────────────
      if (p.overlapPct > 40) {
        const msg = `FAIL: ${p.railA} (${p.sizeA}) <-> ${p.railB} (${p.sizeB}): ${p.overlapPct.toFixed(1)}% overlap (${p.shared} shared items)`;
        log(msg);
        failures.push({
          check: "overlap_hard",
          railA: p.railA,
          railB: p.railB,
          overlapPct: parseFloat(p.overlapPct.toFixed(1)),
          shared: p.shared,
          message: msg,
        });
        totalFailures++;
      }
      // ── WARNING: overlap 15-40% ──────────────────────────────────────
      else {
        const msg = `WARNING: ${p.railA} (${p.sizeA}) <-> ${p.railB} (${p.sizeB}): ${p.overlapPct.toFixed(1)}% overlap (${p.shared} shared items)`;
        log(msg);
        warnings.push({
          check: "overlap_warn",
          railA: p.railA,
          railB: p.railB,
          overlapPct: parseFloat(p.overlapPct.toFixed(1)),
          shared: p.shared,
          message: msg,
        });
        totalWarnings++;
      }
    }
  }

  // ── Summary ──────────────────────────────────────────────────────────
  const passed = totalFailures === 0;
  const verdict = passed ? "PASS" : "FAIL";

  log("");
  log(`---`);
  log(`## Summary`);
  log(`Verdict: ${verdict}`);
  log(`Rails audited: ${railIds.length}`);
  log(`Hard failures: ${totalFailures}`);
  log(`Warnings: ${totalWarnings}`);

  if (totalFailures > 0) {
    log("");
    log(`Failure details:`);
    for (const f of failures) {
      log(`  - [${f.check}] ${f.message}`);
    }
  }

  // ── JSON output ──────────────────────────────────────────────────────
  if (JSON_MODE) {
    const report = {
      date: new Date().toISOString().slice(0, 10),
      verdict,
      rails_audited: railIds.length,
      hard_failures: totalFailures,
      warnings_count: totalWarnings,
      failures,
      warnings,
    };
    console.log(JSON.stringify(report, null, 2));
  }

  if (!passed) {
    process.exit(1);
  }
}

main().catch((e) => {
  console.error(e?.message || String(e));
  process.exit(1);
});
