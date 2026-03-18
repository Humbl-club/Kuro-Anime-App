-- ---------------------------------------------------------------------------
-- Additive club loading RPCs.
-- These are lightweight, compatibility-safe companions to the existing
-- fetch_my_clubs_enriched() and fetch_club_bundle() RPCs.
-- ---------------------------------------------------------------------------

create or replace function public.fetch_my_clubs_loading()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  uid uuid;
  result jsonb;
begin
  uid := auth.uid();
  if uid is null then
    raise exception 'UNAUTHENTICATED' using errcode = 'P0001';
  end if;

  select coalesce(jsonb_agg(row_data order by row_data->>'last_activity_at' desc nulls last), '[]'::jsonb)
  into result
  from (
    select jsonb_build_object(
      'id', c.id,
      'name', c.name,
      'sharing_level', c.sharing_level,
      'is_archived', c.is_archived,
      'created_at', c.created_at,
      'member_count', (select count(*) from public.club_members cm2 where cm2.club_id = c.id),
      'rail_count', (select count(*) from public.club_rails cr2 where cr2.club_id = c.id),
      'poll_count', (select count(*) from public.club_polls cp2 where cp2.club_id = c.id),
      'last_activity_at', greatest(
        (select max(cri.created_at) from public.club_rail_items cri
         join public.club_rails cr on cr.id = cri.rail_id
         where cr.club_id = c.id),
        (select max(cp.created_at) from public.club_polls cp where cp.club_id = c.id),
        (select max(cv.created_at) from public.club_votes cv
         join public.club_polls cp2 on cp2.id = cv.poll_id
         where cp2.club_id = c.id)
      ),
      'activity_preview', (
        select case
          when latest.source = 'item' then 'Added: ' || left(latest.label, 40)
          when latest.source = 'poll' then 'Poll: ' || left(latest.label, 40)
          when latest.source = 'vote' then 'Vote on: ' || left(latest.label, 40)
          else null
        end
        from (
          select 'item' as source,
                 coalesce(a.title_english, a.title_romaji, m.title_english, m.title_romaji, 'Unknown') as label,
                 cri2.created_at as ts
          from public.club_rail_items cri2
          join public.club_rails cr2 on cr2.id = cri2.rail_id
          left join public.anime a on cri2.media_type = 'ANIME' and a.id = cri2.media_id
          left join public.manga m on cri2.media_type = 'MANGA' and m.id = cri2.media_id
          where cr2.club_id = c.id
          union all
          select 'poll' as source, cp3.question as label, cp3.created_at as ts
          from public.club_polls cp3
          where cp3.club_id = c.id
          union all
          select 'vote' as source, cp4.question as label, cv2.created_at as ts
          from public.club_votes cv2
          join public.club_polls cp4 on cp4.id = cv2.poll_id
          where cp4.club_id = c.id
          order by ts desc
          limit 1
        ) latest
      ),
      'cover_images', (
        select coalesce(jsonb_agg(img_url), '[]'::jsonb)
        from (
          select case
            when cri3.media_type = 'ANIME' then coalesce(a3.cover_image_large, a3.cover_image_medium)
            when cri3.media_type = 'MANGA' then coalesce(m3.cover_image_large, m3.cover_image_medium)
          end as img_url
          from public.club_rail_items cri3
          join public.club_rails cr3 on cr3.id = cri3.rail_id
          left join public.anime a3 on cri3.media_type = 'ANIME' and a3.id = cri3.media_id
          left join public.manga m3 on cri3.media_type = 'MANGA' and m3.id = cri3.media_id
          where cr3.club_id = c.id
            and (a3.cover_image_large is not null or a3.cover_image_medium is not null
              or m3.cover_image_large is not null or m3.cover_image_medium is not null)
          order by cri3.created_at desc
          limit 4
        ) imgs
      ),
      'member_names', (
        select coalesce(jsonb_agg(dn), '[]'::jsonb)
        from (
          select coalesce(nullif(trim(p.display_name), ''), 'Member') as dn
          from public.club_members cm3
          left join public.profiles p on p.id = cm3.user_id
          where cm3.club_id = c.id
          order by cm3.joined_at asc
          limit 4
        ) names
      ),
      'loading_state', jsonb_build_object(
        'state', case
          when c.is_archived then 'archived'
          when (
            select greatest(
              (select max(cri.created_at) from public.club_rail_items cri
               join public.club_rails cr on cr.id = cri.rail_id
               where cr.club_id = c.id),
              (select max(cp.created_at) from public.club_polls cp where cp.club_id = c.id),
              (select max(cv.created_at) from public.club_votes cv
               join public.club_polls cp2 on cp2.id = cv.poll_id
               where cp2.club_id = c.id)
            )
          ) is null then 'loading'
          else 'ready'
        end,
        'visibility', case when c.is_archived then 'hidden' else 'visible' end
      )
    ) as row_data
    from public.clubs c
    join public.club_members cm on cm.club_id = c.id
    where cm.user_id = uid and c.is_archived = false
  ) enriched;

  return result;
end;
$$;

grant execute on function public.fetch_my_clubs_loading() to authenticated;

create or replace function public.fetch_club_bundle_loading(p_club_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  _uid uuid;
  _club record;
  _my_membership record;
  _my_effective_level text;
  _club_sharing_rank int;
  _member_count int;
  _rail_count int;
  _poll_count int;
  _last_activity_at timestamptz;
  _activity_preview text;
  _bundle_state text;
  _bundle_visibility text;
begin
  _uid := auth.uid();
  if _uid is null then
    raise exception 'UNAUTHENTICATED' using errcode = 'P0001';
  end if;

  select cm.role, cm.sharing_level, cm.joined_at
  into _my_membership
  from public.club_members cm
  where cm.club_id = p_club_id and cm.user_id = _uid;

  if _my_membership is null then
    raise exception 'NOT_A_MEMBER' using errcode = 'P0001';
  end if;

  select c.id, c.name, c.description, c.sharing_level, c.max_members,
         c.is_archived, c.invite_code, c.created_at
  into _club
  from public.clubs c
  where c.id = p_club_id;

  if _club is null then
    raise exception 'CLUB_NOT_FOUND' using errcode = 'P0001';
  end if;

  _my_effective_level := case
    when _my_membership.sharing_level is null then _club.sharing_level
    when public.sharing_level_rank(_my_membership.sharing_level) < public.sharing_level_rank(_club.sharing_level)
      then _my_membership.sharing_level
    else _club.sharing_level
  end;

  _club_sharing_rank := public.sharing_level_rank(_club.sharing_level);
  select count(*) into _member_count from public.club_members where club_id = p_club_id;
  select count(*) into _rail_count from public.club_rails where club_id = p_club_id;
  select count(*) into _poll_count from public.club_polls where club_id = p_club_id;

  select greatest(
    (select max(cri.created_at) from public.club_rail_items cri
     join public.club_rails cr on cr.id = cri.rail_id
     where cr.club_id = p_club_id),
    (select max(cp.created_at) from public.club_polls cp where cp.club_id = p_club_id),
    (select max(cv.created_at) from public.club_votes cv
     join public.club_polls cp2 on cp2.id = cv.poll_id
     where cp2.club_id = p_club_id)
  )
  into _last_activity_at;

  select case
    when latest.source = 'item' then 'Added: ' || left(latest.label, 40)
    when latest.source = 'poll' then 'Poll: ' || left(latest.label, 40)
    when latest.source = 'vote' then 'Vote on: ' || left(latest.label, 40)
    else null
  end
  into _activity_preview
  from (
    select 'item' as source,
           coalesce(a.title_english, a.title_romaji, m.title_english, m.title_romaji, 'Unknown') as label,
           cri2.created_at as ts
    from public.club_rail_items cri2
    join public.club_rails cr2 on cr2.id = cri2.rail_id
    left join public.anime a on cri2.media_type = 'ANIME' and a.id = cri2.media_id
    left join public.manga m on cri2.media_type = 'MANGA' and m.id = cri2.media_id
    where cr2.club_id = p_club_id
    union all
    select 'poll' as source, cp3.question as label, cp3.created_at as ts
    from public.club_polls cp3
    where cp3.club_id = p_club_id
    union all
    select 'vote' as source, cp4.question as label, cv2.created_at as ts
    from public.club_votes cv2
    join public.club_polls cp4 on cp4.id = cv2.poll_id
    where cp4.club_id = p_club_id
    order by ts desc
    limit 1
  ) latest;

  _bundle_state := case
    when _club.is_archived then 'archived'
    when _last_activity_at is null then 'loading'
    when _rail_count = 0 and _poll_count = 0 then 'loading'
    else 'ready'
  end;
  _bundle_visibility := case when _club.is_archived then 'hidden' else 'visible' end;

  return jsonb_build_object(
    'club', jsonb_build_object(
      'id', _club.id,
      'name', _club.name,
      'description', _club.description,
      'sharing_level', _club.sharing_level,
      'max_members', _club.max_members,
      'is_archived', _club.is_archived,
      'invite_code', case when _my_membership.role in ('owner', 'admin') then _club.invite_code else null end,
      'created_at', _club.created_at
    ),
    'members', '[]'::jsonb,
    'my_role', _my_membership.role,
    'my_sharing_level', _my_effective_level,
    'rails', '[]'::jsonb,
    'polls', '[]'::jsonb,
    'member_count', _member_count,
    'rail_count', _rail_count,
    'poll_count', _poll_count,
    'last_activity_at', _last_activity_at,
    'activity_preview', _activity_preview,
    'loading_state', jsonb_build_object(
      'state', _bundle_state,
      'visibility', _bundle_visibility
    )
  );
end;
$$;

grant execute on function public.fetch_club_bundle_loading(uuid) to authenticated;
