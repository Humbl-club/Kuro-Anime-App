-- Image / CDN convergence v1 (ADR 2026-07-31):
-- 1. BEFORE UPDATE triggers preserve storage-mirrored image columns from being
--    overwritten with remote URLs by bulk imports.
-- 2. image_mirror_state.priority_at + enqueue_image_mirror RPC (mirror-on-view).
-- 3. image_mirror_coverage metrics view (per media type: total / mirrored / %).
-- 4. Candidate views so mirror-images can order characters/staff by visibility.
-- 5. Reschedule mirror cron windows for actionable-only (remote-only) selection.

begin;

-- ---------------------------------------------------------------------------
-- 1. Protect mirrored image columns (anime, manga, characters, staff)
-- ---------------------------------------------------------------------------
create or replace function public.protect_mirrored_image_columns()
returns trigger
language plpgsql
set search_path = public, extensions
as $$
begin
  if tg_table_name in ('anime', 'manga') then
    if old.cover_image_large like '%/storage/v1/%'
       and (new.cover_image_large is null or new.cover_image_large not like '%/storage/v1/%') then
      new.cover_image_large := old.cover_image_large;
    end if;
    if old.cover_image_medium like '%/storage/v1/%'
       and (new.cover_image_medium is null or new.cover_image_medium not like '%/storage/v1/%') then
      new.cover_image_medium := old.cover_image_medium;
    end if;
    if old.banner_image like '%/storage/v1/%'
       and (new.banner_image is null or new.banner_image not like '%/storage/v1/%') then
      new.banner_image := old.banner_image;
    end if;
  elsif tg_table_name in ('characters', 'staff') then
    if old.image_large like '%/storage/v1/%'
       and (new.image_large is null or new.image_large not like '%/storage/v1/%') then
      new.image_large := old.image_large;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists protect_mirrored_image_columns_anime on public.anime;
create trigger protect_mirrored_image_columns_anime
  before update on public.anime
  for each row execute function public.protect_mirrored_image_columns();

drop trigger if exists protect_mirrored_image_columns_manga on public.manga;
create trigger protect_mirrored_image_columns_manga
  before update on public.manga
  for each row execute function public.protect_mirrored_image_columns();

drop trigger if exists protect_mirrored_image_columns_characters on public.characters;
create trigger protect_mirrored_image_columns_characters
  before update on public.characters
  for each row execute function public.protect_mirrored_image_columns();

drop trigger if exists protect_mirrored_image_columns_staff on public.staff;
create trigger protect_mirrored_image_columns_staff
  before update on public.staff
  for each row execute function public.protect_mirrored_image_columns();

-- ---------------------------------------------------------------------------
-- 2. Priority queue for mirror-on-view
-- ---------------------------------------------------------------------------
alter table public.image_mirror_state add column if not exists priority_at timestamptz;

create index if not exists idx_image_mirror_state_priority_at
  on public.image_mirror_state (priority_at)
  where priority_at is not null;

create or replace function public.enqueue_image_mirror(
  p_media_type text,
  p_media_id int
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_media_type text := upper(trim(coalesce(p_media_type, '')));
  v_hits integer;
begin
  if v_uid is null then
    raise exception 'Authentication required'
      using errcode = 'P0001', detail = 'UNAUTHENTICATED';
  end if;

  if v_media_type not in ('ANIME', 'MANGA', 'CHARACTER', 'STAFF') then
    raise exception 'Unsupported media type: %', p_media_type
      using errcode = '22023';
  end if;

  -- 60 calls per user per day (fixed daily window via shared bucket helper).
  v_hits := public.rate_limit_hit('image_mirror_enqueue:user:' || v_uid::text, 86400);
  if v_hits > 60 then
    raise exception 'image mirror enqueue rate limit exceeded'
      using errcode = 'P0001', detail = 'RATE_LIMITED';
  end if;

  -- Mark priority only for assets whose live column is still remote.
  -- Already-mirrored (storage URL) assets are filtered out; already-pending
  -- rows keep their original priority_at (coalesce = no-op).
  if v_media_type = 'ANIME' then
    insert into public.image_mirror_state as ims
      (media_type, media_id, asset_key, source_url, state, visibility, priority_at, updated_at)
    select 'ANIME', a.id, x.asset_key, x.source_url, 'pending', 'remote', now(), now()
    from public.anime a
    cross join lateral (values
      ('cover_image_large', a.cover_image_large),
      ('cover_image_medium', a.cover_image_medium),
      ('banner_image', a.banner_image)
    ) as x(asset_key, source_url)
    where a.id = p_media_id
      and x.source_url is not null
      and x.source_url not like '%/storage/v1/%'
    on conflict (media_type, media_id, asset_key)
    do update set
      priority_at = coalesce(ims.priority_at, now()),
      updated_at = now();
  elsif v_media_type = 'MANGA' then
    insert into public.image_mirror_state as ims
      (media_type, media_id, asset_key, source_url, state, visibility, priority_at, updated_at)
    select 'MANGA', m.id, x.asset_key, x.source_url, 'pending', 'remote', now(), now()
    from public.manga m
    cross join lateral (values
      ('cover_image_large', m.cover_image_large),
      ('cover_image_medium', m.cover_image_medium),
      ('banner_image', m.banner_image)
    ) as x(asset_key, source_url)
    where m.id = p_media_id
      and x.source_url is not null
      and x.source_url not like '%/storage/v1/%'
    on conflict (media_type, media_id, asset_key)
    do update set
      priority_at = coalesce(ims.priority_at, now()),
      updated_at = now();
  elsif v_media_type = 'CHARACTER' then
    insert into public.image_mirror_state as ims
      (media_type, media_id, asset_key, source_url, state, visibility, priority_at, updated_at)
    select 'CHARACTER', c.id, 'image_large', c.image_large, 'pending', 'remote', now(), now()
    from public.characters c
    where c.id = p_media_id
      and c.image_large is not null
      and c.image_large not like '%/storage/v1/%'
    on conflict (media_type, media_id, asset_key)
    do update set
      priority_at = coalesce(ims.priority_at, now()),
      updated_at = now();
  else -- STAFF
    insert into public.image_mirror_state as ims
      (media_type, media_id, asset_key, source_url, state, visibility, priority_at, updated_at)
    select 'STAFF', s.id, 'image_large', s.image_large, 'pending', 'remote', now(), now()
    from public.staff s
    where s.id = p_media_id
      and s.image_large is not null
      and s.image_large not like '%/storage/v1/%'
    on conflict (media_type, media_id, asset_key)
    do update set
      priority_at = coalesce(ims.priority_at, now()),
      updated_at = now();
  end if;
end;
$$;

revoke all on function public.enqueue_image_mirror(text, int) from public;
grant execute on function public.enqueue_image_mirror(text, int) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. Coverage metrics (service_role only)
-- ---------------------------------------------------------------------------
create or replace view public.image_mirror_coverage as
with media_counts as (
  select 'ANIME'::text as media_type,
         count(*)::bigint as total_rows,
         count(*) filter (where cover_image_large like '%/storage/v1/%')::bigint as mirrored_rows
  from public.anime
  union all
  select 'MANGA'::text,
         count(*)::bigint,
         count(*) filter (where cover_image_large like '%/storage/v1/%')::bigint
  from public.manga
  union all
  select 'CHARACTER'::text,
         count(*)::bigint,
         count(*) filter (where image_large like '%/storage/v1/%')::bigint
  from public.characters
  union all
  select 'STAFF'::text,
         count(*)::bigint,
         count(*) filter (where image_large like '%/storage/v1/%')::bigint
  from public.staff
),
priority_counts as (
  select media_type, count(*)::bigint as pending_priority_rows
  from public.image_mirror_state
  where priority_at is not null
  group by media_type
)
select m.media_type,
       m.total_rows,
       m.mirrored_rows,
       round(100.0 * m.mirrored_rows / nullif(m.total_rows, 0), 2) as mirrored_pct,
       coalesce(p.pending_priority_rows, 0) as pending_priority_rows
from media_counts m
left join priority_counts p on p.media_type = m.media_type;

revoke all on public.image_mirror_coverage from public, anon, authenticated;
grant select on public.image_mirror_coverage to service_role;

-- ---------------------------------------------------------------------------
-- 4. Visibility-ordered candidates for mirror-images (service_role only).
--    PostgREST cannot GROUP BY a plain table resource, so the join-count
--    ordering lives in these views; the edge function filters remote-only.
-- ---------------------------------------------------------------------------
create or replace view public.image_mirror_character_candidates as
select c.id,
       c.image_large,
       (coalesce(ac.cnt, 0) + coalesce(mc.cnt, 0))::bigint as visibility_count
from public.characters c
left join (
  select character_id, count(*)::bigint as cnt
  from public.anime_characters
  group by character_id
) ac on ac.character_id = c.id
left join (
  select character_id, count(*)::bigint as cnt
  from public.manga_characters
  group by character_id
) mc on mc.character_id = c.id;

create or replace view public.image_mirror_staff_candidates as
select s.id,
       s.image_large,
       (coalesce(asf.cnt, 0) + coalesce(msf.cnt, 0))::bigint as visibility_count
from public.staff s
left join (
  select staff_id, count(*)::bigint as cnt
  from public.anime_staff
  group by staff_id
) asf on asf.staff_id = s.id
left join (
  select staff_id, count(*)::bigint as cnt
  from public.manga_staff
  group by staff_id
) msf on msf.staff_id = s.id;

revoke all on public.image_mirror_character_candidates from public, anon, authenticated;
grant select on public.image_mirror_character_candidates to service_role;

revoke all on public.image_mirror_staff_candidates from public, anon, authenticated;
grant select on public.image_mirror_staff_candidates to service_role;

-- ---------------------------------------------------------------------------
-- 5. Reschedule mirror cron jobs: same names/times/auth, actionable windows.
-- ---------------------------------------------------------------------------
select cron.unschedule(jobid) from cron.job where jobname = 'mirror-images-anime-manga-0';
select cron.schedule('mirror-images-anime-manga-0', '0 2 * * *', $$
  SELECT net.http_post(
    url := 'https://bkdifromsqxkndnllmdj.supabase.co/functions/v1/mirror-images',
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJrZGlmcm9tc3F4a25kbmxsbWRqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTI1OTg2NjMsImV4cCI6MjA2ODE3NDY2M30.xWtSNgApX5jMZqdWJLjsqNlsXbwubFwW39Hs3x9hOoo',
      'x-import-secret', current_setting('app.settings.import_secret', true)
    ),
    body := '{"bucket":"media","mediaTypes":["ANIME","MANGA"],"limit":200,"offset":0,"overwrite":false,"skipIfMirrored":true,"timeBudgetMs":55000,"lockTtlSeconds":120}'::jsonb
  ) AS request_id;
$$);

select cron.unschedule(jobid) from cron.job where jobname = 'mirror-images-anime-manga-200';
select cron.schedule('mirror-images-anime-manga-200', '15 2 * * *', $$
  SELECT net.http_post(
    url := 'https://bkdifromsqxkndnllmdj.supabase.co/functions/v1/mirror-images',
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJrZGlmcm9tc3F4a25kbmxsbWRqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTI1OTg2NjMsImV4cCI6MjA2ODE3NDY2M30.xWtSNgApX5jMZqdWJLjsqNlsXbwubFwW39Hs3x9hOoo',
      'x-import-secret', current_setting('app.settings.import_secret', true)
    ),
    body := '{"bucket":"media","mediaTypes":["ANIME","MANGA"],"limit":200,"offset":600,"overwrite":false,"skipIfMirrored":true,"timeBudgetMs":55000,"lockTtlSeconds":120}'::jsonb
  ) AS request_id;
$$);

select cron.unschedule(jobid) from cron.job where jobname = 'mirror-images-anime-manga-400';
select cron.schedule('mirror-images-anime-manga-400', '30 2 * * *', $$
  SELECT net.http_post(
    url := 'https://bkdifromsqxkndnllmdj.supabase.co/functions/v1/mirror-images',
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJrZGlmcm9tc3F4a25kbmxsbWRqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTI1OTg2NjMsImV4cCI6MjA2ODE3NDY2M30.xWtSNgApX5jMZqdWJLjsqNlsXbwubFwW39Hs3x9hOoo',
      'x-import-secret', current_setting('app.settings.import_secret', true)
    ),
    body := '{"bucket":"media","mediaTypes":["ANIME","MANGA"],"limit":200,"offset":1200,"overwrite":false,"skipIfMirrored":true,"timeBudgetMs":55000,"lockTtlSeconds":120}'::jsonb
  ) AS request_id;
$$);

select cron.unschedule(jobid) from cron.job where jobname = 'mirror-images-character';
select cron.schedule('mirror-images-character', '45 2 * * *', $$
  SELECT net.http_post(
    url := 'https://bkdifromsqxkndnllmdj.supabase.co/functions/v1/mirror-images',
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJrZGlmcm9tc3F4a25kbmxsbWRqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTI1OTg2NjMsImV4cCI6MjA2ODE3NDY2M30.xWtSNgApX5jMZqdWJLjsqNlsXbwubFwW39Hs3x9hOoo',
      'x-import-secret', current_setting('app.settings.import_secret', true)
    ),
    body := '{"bucket":"media","mediaTypes":["CHARACTER"],"limit":300,"offset":0,"overwrite":false,"skipIfMirrored":true,"timeBudgetMs":55000,"lockTtlSeconds":120}'::jsonb
  ) AS request_id;
$$);

select cron.unschedule(jobid) from cron.job where jobname = 'mirror-images-staff';
select cron.schedule('mirror-images-staff', '0 3 * * *', $$
  SELECT net.http_post(
    url := 'https://bkdifromsqxkndnllmdj.supabase.co/functions/v1/mirror-images',
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJrZGlmcm9tc3F4a25kbmxsbWRqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTI1OTg2NjMsImV4cCI6MjA2ODE3NDY2M30.xWtSNgApX5jMZqdWJLjsqNlsXbwubFwW39Hs3x9hOoo',
      'x-import-secret', current_setting('app.settings.import_secret', true)
    ),
    body := '{"bucket":"media","mediaTypes":["STAFF"],"limit":300,"offset":0,"overwrite":false,"skipIfMirrored":true,"timeBudgetMs":55000,"lockTtlSeconds":120}'::jsonb
  ) AS request_id;
$$);

commit;
