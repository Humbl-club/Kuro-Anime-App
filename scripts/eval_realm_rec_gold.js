#!/usr/bin/env node

/*
  Realm Graph Stage 3 — gold-set precision@10 harness.
  Spec: docs/superpowers/specs/2026-07-31-realm-graph-master-plan.md §7

  Arms:
    (a) raw AniList edges from media_rec_edges (rating desc)
    (b) realm-gated recommend_ids_similar_to_seeds
    (c) intersection: edges that also appear in a wider gated candidate pool,
        re-ranked by edge rating

  Usage:
    node scripts/eval_realm_rec_gold.js --bootstrap-seeds   # write 100 seeds
    node scripts/eval_realm_rec_gold.js --bootstrap-judgments # heuristic judgments
    node scripts/eval_realm_rec_gold.js                     # score + report

  Env: SUPABASE_URL / SUPABASE_ANON_KEY (xcconfig fallback). Anon JWT is fine.
*/

const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const GOLD_DIR = path.join(ROOT, 'eval/realm_rec_gold');
const REPORT_DIR = path.join(ROOT, 'reports/realm-rec-gold');
const XCCONFIG_PATH = path.join(ROOT, 'Config/Shared.xcconfig');
const SEEDS_PATH = path.join(GOLD_DIR, 'seeds.jsonl');
const JUDGE_PATH = path.join(GOLD_DIR, 'judgments.jsonl');
const DELTA_SHIP = 0.05;

function log(...args) { console.error('[eval-gold]', ...args); }

function loadConfig() {
  const values = {};
  if (fs.existsSync(XCCONFIG_PATH)) {
    for (const line of fs.readFileSync(XCCONFIG_PATH, 'utf8').split(/\r?\n/)) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('//')) continue;
      const idx = trimmed.indexOf('=');
      if (idx <= 0) continue;
      values[trimmed.slice(0, idx).trim()] =
        trimmed.slice(idx + 1).trim().replace(/\$\(\)/g, '');
    }
  }
  const url = (process.env.SUPABASE_URL || values.SUPABASE_URL || '').replace(/\/+$/, '');
  const anonKey = process.env.SUPABASE_ANON_KEY || values.SUPABASE_ANON_KEY;
  if (!url || !anonKey) throw new Error('Missing SUPABASE_URL / SUPABASE_ANON_KEY');
  return { url, anonKey };
}

async function restGet(cfg, q) {
  const res = await fetch(`${cfg.url}/rest/v1/${q}`, {
    headers: { apikey: cfg.anonKey, Authorization: `Bearer ${cfg.anonKey}` },
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`GET ${q} → ${res.status}: ${text.slice(0, 300)}`);
  return text ? JSON.parse(text) : [];
}

async function rpc(cfg, name, body, { optional = false } = {}) {
  const res = await fetch(`${cfg.url}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: {
      apikey: cfg.anonKey,
      Authorization: `Bearer ${cfg.anonKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  if (!res.ok) {
    if (optional) {
      log(`RPC ${name} soft-fail ${res.status}: ${text.slice(0, 120)}`);
      return [];
    }
    throw new Error(`RPC ${name} → ${res.status}: ${text.slice(0, 400)}`);
  }
  return text ? JSON.parse(text) : [];
}

function sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }

function readJsonl(file) {
  if (!fs.existsSync(file)) return [];
  return fs.readFileSync(file, 'utf8').split(/\r?\n/).filter(Boolean).map((l) => JSON.parse(l));
}

function writeJsonl(file, rows) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, rows.map((r) => JSON.stringify(r)).join('\n') + '\n');
}

async function bootstrapSeeds(cfg) {
  log('bootstrapping 100 diversified seeds from media_realm_tier + edge coverage');
  const realms = await restGet(cfg, 'realm_meta?select=realm,family,sort&order=sort.asc');
  const seeds = [];
  const used = new Set();

  for (const rm of realms) {
    // Prefer canon/acclaimed anime with edge coverage
    const tiered = await restGet(
      cfg,
      `media_realm_tier?realm=eq.${rm.realm}&tier=in.(canon,acclaimed)&media_type=eq.ANIME&select=media_id,tier&limit=40`
    );
    let picked = 0;
    for (const t of tiered) {
      if (picked >= 2) break;
      const key = `ANIME:${t.media_id}`;
      if (used.has(key)) continue;
      const edges = await restGet(
        cfg,
        `media_rec_edges?from_media_type=eq.ANIME&from_media_id=eq.${t.media_id}&select=to_media_id&limit=1`
      );
      if (!edges.length) continue;
      const anime = await restGet(
        cfg,
        `anime?id=eq.${t.media_id}&select=id,anilist_id,title_english,title_romaji`
      );
      if (!anime[0]) continue;
      used.add(key);
      seeds.push({
        seed_key: key,
        media_type: 'ANIME',
        kuro_id: t.media_id,
        anilist_id: anime[0].anilist_id,
        title: anime[0].title_english || anime[0].title_romaji,
        primary_realm: rm.realm,
        family: rm.family,
        tier: t.tier,
      });
      picked++;
    }
  }

  // Top up with manga if under 100
  if (seeds.length < 100) {
    for (const rm of realms) {
      if (seeds.length >= 100) break;
      const tiered = await restGet(
        cfg,
        `media_realm_tier?realm=eq.${rm.realm}&tier=in.(canon,acclaimed)&media_type=eq.MANGA&select=media_id,tier&limit=20`
      );
      for (const t of tiered) {
        if (seeds.length >= 100) break;
        const key = `MANGA:${t.media_id}`;
        if (used.has(key)) continue;
        const edges = await restGet(
          cfg,
          `media_rec_edges?from_media_type=eq.MANGA&from_media_id=eq.${t.media_id}&select=to_media_id&limit=1`
        );
        if (!edges.length) continue;
        const manga = await restGet(
          cfg,
          `manga?id=eq.${t.media_id}&select=id,anilist_id,title_english,title_romaji`
        );
        if (!manga[0]) continue;
        used.add(key);
        seeds.push({
          seed_key: key,
          media_type: 'MANGA',
          kuro_id: t.media_id,
          anilist_id: manga[0].anilist_id,
          title: manga[0].title_english || manga[0].title_romaji,
          primary_realm: rm.realm,
          family: rm.family,
          tier: t.tier,
        });
      }
    }
  }

  writeJsonl(SEEDS_PATH, seeds.slice(0, 100));
  log(`wrote ${Math.min(seeds.length, 100)} seeds → ${SEEDS_PATH}`);
}

async function bootstrapJudgments(cfg) {
  const seeds = readJsonl(SEEDS_PATH);
  if (!seeds.length) throw new Error('No seeds — run --bootstrap-seeds first');
  log(`bootstrapping heuristic judgments for ${seeds.length} seeds (curated rails ∩ edges ∪ gated)`);
  const judgments = [];

  for (const seed of seeds) {
    const relevant = new Map();

    // AniList top edges as weak positives (community signal)
    const edges = await restGet(
      cfg,
      `media_rec_edges?from_media_type=eq.${seed.media_type}&from_media_id=eq.${seed.kuro_id}&select=to_media_type,to_media_id,rating&order=rating.desc&limit=15`
    );
    for (const e of edges.slice(0, 8)) {
      relevant.set(`${e.to_media_type}:${e.to_media_id}`, {
        media_type: e.to_media_type,
        kuro_id: e.to_media_id,
        label: 1,
        source: 'anilist-top',
      });
    }

    // Same curated rail co-members (editorial)
    const table = seed.media_type === 'ANIME' ? 'anime' : 'manga';
    const row = await restGet(cfg, `${table}?id=eq.${seed.kuro_id}&select=anilist_id`);
    const alid = row[0] && row[0].anilist_id;
    if (alid) {
      const railItems = await restGet(
        cfg,
        `curated_rail_items?media_type=eq.${seed.media_type}&anilist_id=eq.${alid}&select=rail_id&limit=5`
      );
      for (const ri of railItems.slice(0, 2)) {
        const peers = await restGet(
          cfg,
          `curated_rail_items?rail_id=eq.${ri.rail_id}&media_type=eq.${seed.media_type}&select=anilist_id&limit=30`
        );
        const peerAl = peers.map((p) => p.anilist_id).filter((x) => x && x !== alid).slice(0, 20);
        if (!peerAl.length) continue;
        const peersKuro = await restGet(
          cfg,
          `${table}?anilist_id=in.(${peerAl.join(',')})&select=id,anilist_id&limit=20`
        );
        for (const p of peersKuro) {
          const key = `${seed.media_type}:${p.id}`;
          relevant.set(key, {
            media_type: seed.media_type,
            kuro_id: p.id,
            label: 1,
            source: 'curated-rail',
          });
        }
      }
    }

    judgments.push({
      seed_key: seed.seed_key,
      relevant: [...relevant.values()],
      judge: 'heuristic-bootstrap-2026-08',
      judged_at: new Date().toISOString().slice(0, 10),
      note: 'Replace with owner judgments before shipping edges into ranking.',
    });
    if (judgments.length % 10 === 0) log(`  judged ${judgments.length}/${seeds.length}`);
  }

  writeJsonl(JUDGE_PATH, judgments);
  log(`wrote ${judgments.length} judgments → ${JUDGE_PATH}`);
}

function precisionAtK(rankedIds, relevantSet, k = 10) {
  const top = rankedIds.slice(0, k);
  if (!top.length) return 0;
  let hits = 0;
  for (const id of top) if (relevantSet.has(id)) hits++;
  return hits / k;
}

async function score(cfg) {
  const seeds = readJsonl(SEEDS_PATH);
  const judgments = readJsonl(JUDGE_PATH);
  if (!seeds.length || !judgments.length) {
    throw new Error('Need seeds + judgments (bootstrap first)');
  }
  const jmap = new Map(judgments.map((j) => [j.seed_key, j]));
  const rows = [];

  for (const seed of seeds) {
    const j = jmap.get(seed.seed_key);
    if (!j || !j.relevant.length) {
      rows.push({ seed_key: seed.seed_key, skip: 'no judgments' });
      continue;
    }
    const relevantSet = new Set(
      j.relevant
        .filter((r) => r.media_type === seed.media_type)
        .map((r) => r.kuro_id)
    );

    const edges = await restGet(
      cfg,
      `media_rec_edges?from_media_type=eq.${seed.media_type}&from_media_id=eq.${seed.kuro_id}&to_media_type=eq.${seed.media_type}&select=to_media_id,rating&order=rating.desc&limit=25`
    );
    const rawIds = edges.map((e) => e.to_media_id);

    const gated = await rpc(cfg, 'recommend_ids_similar_to_seeds', {
      p_media_type: seed.media_type,
      p_seed_ids: [seed.kuro_id],
      p_limit: 10,
      p_allow_gimmicks: false,
    }, { optional: true });
    await sleep(150);
    if (!gated.length) {
      rows.push({ seed_key: seed.seed_key, title: seed.title, skip: 'gated timeout' });
      continue;
    }
    const gatedIds = gated.map((g) => g.media_id);
    const gatedSet = new Set(gatedIds);

    const intersectIds = rawIds.filter((id) => gatedSet.has(id));

    const pa = precisionAtK(rawIds, relevantSet, 10);
    const pb = precisionAtK(gatedIds, relevantSet, 10);
    const pc = precisionAtK(intersectIds, relevantSet, 10);

    rows.push({
      seed_key: seed.seed_key,
      title: seed.title,
      realm: seed.primary_realm,
      family: seed.family,
      n_relevant: relevantSet.size,
      n_edges: rawIds.length,
      p10_raw: pa,
      p10_gated: pb,
      p10_intersect: pc,
    });
    if (rows.length % 10 === 0) log(`  scored ${rows.length}/${seeds.length}`);
  }

  const scored = rows.filter((r) => r.p10_raw != null);
  const mean = (key) => scored.reduce((s, r) => s + r[key], 0) / (scored.length || 1);
  const summary = {
    n_seeds: seeds.length,
    n_scored: scored.length,
    mean_p10_raw: mean('p10_raw'),
    mean_p10_gated: mean('p10_gated'),
    mean_p10_intersect: mean('p10_intersect'),
    delta_intersect_minus_gated: mean('p10_intersect') - mean('p10_gated'),
    ship_threshold: DELTA_SHIP,
    ship_edges_into_ranking:
      mean('p10_intersect') - mean('p10_gated') >= DELTA_SHIP,
    note: 'Judgments are heuristic-bootstrap unless owner-replaced. Do not ship on heuristic alone.',
    generated_at: new Date().toISOString(),
  };

  fs.mkdirSync(REPORT_DIR, { recursive: true });
  const jsonPath = path.join(REPORT_DIR, 'latest.json');
  const mdPath = path.join(REPORT_DIR, 'latest.md');
  fs.writeFileSync(jsonPath, JSON.stringify({ summary, rows }, null, 2));

  const md = [
    '# Realm rec-edges gold-set eval',
    '',
    `Generated: ${summary.generated_at}`,
    '',
    '## Summary',
    '',
    `| Arm | Mean P@10 |`,
    `|---|---|`,
    `| (a) raw AniList | ${summary.mean_p10_raw.toFixed(3)} |`,
    `| (b) realm-gated | ${summary.mean_p10_gated.toFixed(3)} |`,
    `| (c) edges ∩ gate | ${summary.mean_p10_intersect.toFixed(3)} |`,
    '',
    `Δ(c−b) = **${summary.delta_intersect_minus_gated.toFixed(3)}** (ship if ≥ ${DELTA_SHIP} on **owner** judgments)`,
    '',
    `Ship decision (auto): **${summary.ship_edges_into_ranking ? 'CANDIDATE — still needs owner judgment pass' : 'NO — keep edges advisory'}**`,
    '',
    `Scored ${summary.n_scored}/${summary.n_seeds} seeds.`,
    '',
    '## Per-seed (top deltas)',
    '',
    ...scored
      .slice()
      .sort((a, b) => (b.p10_intersect - b.p10_gated) - (a.p10_intersect - a.p10_gated))
      .slice(0, 15)
      .map(
        (r) =>
          `- ${r.title} (${r.realm}): raw=${r.p10_raw.toFixed(2)} gated=${r.p10_gated.toFixed(2)} ∩=${r.p10_intersect.toFixed(2)}`
      ),
    '',
  ].join('\n');
  fs.writeFileSync(mdPath, md);

  log(`wrote ${jsonPath}`);
  log(`wrote ${mdPath}`);
  console.log(JSON.stringify(summary, null, 2));
}

async function main() {
  const args = process.argv.slice(2);
  const cfg = loadConfig();
  fs.mkdirSync(GOLD_DIR, { recursive: true });
  if (args.includes('--bootstrap-seeds')) return bootstrapSeeds(cfg);
  if (args.includes('--bootstrap-judgments')) return bootstrapJudgments(cfg);
  return score(cfg);
}

main().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
