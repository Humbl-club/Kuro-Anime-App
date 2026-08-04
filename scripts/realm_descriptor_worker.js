#!/usr/bin/env node

/*
  Realm Graph Stage 2b — checkpointed driver for realm-describe.
  Spec: docs/superpowers/specs/2026-08-02-realm-descriptor-groq-pipeline-design.md

  Pages media_realm_llm_pending, calls the realm-describe edge function
  (IMPORT_SECRET), checkpoints every 25 titles.

  Usage:
    node scripts/realm_descriptor_worker.js --dry-run --limit 3
    node scripts/realm_descriptor_worker.js --limit 50
    node scripts/realm_descriptor_worker.js --batch --batch-size 10 --limit 100

  --batch        Use function batch mode (one HTTP call per batch-size titles)
  --concurrency N  Parallel single-title calls (default 3; ignored with --batch)
  --limit N
  --offset N     Skip first N pending rows (after checkpoint skips)
  --dry-run      Print what WOULD be sent; no HTTP to the function

  Env:
    IMPORT_SECRET     required unless --dry-run
    KURO_TEST_JWT     required to read media_realm_llm_pending
    SUPABASE_URL / SUPABASE_ANON_KEY  optional (xcconfig fallback)
*/

const fs = require('fs');
const path = require('path');

const PROGRESS_PATH = path.join(__dirname, '.realm_descriptor_progress.json');
const XCCONFIG_PATH = path.join(__dirname, '..', 'Config', 'Shared.xcconfig');
const QUEUE_PAGE = 50;
const DEFAULT_CONCURRENCY = 3;
const CHECKPOINT_EVERY = 25;

function log(...args) { console.error('[worker]', ...args); }
function sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }

function parseArgs(argv) {
  const args = {
    limit: null,
    offset: 0,
    dryRun: false,
    batch: false,
    batchSize: 10,
    concurrency: DEFAULT_CONCURRENCY,
  };
  const list = argv.slice(2);
  for (let i = 0; i < list.length; i++) {
    const a = list[i];
    if (a === '--dry-run') args.dryRun = true;
    else if (a === '--batch') args.batch = true;
    else if (a === '--limit' && list[i + 1]) args.limit = Number.parseInt(list[++i], 10);
    else if (a === '--offset' && list[i + 1]) args.offset = Number.parseInt(list[++i], 10);
    else if (a === '--batch-size' && list[i + 1]) args.batchSize = Number.parseInt(list[++i], 10);
    else if (a === '--concurrency' && list[i + 1]) args.concurrency = Number.parseInt(list[++i], 10);
    else throw new Error(`Unknown argument: ${a}`);
  }
  if (args.limit != null && (!Number.isInteger(args.limit) || args.limit < 1)) {
    throw new Error('--limit must be a positive integer');
  }
  if (!Number.isInteger(args.batchSize) || args.batchSize < 1 || args.batchSize > 25) {
    throw new Error('--batch-size must be 1..25');
  }
  if (!Number.isInteger(args.concurrency) || args.concurrency < 1 || args.concurrency > 8) {
    throw new Error('--concurrency must be 1..8');
  }
  return args;
}

function loadConfig() {
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
  const jwt = process.env.KURO_TEST_JWT || null;
  const importSecret = process.env.IMPORT_SECRET || process.env.SUPABASE_IMPORT_SECRET || null;
  if (!url || !anonKey) throw new Error('Missing SUPABASE_URL / SUPABASE_ANON_KEY');
  return { url, anonKey, jwt, importSecret };
}

function functionsBase(url) {
  const host = new URL(url).host.replace('.supabase.co', '.functions.supabase.co');
  return `https://${host}`;
}

function loadProgress() {
  const done = new Set();
  if (!fs.existsSync(PROGRESS_PATH)) return done;
  for (const line of fs.readFileSync(PROGRESS_PATH, 'utf8').split(/\r?\n/)) {
    if (!line.trim()) continue;
    try {
      const row = JSON.parse(line);
      if (row.media_type && row.media_id != null && row.ok) {
        done.add(`${row.media_type}|${row.media_id}`);
      }
    } catch {
      // ignore corrupt lines
    }
  }
  return done;
}

function appendProgress(rows) {
  if (rows.length === 0) return;
  fs.appendFileSync(
    PROGRESS_PATH,
    rows.map((r) => JSON.stringify(r)).join('\n') + '\n',
    'utf8',
  );
}

async function restGet(config, pathAndQuery) {
  const response = await fetch(`${config.url}/rest/v1/${pathAndQuery}`, {
    headers: {
      apikey: config.anonKey,
      Authorization: `Bearer ${config.jwt || config.anonKey}`,
    },
  });
  if (!response.ok) {
    const text = await response.text();
    throw new Error(`REST ${pathAndQuery.slice(0, 80)} HTTP ${response.status}: ${text.slice(0, 200)}`);
  }
  return response.json();
}

async function fetchPending(config, limit, offset) {
  const out = [];
  let cursor = offset;
  const target = limit == null ? Number.POSITIVE_INFINITY : limit;
  while (out.length < target) {
    const pageSize = Math.min(QUEUE_PAGE, Number.isFinite(target) ? target - out.length : QUEUE_PAGE);
    const page = await restGet(
      config,
      `media_realm_llm_pending?select=media_type,media_id,title,popularity` +
      `&order=popularity.desc,media_type.asc,media_id.asc&limit=${pageSize}&offset=${cursor}`,
    );
    if (page.length === 0) break;
    out.push(...page);
    cursor += page.length;
    if (page.length < pageSize) break;
  }
  return out;
}

async function callDescribe(config, body) {
  const response = await fetch(`${functionsBase(config.url)}/realm-describe`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: config.anonKey,
      Authorization: `Bearer ${config.anonKey}`,
      'x-import-secret': config.importSecret,
    },
    body: JSON.stringify(body),
  });
  const text = await response.text();
  let parsed;
  try { parsed = JSON.parse(text); } catch { parsed = { raw: text.slice(0, 300) }; }
  if (!response.ok) {
    const err = new Error(`realm-describe HTTP ${response.status}: ${text.slice(0, 400)}`);
    err.status = response.status;
    err.body = parsed;
    throw err;
  }
  return parsed;
}

async function mapPool(items, concurrency, fn) {
  const results = new Array(items.length);
  let next = 0;
  async function worker() {
    for (;;) {
      const i = next++;
      if (i >= items.length) return;
      results[i] = await fn(items[i], i);
    }
  }
  await Promise.all(Array.from({ length: Math.min(concurrency, items.length) }, () => worker()));
  return results;
}

async function main() {
  const args = parseArgs(process.argv);
  const config = loadConfig();
  if (!config.jwt) throw new Error('Missing KURO_TEST_JWT (pending view is authenticated-only)');
  if (!args.dryRun && !config.importSecret) {
    throw new Error('Missing IMPORT_SECRET (or SUPABASE_IMPORT_SECRET)');
  }

  const done = loadProgress();
  log(`checkpoint already_ok=${done.size}`);

  const pending = await fetchPending(config, args.limit, args.offset);
  const todo = pending.filter((p) => !done.has(`${p.media_type}|${p.media_id}`));
  log(`pending_fetched=${pending.length} after_checkpoint=${todo.length} dryRun=${args.dryRun} batch=${args.batch}`);

  if (todo.length === 0) {
    console.log(JSON.stringify({ done: true, fetched: pending.length, remaining: 0 }));
    return;
  }

  if (args.dryRun) {
    const sample = todo.slice(0, Math.min(3, todo.length));
    for (const p of sample) {
      const body = args.batch
        ? { batch: true, limit: args.batchSize }
        : { media_type: p.media_type, media_id: p.media_id };
      console.log('--- WOULD POST /realm-describe');
      console.log(JSON.stringify(body, null, 2));
      console.log(`# title hint: ${p.title || '?'} pop=${p.popularity}`);
      if (args.batch) break;
    }
    console.log(`[dry-run] would process ${todo.length} title(s); nothing sent.`);
    return;
  }

  let ok = 0;
  let fail = 0;
  const pendingProgress = [];

  const flush = () => {
    if (pendingProgress.length === 0) return;
    appendProgress(pendingProgress.splice(0, pendingProgress.length));
  };

  // Only checkpoint successes. Failures (esp. 429) must retry later and
  // should not bloat the progress file.
  const recordOk = (mediaType, mediaId) => {
    pendingProgress.push({
      media_type: mediaType,
      media_id: mediaId,
      ok: true,
      error: null,
      at: new Date().toISOString(),
    });
    ok += 1;
  };

  if (args.batch) {
    let rateLimitedStreak = 0;
    for (let i = 0; i < todo.length; ) {
      const slice = todo.slice(i, i + args.batchSize);
      let batchOk = 0;
      let batchFail = 0;
      let hit429 = false;
      let retryHintSec = null;
      try {
        const result = await callDescribe(config, { batch: true, limit: slice.length });
        for (const r of result.results || []) {
          if (r.ok) {
            recordOk(r.media_type, r.media_id);
            batchOk += 1;
          } else {
            batchFail += 1;
            fail += 1;
            const err = r.error || '';
            if (err.includes('429') || /rate limit/i.test(err)) hit429 = true;
            const m = err.match(/try again in ([0-9.]+)\s*s/i);
            if (m) retryHintSec = Math.max(retryHintSec || 0, Number(m[1]));
            log(`fail ${r.media_type}:${r.media_id} ${err.slice(0, 160)}`);
          }
        }
        if (!result.results || result.results.length === 0) {
          batchFail = slice.length;
          fail += slice.length;
        }
      } catch (e) {
        const msg = e.message || String(e);
        log(`batch error: ${msg.slice(0, 220)}`);
        batchFail = slice.length;
        fail += slice.length;
        if (msg.includes('429') || /rate limit/i.test(msg) || e.status === 429) hit429 = true;
        const m = msg.match(/try again in ([0-9.]+)\s*s/i);
        if (m) retryHintSec = Number(m[1]);
        if (e.status === 401) break;
      }

      flush();
      log(`progress ok=${ok} fail=${fail} / ${todo.length} (batch +${batchOk}/-${batchFail})`);

      if (hit429 || batchOk === 0) {
        rateLimitedStreak += 1;
        const exponential = Math.min(600000, 60000 * (2 ** Math.min(rateLimitedStreak - 1, 4)));
        const hinted = retryHintSec != null
          ? Math.min(600000, Math.ceil(retryHintSec * 1000) + 2000)
          : null;
        const cool = Math.max(exponential, hinted || 0);
        log(`rate-limit cool-down ${Math.round(cool / 1000)}s (streak=${rateLimitedStreak}${hinted != null ? ` hint=${retryHintSec}s` : ''})`);
        await sleep(cool);
        if (batchOk > 0) {
          rateLimitedStreak = 0;
          i += args.batchSize;
        } else if (rateLimitedStreak >= 4) {
          log('rate-limit streak high — yielding to outer drain loop');
          break;
        }
      } else {
        rateLimitedStreak = 0;
        i += args.batchSize;
        // ~1 title / 25–30s keeps on_demand TPM (~8k) healthy for llama-3.3-70b.
        await sleep(Math.max(25000, slice.length * 20000));
      }
    }
  } else {
    await mapPool(todo, args.concurrency, async (p) => {
      try {
        await callDescribe(config, { media_type: p.media_type, media_id: p.media_id });
        recordOk(p.media_type, p.media_id);
      } catch (e) {
        fail += 1;
        log(`fail ${p.media_type}:${p.media_id} ${e.message}`);
      }
      if (pendingProgress.length >= CHECKPOINT_EVERY) flush();
      if ((ok + fail) % 25 === 0) log(`progress ok=${ok} fail=${fail} / ${todo.length}`);
    });
  }

  flush();
  console.log(JSON.stringify({ ok, fail, total: todo.length, progress: PROGRESS_PATH }));
  // Exit 0 even with partial failures so the outer drain keeps looping;
  // exit 1 only when we made zero progress (likely hard misconfig).
  if (ok === 0 && fail > 0) process.exit(1);
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
