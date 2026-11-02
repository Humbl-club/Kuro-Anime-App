-- TEMPORARY debug #4: run the exact cand_cos math for one (seed, candidate) pair.
drop function if exists public.debug_sim_pair(integer, integer);
create function public.debug_sim_pair(p_seed integer, p_cand integer)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_dot double precision; v_seedn double precision; v_candn double precision;
begin
  select nullif(sqrt(sum(sv.w * sv.w)), 0) into v_seedn
  from (select v.tag_key, avg(v.w)::double precision as w
        from public.media_tag_vectors v
        where v.media_type = 'ANIME' and v.media_id = p_seed
        group by v.tag_key) sv;
  select max(v.l2_norm) into v_candn from public.media_tag_vectors v
  where v.media_type = 'ANIME' and v.media_id = p_cand;
  select sum(v.w::double precision * sv.w) into v_dot
  from public.media_tag_vectors v
  join (select v2.tag_key, avg(v2.w)::double precision as w
        from public.media_tag_vectors v2
        where v2.media_type = 'ANIME' and v2.media_id = p_seed
        group by v2.tag_key) sv on sv.tag_key = v.tag_key
  where v.media_type = 'ANIME' and v.media_id = p_cand;
  return jsonb_build_object('dot', v_dot, 'seed_norm', v_seedn, 'cand_norm', v_candn,
    'similarity', v_dot / (v_seedn * v_candn));
end;
$$;
revoke all on function public.debug_sim_pair(integer, integer) from public;
grant execute on function public.debug_sim_pair(integer, integer) to authenticated;
