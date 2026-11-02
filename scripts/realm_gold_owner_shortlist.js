#!/usr/bin/env node
/**
 * Build owner-judgment shortlists for the realm rec gold set.
 * Candidate pool = A-tier canon_seed neighbors that share the seed's top realm,
 * plus existing heuristic judgments (marked heuristic=true).
 *
 * Writes: eval/realm_rec_gold/owner_shortlists.jsonl
 *         eval/realm_rec_gold/owner_judgments.template.jsonl
 *
 * Owner fills owner_judgments.jsonl with {seed_id, media_type, relevant:[{media_id,...}]}
 * then: node scripts/eval_realm_rec_gold.js --judgments eval/realm_rec_gold/owner_judgments.jsonl
 */
'use strict';

const fs = require('fs');
const path = require('path');
const { getPublicProjectConfig } = require('./lib/project_config');

const ROOT = path.join(__dirname, '..');
const SEEDS_PATH = path.join(ROOT, 'eval', 'realm_rec_gold', 'seeds.jsonl');
const OUT_SHORT = path.join(ROOT, 'eval', 'realm_rec_gold', 'owner_shortlists.jsonl');
const OUT_TMPL = path.join(ROOT, 'eval', 'realm_rec_gold', 'owner_judgments.template.jsonl');

function loadJsonl(p) {
  if (!fs.existsSync(p)) return [];
  return fs.readFileSync(p, 'utf8').split(/\r?\n/).filter(Boolean).map((l) => JSON.parse(l));
}

async function rest(url, key, p) {
  const r = await fetch(`${url}/rest/v1/${p}`, {
    headers: { apikey: key, Authorization: `Bearer ${key}`, Prefer: 'count=exact' },
  });
  if (!r.ok) throw new Error(`${r.status} ${await r.text()}`);
  return r.json();
}

async function rpc(url, key, name, body) {
  const r = await fetch(`${url}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  if (!r.ok) {
    const t = await r.text();
    throw new Error(`rpc ${name}: ${r.status} ${t.slice(0, 240)}`);
  }
  return r.json();
}

(async () => {
  const { url, anonKey } = getPublicProjectConfig();
  const seeds = loadJsonl(SEEDS_PATH);
  if (!seeds.length) {
    console.error('No seeds — run: node scripts/eval_realm_rec_gold.js --bootstrap-seeds');
    process.exit(1);
  }

  const canon = await rest(
    url,
    anonKey,
    'canon_seed?select=media_type,media_id,title,source,blessed&blessed=eq.true&limit=2000'
  );
  const byType = { ANIME: new Map(), MANGA: new Map() };
  for (const c of canon) {
    const map = byType[c.media_type];
    if (!map.has(c.media_id)) map.set(c.media_id, { media_id: c.media_id, title: c.title, sources: [] });
    map.get(c.media_id).sources.push(c.source);
  }

  const shortlines = [];
  const tmplLines = [];

  for (const seed of seeds.slice(0, 100)) {
    const mt = seed.media_type === 'anime' || seed.media_type === 'ANIME' ? 'ANIME' : 'MANGA';
    const seedId = seed.media_id ?? seed.id;
    let topRealm = seed.realm || null;
    try {
      const tiers = await rest(
        url,
        anonKey,
        `media_realm_tier?select=realm,tier&media_type=eq.${mt}&media_id=eq.${seedId}&limit=1`
      );
      if (tiers[0]) topRealm = tiers[0].realm;
    } catch {
      // matview may require auth; keep seed.realm
    }

    // Prefer similarity neighbors when RPC works; soft-fail to canon pool.
    let similar = [];
    try {
      similar = await rpc(url, anonKey, 'recommend_ids_similar_to_seeds', {
        p_media_type: mt,
        p_seed_ids: [seedId],
        p_limit: 25,
        p_allow_gimmicks: false,
      });
    } catch {
      similar = [];
    }

    const canonPool = [...byType[mt].values()]
      .filter((c) => c.media_id !== seedId)
      .slice(0, 40);

    const candidates = [];
    const seen = new Set();
    for (const s of similar) {
      const id = s.media_id;
      if (seen.has(id)) continue;
      seen.add(id);
      candidates.push({
        media_id: id,
        origin: 'gated_similarity',
        score: s.score ?? null,
        relevant: null,
      });
    }
    for (const c of canonPool) {
      if (seen.has(c.media_id)) continue;
      seen.add(c.media_id);
      candidates.push({
        media_id: c.media_id,
        title: c.title,
        origin: 'canon_seed',
        sources: c.sources,
        relevant: null,
      });
    }

    shortlines.push(JSON.stringify({
      seed_media_type: mt,
      seed_media_id: seedId,
      seed_title: seed.title || null,
      realm: topRealm,
      candidates: candidates.slice(0, 40),
    }));

    tmplLines.push(JSON.stringify({
      seed_media_type: mt,
      seed_media_id: seedId,
      seed_title: seed.title || null,
      realm: topRealm,
      relevant: [],
      rejected: [],
      notes: '',
      judged_by: 'owner',
      judged_at: null,
    }));

    await new Promise((r) => setTimeout(r, 30));
  }

  fs.writeFileSync(OUT_SHORT, shortlines.join('\n') + '\n');
  fs.writeFileSync(OUT_TMPL, tmplLines.join('\n') + '\n');
  console.log(`Wrote ${shortlines.length} shortlists → ${OUT_SHORT}`);
  console.log(`Wrote owner template → ${OUT_TMPL}`);
  console.log('Fill relevant[] / rejected[] then save as owner_judgments.jsonl');
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
