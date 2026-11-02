-- 2026-08-05: Critique ingestion schema — Round 2 pilot (plan §5, Round 2).
-- Owner blessed the slate by direction 2026-08-05: agent-fetchable pilot =
-- Wrong Every Time (B), Manga Bookshelf (C), 藤津亮太のアニメの門V (B, ClaudeBot
-- explicitly permitted). Medium = owner-session lane only (never agent-fetched).
-- Japan Powered = blocked pending permission (reports/critique-pilot/kincaid-permission-email.md).
-- Design rules: parse-don't-hoard (no prose columns anywhere), verbatim quotes
-- <= 300 chars validated at the write path, content notes deadpan and separate.

begin;

-- 1) Source registry ---------------------------------------------------------
create table if not exists public.critic_sources (
  slug           text primary key,
  name           text not null,
  url            text not null,
  lang           text not null check (lang in ('en', 'ja')),
  covers         text not null check (covers in ('anime', 'manga', 'both')),
  tier           text not null check (tier in ('A', 'B', 'C', 'D', 'E')),
  lens           text,
  robots_posture text,
  fetch_mode     text not null check (fetch_mode in ('agent', 'owner_session', 'blocked')),
  blessed_at     timestamptz,
  created_at     timestamptz not null default now()
);
alter table public.critic_sources enable row level security;
drop policy if exists critic_sources_read on public.critic_sources;
create policy critic_sources_read on public.critic_sources for select using (true);
revoke all on public.critic_sources from public, anon, authenticated;
grant select on public.critic_sources to authenticated, service_role;
grant all on public.critic_sources to service_role;

insert into public.critic_sources (slug, name, url, lang, covers, tier, lens, robots_posture, fetch_mode, blessed_at) values
  ('wrong-every-time',  'Wrong Every Time (Nick Creamer)', 'https://wrongeverytime.com/',   'en', 'anime', 'B', 'individual critic, craft+theme',  'permissive + sitemaps',                          'agent',         now()),
  ('manga-bookshelf',   'Manga Bookshelf',                 'https://mangabookshelf.com/',   'en', 'manga', 'C', 'manga-first desk',                'permissive + sitemaps',                          'agent',         now()),
  ('fujitsu-anime-mon', '藤津亮太のアニメの門V',             'https://animeanime.jp/',        'ja', 'anime', 'B', 'real-name JP critic essays',      'ClaudeBot explicitly permitted (crawl-delay 5)', 'agent',         now()),
  ('medium-authors',    'Medium (blessed authors only)',   'https://medium.com/',           'en', 'both',  'C', 'per-author curation, AniTAY+',    'robots blocks agents; TOS bans scraping',        'owner_session', now()),
  ('japan-powered',     'Japan Powered (Chris Kincaid)',   'https://www.japanpowered.com/', 'en', 'both',  'C', 'cultural-analysis essays',        'AI-agents disallowed + enforcing WAF',           'blocked',       null)
on conflict (slug) do update set
  tier = excluded.tier, lens = excluded.lens, robots_posture = excluded.robots_posture,
  fetch_mode = excluded.fetch_mode;

-- 2) Parsed-review registry (NO prose column, by construction) ---------------
create table if not exists public.critic_reviews (
  id           bigserial primary key,
  source_slug  text not null references public.critic_sources(slug),
  url          text not null unique,
  url_hash     text,
  media_type   text not null check (media_type in ('ANIME', 'MANGA')),
  media_id     integer not null,
  critic_name  text,
  published_on date,
  fetched_at   timestamptz not null default now()
);
create index if not exists critic_reviews_media_idx on public.critic_reviews (media_type, media_id);
alter table public.critic_reviews enable row level security;
revoke all on public.critic_reviews from public, anon, authenticated;
grant all on public.critic_reviews to service_role;

-- 3) Structured claims: axis x verdict x quote -------------------------------
create table if not exists public.media_critic_claims (
  review_id      bigint not null references public.critic_reviews(id) on delete cascade,
  axis           text not null check (axis in ('story', 'visuals', 'characters', 'pacing', 'sound', 'legacy')),
  verdict        smallint not null check (verdict between 0 and 4),
  quote          text not null check (char_length(quote) <= 300),
  confidence     real check (confidence between 0 and 1),
  compound_flags text[] not null default '{}',
  primary key (review_id, axis),
  constraint claims_flags_valid check (
    compound_flags <@ array['carried_by_animation','three_episode_rule','fumbled_the_ending',
                            'read_the_manga','sleeper','slow_burn_worth_it']::text[]
  )
);
alter table public.media_critic_claims enable row level security;
revoke all on public.media_critic_claims from public, anon, authenticated;
grant all on public.media_critic_claims to service_role;

-- 4) Aggregated craft consensus ----------------------------------------------
create table if not exists public.media_craft_scores (
  media_type text not null check (media_type in ('ANIME', 'MANGA')),
  media_id   integer not null,
  axis       text not null check (axis in ('story', 'visuals', 'characters', 'pacing', 'sound', 'legacy')),
  consensus  real not null check (consensus between 0 and 1),
  n_reviews  integer not null,
  updated_at timestamptz not null default now(),
  primary key (media_type, media_id, axis)
);
alter table public.media_craft_scores enable row level security;
drop policy if exists media_craft_scores_read on public.media_craft_scores;
create policy media_craft_scores_read on public.media_craft_scores for select using (true);
revoke all on public.media_craft_scores from public, anon, authenticated;
grant select on public.media_craft_scores to authenticated, service_role;
grant all on public.media_craft_scores to service_role;

create or replace function public.rebuild_media_craft_scores()
returns integer
language sql
security definer
set search_path = public, extensions, pg_temp
as $$
  with weighted as (
    select r.media_type, r.media_id, c.axis,
           sum((c.verdict / 4.0) * case s.tier when 'A' then 1.0 when 'B' then 0.8
                                               when 'C' then 0.6 when 'D' then 0.4 else 0.2 end) as num,
           sum(case s.tier when 'A' then 1.0 when 'B' then 0.8
                           when 'C' then 0.6 when 'D' then 0.4 else 0.2 end) as den,
           count(*)::int as n
    from public.media_critic_claims c
    join public.critic_reviews r on r.id = c.review_id
    join public.critic_sources s on s.slug = r.source_slug
    group by r.media_type, r.media_id, c.axis
  ),
  up as (
    insert into public.media_craft_scores (media_type, media_id, axis, consensus, n_reviews, updated_at)
    select media_type, media_id, axis, (num / nullif(den, 0))::real, n, now() from weighted
    on conflict (media_type, media_id, axis) do update
      set consensus = excluded.consensus, n_reviews = excluded.n_reviews, updated_at = now()
    returning 1
  )
  select count(*)::int from up;
$$;
revoke all on function public.rebuild_media_craft_scores() from public, anon, authenticated;
grant execute on function public.rebuild_media_craft_scores() to service_role;

-- 5) Content notes: deadpan, separate, evidence-backed -----------------------
create table if not exists public.media_content_notes (
  media_type     text not null check (media_type in ('ANIME', 'MANGA')),
  media_id       integer not null,
  note_type      text not null check (note_type in ('sexual_content', 'sexualized_minors',
                                                    'graphic_violence', 'self_harm', 'abuse')),
  severity       text not null check (severity in ('low', 'medium', 'high')),
  evidence_quote text not null check (char_length(evidence_quote) <= 300),
  review_id      bigint not null references public.critic_reviews(id) on delete cascade,
  created_at     timestamptz not null default now(),
  primary key (media_type, media_id, note_type, review_id)
);
alter table public.media_content_notes enable row level security;
drop policy if exists media_content_notes_read on public.media_content_notes;
create policy media_content_notes_read on public.media_content_notes for select using (true);
revoke all on public.media_content_notes from public, anon, authenticated;
grant select on public.media_content_notes to authenticated, service_role;
grant all on public.media_content_notes to service_role;

-- 6) Verdict voice (display copy; DB stays numeric) --------------------------
create table if not exists public.verdict_voice (
  axis    text not null,
  verdict smallint not null check (verdict between 0 and 4),
  lang    text not null check (lang in ('en', 'de')),
  label   text not null,
  primary key (axis, verdict, lang)
);
alter table public.verdict_voice enable row level security;
drop policy if exists verdict_voice_read on public.verdict_voice;
create policy verdict_voice_read on public.verdict_voice for select using (true);
revoke all on public.verdict_voice from public, anon, authenticated;
grant select on public.verdict_voice to authenticated, service_role;
grant all on public.verdict_voice to service_role;

insert into public.verdict_voice (axis, verdict, lang, label) values
  ('story', 4, 'en', 'peak fiction'), ('story', 3, 'en', 'cooking'), ('story', 2, 'en', 'mid'),
  ('story', 1, 'en', 'plot optional'), ('story', 0, 'en', 'dumpster fire'),
  ('visuals', 4, 'en', 'sakuga feast'), ('visuals', 3, 'en', 'clean'), ('visuals', 2, 'en', 'serviceable'),
  ('visuals', 1, 'en', 'budget ran out'), ('visuals', 0, 'en', 'slideshow'),
  ('characters', 4, 'en', 'unforgettable'), ('characters', 3, 'en', 'alive'), ('characters', 2, 'en', 'fine'),
  ('characters', 1, 'en', 'cardboard'), ('characters', 0, 'en', 'who?'),
  ('pacing', 4, 'en', 'no filler'), ('pacing', 3, 'en', 'tight'), ('pacing', 2, 'en', 'breathes'),
  ('pacing', 1, 'en', 'drags'), ('pacing', 0, 'en', 'filler hell'),
  -- sound axis provisional (plan §2: owner may drop it at the pilot gate)
  ('sound', 4, 'en', 'ost goes hard'), ('sound', 3, 'en', 'sets the mood'), ('sound', 2, 'en', 'fine'),
  ('sound', 1, 'en', 'forgettable'), ('sound', 0, 'en', 'tinny'),
  ('legacy', 4, 'en', 'changed the game'), ('legacy', 3, 'en', 'aged like wine'), ('legacy', 2, 'en', 'of its time'),
  ('legacy', 1, 'en', 'aged like milk'), ('legacy', 0, 'en', 'footnote')
on conflict (axis, verdict, lang) do update set label = excluded.label;

-- 7) Atomic ingest write path ------------------------------------------------
create or replace function public.upsert_critic_review_claims(
  p_source_slug  text,
  p_url          text,
  p_media_type   text,
  p_media_id     integer,
  p_critic_name  text,
  p_published_on date,
  p_claims       jsonb,
  p_content_notes jsonb default '[]'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_review_id bigint;
  v_claim jsonb;
begin
  if not exists (select 1 from public.critic_sources s
                 where s.slug = p_source_slug and s.blessed_at is not null) then
    raise exception 'source not blessed' using detail = 'SOURCE_NOT_BLESSED';
  end if;
  if p_media_type not in ('ANIME', 'MANGA') then
    raise exception 'invalid media type' using detail = 'INVALID_MEDIA_TYPE';
  end if;
  if p_media_type = 'ANIME' and not exists (select 1 from public.anime a where a.id = p_media_id) then
    raise exception 'media not found' using detail = 'MEDIA_NOT_FOUND';
  end if;
  if p_media_type = 'MANGA' and not exists (select 1 from public.manga m where m.id = p_media_id) then
    raise exception 'media not found' using detail = 'MEDIA_NOT_FOUND';
  end if;
  if jsonb_typeof(p_claims) <> 'array' or jsonb_array_length(p_claims) = 0 then
    raise exception 'claims must be a non-empty array' using detail = 'CLAIMS_EMPTY';
  end if;

  insert into public.critic_reviews (source_slug, url, url_hash, media_type, media_id, critic_name, published_on)
  values (p_source_slug, p_url, md5(p_url), p_media_type, p_media_id, p_critic_name, p_published_on)
  on conflict (url) do update
    set critic_name = excluded.critic_name, published_on = excluded.published_on, fetched_at = now()
  returning id into v_review_id;

  -- re-parse replaces this review's claims/notes (targeted deletes)
  delete from public.media_critic_claims c where c.review_id = v_review_id;
  delete from public.media_content_notes n where n.review_id = v_review_id;

  for v_claim in select * from jsonb_array_elements(p_claims) loop
    insert into public.media_critic_claims (review_id, axis, verdict, quote, confidence, compound_flags)
    values (
      v_review_id,
      v_claim->>'axis',
      (v_claim->>'verdict')::smallint,
      v_claim->>'quote',
      nullif(v_claim->>'confidence', '')::real,
      coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(v_claim->'flags', '[]'::jsonb)) x), '{}')
    );
  end loop;

  for v_claim in select * from jsonb_array_elements(coalesce(p_content_notes, '[]'::jsonb)) loop
    insert into public.media_content_notes (media_type, media_id, note_type, severity, evidence_quote, review_id)
    values (p_media_type, p_media_id, v_claim->>'note_type', v_claim->>'severity', v_claim->>'quote', v_review_id);
  end loop;

  return v_review_id;
end;
$$;
revoke all on function public.upsert_critic_review_claims(text, text, text, integer, text, date, jsonb, jsonb)
  from public, anon, authenticated;
grant execute on function public.upsert_critic_review_claims(text, text, text, integer, text, date, jsonb, jsonb)
  to service_role;

commit;
