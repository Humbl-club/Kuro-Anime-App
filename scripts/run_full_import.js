/*
  Orchestrates full imports using deployed Supabase Edge Functions and mirrors images.
  - Ensures import_state rows exist (ANIME/MANGA)
  - Repeatedly invokes bulk-import-anime and bulk-import-manga with useCursor/runToEnd
  - Sweeps mirror-images across ANIME/MANGA/CHARACTER/STAFF with offsets
  - Requires IMPORT_SECRET header for function auth
*/

const { createClient } = require('@supabase/supabase-js');
const { getProjectUrl } = require('./lib/project_config');

const SUPABASE_URL = getProjectUrl();
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const IMPORT_SECRET = process.env.IMPORT_SECRET ?? process.env.SUPABASE_IMPORT_SECRET;
if (!SERVICE_ROLE_KEY) {
  throw new Error('Missing SUPABASE_SERVICE_ROLE_KEY env var.');
}
if (!IMPORT_SECRET) {
  throw new Error('Missing IMPORT_SECRET (or SUPABASE_IMPORT_SECRET) env var.');
}

const FUNCTIONS_BASE = `https://${new URL(SUPABASE_URL).host.replace('.supabase.co', '.functions.supabase.co')}`;
const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

async function ensureImportState() {
  try {
    await supabase
      .from('import_state')
      .upsert(
        [
          { media_type: 'ANIME', last_page: 0 },
          { media_type: 'MANGA', last_page: 0 },
        ],
        { onConflict: 'media_type', ignoreDuplicates: true }
      );
  } catch (e) {
    console.log('⚠️ Could not seed import_state (table missing?). Will proceed without cursor.');
  }
}

async function getLastPage(mediaType) {
  const { data, error } = await supabase.from('import_state').select('last_page').eq('media_type', mediaType).maybeSingle();
  if (error) return null;
  return data?.last_page ?? null;
}

async function callFunction(name, payload) {
  const url = `${FUNCTIONS_BASE}/${name}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
      'x-import-secret': IMPORT_SECRET,
    },
    body: JSON.stringify(payload),
  });
  const text = await res.text();
  try { return { status: res.status, json: JSON.parse(text) }; } catch { return { status: res.status, text }; }
}

function shouldFallback(response) {
  if (!response) return false;
  if (response.status === 504 || response.status === 524) return true;
  const message = `${response.json?.error ?? ''} ${response.text ?? ''}`.toLowerCase();
  return message.includes('timeout') || message.includes('timed out');
}

function buildFallbackPayload(kind, options = {}) {
  const safe = {
    useCursor: true,
    runToEnd: false,
    scheduleSafe: true,
    lightweight: true,
    pagesPerBatch: 1,
    maxPagesPerRun: 1,
    perPage: 10,
    delayMs: 100,
    timeBudgetMs: 10_000,
    lockTtlSeconds: 120,
  };
  if (kind === 'ANIME') {
    return {
      ...safe,
      includeRelations: false,
      includeEpisodes: false,
      ...(options.fallbackPayload ?? {}),
    };
  }
  return {
    ...safe,
    includeRelations: false,
    includeChapters: false,
    includeVolumes: false,
    maxPlaceholderChapters: 0,
    maxPlaceholderVolumes: 0,
    ...(options.fallbackPayload ?? {}),
  };
}

async function runImporter(kind, options = {}) {
  const func = kind === 'ANIME' ? 'bulk-import-anime' : 'bulk-import-manga';
  let useCursor = true;
  let last = await getLastPage(kind);
  if (last === null) useCursor = false; // table missing or inaccessible
  console.log(`\n▶️ Starting ${kind} import (cursor=${useCursor})…`);

  let stagnant = 0;
  const maxLoops = options.maxLoops ?? 10; // adjust as needed for long backfills
  for (let i = 0; i < maxLoops; i++) {
    const payload = {
      useCursor,
      runToEnd: true,
      pagesPerBatch: 10,
      maxPagesPerRun: 200,
      timeBudgetMs: 54000,
      ...(options.payload ?? {}),
    };
    const r = await callFunction(func, payload);
    if (r.status !== 200 || !r.json?.success) {
      const reason = r.json?.error || r.text || '';
      console.log(`❌ ${func} failed [${r.status}]:`, reason);
      if (shouldFallback(r)) {
        const fallbackPayload = buildFallbackPayload(kind, options);
        console.log(`↪️ ${func} timeout detected, running schedule-safe fallback batch…`);
        const fallback = await callFunction(func, fallbackPayload);
        if (fallback.status === 200 && fallback.json?.success) {
          console.log(`✅ ${func} fallback results:`, fallback.json.results);
          if (useCursor) {
            const now = await getLastPage(kind);
            console.log(`   last_page: ${last} -> ${now}`);
            if (now === null || now === last) {
              stagnant++;
            } else {
              stagnant = 0; last = now;
            }
            if (stagnant >= 2) {
              console.log('ℹ️ No further progress detected after fallback; stopping importer loop.');
              break;
            }
          }
          continue;
        }
        console.log(`❌ ${func} fallback failed [${fallback.status}]:`, fallback.json?.error || fallback.text);
      }
      break;
    }
    console.log(`✅ ${func} results:`, r.json.results);
    if (useCursor) {
      const now = await getLastPage(kind);
      console.log(`   last_page: ${last} -> ${now}`);
      if (now === null || now === last) {
        stagnant++;
      } else {
        stagnant = 0; last = now;
      }
      if (stagnant >= 2) { // two consecutive no-progress calls
        console.log('ℹ️ No further progress detected; stopping importer loop.');
        break;
      }
    }
  }
}

async function runMirrorSweeps() {
  console.log('\n▶️ Starting mirror-images sweeps…');
  const total = 7000; // rough upper bound across all types
  const step = 1000;
  for (let offset = 0; offset < total; offset += step) {
    const payload = { bucket: 'media', mediaTypes: ['ANIME','MANGA','CHARACTER','STAFF'], limit: step, offset, overwrite: false, skipIfMirrored: true };
    const r = await callFunction('mirror-images', payload);
    if (r.status !== 200 || !r.json?.success) {
      console.log(`❌ mirror-images failed at offset ${offset} [${r.status}]:`, r.json?.error || r.text);
      break;
    }
    console.log(`✅ mirror-images offset ${offset}:`, r.json.results);
  }
}

async function main() {
  console.log('🌐 Project:', SUPABASE_URL);
  console.log('🛠️  Functions base:', FUNCTIONS_BASE);
  await ensureImportState();
  await runImporter('ANIME', { maxLoops: 6 });
  await runImporter('MANGA', {
    maxLoops: 6,
    payload: {
      // Keep full imports non-destructive. Chapter/volume enrichment is handled separately.
      includeChapters: false,
      includeVolumes: false,
      maxPlaceholderChapters: 0,
      maxPlaceholderVolumes: 0,
    },
  });
  await runMirrorSweeps();
  console.log('\n📊 Final snapshot:');
  // Lightweight snapshot: counts for key tables
  const tables = ['anime','manga','episodes','chapters','volumes','characters','studios','authors','staff','tags'];
  for (const t of tables) {
    const { count, error } = await supabase.from(t).select('*', { count: 'exact', head: true });
    console.log(`- ${t}: ${error ? 'ERR' : count}`);
  }
}

main().catch(e => { console.error(e); process.exit(1); });
