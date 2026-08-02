#!/usr/bin/env node

/*
  Realm Graph Stage 2b — LLM descriptor pass: submit runner.
  Spec: docs/superpowers/specs/2026-07-31-realm-graph-master-plan.md §6

  Reads a JSONL file of descriptor rows (one JSON object per line, exactly the
  shape upsert_media_realm_llm expects), validates every row CLIENT-SIDE with
  the same rules as the RPC, then posts to the upsert_media_realm_llm RPC
  (migration 20260731170000) in batches of 100.

    node scripts/realm_llm_pass_submit.js descriptors.jsonl [--batch-size 100]
    node scripts/realm_llm_pass_submit.js descriptors.jsonl --dry-run

    --dry-run    Validate and print the exact RPC payloads that WOULD be sent.
                 No JWT required, no writes.

  Row shape (all keys required; unknown keys are stripped with a warning):
    media_type   'ANIME' | 'MANGA'
    media_id     positive integer (Kuro-internal id, from the fetch script)
    realms       1..3 of {"realm": <realm_meta.realm>, "weight": 0..1}, distinct
    tone         1..3 distinct words of the fixed 24-word vocabulary
    register     'family' | 'general' | 'seinen-otaku' | 'arthouse'
    pacing       'slow-burn' | 'steady' | 'relentless'
    confidence   number 0..1
    descriptor   string, 100..600 chars (PG char_length semantics: code points)
    model        writer id, e.g. 'kimi-swarm-2026-08'

  Validation is all-or-nothing per FILE before any network write: one bad row
  fails the whole file (fix the generator, don't ship a partial batch). The RPC
  re-validates server-side and is all-or-nothing per 100-row call.

  Rate limit: the RPC allows 60 accepted calls/hour/user (fixed epoch-aligned
  hourly windows). On RATE_LIMITED the script sleeps until the next window, up
  to 3 waits, then aborts. Reruns are safe: the RPC is an upsert.

  Env:
    KURO_TEST_JWT        Bearer token (test account). Required unless --dry-run.
    SUPABASE_URL         Optional override; default parsed from Config/Shared.xcconfig.
    SUPABASE_ANON_KEY    Optional override; default parsed from Config/Shared.xcconfig.
*/

const fs = require('fs');
const path = require('path');

const BATCH_SIZE_DEFAULT = 100; // the RPC hard-validates <= 100 rows per call
const RATE_LIMIT_MAX_WAITS = 3;
const XCCONFIG_PATH = path.join(__dirname, '..', 'Config', 'Shared.xcconfig');

// The fixed 24-word tone vocabulary (spec §6; mirrored in the RPC).
const TONE_VOCAB = new Set([
  'whimsical', 'melancholic', 'brutal', 'cozy', 'cerebral', 'kinetic',
  'tender', 'eerie', 'absurd', 'earnest', 'dark', 'warm',
  'bleak', 'playful', 'solemn', 'lush', 'gritty', 'dreamlike',
  'frantic', 'intimate', 'epic', 'quiet', 'hysterical', 'meditative',
]);
const REGISTERS = new Set(['family', 'general', 'seinen-otaku', 'arthouse']);
const PACINGS = new Set(['slow-burn', 'steady', 'relentless']);
const KNOWN_KEYS = new Set(['media_type', 'media_id', 'realms', 'tone', 'register', 'pacing', 'confidence', 'descriptor', 'model']);

function log(...args) { console.error('[submit]', ...args); }

function sleep(ms) { return new Promise(resolve => setTimeout(resolve, ms)); }

function charLen(s) { return [...s].length; } // PG char_length counts code points

function parseArgs(argv) {
  const args = { file: null, dryRun: false, batchSize: BATCH_SIZE_DEFAULT };
  const list = argv.slice(2);
  for (let i = 0; i < list.length; i++) {
    if (list[i] === '--dry-run') {
      args.dryRun = true;
    } else if (list[i] === '--batch-size' && list[i + 1]) {
      args.batchSize = Number.parseInt(list[++i], 10);
    } else if (!list[i].startsWith('--') && args.file === null) {
      args.file = list[i];
    } else {
      throw new Error(`Unknown argument: ${list[i]} (usage: <rows.jsonl> [--dry-run] [--batch-size N])`);
    }
  }
  if (!args.file) throw new Error('Missing JSONL file argument.');
  if (!Number.isInteger(args.batchSize) || args.batchSize < 1 || args.batchSize > 100) {
    throw new Error('--batch-size must be 1..100 (the RPC rejects batches over 100).');
  }
  return args;
}

function loadSupabaseConfig() {
  const values = {};
  if (fs.existsSync(XCCONFIG_PATH)) {
    for (const line of fs.readFileSync(XCCONFIG_PATH, 'utf8').split(/\r?\n/)) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('//')) continue;
      const idx = trimmed.indexOf('=');
      if (idx <= 0) continue;
      const key = trimmed.slice(0, idx).trim();
      // xcconfig escapes a literal "/" as "$()/" — strip the escape.
      values[key] = trimmed.slice(idx + 1).trim().replace(/\$\(\)/g, '');
    }
  }
  const url = process.env.SUPABASE_URL || values.SUPABASE_URL;
  const anonKey = process.env.SUPABASE_ANON_KEY || values.SUPABASE_ANON_KEY;
  if (!url || !anonKey) {
    throw new Error('Missing SUPABASE_URL / SUPABASE_ANON_KEY (env or Config/Shared.xcconfig).');
  }
  return { url: url.replace(/\/+$/, ''), anonKey, jwt: process.env.KURO_TEST_JWT || null };
}

// ---------------------------------------------------------------------------
// Client-side validation (mirrors upsert_media_realm_llm's server-side rules)
// ---------------------------------------------------------------------------

async function fetchRealmNames(config) {
  try {
    const response = await fetch(`${config.url}/rest/v1/realm_meta?select=realm`, {
      headers: { apikey: config.anonKey, Authorization: `Bearer ${config.anonKey}` },
    });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const rows = await response.json();
    return new Set(rows.map(r => r.realm));
  } catch (error) {
    log(`WARNING: could not fetch realm_meta (${error.message}) — realm names will only be validated server-side.`);
    return null;
  }
}

function validateRow(row, realms) {
  const errors = [];
  if (row === null || typeof row !== 'object' || Array.isArray(row)) {
    return ['row must be a JSON object'];
  }

  if (row.media_type !== 'ANIME' && row.media_type !== 'MANGA') {
    errors.push(`media_type must be 'ANIME' or 'MANGA' (got ${JSON.stringify(row.media_type)})`);
  }
  if (!Number.isInteger(row.media_id) || row.media_id < 1 || row.media_id > 2147483647) {
    errors.push(`media_id must be a positive integer (got ${JSON.stringify(row.media_id)})`);
  }

  if (!Array.isArray(row.realms) || row.realms.length < 1 || row.realms.length > 3) {
    errors.push('realms must be an array of 1..3 entries');
  } else {
    const seen = new Set();
    row.realms.forEach((entry, i) => {
      if (entry === null || typeof entry !== 'object' || Array.isArray(entry)) {
        errors.push(`realms[${i}] must be an object {"realm","weight"}`);
        return;
      }
      if (typeof entry.realm !== 'string' || entry.realm.length === 0) {
        errors.push(`realms[${i}].realm must be a non-empty string`);
      } else {
        if (realms && !realms.has(entry.realm)) {
          errors.push(`realms[${i}].realm '${entry.realm}' is not in realm_meta`);
        }
        if (seen.has(entry.realm)) {
          errors.push(`duplicate realm '${entry.realm}'`);
        }
        seen.add(entry.realm);
      }
      if (typeof entry.weight !== 'number' || !Number.isFinite(entry.weight) || entry.weight < 0 || entry.weight > 1) {
        errors.push(`realms[${i}].weight must be a number 0..1 (got ${JSON.stringify(entry.weight)})`);
      }
    });
  }

  if (!Array.isArray(row.tone) || row.tone.length < 1 || row.tone.length > 3) {
    errors.push('tone must be an array of 1..3 words');
  } else {
    const seen = new Set();
    row.tone.forEach((word, i) => {
      if (typeof word !== 'string' || !TONE_VOCAB.has(word)) {
        errors.push(`tone[${i}] ${JSON.stringify(word)} is outside the 24-word vocabulary`);
        return;
      }
      if (seen.has(word)) errors.push(`duplicate tone word '${word}'`);
      seen.add(word);
    });
  }

  if (!REGISTERS.has(row.register)) {
    errors.push(`register must be one of ${[...REGISTERS].join('/')} (got ${JSON.stringify(row.register)})`);
  }
  if (!PACINGS.has(row.pacing)) {
    errors.push(`pacing must be one of ${[...PACINGS].join('/')} (got ${JSON.stringify(row.pacing)})`);
  }
  if (typeof row.confidence !== 'number' || !Number.isFinite(row.confidence) || row.confidence < 0 || row.confidence > 1) {
    errors.push(`confidence must be a number 0..1 (got ${JSON.stringify(row.confidence)})`);
  }
  if (typeof row.descriptor !== 'string' || charLen(row.descriptor) < 100 || charLen(row.descriptor) > 600) {
    errors.push(`descriptor must be a string of 100..600 chars (got ${typeof row.descriptor === 'string' ? charLen(row.descriptor) + ' chars' : JSON.stringify(row.descriptor)})`);
  }
  if (typeof row.model !== 'string' || row.model.trim().length < 1 || charLen(row.model) > 100) {
    errors.push('model must be a string of 1..100 chars');
  }
  return errors;
}

function cleanRow(row) {
  return {
    media_type: row.media_type,
    media_id: row.media_id,
    realms: row.realms.map(e => ({ realm: e.realm, weight: e.weight })),
    tone: [...row.tone],
    register: row.register,
    pacing: row.pacing,
    confidence: row.confidence,
    descriptor: row.descriptor,
    model: row.model,
  };
}

function readAndValidate(filePath, realmNames) {
  const text = fs.readFileSync(filePath, 'utf8');
  const rows = [];
  const problems = [];
  let strippedKeys = 0;

  text.split(/\r?\n/).forEach((line, index) => {
    const lineNo = index + 1;
    if (!line.trim()) return;
    let parsed;
    try {
      parsed = JSON.parse(line);
    } catch (error) {
      problems.push(`line ${lineNo}: invalid JSON (${error.message})`);
      return;
    }
    const errors = validateRow(parsed, realmNames);
    for (const err of errors) problems.push(`line ${lineNo}: ${err}`);
    if (errors.length === 0) {
      const unknown = Object.keys(parsed).filter(k => !KNOWN_KEYS.has(k));
      if (unknown.length > 0) {
        strippedKeys += unknown.length;
        log(`line ${lineNo}: stripping unknown key(s): ${unknown.join(', ')}`);
      }
      rows.push(cleanRow(parsed));
    }
  });

  return { rows, problems, strippedKeys };
}

// ---------------------------------------------------------------------------
// RPC
// ---------------------------------------------------------------------------

async function postBatch(config, rows) {
  for (let waits = 0;;) {
    const response = await fetch(`${config.url}/rest/v1/rpc/upsert_media_realm_llm`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        apikey: config.anonKey,
        Authorization: `Bearer ${config.jwt}`,
      },
      body: JSON.stringify({ p_rows: rows }),
    });

    if (response.ok) {
      const text = await response.text();
      const count = Number.parseInt(text, 10);
      return { ok: true, count: Number.isFinite(count) ? count : 0 };
    }

    const body = await response.text();
    if (body.includes('RATE_LIMITED')) {
      waits += 1;
      if (waits > RATE_LIMIT_MAX_WAITS) {
        return { ok: false, error: 'RATE_LIMITED persisted across 3 hourly windows — aborting (rerun to resume; the RPC is an upsert).' };
      }
      // rate_limit_hit uses fixed epoch-aligned hourly windows.
      const waitMs = 3600000 - (Date.now() % 3600000) + 5000;
      log(`RATE_LIMITED (60 accepted calls/hour) — sleeping ${Math.round(waitMs / 60000)}min until next window (wait ${waits}/${RATE_LIMIT_MAX_WAITS})`);
      await sleep(waitMs);
      continue;
    }
    if (response.status >= 500) {
      await sleep(2000);
      continue;
    }
    return { ok: false, error: `HTTP ${response.status}: ${body.slice(0, 500)}` };
  }
}

// ---------------------------------------------------------------------------

async function main() {
  const args = parseArgs(process.argv);
  const config = loadSupabaseConfig();
  if (!args.dryRun && !config.jwt) {
    throw new Error('Missing KURO_TEST_JWT env var (bearer for upsert_media_realm_llm). Only --dry-run works without it.');
  }

  const realmNames = await fetchRealmNames(config);
  if (realmNames) log(`realm vocabulary: ${realmNames.size} realms from realm_meta`);

  const { rows, problems, strippedKeys } = readAndValidate(args.file, realmNames);
  if (problems.length > 0) {
    for (const p of problems) console.error(p);
    throw new Error(`${problems.length} validation problem(s) in ${args.file} — nothing was sent. Fix the generator output and rerun.`);
  }
  if (rows.length === 0) {
    throw new Error(`No rows found in ${args.file}.`);
  }
  log(`validated ${rows.length} row(s) from ${args.file}${strippedKeys ? ` (${strippedKeys} unknown key(s) stripped)` : ''}`);

  const batches = [];
  for (let i = 0; i < rows.length; i += args.batchSize) {
    batches.push(rows.slice(i, i + args.batchSize));
  }

  if (args.dryRun) {
    for (let i = 0; i < batches.length; i++) {
      console.log(`--- batch ${i + 1}/${batches.length} (${batches[i].length} row(s)) — POST body that WOULD be sent:`);
      console.log(JSON.stringify({ p_rows: batches[i] }, null, 2));
    }
    console.log(`[dry-run] ${rows.length} row(s) in ${batches.length} batch(es) validated; no requests sent, nothing written.`);
    return;
  }

  let totalUpserted = 0;
  const failures = [];
  for (let i = 0; i < batches.length; i++) {
    const result = await postBatch(config, batches[i]);
    if (result.ok) {
      totalUpserted += result.count;
      console.log(`[batch ${i + 1}/${batches.length}] ok — upserted=${result.count}`);
    } else {
      failures.push({ batch: i + 1, error: result.error });
      console.error(`[batch ${i + 1}/${batches.length}] FAILED — ${result.error}`);
      if (result.error.startsWith('RATE_LIMITED persisted')) break; // no point continuing this run
    }
  }
  console.log(`[submit] done. rows_valid=${rows.length} upserted=${totalUpserted} batches_ok=${batches.length - failures.length}/${batches.length}`);
  if (failures.length > 0) {
    throw new Error(`${failures.length} batch(es) failed (see above). Reruns are safe: the RPC is an upsert.`);
  }
}

main().catch(error => {
  console.error(error.message || error);
  process.exit(1);
});
