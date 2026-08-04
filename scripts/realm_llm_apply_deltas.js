#!/usr/bin/env node

/*
  Realm Graph Stage 2 — recompute membership deltas from media_realm_llm.
  Calls recompute_media_realm_llm_deltas (migration 20260802123000).

    node scripts/realm_llm_apply_deltas.js
    node scripts/realm_llm_apply_deltas.js --min-confidence 0.7

  Env:
    SUPABASE_SERVICE_ROLE_KEY  required
    SUPABASE_URL / SUPABASE_ANON_KEY  optional (xcconfig fallback)
*/

const fs = require('fs');
const path = require('path');

const XCCONFIG_PATH = path.join(__dirname, '..', 'Config', 'Shared.xcconfig');

function log(...args) { console.error('[deltas]', ...args); }

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
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !anonKey) throw new Error('Missing SUPABASE_URL / SUPABASE_ANON_KEY');
  if (!serviceKey) throw new Error('Missing SUPABASE_SERVICE_ROLE_KEY');
  return { url, anonKey, serviceKey };
}

function parseArgs(argv) {
  let minConfidence = 0.5;
  const list = argv.slice(2);
  for (let i = 0; i < list.length; i++) {
    if (list[i] === '--min-confidence' && list[i + 1]) {
      minConfidence = Number.parseFloat(list[++i]);
    } else {
      throw new Error(`Unknown arg: ${list[i]}`);
    }
  }
  if (!(minConfidence >= 0 && minConfidence <= 1)) {
    throw new Error('--min-confidence must be in [0,1]');
  }
  return { minConfidence };
}

async function main() {
  const args = parseArgs(process.argv);
  const cfg = loadConfig();
  log(`recompute min_confidence=${args.minConfidence}`);

  const res = await fetch(`${cfg.url}/rest/v1/rpc/recompute_media_realm_llm_deltas`, {
    method: 'POST',
    headers: {
      apikey: cfg.anonKey,
      Authorization: `Bearer ${cfg.serviceKey}`,
      'Content-Type': 'application/json',
      Prefer: 'return=representation',
    },
    body: JSON.stringify({
      p_min_confidence: args.minConfidence,
      p_model: 'llm-delta-recompute-2026-08',
    }),
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`RPC failed ${res.status}: ${text}`);
  }
  const n = JSON.parse(text);
  log(`wrote ${n} delta rows`);
  console.log(JSON.stringify({ delta_rows: n, min_confidence: args.minConfidence }, null, 2));
}

main().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
