#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { getProjectUrl } = require('./lib/project_config');

const ANILIST_API = 'https://graphql.anilist.co';
const SUPPORTED_RELATIONS = new Set(['SOURCE', 'ADAPTATION', 'PREQUEL', 'SEQUEL', 'SIDE_STORY', 'SPIN_OFF']);
const LEGACY_APPLICATIONS_ROOT = '/Applications/Kuro';

let activeReportDir = null;

function parsePositiveInt(raw, fallback) {
  const value = Number.parseInt(raw ?? '', 10);
  return Number.isFinite(value) && value > 0 ? value : fallback;
}

function defaultSleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function nowIso(ctx) {
  return ctx.clock().toISOString();
}

function readGitRoot() {
  try {
    return execFileSync('git', ['rev-parse', '--show-toplevel'], {
      cwd: __dirname,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
  } catch (error) {
    return '';
  }
}

// 1. KURO_PROJECT_ROOT, when set
// 2. else `git rev-parse --show-toplevel` from this script's directory
// 3. else /Applications/Kuro, only when git is unavailable and that directory exists
// 4. else the parent of scripts/
function resolveProjectRoot(options = {}) {
  const env = options.env || process.env;
  const existsSync = options.existsSync || fs.existsSync;
  const scriptsDir = options.scriptsDir || __dirname;
  const gitRoot = options.gitRoot || readGitRoot;

  const override = env.KURO_PROJECT_ROOT;
  if (typeof override === 'string' && override.trim()) {
    return override.trim();
  }

  let resolved = '';
  try {
    resolved = gitRoot();
  } catch (error) {
    resolved = '';
  }
  if (typeof resolved === 'string' && resolved.trim()) {
    return resolved.trim();
  }

  if (existsSync(LEGACY_APPLICATIONS_ROOT)) {
    return LEGACY_APPLICATIONS_ROOT;
  }
  return path.resolve(scriptsDir, '..');
}

function resolveReportDir() {
  if (process.env.MEDIA_RELATIONS_REPORTS_DIR) {
    return process.env.MEDIA_RELATIONS_REPORTS_DIR;
  }
  return path.join(resolveProjectRoot(), 'reports/media-relations');
}

function makeContext(deps) {
  if (!deps || typeof deps !== 'object') {
    throw new Error('runMediaRelations requires deps');
  }
  if (!deps.supabase) {
    throw new Error('runMediaRelations requires deps.supabase');
  }
  if (!deps.reportDir) {
    throw new Error('runMediaRelations requires deps.reportDir');
  }
  const fetchImpl = deps.fetch || globalThis.fetch;
  if (typeof fetchImpl !== 'function') {
    throw new Error('runMediaRelations requires deps.fetch');
  }
  const clock = deps.clock || (() => new Date());
  if (typeof clock !== 'function') {
    throw new Error('runMediaRelations requires deps.clock to be a function');
  }
  return {
    supabase: deps.supabase,
    fetch: fetchImpl,
    clock,
    sleep: deps.sleep || defaultSleep,
    reportDir: deps.reportDir,
    projectUrl: deps.projectUrl || process.env.SUPABASE_URL || '',
    requestDelayMs: parsePositiveInt(deps.requestDelayMs ?? process.env.ANILIST_REQUEST_DELAY_MS, 350),
    anilistTimeoutMs: parsePositiveInt(deps.anilistTimeoutMs ?? process.env.ANILIST_TIMEOUT_MS, 20000),
    anilistBatchSize: parsePositiveInt(deps.anilistBatchSize ?? process.env.ANILIST_BATCH_SIZE, 10),
    reportTopMissingLimit: parsePositiveInt(
      deps.reportTopMissingLimit ?? process.env.MEDIA_RELATIONS_REPORT_TOP_MISSING_LIMIT,
      30
    ),
    localIdCache: new Map(),
    lastAniListRequestAt: 0,
  };
}

async function rateLimitAniList(ctx) {
  const now = ctx.clock().getTime();
  const elapsed = now - ctx.lastAniListRequestAt;
  if (elapsed < ctx.requestDelayMs) {
    await ctx.sleep(ctx.requestDelayMs - elapsed);
  }
  ctx.lastAniListRequestAt = ctx.clock().getTime();
}

function normalizeAniListMediaType(raw) {
  if (typeof raw !== 'string') return null;
  const normalized = raw.trim().toUpperCase();
  return normalized === 'ANIME' || normalized === 'MANGA' ? normalized : null;
}

function normalizeRelationType(raw) {
  if (typeof raw !== 'string') return null;
  const normalized = raw.trim().toUpperCase();
  return SUPPORTED_RELATIONS.has(normalized) ? normalized : null;
}

async function fetchAniListMediaRelations(ctx, anilistId, mediaType) {
  const query = `
    query ($id: Int, $type: MediaType) {
      Media(id: $id, type: $type) {
        id
        relations {
          edges {
            relationType(version: 2)
            node {
              id
              type
            }
          }
        }
      }
    }
  `;

  let attempt = 0;
  while (true) {
    await rateLimitAniList(ctx);
    try {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), ctx.anilistTimeoutMs);
      let response;
      try {
        response = await ctx.fetch(ANILIST_API, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ query, variables: { id: anilistId, type: mediaType } }),
          signal: controller.signal,
        });
      } finally {
        clearTimeout(timeout);
      }
      if (response.ok) {
        const payload = await response.json();
        return payload?.data?.Media?.relations?.edges ?? [];
      }
      if ((response.status === 429 || response.status >= 500) && attempt < 4) {
        await ctx.sleep(500 * Math.pow(2, attempt));
        attempt += 1;
        continue;
      }
      const text = await response.text();
      throw new Error(`AniList HTTP ${response.status}: ${text.slice(0, 300)}`);
    } catch (error) {
      if (attempt < 4) {
        await ctx.sleep(500 * Math.pow(2, attempt));
        attempt += 1;
        continue;
      }
      throw error;
    }
  }
}

async function fetchAniListRelationsBatch(ctx, items) {
  const query = [
    'query {',
    ...items.map((item, index) => {
      const mediaType = item.media_type === 'ANIME' ? 'ANIME' : 'MANGA';
      return `  m${index}: Media(id: ${item.anilist_id}, type: ${mediaType}) { relations { edges { relationType(version: 2) node { id type } } } }`;
    }),
    '}',
  ].join('\n');

  let attempt = 0;
  while (true) {
    await rateLimitAniList(ctx);
    try {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), ctx.anilistTimeoutMs);
      let response;
      try {
        response = await ctx.fetch(ANILIST_API, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ query }),
          signal: controller.signal,
        });
      } finally {
        clearTimeout(timeout);
      }

      if (response.ok) {
        const payload = await response.json();
        const data = payload?.data || {};
        return items.map((item, index) => ({
          item,
          edges: data?.[`m${index}`]?.relations?.edges ?? [],
        }));
      }

      if ((response.status === 429 || response.status >= 500) && attempt < 4) {
        await ctx.sleep(500 * Math.pow(2, attempt));
        attempt += 1;
        continue;
      }
      const text = await response.text();
      throw new Error(`AniList batch HTTP ${response.status}: ${text.slice(0, 300)}`);
    } catch (error) {
      if (attempt < 4) {
        await ctx.sleep(500 * Math.pow(2, attempt));
        attempt += 1;
        continue;
      }
      throw error;
    }
  }
}

async function resolveLocalMediaId(ctx, mediaType, anilistId) {
  const key = `${mediaType}:${anilistId}`;
  if (ctx.localIdCache.has(key)) {
    return ctx.localIdCache.get(key);
  }
  const table = mediaType === 'ANIME' ? 'anime' : 'manga';
  const { data, error } = await ctx.supabase
    .from(table)
    .select('id')
    .eq('anilist_id', anilistId)
    .maybeSingle();
  if (error) {
    throw new Error(`Local media lookup failed for ${table} anilist_id=${anilistId}: ${error.message}`);
  }
  const localId = data?.id ?? null;
  ctx.localIdCache.set(key, localId);
  return localId;
}

async function replaceRelationsForSource(ctx, fromMediaType, fromMediaId, edges) {
  const { error: deleteError } = await ctx.supabase
    .from('media_relations')
    .delete()
    .eq('from_media_type', fromMediaType)
    .eq('from_media_id', fromMediaId)
    .eq('source', 'anilist');
  if (deleteError) {
    throw new Error(`media_relations delete failed for ${fromMediaType}:${fromMediaId}: ${deleteError.message}`);
  }

  const rows = [];
  const seen = new Set();
  for (const edge of edges ?? []) {
    const relationType = normalizeRelationType(edge?.relationType);
    const targetType = normalizeAniListMediaType(edge?.node?.type);
    const targetAniListId = Number(edge?.node?.id);
    if (!relationType || !targetType || !Number.isFinite(targetAniListId)) {
      continue;
    }
    const targetMediaId = await resolveLocalMediaId(ctx, targetType, targetAniListId);
    if (!targetMediaId) continue;
    const dedupeKey = `${relationType}:${targetType}:${targetMediaId}`;
    if (seen.has(dedupeKey)) continue;
    seen.add(dedupeKey);
    rows.push({
      from_media_type: fromMediaType,
      from_media_id: fromMediaId,
      relation_type: relationType,
      to_media_type: targetType,
      to_media_id: targetMediaId,
      source: 'anilist',
    });
  }

  if (rows.length === 0) {
    return { inserted: 0 };
  }

  const { error } = await ctx.supabase
    .from('media_relations')
    .upsert(rows, { onConflict: 'from_media_type,from_media_id,relation_type,to_media_type,to_media_id,source' });
  if (error) {
    throw new Error(`media_relations upsert failed for ${fromMediaType}:${fromMediaId}: ${error.message}`);
  }
  return { inserted: rows.length };
}

async function refreshSource(ctx, item) {
  if (!item?.anilist_id) {
    throw new Error(`Missing AniList ID for ${item.media_type}:${item.id}`);
  }
  const edges = await fetchAniListMediaRelations(ctx, item.anilist_id, item.media_type);
  return replaceRelationsForSource(ctx, item.media_type, item.id, edges);
}

async function fetchQueueBatch(ctx, limit) {
  const { data, error } = await ctx.supabase
    .from('media_relation_refresh_queue')
    .select('media_type, media_id, reason, retry_count')
    .in('status', ['pending', 'error'])
    .order('requested_at', { ascending: true })
    .limit(limit);
  if (error) {
    throw new Error(`Failed to fetch ladder refresh queue: ${error.message}`);
  }
  if (!data?.length) return [];

  const resolved = [];
  for (const row of data) {
    const table = row.media_type === 'ANIME' ? 'anime' : 'manga';
    const { data: media, error: mediaError } = await ctx.supabase
      .from(table)
      .select('id, anilist_id, title_english, title_romaji, popularity')
      .eq('id', row.media_id)
      .maybeSingle();
    if (mediaError) {
      throw new Error(`Failed to load ${table}:${row.media_id} for ladder queue: ${mediaError.message}`);
    }
    if (!media) continue;
    resolved.push({
      media_type: row.media_type,
      id: media.id,
      anilist_id: media.anilist_id,
      title: media.title_english || media.title_romaji || `${row.media_type} ${row.media_id}`,
      popularity: media.popularity || 0,
      reason: row.reason || 'queued',
      retry_count: row.retry_count || 0,
    });
  }
  return resolved;
}

async function setQueueStatus(ctx, mediaType, mediaId, patch) {
  const { error } = await ctx.supabase
    .from('media_relation_refresh_queue')
    .update(patch)
    .eq('media_type', mediaType)
    .eq('media_id', mediaId);
  if (error) {
    throw new Error(`Failed to update ladder queue ${mediaType}:${mediaId}: ${error.message}`);
  }
}

async function processQueue(ctx, limit) {
  const batch = await fetchQueueBatch(ctx, limit);
  const summary = { mode: 'queue', processed: 0, refreshed: 0, errors: 0, items: [] };
  for (const item of batch) {
    await setQueueStatus(ctx, item.media_type, item.id, {
      status: 'processing',
      last_attempt_at: nowIso(ctx),
      retry_count: item.retry_count + 1,
      last_error: null,
      updated_at: nowIso(ctx),
    });

    try {
      const result = await refreshSource(ctx, item);
      await setQueueStatus(ctx, item.media_type, item.id, {
        status: 'ok',
        last_completed_at: nowIso(ctx),
        last_error: null,
        updated_at: nowIso(ctx),
      });
      summary.processed += 1;
      summary.refreshed += 1;
      summary.items.push({ ...item, inserted: result.inserted, status: 'ok' });
      if (summary.processed % 10 === 0) {
        console.log(`[media-relations] queue progress ${summary.processed}/${batch.length}`);
      }
    } catch (error) {
      await setQueueStatus(ctx, item.media_type, item.id, {
        status: 'error',
        last_error: String(error.message || error).slice(0, 1000),
        updated_at: nowIso(ctx),
      });
      summary.processed += 1;
      summary.errors += 1;
      summary.items.push({ ...item, status: 'error', error: String(error.message || error) });
      if (summary.processed % 10 === 0) {
        console.log(`[media-relations] queue progress ${summary.processed}/${batch.length}`);
      }
    }
  }
  return summary;
}

async function fetchTopCatalog(ctx, topCount) {
  const [animeRes, mangaRes] = await Promise.all([
    ctx.supabase
      .from('anime')
      .select('id, anilist_id, title_english, title_romaji, popularity')
      .eq('is_adult', false)
      .order('popularity', { ascending: false, nullsFirst: false })
      .limit(topCount),
    ctx.supabase
      .from('manga')
      .select('id, anilist_id, title_english, title_romaji, popularity')
      .eq('is_adult', false)
      .order('popularity', { ascending: false, nullsFirst: false })
      .limit(topCount),
  ]);
  if (animeRes.error) throw new Error(`Failed to load top anime catalog: ${animeRes.error.message}`);
  if (mangaRes.error) throw new Error(`Failed to load top manga catalog: ${mangaRes.error.message}`);

  const anime = (animeRes.data || []).map(row => ({
    media_type: 'ANIME',
    id: row.id,
    anilist_id: row.anilist_id,
    title: row.title_english || row.title_romaji || `ANIME ${row.id}`,
    popularity: row.popularity || 0,
  }));
  const manga = (mangaRes.data || []).map(row => ({
    media_type: 'MANGA',
    id: row.id,
    anilist_id: row.anilist_id,
    title: row.title_english || row.title_romaji || `MANGA ${row.id}`,
    popularity: row.popularity || 0,
  }));
  return { anime, manga, all: [...anime, ...manga] };
}

async function backfillTopCatalog(ctx, topCount) {
  const top = await fetchTopCatalog(ctx, topCount);
  const summary = {
    mode: 'top-catalog',
    topCount,
    processed: 0,
    refreshed: 0,
    errors: 0,
    animeCount: top.anime.length,
    mangaCount: top.manga.length,
    samples: [],
  };

  for (let offset = 0; offset < top.all.length; offset += ctx.anilistBatchSize) {
    const batch = top.all.slice(offset, offset + ctx.anilistBatchSize);
    let fetchedBatch;
    try {
      fetchedBatch = await fetchAniListRelationsBatch(ctx, batch);
    } catch (error) {
      for (const item of batch) {
        summary.processed += 1;
        summary.errors += 1;
        if (summary.samples.length < 20) {
          summary.samples.push({ ...item, status: 'error', error: String(error.message || error) });
        }
      }
      console.log(
        `[media-relations] top-catalog progress ${summary.processed}/${top.all.length} ` +
        `(refreshed=${summary.refreshed}, errors=${summary.errors})`
      );
      continue;
    }

    for (const entry of fetchedBatch) {
      const item = entry.item;
      try {
        const result = await replaceRelationsForSource(ctx, item.media_type, item.id, entry.edges);
        summary.processed += 1;
        summary.refreshed += 1;
        if (summary.samples.length < 20) {
          summary.samples.push({ ...item, inserted: result.inserted, status: 'ok' });
        }
      } catch (error) {
        summary.processed += 1;
        summary.errors += 1;
        if (summary.samples.length < 20) {
          summary.samples.push({ ...item, status: 'error', error: String(error.message || error) });
        }
      }
    }

    if (summary.processed % 25 === 0 || summary.processed === top.all.length) {
      console.log(
        `[media-relations] top-catalog progress ${summary.processed}/${top.all.length} ` +
        `(refreshed=${summary.refreshed}, errors=${summary.errors})`
      );
    }
  }

  return summary;
}

async function countDistinctRelationSources(ctx) {
  const pageSize = 1000;
  let from = 0;
  const seen = new Set();
  while (true) {
    const to = from + pageSize - 1;
    const { data, error } = await ctx.supabase
      .from('media_relations')
      .select('from_media_type, from_media_id')
      .order('from_media_type', { ascending: true })
      .order('from_media_id', { ascending: true })
      .range(from, to);
    if (error) {
      throw new Error(`Failed to read media_relations for distinct source count: ${error.message}`);
    }
    if (!data?.length) break;
    for (const row of data) {
      seen.add(`${row.from_media_type}:${row.from_media_id}`);
    }
    if (data.length < pageSize) break;
    from += pageSize;
  }
  return seen.size;
}

function ladderHasContent(ladder) {
  if (!ladder || typeof ladder !== 'object') return false;
  return Boolean(
    ladder.entry_point || ladder.next_step || ladder.primary_source || ladder.primary_adaptation ||
    (Array.isArray(ladder.source_material) && ladder.source_material.length) ||
    (Array.isArray(ladder.adaptations) && ladder.adaptations.length) ||
    (Array.isArray(ladder.prequels) && ladder.prequels.length) ||
    (Array.isArray(ladder.sequels) && ladder.sequels.length) ||
    (Array.isArray(ladder.side_stories) && ladder.side_stories.length) ||
    (Array.isArray(ladder.spin_offs) && ladder.spin_offs.length)
  );
}

async function mapWithConcurrency(items, concurrency, fn) {
  const results = new Array(items.length);
  let cursor = 0;
  async function worker() {
    while (true) {
      const index = cursor;
      cursor += 1;
      if (index >= items.length) return;
      results[index] = await fn(items[index], index);
    }
  }
  const count = Math.max(1, Math.min(concurrency, items.length));
  await Promise.all(Array.from({ length: count }, worker));
  return results;
}

async function buildCoverageReport(ctx, sampleSize) {
  const top = await fetchTopCatalog(ctx, sampleSize);
  const { count: totalRelations, error: countError } = await ctx.supabase
    .from('media_relations')
    .select('*', { count: 'exact', head: true });
  if (countError) {
    throw new Error(`Failed to count media_relations rows: ${countError.message}`);
  }

  const ladders = await mapWithConcurrency(top.all, 8, async (item) => {
    const { data, error } = await ctx.supabase.rpc('get_media_ladder', {
      p_media_type: item.media_type,
      p_media_id: item.id,
    });
    if (error) {
      return { item, ladder: null, error: error.message };
    }
    return { item, ladder: data, error: null };
  });

  const coverageCounts = { strong: 0, partial: 0, minimal: 0, none: 0, errors: 0 };
  const missing = [];
  for (const row of ladders) {
    if (row.error) {
      coverageCounts.errors += 1;
      continue;
    }
    const ladder = row.ladder || {};
    if (!ladderHasContent(ladder)) {
      coverageCounts.none += 1;
      missing.push(row.item);
      continue;
    }
    const status = ladder.coverage_status;
    if (status === 'strong' || status === 'partial' || status === 'minimal') {
      coverageCounts[status] += 1;
    } else {
      coverageCounts.partial += 1;
    }
  }

  const distinctSources = await countDistinctRelationSources(ctx);
  const latestStatus = {
    generated_at: nowIso(ctx),
    project_url: ctx.projectUrl,
    total_media_relations_rows: totalRelations || 0,
    distinct_source_titles_with_relations: distinctSources,
    top_catalog_sample_size: sampleSize,
    top_catalog_coverage: coverageCounts,
    top_missing_titles: missing
      .sort((lhs, rhs) => (rhs.popularity || 0) - (lhs.popularity || 0))
      .slice(0, ctx.reportTopMissingLimit)
      .map(item => ({
        media_type: item.media_type,
        media_id: item.id,
        anilist_id: item.anilist_id,
        title: item.title,
        popularity: item.popularity || 0,
      })),
  };

  fs.writeFileSync(
    path.join(ctx.reportDir, 'latest-status.json'),
    JSON.stringify(latestStatus, null, 2) + '\n',
    'utf8'
  );

  const mdLines = [
    '# Media Relations Coverage',
    '',
    `- Generated: ${latestStatus.generated_at}`,
    `- Total relation rows: ${latestStatus.total_media_relations_rows}`,
    `- Distinct source titles with at least one relation: ${latestStatus.distinct_source_titles_with_relations}`,
    `- Top catalog sample size: ${latestStatus.top_catalog_sample_size}`,
    `- Coverage in top catalog: ${coverageCounts.strong} strong / ${coverageCounts.partial} partial / ${coverageCounts.minimal} minimal / ${coverageCounts.none} none / ${coverageCounts.errors} errors`,
    '',
    '## Top Missing High-Popularity Titles',
    '',
  ];

  if (latestStatus.top_missing_titles.length === 0) {
    mdLines.push('- None in current sample.');
  } else {
    for (const item of latestStatus.top_missing_titles) {
      mdLines.push(`- ${item.media_type} #${item.media_id} — ${item.title} (popularity ${item.popularity})`);
    }
  }

  fs.writeFileSync(path.join(ctx.reportDir, 'missing-top-catalog.md'), mdLines.join('\n') + '\n', 'utf8');
  return latestStatus;
}

async function runMediaRelations(deps) {
  const ctx = makeContext(deps);
  const mode = (deps.mode ?? process.env.MEDIA_RELATIONS_MODE ?? 'queue').trim().toLowerCase();
  const topCount = deps.topCount ?? parsePositiveInt(process.env.MEDIA_RELATIONS_TOP_COUNT, 500);
  const queueLimit = deps.queueLimit ?? parsePositiveInt(process.env.MEDIA_RELATIONS_QUEUE_LIMIT, 40);
  const reportSampleSize = deps.reportSampleSize ?? parsePositiveInt(
    process.env.MEDIA_RELATIONS_REPORT_SAMPLE_SIZE,
    topCount
  );

  const summary = { started_at: nowIso(ctx), mode };
  if (mode === 'queue') {
    summary.queue = await processQueue(ctx, queueLimit);
  } else if (mode === 'top-catalog') {
    summary.backfill = await backfillTopCatalog(ctx, topCount);
  } else if (mode !== 'report') {
    throw new Error(`Unsupported MEDIA_RELATIONS_MODE: ${mode}`);
  }

  summary.report = await buildCoverageReport(ctx, reportSampleSize);
  summary.completed_at = nowIso(ctx);
  fs.writeFileSync(path.join(ctx.reportDir, 'latest-run.json'), JSON.stringify(summary, null, 2) + '\n', 'utf8');
  console.log(JSON.stringify(summary, null, 2));
  return summary;
}

async function main() {
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!serviceRoleKey) {
    throw new Error('Missing SUPABASE_SERVICE_ROLE_KEY env var.');
  }
  const projectUrl = process.env.SUPABASE_URL || getProjectUrl();
  const reportDir = resolveReportDir();
  fs.mkdirSync(reportDir, { recursive: true });
  activeReportDir = reportDir;
  const { createClient } = require('@supabase/supabase-js');
  const supabase = createClient(projectUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { 'x-client-info': 'kuro-media-relations-worker/1.0' } },
  });
  await runMediaRelations({
    supabase,
    fetch: globalThis.fetch,
    clock: () => new Date(),
    reportDir,
    projectUrl,
  });
}

module.exports = {
  runMediaRelations,
  resolveProjectRoot,
};

if (require.main === module) {
  main().catch(error => {
    if (activeReportDir) {
      const payload = {
        started_at: new Date().toISOString(),
        mode: (process.env.MEDIA_RELATIONS_MODE || 'queue').trim().toLowerCase(),
        error: String(error.message || error),
      };
      fs.writeFileSync(
        path.join(activeReportDir, 'latest-run.json'),
        JSON.stringify(payload, null, 2) + '\n',
        'utf8'
      );
    }
    console.error(error);
    process.exit(1);
  });
}
