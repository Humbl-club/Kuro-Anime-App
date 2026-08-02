#!/usr/bin/env node

/*
  Salvage leftover agent-swarm descriptor JSONL into media_realm_llm.
  Spec: docs/superpowers/specs/2026-08-02-realm-descriptor-groq-pipeline-design.md

  Usage:
    node scripts/realm_llm_salvage_swarm.js [--dir /tmp] [--dry-run]
    node scripts/realm_llm_salvage_swarm.js --out /tmp/realm_salvage_clean.jsonl --dry-run

  Finds /tmp/realm_out_*.jsonl (or --dir), validates each line with the same
  rules as realm_llm_pass_submit.js, writes a clean JSONL, then optionally
  submits via scripts/realm_llm_pass_submit.js (unless --dry-run).
*/

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const TONE_VOCAB = new Set([
  'whimsical', 'melancholic', 'brutal', 'cozy', 'cerebral', 'kinetic',
  'tender', 'eerie', 'absurd', 'earnest', 'dark', 'warm',
  'bleak', 'playful', 'solemn', 'lush', 'gritty', 'dreamlike',
  'frantic', 'intimate', 'epic', 'quiet', 'hysterical', 'meditative',
]);
const REGISTERS = new Set(['family', 'general', 'seinen-otaku', 'arthouse']);
const PACINGS = new Set(['slow-burn', 'steady', 'relentless']);
const XCCONFIG_PATH = path.join(__dirname, '..', 'Config', 'Shared.xcconfig');

function log(...args) { console.error('[salvage]', ...args); }
function charLen(s) { return [...s].length; }

function parseArgs(argv) {
  const args = { dir: '/tmp', out: '/tmp/realm_salvage_clean.jsonl', dryRun: false };
  const list = argv.slice(2);
  for (let i = 0; i < list.length; i++) {
    if (list[i] === '--dir' && list[i + 1]) args.dir = list[++i];
    else if (list[i] === '--out' && list[i + 1]) args.out = list[++i];
    else if (list[i] === '--dry-run') args.dryRun = true;
    else throw new Error(`Unknown argument: ${list[i]}`);
  }
  return args;
}

function loadAnonConfig() {
  const values = {};
  if (fs.existsSync(XCCONFIG_PATH)) {
    for (const line of fs.readFileSync(XCCONFIG_PATH, 'utf8').split(/\r?\n/)) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('//')) continue;
      const idx = trimmed.indexOf('=');
      if (idx <= 0) continue;
      values[trimmed.slice(0, idx).trim()] = trimmed.slice(idx + 1).trim().replace(/\$\(\)/g, '');
    }
  }
  const url = (process.env.SUPABASE_URL || values.SUPABASE_URL || '').replace(/\/+$/, '');
  const anonKey = process.env.SUPABASE_ANON_KEY || values.SUPABASE_ANON_KEY;
  if (!url || !anonKey) throw new Error('Missing SUPABASE_URL / SUPABASE_ANON_KEY');
  return { url, anonKey };
}

async function fetchRealmNames(config) {
  const response = await fetch(`${config.url}/rest/v1/realm_meta?select=realm`, {
    headers: { apikey: config.anonKey, Authorization: `Bearer ${config.anonKey}` },
  });
  if (!response.ok) throw new Error(`realm_meta HTTP ${response.status}`);
  return new Set((await response.json()).map((r) => r.realm));
}

function validateRow(row, realms) {
  const errors = [];
  if (!row || typeof row !== 'object' || Array.isArray(row)) return ['not an object'];
  if (row.media_type !== 'ANIME' && row.media_type !== 'MANGA') errors.push('media_type');
  if (!Number.isInteger(row.media_id) || row.media_id < 1) errors.push('media_id');
  if (!Array.isArray(row.realms) || row.realms.length < 1 || row.realms.length > 3) {
    errors.push('realms length');
  } else {
    const seen = new Set();
    for (const e of row.realms) {
      if (!e || typeof e.realm !== 'string' || !realms.has(e.realm)) errors.push(`realm ${e && e.realm}`);
      if (typeof e.weight !== 'number' || e.weight < 0 || e.weight > 1) errors.push('weight');
      if (seen.has(e.realm)) errors.push('dup realm');
      seen.add(e.realm);
    }
  }
  if (!Array.isArray(row.tone) || row.tone.length < 1 || row.tone.length > 3) errors.push('tone');
  else {
    const seen = new Set();
    for (const w of row.tone) {
      if (!TONE_VOCAB.has(w)) errors.push(`tone ${w}`);
      if (seen.has(w)) errors.push('dup tone');
      seen.add(w);
    }
  }
  if (!REGISTERS.has(row.register)) errors.push('register');
  if (!PACINGS.has(row.pacing)) errors.push('pacing');
  if (typeof row.confidence !== 'number' || row.confidence < 0 || row.confidence > 1) errors.push('confidence');
  if (typeof row.descriptor !== 'string' || charLen(row.descriptor) < 100 || charLen(row.descriptor) > 600) {
    errors.push('descriptor');
  }
  if (typeof row.model !== 'string' || !row.model.trim()) {
    row.model = 'kimi-swarm-2026-08';
  }
  return errors;
}

function cleanRow(row) {
  return {
    media_type: row.media_type,
    media_id: row.media_id,
    realms: row.realms.map((e) => ({ realm: e.realm, weight: e.weight })),
    tone: [...row.tone],
    register: row.register,
    pacing: row.pacing,
    confidence: row.confidence,
    descriptor: row.descriptor,
    model: row.model || 'kimi-swarm-2026-08',
  };
}

function collectFiles(dir) {
  return fs.readdirSync(dir)
    .filter((n) => /^realm_out_\d+\.jsonl$/.test(n))
    .map((n) => path.join(dir, n))
    .sort();
}

async function main() {
  const args = parseArgs(process.argv);
  const config = loadAnonConfig();
  const realms = await fetchRealmNames(config);
  log(`realm vocabulary: ${realms.size}`);

  const files = collectFiles(args.dir);
  if (files.length === 0) throw new Error(`No realm_out_*.jsonl in ${args.dir}`);
  log(`found ${files.length} jsonl file(s)`);

  const byKey = new Map(); // media_type|id -> row (last wins)
  let rawLines = 0;
  let invalid = 0;
  const problemSamples = [];

  for (const file of files) {
    for (const line of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
      if (!line.trim()) continue;
      rawLines += 1;
      let parsed;
      try {
        parsed = JSON.parse(line);
      } catch {
        invalid += 1;
        if (problemSamples.length < 8) problemSamples.push(`${path.basename(file)}: bad JSON`);
        continue;
      }
      const errors = validateRow(parsed, realms);
      if (errors.length) {
        invalid += 1;
        if (problemSamples.length < 8) {
          problemSamples.push(`${path.basename(file)} ${parsed.media_type}:${parsed.media_id}: ${errors.join(',')}`);
        }
        continue;
      }
      const clean = cleanRow(parsed);
      byKey.set(`${clean.media_type}|${clean.media_id}`, clean);
    }
  }

  const rows = [...byKey.values()].sort((a, b) =>
    a.media_type.localeCompare(b.media_type) || a.media_id - b.media_id
  );
  fs.writeFileSync(args.out, rows.map((r) => JSON.stringify(r)).join('\n') + (rows.length ? '\n' : ''));
  log(`raw_lines=${rawLines} invalid=${invalid} unique_valid=${rows.length}`);
  log(`wrote ${args.out}`);
  for (const s of problemSamples) log(`sample_problem: ${s}`);

  if (args.dryRun) {
    log('dry-run: not submitting');
    console.log(JSON.stringify({ rawLines, invalid, uniqueValid: rows.length, out: args.out }, null, 2));
    return;
  }

  if (rows.length === 0) throw new Error('No valid rows to submit');
  if (!process.env.KURO_TEST_JWT) {
    throw new Error('KURO_TEST_JWT required to submit (or pass --dry-run)');
  }

  const submit = path.join(__dirname, 'realm_llm_pass_submit.js');
  const result = spawnSync(process.execPath, [submit, args.out], {
    stdio: 'inherit',
    env: process.env,
  });
  if (result.status !== 0) process.exit(result.status || 1);
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
