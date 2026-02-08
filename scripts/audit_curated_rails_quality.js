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

  Uses Supabase anon key (read-only) extracted from SupabaseService.swift.

  Usage:
    node scripts/audit_curated_rails_quality.js
*/

const fs = require("fs");
const path = require("path");
const { createClient } = require("@supabase/supabase-js");

function extractSupabaseConfigFromSwift() {
  const swiftPath = path.join(__dirname, "..", "Kuro", "Services", "SupabaseService.swift");
  const text = fs.readFileSync(swiftPath, "utf8");
  const urlMatch = text.match(/fallbackURL\\s*=\\s*URL\\(string:\\s*\"([^\"]+)\"\\)/);
  const keyMatch = text.match(/fallbackKey\\s*=\\s*\"([^\"]+)\"/);
  const urlFallback = text.match(new RegExp("https://[a-z0-9]+\\.supabase\\.co", "i"));
  const keyFallback = text.match(new RegExp("eyJhbGci[0-9A-Za-z._-]+"));
  const url = urlMatch?.[1] ?? (urlFallback ? urlFallback[0] : null);
  const anonKey = keyMatch?.[1] ?? (keyFallback ? keyFallback[0] : null);
  if (!url || !anonKey) throw new Error("Could not extract `fallbackURL` / `fallbackKey` from SupabaseService.swift");
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

async function main() {
  const { url, anonKey } = extractSupabaseConfigFromSwift();
  const supabase = createClient(url, anonKey, { auth: { persistSession: false } });

  const { data: rails, error: railErr } = await supabase
    .from("curated_rails")
    .select("id,title,media_type")
    .order("id", { ascending: true });
  if (railErr) throw new Error(`curated_rails query failed: ${railErr.message}`);

  const railIds = (rails || []).map((r) => r.id);
  if (railIds.length === 0) {
    console.log("No curated rails found.");
    return;
  }

  console.log(`# Curated Rails Audit`);
  console.log(`Rails: ${railIds.length}`);
  console.log(`Date: ${new Date().toISOString().slice(0, 10)}`);
  console.log("");

  let totalWarnings = 0;

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
      console.log(`- ${railId}: RPC error: ${error.message}`);
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
    console.log(`## ${railId}`);
    console.log(`items=${rawItems.length} (RPC returned ${items.length}) avg_score=${avg}`);
    console.log(`ecchi=${ecchi} hentai=${hentai} kids=${kids} adult=${adult} lowScore(<70)=${lowScore}`);

    if (suspicious.length) {
      console.log(`suspicious=${suspicious.length} (${pct(suspicious.length, items.length)})`);
      for (const s of suspicious.slice(0, 5)) {
        console.log(`  - ${s.title} score=${s.s ?? "?"} genres=${(s.gs || []).slice(0, 4).join(",")}`);
      }
    }

    // ── Rail size check ──────────────────────────────────────────────
    if (rawItems.length > 80) {
      console.log(`WARNING: ${railId} has ${rawItems.length} items (target: <=80)`);
      totalWarnings++;
    }

    // ── Score floor check ────────────────────────────────────────────
    if (belowFloor.length > 0) {
      console.log(`WARNING: ${belowFloor.length} items below ${getScoreFloorLabel(railId)} score floor (${scoreFloor}):`);
      for (const bf of belowFloor.slice(0, 5)) {
        console.log(`  - ${bf.title} (${bf.score})`);
      }
      if (belowFloor.length > 5) console.log(`  ... and ${belowFloor.length - 5} more`);
      totalWarnings++;
    }

    // ── Classics year validation ─────────────────────────────────────
    if (railId.startsWith("classics")) {
      const tooNew = items.filter((it) => typeof it.year === "number" && it.year > 2014);
      if (tooNew.length > 0) {
        console.log(`WARNING: ${railId} contains ${tooNew.length} items from after 2014:`);
        for (const t of tooNew.slice(0, 8)) {
          console.log(`  - ${t.title_english || t.title_romaji || "?"} (${t.year})`);
        }
        if (tooNew.length > 8) console.log(`  ... and ${tooNew.length - 8} more`);
        totalWarnings++;
      }
    }

    // ── Franchise duplication check ──────────────────────────────────
    const franchiseDupes = detectFranchiseDuplicates(items);
    if (franchiseDupes.length > 0) {
      for (const group of franchiseDupes) {
        console.log(`WARNING: ${railId} has ${group.length} entries from same franchise: ${JSON.stringify(group)}`);
        totalWarnings++;
      }
    }

    console.log("");
  }

  // ── Cross-rail overlap detection ─────────────────────────────────────
  console.log(`## Cross-Rail Overlap Analysis`);
  console.log("");

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
    console.log("No rail pairs exceed 15% overlap. Good.");
  } else {
    console.log(`Found ${overlapPairs.length} rail pairs exceeding 15% overlap:`);
    console.log("");
    for (const p of overlapPairs) {
      console.log(
        `WARNING: ${p.railA} (${p.sizeA}) <-> ${p.railB} (${p.sizeB}): ${p.overlapPct.toFixed(1)}% overlap (${p.shared} shared items)`
      );
      totalWarnings++;
    }
  }

  console.log("");
  console.log(`---`);
  console.log(`Total warnings: ${totalWarnings}`);
}

main().catch((e) => {
  console.error(e?.message || String(e));
  process.exit(1);
});
