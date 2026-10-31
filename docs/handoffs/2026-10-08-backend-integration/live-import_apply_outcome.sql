CREATE OR REPLACE FUNCTION public._import_apply_outcome(p_session_id uuid, p_replayed boolean)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'extensions'
AS $function$
  with items as (
    select i.*,
           case when coalesce(i.action ->> 'ordinal', '') ~ '^[0-9]{1,9}$' then (i.action ->> 'ordinal')::integer else 0 end as ord,
           -- same identity rule as the item guard and the Undo journal guard (1..2147483647)
           jsonb_build_object('mediaType', i.chosen ->> 'mediaType',
                              'mediaId', case when coalesce(i.chosen ->> 'mediaId', '') ~ '^[1-9][0-9]{0,9}$'
                                              then case when (i.chosen ->> 'mediaId')::bigint <= 2147483647
                                                        then (i.chosen ->> 'mediaId')::integer end
                                         end) as ident
    from public.import_session_items i
    where i.session_id = p_session_id
  )
  select jsonb_build_object(
    'session_id', p_session_id,
    'replayed', coalesce(p_replayed, false),
    'applied', coalesce((
      select jsonb_agg(ident || jsonb_build_object('status', after_values ->> 'list_type', 'action', import_action)
                       order by ord, created_at, id)
      from items where state = 'applied'), '[]'::jsonb),
    'skipped', coalesce((
      select jsonb_agg(ident order by ord, created_at, id)
      from items where state = 'skipped'), '[]'::jsonb),
    'conflicts', coalesce((
      select jsonb_agg(ident || jsonb_build_object('error', error) order by ord, created_at, id)
      from items where state = 'error' and action ->> 'outcome' = 'conflict'), '[]'::jsonb),
    'errors', coalesce((
      select jsonb_agg(ident || jsonb_build_object('error', error) order by ord, created_at, id)
      from items where state = 'error' and coalesce(action ->> 'outcome', 'error') <> 'conflict'), '[]'::jsonb),
    'undoable', exists (select 1 from public.import_sessions s where s.id = p_session_id and s.status = 'applied')
                and exists (select 1 from items where state = 'applied' and reverted_at is null)
  );
$function$

