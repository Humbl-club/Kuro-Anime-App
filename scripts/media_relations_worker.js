#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { createClient } = require('@supabase/supabase-js');
const { getProjectUrl } = require('./lib/project_config');

const ROOT = '/Applications/Kuro';
const PROJECT_URL = process.env.SUPABASE_URL || getProjectUrl();
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const REPORT_DIR = process.env.MEDIA_RELATIONS_REPORTS_DIR || path.join(ROOT, 'reports/media-relations');
const MODE = (process.env.MEDIA_RELATIONS_MODE || 'queue').trim().toLowerCase();
const TOP_COUNT = parsePositiveInt(process.env.MEDIA_RELATIONS_TOP_COUNT, 500);
const QUEUE_LIMIT = parsePositiveInt(process.env.MEDIA_RELATIONS_QUEUE_LIMIT, 40);
const ANILIST_BATCH_SIZE = parsePositiveInt(process.env.ANILIST_BATCH_SIZE, 10);
const REQUEST_DELAY_MS = parsePositiveInt(process.env.ANILIST_REQUEST_DELAY_MS, 350);
const ANILIST_TIMEOUT_MS = parsePositiveInt(process.env.ANILIST_TIMEOUT_MS, 20000);
const REPORT_TOP_MISSING_LIMIT = parsePositiveInt(process.env.MEDIA_RELATIONS_REPORT_TOP_MISSING_LIMIT, 30);
const REPORT_SAMPLE_SIZE = parsePositiveInt(process.env.MEDIA_RELATIONS_REPORT_SAMPLE_SIZE, TOP_COUNT);
const ANILIST_API = 'https://graphql.anilist.co';
const SUPPORTED_RELATIONS = new Set(['SOURCE', 'ADAPTATION', 'PREQUEL', 'SEQUEL', 'SIDE_STORY', 'SPIN_OFF']);

if (!SERVICE_ROLE_KEY) {
  throw new Error('Missing SUPABASE_SERVICE_ROLE_KEY env var.');
}

fs.mkdirSync(REPORT_DIR, { recursive: true });

const supabase = createClient(PROJECT_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
  global: { headers: { 'x-client-info': 'kuro-media-relations-worker/1.0' } },
});

const localIdCache = new Map();
let lastAniListRequestAt = 0;

function parsePositiveInt(raw, fallback) {
  const value = Number.parseInt(raw ?? '', 10);
  return Number.isFinite(value) && value > 0 ? value : fallback;
}

function nowIso() {
  return new Date().toISOString();
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function rateLimitAniList() {
  const now = Date.now();
  const elapsed = now - lastAniListRequestAt;
  if (elapsed < REQUEST_DELAY_MS) {
    await sleep(REQUEST_DELAY_MS - elapsed);
  }
  lastAniListRequestAt = Date.now();
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

async function fetchAniListMediaRelations(anilistId, mediaType) {
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
    await rateLimitAniList();
    try {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), ANILIST_TIMEOUT_MS);
      let response;
      try {
        response = await fetch(ANILIST_API, {
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
        await sleep(500 * Math.pow(2, attempt));
        attempt += 1;
        continue;
      }
      const text = await response.text();
      throw new Error(`AniList HTTP ${response.status}: ${text.slice(0, 300)}`);
    } catch (error) {
      if (attempt < 4) {
        await sleep(500 * Math.pow(2, attempt));
        attempt += 1;
        continue;
      }
      throw error;
    }
  }
}

async function fetchAniListRelationsBatch(items) {
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
    await rateLimitAniList();
    try {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), ANILIST_TIMEOUT_MS);
      let response;
      try {
        response = await fetch(ANILIST_API, {
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
        await sleep(500 * Math.pow(2, attempt));
        attempt += 1;
        continue;
      }
      const text = await response.text();
      throw new Error(`AniList batch HTTP ${response.status}: ${text.slice(0, 300)}`);
    } catch (error) {
      if (attempt < 4) {
        await sleep(500 * Math.pow(2, attempt));
        attempt += 1;
        continue;
      }
      throw error;
    }
  }
}

async function resolveLocalMediaId(mediaType, anilistId) {
  const key = `${mediaType}:${anilistId}`;
  if (localIdCache.has(key)) {
    return localIdCache.get(key);
  }
  const table = mediaType === 'ANIME' ? 'anime' : 'manga';
  const { data, error } = await supabase
    .from(table)
    .select('id')
    .eq('anilist_id', anilistId)
    .maybeSingle();
  if (error) {
    throw new Error(`Local media lookup failed for ${table} anilist_id=${anilistId}: ${error.message}`);
  }
  const localId = data?.id ?? null;
  localIdCache.set(key, localId);
  return localId;
}

async function replaceRelationsForSource(fromMediaType, fromMediaId, edges) {
  const { error: deleteError } = await supabase
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
    const targetMediaId = await resolveLocalMediaId(targetType, targetAniListId);
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

  const { error } = await supabase
    .from('media_relations')
    .upsert(rows, { onConflict: 'from_media_type,from_media_id,relation_type,to_media_type,to_media_id,source' });
  if (error) {
    throw new Error(`media_relations upsert failed for ${fromMediaType}:${fromMediaId}: ${error.message}`);
  }
  return { inserted: rows.length };
}

async function refreshSource(item) {
  if (!item?.anilist_id) {
    throw new Error(`Missing AniList ID for ${item.media_type}:${item.id}`);
  }
  const edges = await fetchAniListMediaRelations(item.anilist_id, item.media_type);
  return replaceRelationsForSource(item.media_type, item.id, edges);
}

async function fetchQueueBatch(limit) {
  const { data, error } = await supabase
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
    const { data: media, error: mediaError } = await supabase
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

async function setQueueStatus(mediaType, mediaId, patch) {
  const { error } = await supabase
    .from('media_relation_refresh_queue')
    .update(patch)
    .eq('media_type', mediaType)
    .eq('media_id', mediaId);
  if (error) {
    throw new Error(`Failed to update ladder queue ${mediaType}:${mediaId}: ${error.message}`);
  }
}

async function processQueue(limit) {
  const batch = await fetchQueueBatch(limit);
  const summary = { mode: 'queue', processed: 0, refreshed: 0, errors: 0, items: [] };
  for (const item of batch) {
    await setQueueStatus(item.media_type, item.id, {
      status: 'processing',
      last_attempt_at: nowIso(),
      retry_count: item.retry_count + 1,
      last_error: null,
      updated_at: nowIso(),
    });

    try {
      const result = await refreshSource(item);
      await setQueueStatus(item.media_type, item.id, {
        status: 'ok',
        last_completed_at: nowIso(),
        last_error: null,
        updated_at: nowIso(),
      });
      summary.processed += 1;
      summary.refreshed += 1;
      summary.items.push({ ...item, inserted: result.inserted, status: 'ok' });
      if (summary.processed % 10 === 0) {
        console.log(`[media-relations] queue progress ${summary.processed}/${batch.length}`);
      }
    } catch (error) {
      await setQueueStatus(item.media_type, item.id, {
        status: 'error',
        last_error: String(error.message || error).slice(0, 1000),
        updated_at: nowIso(),
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

async function fetchTopCatalog(topCount) {
  const [animeRes, mangaRes] = await Promise.all([
    supabase
      .from('anime')
      .select('id, anilist_id, title_english, title_romaji, popularity')
      .eq('is_adult', false)
      .order('popularity', { ascending: false, nullsFirst: false })
      .limit(topCount),
    supabase
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

async function backfillTopCatalog(topCount) {
  const top = await fetchTopCatalog(topCount);
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

  for (let offset = 0; offset < top.all.length; offset += ANILIST_BATCH_SIZE) {
    const batch = top.all.slice(offset, offset + ANILIST_BATCH_SIZE);
    let fetchedBatch;
    try {
      fetchedBatch = await fetchAniListRelationsBatch(batch);
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
        const result = await replaceRelationsForSource(item.media_type, item.id, entry.edges);
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

async function countDistinctRelationSources() {
  const pageSize = 1000;
  let from = 0;
  const seen = new Set();
  while (true) {
    const to = from + pageSize - 1;
    const { data, error } = await supabase
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

async function buildCoverageReport(sampleSize) {
  const top = await fetchTopCatalog(sampleSize);
  const { count: totalRelations, error: countError } = await supabase
    .from('media_relations')
    .select('*', { count: 'exact', head: true });
  if (countError) {
    throw new Error(`Failed to count media_relations rows: ${countError.message}`);
  }

  const ladders = await mapWithConcurrency(top.all, 8, async (item) => {
    const { data, error } = await supabase.rpc('get_media_ladder', {
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

  const distinctSources = await countDistinctRelationSources();
  const latestStatus = {
    generated_at: nowIso(),
    project_url: PROJECT_URL,
    total_media_relations_rows: totalRelations || 0,
    distinct_source_titles_with_relations: distinctSources,
    top_catalog_sample_size: sampleSize,
    top_catalog_coverage: coverageCounts,
    top_missing_titles: missing
      .sort((lhs, rhs) => (rhs.popularity || 0) - (lhs.popularity || 0))
      .slice(0, REPORT_TOP_MISSING_LIMIT)
      .map(item => ({
        media_type: item.media_type,
        media_id: item.id,
        anilist_id: item.anilist_id,
        title: item.title,
        popularity: item.popularity || 0,
      })),
  };

  fs.writeFileSync(
    path.join(REPORT_DIR, 'latest-status.json'),
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

  fs.writeFileSync(path.join(REPORT_DIR, 'missing-top-catalog.md'), mdLines.join('\n') + '\n', 'utf8');
  return latestStatus;
}

async function main() {
  const summary = { started_at: nowIso(), mode: MODE };
  if (MODE === 'queue') {
    summary.queue = await processQueue(QUEUE_LIMIT);
  } else if (MODE === 'top-catalog') {
    summary.backfill = await backfillTopCatalog(TOP_COUNT);
  } else if (MODE !== 'report') {
    throw new Error(`Unsupported MEDIA_RELATIONS_MODE: ${MODE}`);
  }

  summary.report = await buildCoverageReport(REPORT_SAMPLE_SIZE);
  summary.completed_at = nowIso();
  fs.writeFileSync(path.join(REPORT_DIR, 'latest-run.json'), JSON.stringify(summary, null, 2) + '\n', 'utf8');
  console.log(JSON.stringify(summary, null, 2));
}

main().catch(error => {
  const payload = {
    started_at: nowIso(),
    mode: MODE,
    error: String(error.message || error),
  };
  fs.writeFileSync(path.join(REPORT_DIR, 'latest-run.json'), JSON.stringify(payload, null, 2) + '\n', 'utf8');
  console.error(error);
  process.exit(1);
});
