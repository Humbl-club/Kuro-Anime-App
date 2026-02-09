// Mirror remote AniList images into Supabase Storage and update DB URLs
// Usage payload (examples):
// {
//   "bucket": "media",
//   "mediaTypes": ["ANIME","MANGA","CHARACTER","STAFF"],
//   "limit": 200,
//   "offset": 0,
//   "overwrite": false
// }

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

type MediaType = 'ANIME' | 'MANGA' | 'CHARACTER' | 'STAFF';

serve(async (req) => {
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const supabase = createClient(supabaseUrl, supabaseKey);

  const payload = await req.json().catch(() => ({} as any));
  const bucket = payload.bucket ?? 'media';
  const mediaTypes: MediaType[] = payload.mediaTypes ?? ['ANIME','MANGA'];
  const limit: number = payload.limit ?? 200;
  const offset: number = payload.offset ?? 0;
  const overwrite: boolean = payload.overwrite ?? false;
  // New: skip processing if URL already points to our Storage CDN
  const skipIfMirrored: boolean = payload.skipIfMirrored ?? true;
  // New: cache control for uploads (seconds)
  const cacheControl: string = (payload.cacheControl !== undefined ? String(payload.cacheControl) : '604800');
  // New: soft time budget to keep cron runs reliable (Edge Functions have a hard timeout).
  const timeBudgetMs: number = payload.timeBudgetMs ?? 90000;
  const startedMs = Date.now();
  const shouldStop = () => (Date.now() - startedMs) >= timeBudgetMs;

  // Derive a unique lock key from the payload so different batches don't block each other.
  // e.g. "mirror-images:ANIME,MANGA:0" vs "mirror-images:CHARACTER:0"
  const lockKeySuffix = `${mediaTypes.sort().join(',')}:${offset}`;
  const lockKey = `mirror-images:${lockKeySuffix}`;
  // Lock TTL should be just slightly longer than the time budget (default 2 min).
  // The old 1800s (30 min) TTL was causing 58% skip rate across staggered jobs.
  const lockTtlSeconds: number = payload.lockTtlSeconds ?? 120;

  let runId: number | null = null;
  let lockAcquired = false;
  try {
    runId = await startMirrorRun(supabase, payload);
    lockAcquired = await acquireImportLock(supabase, lockKey, lockTtlSeconds);
    if (!lockAcquired) {
      await finishMirrorRun(supabase, runId, 'skipped', {}, `locked (key=${lockKey})`, startedMs);
      return new Response(JSON.stringify({ success: true, skipped: true, reason: 'locked', lockKey }), { headers: { 'Content-Type': 'application/json' } });
    }

    const results: Record<string, number> = {};

    if (mediaTypes.includes('ANIME')) {
      results['anime'] = await mirrorAnime(supabase, bucket, limit, offset, overwrite);
    }
    if (mediaTypes.includes('MANGA')) {
      results['manga'] = await mirrorManga(supabase, bucket, limit, offset, overwrite);
    }
    if (mediaTypes.includes('CHARACTER')) {
      results['characters'] = await mirrorCharacters(supabase, bucket, limit, offset, overwrite);
    }
    if (mediaTypes.includes('STAFF')) {
      results['staff'] = await mirrorStaff(supabase, bucket, limit, offset, overwrite);
    }

    await finishMirrorRun(supabase, runId, 'success', results, null, startedMs);
    return new Response(JSON.stringify({ success: true, results }), { headers: { 'Content-Type': 'application/json' } });
  } catch (e) {
    // Best-effort logging; do not mask original error.
    try { await finishMirrorRun(supabase, runId, 'error', {}, (e as Error).message, startedMs); } catch (_ignored) {}
    return new Response(JSON.stringify({ success: false, error: (e as Error).message }), { status: 500, headers: { 'Content-Type': 'application/json' } });
  } finally {
    if (lockAcquired) {
      try {
        const { error } = await supabase.rpc('release_import_lock', { p_key: lockKey });
        if (error) console.error('Release lock error:', error);
      } catch (e) {
        console.error('Release lock exception:', e);
      }
    }
  }

  async function mirrorAnime(supabase: any, bucket: string, limit: number, offset: number, overwrite: boolean): Promise<number> {
    const { data, error } = await supabase
      .from('anime')
      // In this schema, `id` is the AniList id (no separate `anilist_id` column).
      .select('id, cover_image_large, cover_image_medium, banner_image')
      .order('popularity', { ascending: false })
      .range(offset, offset + limit - 1);
    if (error) throw error;
    let updated = 0;
    for (const row of (data ?? [])) {
      if (shouldStop()) break;
      const id = row.id;
      const basePath = `anime/${id}`;
      const updates: any = {};
      // cover large
      if (row.cover_image_large && isRemoteAndNotMirrored(row.cover_image_large)) {
        const path = await mirrorOne(bucket, `${basePath}/cover_large`, row.cover_image_large);
        if (path) updates.cover_image_large = getPublicUrl(bucket, path);
      }
      // cover medium
      if (row.cover_image_medium && isRemoteAndNotMirrored(row.cover_image_medium)) {
        const path = await mirrorOne(bucket, `${basePath}/cover_medium`, row.cover_image_medium);
        if (path) updates.cover_image_medium = getPublicUrl(bucket, path);
      }
      // banner
      if (row.banner_image && isRemoteAndNotMirrored(row.banner_image)) {
        const path = await mirrorOne(bucket, `${basePath}/banner`, row.banner_image);
        if (path) updates.banner_image = getPublicUrl(bucket, path);
      }
      if (Object.keys(updates).length > 0) {
        const { error: uerr } = await supabase.from('anime').update(updates).eq('id', row.id);
        if (!uerr) updated++;
      }
    }
    return updated;
  }

  async function mirrorManga(supabase: any, bucket: string, limit: number, offset: number, overwrite: boolean): Promise<number> {
    const { data, error } = await supabase
      .from('manga')
      // In this schema, `id` is the AniList id (no separate `anilist_id` column).
      .select('id, cover_image_large, cover_image_medium, banner_image')
      .order('popularity', { ascending: false })
      .range(offset, offset + limit - 1);
    if (error) throw error;
    let updated = 0;
    for (const row of (data ?? [])) {
      if (shouldStop()) break;
      const id = row.id;
      const basePath = `manga/${id}`;
      const updates: any = {};
      if (row.cover_image_large && isRemoteAndNotMirrored(row.cover_image_large)) {
        const path = await mirrorOne(bucket, `${basePath}/cover_large`, row.cover_image_large);
        if (path) updates.cover_image_large = getPublicUrl(bucket, path);
      }
      if (row.cover_image_medium && isRemoteAndNotMirrored(row.cover_image_medium)) {
        const path = await mirrorOne(bucket, `${basePath}/cover_medium`, row.cover_image_medium);
        if (path) updates.cover_image_medium = getPublicUrl(bucket, path);
      }
      if (row.banner_image && isRemoteAndNotMirrored(row.banner_image)) {
        const path = await mirrorOne(bucket, `${basePath}/banner`, row.banner_image);
        if (path) updates.banner_image = getPublicUrl(bucket, path);
      }
      if (Object.keys(updates).length > 0) {
        const { error: uerr } = await supabase.from('manga').update(updates).eq('id', row.id);
        if (!uerr) updated++;
      }
    }
    return updated;
  }

  async function mirrorCharacters(supabase: any, bucket: string, limit: number, offset: number, overwrite: boolean): Promise<number> {
    const { data, error } = await supabase
      .from('characters')
      // In this schema, `id` is the AniList id (no separate `anilist_id` column).
      .select('id, image_large')
      .order('id', { ascending: true })
      .range(offset, offset + limit - 1);
    if (error) throw error;
    let updated = 0;
    for (const row of (data ?? [])) {
      if (shouldStop()) break;
      const id = row.id;
      if (row.image_large && isRemoteAndNotMirrored(row.image_large)) {
        const path = await mirrorOne(bucket, `characters/${id}`, row.image_large);
        if (path) {
          const updates = { image_large: getPublicUrl(bucket, path) };
          const { error: uerr } = await supabase.from('characters').update(updates).eq('id', row.id);
          if (!uerr) updated++;
        }
      }
    }
    return updated;
  }

  async function mirrorStaff(supabase: any, bucket: string, limit: number, offset: number, overwrite: boolean): Promise<number> {
    const { data, error } = await supabase
      .from('staff')
      // In this schema, `id` is the AniList id (no separate `anilist_id` column).
      .select('id, image_large')
      .order('id', { ascending: true })
      .range(offset, offset + limit - 1);
    if (error) throw error;
    let updated = 0;
    for (const row of (data ?? [])) {
      if (shouldStop()) break;
      const id = row.id;
      if (row.image_large && isRemoteAndNotMirrored(row.image_large)) {
        const path = await mirrorOne(bucket, `staff/${id}`, row.image_large);
        if (path) {
          const updates = { image_large: getPublicUrl(bucket, path) };
          const { error: uerr } = await supabase.from('staff').update(updates).eq('id', row.id);
          if (!uerr) updated++;
        }
      }
    }
    return updated;
  }

  function isRemote(url: string): boolean {
    return url.startsWith('http://') || url.startsWith('https://');
  }

  function isStorageUrl(url: string): boolean {
    if (!url) return false;
    try {
      const u = new URL(url);
      const host = new URL(supabaseUrl).host;
      // Typical pattern: https://<ref>.supabase.co/storage/v1/object/public/<bucket>/<path>
      return u.host === host && u.pathname.includes('/storage/v1/object/public/');
    } catch (_e) {
      return url.includes('/storage/v1/object/public/');
    }
  }

  function isRemoteAndNotMirrored(url: string): boolean {
    if (!isRemote(url)) return false;
    if (skipIfMirrored && isStorageUrl(url)) return false;
    return true;
  }

  function getExtFromContentType(ct: string | null): string {
    if (!ct) return 'jpg';
    if (ct.includes('png')) return 'png';
    if (ct.includes('webp')) return 'webp';
    return 'jpg';
  }

  async function mirrorOne(bucket: string, basePath: string, url: string): Promise<string | null> {
    try {
      const res = await fetch(url);
      if (!res.ok) return null;
      const ct = res.headers.get('content-type');
      const ext = getExtFromContentType(ct);
      const path = `${basePath}.${ext}`;
      const blob = await res.blob();
      // upload with upsert behavior
      const { error: uerr } = await supabase.storage.from(bucket).upload(path, blob, { upsert: true, contentType: ct ?? undefined, cacheControl });
      if (uerr) return null;
      return path;
    } catch (_e) {
      return null;
    }
  }

  function getPublicUrl(bucket: string, path: string): string {
    const { data } = supabase.storage.from(bucket).getPublicUrl(path);
    return data.publicUrl;
  }

  async function acquireImportLock(supabase: any, key: string, ttlSeconds: number): Promise<boolean> {
    try {
      const { data, error } = await supabase.rpc('acquire_import_lock', { p_key: key, p_ttl_seconds: ttlSeconds });
      if (error) {
        console.error('Acquire lock error:', error);
        return true; // fail open to avoid blocking if RPC missing
      }
      return Boolean(data);
    } catch (e) {
      console.error('Acquire lock exception:', e);
      return true;
    }
  }

  async function startMirrorRun(supabase: any, payload: any): Promise<number | null> {
    try {
      const { data, error } = await supabase
        .from('mirror_runs')
        .insert({ payload, status: 'running', started_at: new Date().toISOString() })
        .select('id')
        .single();
      if (error) {
        console.error('mirror_runs insert error:', error);
        return null;
      }
      return data?.id ?? null;
    } catch (e) {
      console.error('mirror_runs insert exception:', e);
      return null;
    }
  }

  async function finishMirrorRun(
    supabase: any,
    runId: number | null,
    status: string,
    results: Record<string, number>,
    message: string | null,
    startedAtMs: number
  ): Promise<void> {
    if (!runId) return;
    try {
      const durationMs = Date.now() - startedAtMs;
      const { error } = await supabase
        .from('mirror_runs')
        .update({ status, results, message, finished_at: new Date().toISOString(), duration_ms: durationMs })
        .eq('id', runId);
      if (error) console.error('mirror_runs update error:', error);
    } catch (e) {
      console.error('mirror_runs update exception:', e);
    }
  }
});
