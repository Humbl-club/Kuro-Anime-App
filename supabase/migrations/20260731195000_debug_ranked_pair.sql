-- TEMPORARY debug #6: replicate ranked.score end-to-end for one (seed, cand) pair.
drop function if exists public.debug_ranked_pair(integer, integer);
create function public.debug_ranked_pair(p_seed integer, p_cand integer)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_sim double precision; v_creator boolean; v_studio boolean; v_author boolean;
  v_rail boolean; v_pen double precision; v_mult double precision; v_score double precision;
begin
  with seed_vec as (
    select v.tag_key, avg(v.w)::double precision as w
    from public.media_tag_vectors v
    where v.media_type = 'ANIME' and v.media_id = p_seed
    group by v.tag_key
  ), seed_norm as (
    select nullif(sqrt(sum(sv.w * sv.w)), 0)::double precision as n from seed_vec sv
  )
  select sum(v.w::double precision * sv.w) / ((select n from seed_norm) * max(v.l2_norm)::double precision)
    into v_sim
  from public.media_tag_vectors v
  join seed_vec sv on sv.tag_key = v.tag_key
  where v.media_type = 'ANIME' and v.media_id = p_cand
  group by v.media_id;

  select exists (select 1 from public.anime_staff xs join public.anime_staff ys
      on ys.staff_id = xs.staff_id and ys.anime_id = p_seed
      where xs.anime_id = p_cand and xs.role ilike '%director%' and ys.role ilike '%director%'),
    exists (select 1 from public.anime_studios xs join public.anime_studios ys
      on ys.studio_id = xs.studio_id and ys.anime_id = p_seed where xs.anime_id = p_cand),
    exists (select 1 from public.anime_staff xs join public.anime_staff ys
      on ys.staff_id = xs.staff_id and ys.anime_id = p_seed
      where xs.anime_id = p_cand and xs.role ilike '%creator%' and ys.role ilike '%creator%')
    into v_creator, v_studio, v_author;

  select coalesce(sum(p.penalty), 0) into v_pen
  from public.anime_tags at join public.editorial_penalty_tags p on p.tag_id = at.tag_id
  where at.anime_id = p_cand;

  v_rail := false;
  v_mult := least(2.5, least(2.0, 1.0 + 0.5 * v_creator::int + 0.15 * v_studio::int + 0.5 * v_author::int));
  v_score := (v_sim * v_mult - v_pen)::double precision;

  return jsonb_build_object('sim', v_sim, 'creator', v_creator, 'studio', v_studio,
    'author', v_author, 'mult', v_mult, 'penalty', v_pen, 'score', v_score,
    'seed', p_seed, 'cand', p_cand);
end;
$$;
revoke all on function public.debug_ranked_pair(integer, integer) from public;
grant execute on function public.debug_ranked_pair(integer, integer) to authenticated;
