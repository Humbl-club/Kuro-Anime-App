-- Import review/recovery v2. Forward only: existing identities and legacy repair
-- are retained. One existing job/item lifecycle, with explicit review receipts.
begin;
alter table public.library_import_jobs
  add column contract_version integer not null default 1 check(contract_version in (1,2)),
  add column phase text,
  add column selection jsonb,
  add column exhausted_media jsonb not null default '{}',
  add column home_revisions jsonb not null default '{}',
  add column history_available boolean not null default true,
  add column completed_at timestamptz,
  add column apply_receipts jsonb not null default '{}',
  add column undo_action_id text,
  add column undo_next_cursor text,
  add column undo_receipts jsonb not null default '{}',
  add column undo_reverted integer not null default 0,
  add column undo_skipped integer not null default 0;
alter table public.library_import_items
  add column media_id integer,
  add column title text,
  add column incoming jsonb,
  add column current_values jsonb,
  add column changed_fields jsonb not null default '[]',
  add column expected_revision bigint,
  add column baseline_tombstones jsonb not null default '[]',
  add column expected_lifecycle uuid,
  add column identity_resolved boolean not null default false,
  add column manual_resolved boolean not null default false,
  add column terminal boolean not null default false,
  add column decision_action_id text,
  add column decision_hash text,
  add column before_image jsonb,
  add column after_image jsonb,
  add column post_revision bigint,
  add column post_lifecycle uuid,
  add column applied_effect boolean not null default false,
  add column undo_disposition text;
create index library_import_jobs_v2_page on public.library_import_jobs(user_id,created_at desc,id desc) where contract_version=2;
-- Existing owner SELECT RLS, auth FK/cascade, deletion barrier and write revokes
-- cover every added column. Only these definer RPCs can mutate job/item storage.

create function public._import_v2_status(p_status text,p_medium text) returns text
language sql immutable set search_path=public,extensions as $$
 select case lower(btrim(p_status))
 when 'watching' then 'WATCHING' when 'reading' then 'READING'
 when 'current' then case p_medium when 'manga' then 'READING' else 'WATCHING' end
 when 'repeating' then case p_medium when 'manga' then 'READING' else 'WATCHING' end
 when 'completed' then 'COMPLETED' when 'dropped' then 'DROPPED'
 when 'planning' then 'PLANNING' when 'plan_to_watch' then 'PLANNING' when 'plan_to_read' then 'PLANNING'
 when 'plan to watch' then 'PLANNING' when 'plan to read' then 'PLANNING'
 when 'paused' then 'PAUSED' when 'on_hold' then 'PAUSED' when 'on-hold' then 'PAUSED' when 'on hold' then 'PAUSED' end
$$;

-- Canonical wire values: absence never becomes clear. Zero score removes the
-- whole score group, keeping the previous raw value/scale/rating together.
create function public._import_v2_values(p_values jsonb,p_medium text) returns jsonb
language plpgsql immutable set search_path=public,extensions as $$
#variable_conflict use_variable
declare v jsonb:='{}'; a jsonb; k text; raw numeric; scale text; maximum numeric; rating integer; normalized_status text;
begin
 if jsonb_typeof(p_values)<>'object' or octet_length(p_values::text)>65536 then raise exception 'INVALID_VALUES'; end if;
 a:=coalesce(p_values->'unavailable_fields','[]');
 if jsonb_typeof(a)<>'array' or jsonb_array_length(a)>32
    or exists(select 1 from jsonb_array_elements(a)e where jsonb_typeof(e)<>'string') then raise exception 'INVALID_UNAVAILABLE_FIELDS'; end if;
 select coalesce(jsonb_agg(x order by x),'[]') into a from(select distinct value x from jsonb_array_elements_text(a))q;
 v:=jsonb_build_object('unavailable_fields',a);
 if p_values->>'status' is not null and not(a?'status') then
  normalized_status:=public._import_v2_status(p_values->>'status',p_medium);
  if normalized_status is null or (p_medium='anime' and normalized_status='READING') or (p_medium='manga' and normalized_status='WATCHING') then raise exception 'INVALID_STATUS'; end if;
  v:=v||jsonb_build_object('status',normalized_status);
 end if;
 foreach k in array array['progress','volumes_progress','repeat_count'] loop
  if p_values->>k is not null and not(a?k) then
   if jsonb_typeof(p_values->k)<>'number' or (p_values->>k)!~'^[0-9]{1,9}$' then raise exception 'INVALID_COUNT'; end if;
   if k='volumes_progress' and p_medium<>'manga' then raise exception 'INVALID_VOLUMES'; end if;
   v:=v||jsonb_build_object(k,(p_values->>k)::integer);
  end if;
 end loop;
 foreach k in array array['progress_label','unit_id','notes','started_raw','finished_raw','source_list_options'] loop
  if p_values->>k is not null and not(a?k) and not(k in('unit_id','progress_label')and a?'progress') and not(k in('started_raw','finished_raw')and a?'dates') and btrim(p_values->>k)<>'' then
   if jsonb_typeof(p_values->k)<>'string' or length(p_values->>k)>16384 then raise exception 'INVALID_TEXT'; end if;
   if k='unit_id' and (p_values->>k)!~*'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then raise exception 'INVALID_UNIT'; end if;
   v:=v||jsonb_build_object(k,p_values->>k);
  end if;
 end loop;
 foreach k in array array['private','hidden_from_status_lists'] loop
  if p_values->>k is not null and not(a?k or a?'privacy') then
   if jsonb_typeof(p_values->k)<>'boolean' then raise exception 'INVALID_PRIVACY'; end if;
   v:=v||jsonb_build_object(k,p_values->k);
  end if;
 end loop;
 if p_values->'custom_lists' is not null and jsonb_typeof(p_values->'custom_lists')<>'null' and not(a?'custom_lists') then
  if jsonb_typeof(p_values->'custom_lists')<>'array' or jsonb_array_length(p_values->'custom_lists')>100
     or exists(select 1 from jsonb_array_elements(p_values->'custom_lists')e where jsonb_typeof(e)<>'string' or length(e#>>'{}')>200) then raise exception 'INVALID_MEMBERSHIPS'; end if;
  select coalesce(jsonb_agg(x order by x),'[]') into a from(select distinct value x from jsonb_array_elements_text(p_values->'custom_lists')where btrim(value)<>'')q;
  if jsonb_array_length(a)>0 then v:=v||jsonb_build_object('custom_lists',a); end if;
 end if;
 a:=v->'unavailable_fields';
 if nullif(p_values->>'score_raw','') is not null and not(a?'score_raw' or a?'score' or a?'score_scale' or a?'normalized_rating') then
  if (p_values->>'score_raw')!~'^[0-9]{1,3}(\.[0-9]{1,3})?$' then raise exception 'INVALID_SCORE'; end if;
  raw:=(p_values->>'score_raw')::numeric;
  if raw>0 then
   scale:=p_values->>'score_scale'; maximum:=case scale when 'POINT_100' then 100 when 'POINT_10' then 10 when 'POINT_10_DECIMAL' then 10 when 'MAL_10' then 10 when 'POINT_5' then 5 when 'POINT_3' then 3 end;
   if maximum is null or raw>maximum then raise exception 'INVALID_SCORE_SCALE'; end if;
   if p_values->>'normalized_rating' is not null then
    if jsonb_typeof(p_values->'normalized_rating')<>'number' or (p_values->>'normalized_rating')!~'^([1-9]|10)$' then raise exception 'INVALID_RATING'; end if;
    rating:=(p_values->>'normalized_rating')::integer;
   else rating:=greatest(1,least(10,round(raw*10/maximum)::integer)); end if;
   v:=v||jsonb_build_object('score_raw',trim_scale(raw)::text,'score_scale',scale,'normalized_rating',rating);
  end if;
 end if;
 return v;
end;$$;

-- One full snapshot representation is shared by review, compare and compensation.
create function public._import_v2_row(p_user text,p_medium text,p_media integer,p_lock boolean default false) returns jsonb
language plpgsql set search_path=public,extensions as $$
#variable_conflict use_variable
declare r jsonb;
begin
 if p_medium='anime' then
  if p_lock then select to_jsonb(l) into r from public.anime_user_lists l where user_id=p_user and anime_id=p_media for update;
  else select to_jsonb(l) into r from public.anime_user_lists l where user_id=p_user and anime_id=p_media; end if;
 else
  if p_lock then select to_jsonb(l) into r from public.manga_user_lists l where user_id=p_user and manga_id=p_media for update;
  else select to_jsonb(l) into r from public.manga_user_lists l where user_id=p_user and manga_id=p_media; end if;
 end if;
 if r is null then return null; end if;
 return jsonb_build_object('status',r->'list_type','progress',r->'progress','progress_label',r->'progress_label','unit_id',r->'unit_id',
 'volumes_progress',r->'volumes_progress','score_raw',trim_scale((r->>'score_raw')::numeric)::text,'score_scale',r->'score_scale','normalized_rating',r->'rating',
 'notes',r->'notes','repeat_count',r->'repeat_count','started_raw',r->'started_raw','finished_raw',r->'finished_raw',
 'private',r->'entry_private','custom_lists',r->'source_custom_lists','hidden_from_status_lists',r->'source_hidden',
 'source_list_options',r->'source_list_options','unavailable_fields','[]'::jsonb,
 'server_revision',r->'server_revision','lifecycle_id',r->'lifecycle_id');
end;$$;

-- Apply selected semantic groups to a snapshot. An unchanged integer position
-- preserves its precise identity; a changed one clears incompatible old identity.
create function public._import_v2_target(p_current jsonb,p_incoming jsonb,p_fields jsonb,p_medium text) returns jsonb
language plpgsql immutable set search_path=public,extensions as $$
#variable_conflict use_variable
declare t jsonb:=coalesce(p_current,jsonb_build_object('status',case p_medium when 'manga' then 'READING' else 'WATCHING' end,'progress',0,'progress_label',null,'unit_id',null,
 'volumes_progress',null,'score_raw',null,'score_scale',null,'normalized_rating',null,'notes',null,'repeat_count',0,'started_raw',null,'finished_raw',null,
 'private',false,'custom_lists','[]'::jsonb,'hidden_from_status_lists',false,'source_list_options',null,'unavailable_fields','[]'::jsonb)); f text; k text;
begin
 for f in select value from jsonb_array_elements_text(p_fields) loop
  if f='progress' then
   if p_incoming?'progress' then
    if (t->'progress') is distinct from (p_incoming->'progress') then t:=t||jsonb_build_object('unit_id',null,'progress_label',null); end if;
    t:=t||jsonb_build_object('progress',p_incoming->'progress');
   end if;
   -- Never attach a new label to an old unit, or a new unit to an old label.
   if p_incoming?'progress_label'and not(p_incoming?'unit_id')and(t->'progress_label')is distinct from(p_incoming->'progress_label')then t:=t||jsonb_build_object('unit_id',null);end if;
   if p_incoming?'unit_id'and not(p_incoming?'progress_label')and(t->'unit_id')is distinct from(p_incoming->'unit_id')then t:=t||jsonb_build_object('progress_label',null);end if;
   foreach k in array array['unit_id','progress_label'] loop if p_incoming?k then t:=t||jsonb_build_object(k,p_incoming->k); end if; end loop;
  else
   for k in select unnest(case f when 'status' then array['status'] when 'score' then array['score_raw','score_scale','normalized_rating']
    when 'notes' then array['notes'] when 'privacy' then array['private','hidden_from_status_lists']
    when 'volumes_progress' then array['volumes_progress'] when 'repeat_count' then array['repeat_count']
    when 'dates' then array['started_raw','finished_raw'] when 'custom_lists' then array['custom_lists']
    when 'source_options' then array['source_list_options'] else array[]::text[] end) loop
    if p_incoming?k then t:=t||jsonb_build_object(k,p_incoming->k); end if;
   end loop;
  end if;
 end loop;
 return t;
end;$$;

create function public._import_v2_changed(p_current jsonb,p_incoming jsonb,p_medium text) returns jsonb
language plpgsql immutable set search_path=public,extensions as $$
#variable_conflict use_variable
declare f text; changed jsonb:='[]';
begin
 foreach f in array array['status','progress','score','notes','privacy','volumes_progress','repeat_count','dates','custom_lists','source_options'] loop
  if public._import_v2_target(p_current,p_incoming,jsonb_build_array(f),p_medium) is distinct from p_current then changed:=changed||jsonb_build_array(f); end if;
 end loop;
 return changed;
end;$$;

-- One database-owned Library write applies all approved fields atomically. Table
-- admission/deletion/unit-owner/revision triggers remain authoritative.
create function public._import_v2_store(p_user text,p_medium text,p_media integer,p_target jsonb,p_insert boolean) returns jsonb
language plpgsql set search_path=public,extensions as $$
begin
 if p_medium='anime' then
  if p_insert then
   insert into public.anime_user_lists(user_id,anime_id,list_type,progress,unit_id,progress_label,notes,rating,score_raw,score_scale,repeat_count,started_raw,finished_raw,entry_private,source_custom_lists,source_hidden,source_list_options)
   values(p_user,p_media,p_target->>'status',(p_target->>'progress')::integer,(p_target->>'unit_id')::uuid,p_target->>'progress_label',p_target->>'notes',(p_target->>'normalized_rating')::integer,(p_target->>'score_raw')::numeric,p_target->>'score_scale',
    (p_target->>'repeat_count')::integer,p_target->>'started_raw',p_target->>'finished_raw',(p_target->>'private')::boolean,p_target->'custom_lists',(p_target->>'hidden_from_status_lists')::boolean,p_target->>'source_list_options');
  else
   update public.anime_user_lists set list_type=p_target->>'status',progress=(p_target->>'progress')::integer,unit_id=(p_target->>'unit_id')::uuid,progress_label=p_target->>'progress_label',notes=p_target->>'notes',rating=(p_target->>'normalized_rating')::integer,
    score_raw=(p_target->>'score_raw')::numeric,score_scale=p_target->>'score_scale',repeat_count=(p_target->>'repeat_count')::integer,started_raw=p_target->>'started_raw',finished_raw=p_target->>'finished_raw',entry_private=(p_target->>'private')::boolean,
    source_custom_lists=p_target->'custom_lists',source_hidden=(p_target->>'hidden_from_status_lists')::boolean,source_list_options=p_target->>'source_list_options' where user_id=p_user and anime_id=p_media;
  end if;
 else
  if p_insert then
   insert into public.manga_user_lists(user_id,manga_id,list_type,progress,unit_id,progress_label,notes,rating,score_raw,score_scale,repeat_count,volumes_progress,started_raw,finished_raw,entry_private,source_custom_lists,source_hidden,source_list_options)
   values(p_user,p_media,p_target->>'status',(p_target->>'progress')::integer,(p_target->>'unit_id')::uuid,p_target->>'progress_label',p_target->>'notes',(p_target->>'normalized_rating')::integer,(p_target->>'score_raw')::numeric,p_target->>'score_scale',
    (p_target->>'repeat_count')::integer,(p_target->>'volumes_progress')::integer,p_target->>'started_raw',p_target->>'finished_raw',(p_target->>'private')::boolean,p_target->'custom_lists',(p_target->>'hidden_from_status_lists')::boolean,p_target->>'source_list_options');
  else
   update public.manga_user_lists set list_type=p_target->>'status',progress=(p_target->>'progress')::integer,unit_id=(p_target->>'unit_id')::uuid,progress_label=p_target->>'progress_label',notes=p_target->>'notes',rating=(p_target->>'normalized_rating')::integer,
    score_raw=(p_target->>'score_raw')::numeric,score_scale=p_target->>'score_scale',repeat_count=(p_target->>'repeat_count')::integer,volumes_progress=(p_target->>'volumes_progress')::integer,started_raw=p_target->>'started_raw',finished_raw=p_target->>'finished_raw',entry_private=(p_target->>'private')::boolean,
    source_custom_lists=p_target->'custom_lists',source_hidden=(p_target->>'hidden_from_status_lists')::boolean,source_list_options=p_target->>'source_list_options' where user_id=p_user and manga_id=p_media;
  end if;
 end if;
 return public._import_v2_row(p_user,p_medium,p_media);
end;$$;

create function public._import_v2_counts(p_job uuid) returns jsonb language sql stable set search_path=public,extensions as $$
 select jsonb_build_object('added',count(*)filter(where disposition='added'),'updated',count(*)filter(where disposition='updated'),
 'unchanged',count(*)filter(where disposition='unchanged'),'conflict',count(*)filter(where disposition in('conflict','source_changed')),
 'unmatched',count(*)filter(where disposition='unmatched'),'invalid',count(*)filter(where disposition='invalid'),
 'pending',count(*)filter(where not terminal and disposition in('new','existing','changes','pending')))from public.library_import_items where job_id=p_job
$$;
create function public._import_v2_outcome(p_job uuid) returns jsonb language sql stable set search_path=public,extensions as $$
 select jsonb_build_object('job_id',j.id,'selection',j.selection,'phase',j.phase,'counts',j.counters,
 'exhausted_media',j.exhausted_media,'home_revisions',j.home_revisions,'projection_ready',false,'history_available',j.history_available,
 'undo_action_id',j.undo_action_id,'undo_available',j.history_available and j.phase not in('undoing','undone')and exists(select 1 from public.library_import_items i where i.job_id=j.id and i.applied_effect and i.undo_disposition is null))
 from public.library_import_jobs j where j.id=p_job
$$;
create function public._import_v2_prune(p_user uuid) returns void language plpgsql set search_path=public,extensions as $$
#variable_conflict use_variable
declare ids uuid[];
begin
 select array_agg(id) into ids from(select id from public.library_import_jobs where user_id=p_user and contract_version=2 and phase in('ready','cancelled','failed','undone')
  order by completed_at desc nulls last,created_at desc,id desc offset 10)q;
 if ids is null then return; end if;
 delete from public.library_import_items where job_id=any(ids);
 delete from public.library_import_baselines where job_id=any(ids);
 update public.library_import_jobs set history_available=false,apply_receipts='{}',undo_receipts='{}' where id=any(ids)and history_available;
end;$$;
create function public._import_v2_publish(p_job uuid,p_user uuid,p_media text[]) returns void language plpgsql set search_path=public,extensions as $$
#variable_conflict use_variable
declare m text; revision bigint;
begin
 foreach m in array p_media loop
  insert into public.home_publications(user_id,medium,revision)values(p_user::text,m,1)on conflict(user_id,medium)do update set revision=public.home_publications.revision+1 returning home_publications.revision into revision;
  update public.library_import_jobs set home_revisions=home_revisions||jsonb_build_object(m,revision),home_revision=greatest(home_revision,revision)where id=p_job;
 end loop;
end;$$;

create function public.start_library_import_v2(p_selection jsonb,p_action_id text) returns jsonb
language plpgsql security definer set search_path=public,extensions as $$
#variable_conflict use_variable
declare uid uuid:=auth.uid(); sel jsonb; media jsonb; statuses jsonb; j public.library_import_jobs%rowtype; h text;
begin
 if uid is null then raise exception 'UNAUTHENTICATED'; end if;
 perform pg_advisory_xact_lock(hashtextextended('kuro.library.account:'||uid::text,0));
 perform public._account_write_guard(uid::text);
 if jsonb_typeof(p_selection)<>'object' or p_action_id is null or length(p_action_id)not between 8 and 128
  or p_selection->>'provider' is null or p_selection->>'provider' not in('anilist','myanimelist')or p_selection->>'source_kind' is null or p_selection->>'source_kind' not in('account','export')
  or nullif(btrim(p_selection->>'source_identity'),'')is null or length(p_selection->>'source_identity')>500
  or jsonb_typeof(p_selection->'media')is distinct from 'array' then raise exception 'INVALID_SELECTION'; end if;
 if jsonb_array_length(p_selection->'media')not between 1 and 2 or exists(select 1 from jsonb_array_elements(p_selection->'media')e where jsonb_typeof(e)<>'string'or lower(e#>>'{}')not in('anime','manga'))then raise exception 'INVALID_SELECTION'; end if;
 select jsonb_agg(x order by x) into media from(select distinct lower(value)x from jsonb_array_elements_text(p_selection->'media'))q;
 statuses:=coalesce(p_selection->'statuses','[]');
 if jsonb_typeof(statuses)<>'array' or jsonb_array_length(statuses)>32 or exists(select 1 from jsonb_array_elements(statuses)e where jsonb_typeof(e)<>'string')then raise exception 'INVALID_SELECTION'; end if;
 select coalesce(jsonb_agg(x order by x),'[]')into statuses from(select distinct value x from jsonb_array_elements_text(statuses))q;
 sel:=jsonb_build_object('provider',p_selection->>'provider','source_kind',p_selection->>'source_kind','source_identity',btrim(p_selection->>'source_identity'),'media',media,'statuses',statuses);
 h:=encode(digest(sel::text,'sha256'),'hex');
 select * into j from public.library_import_jobs where user_id=uid and idempotency_key=p_action_id for update;
 if found then
  if j.contract_version<>2 or j.selection is distinct from sel then raise exception 'IDEMPOTENCY_CONFLICT'; end if;
  return public._import_v2_outcome(j.id);
 end if;
 if exists(select 1 from public.library_import_jobs where user_id=uid and provider=sel->>'provider'and state in('queued','running'))then raise exception 'IMPORT_ALREADY_ACTIVE'; end if;
 insert into public.library_import_jobs(user_id,provider,source_kind,medium_filter,idempotency_key,payload_hash,state,contract_version,phase,selection,exhausted_media,counters)
 values(uid,sel->>'provider',sel->>'source_kind',case when jsonb_array_length(media)=2 then 'both'else media->>0 end,p_action_id,h,'running',2,'preparing',sel,
  (select jsonb_object_agg(x,false)from jsonb_array_elements_text(media)x),jsonb_build_object('added',0,'updated',0,'unchanged',0,'conflict',0,'unmatched',0,'invalid',0,'pending',0))returning * into j;
 return public._import_v2_outcome(j.id);
end;$$;

create function public._import_v2_tombstones(p_user text,p_medium text,p_media integer)returns jsonb
language sql stable set search_path=public,extensions as $$
 select coalesce(jsonb_agg(jsonb_build_array(lifecycle_id,server_revision)order by lifecycle_id),'[]')from public.list_entry_tombstones where user_id=p_user and medium=p_medium and media_id=p_media
$$;

create function public.prepare_import_chunk_v2(p_job_id uuid,p_items jsonb,p_exhausted_media jsonb default '{}')returns jsonb
language plpgsql security definer set search_path=public,extensions as $$
#variable_conflict use_variable
declare uid uuid:=auth.uid(); j public.library_import_jobs%rowtype; old public.library_import_items%rowtype;
 it jsonb; inc jsonb; cur jsonb; fields jsonb; medium text; external text; title text; med integer; found_ref boolean; resolved boolean;
 manual integer; disposition text; detail text; h text; m text; complete boolean; merged jsonb;
begin
 if uid is null then raise exception 'UNAUTHENTICATED'; end if;
 perform pg_advisory_xact_lock(hashtextextended('kuro.library.account:'||uid::text,0));
 select * into j from public.library_import_jobs where id=p_job_id and user_id=uid for update;
 if not found then raise exception 'NOT_AUTHORIZED'; end if;
 if j.contract_version<>2 then raise exception 'CONTRACT_VERSION_MISMATCH'; end if;
 if j.phase not in('preparing','reviewing')then raise exception 'JOB_NOT_PREPARING'; end if;
 if jsonb_typeof(p_items)is distinct from 'array' or jsonb_array_length(p_items)>100
  or jsonb_typeof(p_exhausted_media)is distinct from 'object' then raise exception 'INVALID_PAYLOAD'; end if;
 if exists(select 1 from jsonb_each(p_exhausted_media)e where not(j.selection->'media'?e.key)or jsonb_typeof(e.value)<>'boolean')then raise exception 'INVALID_COVERAGE'; end if;
 for it in select value from jsonb_array_elements(p_items)loop
  medium:=lower(it->>'medium'); external:=it->>'external_id'; manual:=null;
  if jsonb_typeof(it)<>'object'or medium is null or not(j.selection->'media'?medium)or external is null or length(external)>100 then raise exception 'INVALID_ITEM'; end if;
  if it->>'resolved_media_id' is not null then
   if jsonb_typeof(it->'resolved_media_id')<>'number'or(it->>'resolved_media_id')!~'^[1-9][0-9]{0,9}$'or(it->>'resolved_media_id')::numeric>2147483647 then raise exception 'INVALID_MAPPING'; end if;
   manual:=(it->>'resolved_media_id')::integer;
  end if;
  title:=left(coalesce(nullif(it->>'title',''),case medium when 'anime'then 'Anime 'else 'Manga 'end||external),500);
  med:=null;cur:=null;resolved:=false;found_ref:=false;detail:=null;fields:='[]';disposition:=null;
  begin
   if jsonb_typeof(it->'external_id')<>'string'or external!~'^[0-9]{1,10}$'or external::numeric>2147483647 or external::numeric<1 then raise exception 'INVALID_EXTERNAL_ID'; end if;
   inc:=public._import_v2_values(it->'values',medium);
   if not(inc?'status')then raise exception 'MISSING_STATUS'; end if;
  exception when others then
   disposition:='invalid';detail:=case sqlerrm when 'INVALID_EXTERNAL_ID'then 'Invalid provider ID'when 'INVALID_STATUS'then 'Unsupported status'else 'Invalid source values'end;
   inc:=jsonb_build_object('unavailable_fields','[]'::jsonb);
  end;
  h:=encode(digest(inc::text,'sha256'),'hex');
  select * into old from public.library_import_items where job_id=j.id and provider=j.provider and library_import_items.medium=medium and external_id=external for update;
  if found then
   if old.terminal or old.decision_hash is not null then
    if old.request_hash<>h or manual is not null then raise exception 'SOURCE_ALREADY_DECIDED'; end if;
    continue;
   end if;
   if exists(select 1 from jsonb_each(old.incoming-'custom_lists'-'unavailable_fields')x where inc?x.key and (inc->x.key)is distinct from x.value)then
    update public.library_import_items set disposition='source_changed',detail='Contradictory values across source appearances',changed_fields='[]'where job_id=j.id and provider=j.provider and library_import_items.medium=medium and external_id=external;
    continue;
   end if;
   if old.disposition='source_changed'then continue; end if;
   -- Missing/unavailable fields are not contradictory values. Merge available
   -- evidence; do not let an unavailable marker suppress a supplied valid value.
   inc:=old.incoming||inc;
   select coalesce(jsonb_agg(x order by x),'[]')into merged from(
    select distinct value x from jsonb_array_elements_text(coalesce(old.incoming->'unavailable_fields','[]')||coalesce(inc->'unavailable_fields','[]'))
    where not(inc?value))q;
   inc:=inc||jsonb_build_object('unavailable_fields',merged);
   if old.incoming?'custom_lists'or inc?'custom_lists'then
    select coalesce(jsonb_agg(x order by x),'[]')into merged from(select distinct value x from jsonb_array_elements_text(coalesce(old.incoming->'custom_lists','[]')||coalesce(inc->'custom_lists','[]')))q;
    inc:=inc||jsonb_build_object('custom_lists',merged);
   end if;
   h:=encode(digest(inc::text,'sha256'),'hex');
   -- After coverage closes, effective source evidence is immutable. A new
   -- field cannot expand a previously reviewed semantic approval group.
   if j.phase='reviewing'and inc is distinct from old.incoming then
    update public.library_import_items set disposition='source_changed',detail='Source values changed after review became ready',changed_fields='[]'where job_id=j.id and provider=j.provider and library_import_items.medium=medium and external_id=external;
    continue;
   end if;
   -- Compatible duplicate evidence must pass the same precise-unit policy
   -- as first staging before either duplicate fast path can return.
   if old.media_id is not null and(manual is null or(old.manual_resolved and manual=old.media_id))and inc->>'unit_id'is not null
    and not exists(select 1 from public.catalogue_units u where u.id=(inc->>'unit_id')::uuid and u.medium=medium
     and(case medium when 'anime'then u.anime_id else u.manga_id end)=old.media_id
     and(not(inc?'progress_label')or u.label=inc->>'progress_label'))then
    update public.library_import_items set incoming=inc,request_hash=h,disposition='invalid',detail='Source unit does not belong to the matched title or label',changed_fields='[]'where job_id=j.id and provider=j.provider and library_import_items.medium=medium and external_id=external;
    continue;
   end if;
   -- Repeating the same match must not launder a later edit/tombstone into
   -- the original review baseline. Deliberate target changes get fresh review.
   if manual is not null and old.manual_resolved and old.media_id=manual then
    update public.library_import_items set incoming=inc,request_hash=h,changed_fields=case when old.current_values is null then old.changed_fields else public._import_v2_changed(old.current_values,inc,medium)end where job_id=j.id and provider=j.provider and library_import_items.medium=medium and external_id=external;
    continue;
   end if;
   if manual is null then
    update public.library_import_items set incoming=inc,request_hash=h,
     changed_fields=case when current_values is not null then public._import_v2_changed(current_values,inc,medium)else changed_fields end,
     disposition=case when current_values is not null then case when jsonb_array_length(public._import_v2_changed(current_values,inc,medium))=0 then 'existing'else 'changes'end else library_import_items.disposition end
     where job_id=j.id and provider=j.provider and library_import_items.medium=medium and external_id=external;
    continue;
   end if;
  elsif coalesce((j.exhausted_media->>medium)::boolean,false)then raise exception 'SOURCE_ALREADY_EXHAUSTED'; end if;
  if disposition is null then
   select case when unresolved then null when medium='anime'then anime_id else manga_id end,not unresolved into med,resolved from public.provider_entry_refs
    where provider=j.provider and provider_entry_refs.medium=medium and external_id=external;
   found_ref:=found;
   if not found_ref then
    if medium='anime'then
     if j.provider='anilist'then select min(id)into med from public.anime where anilist_id=external::integer having count(*)=1;
     else select min(id)into med from public.anime where mal_id=external::integer having count(*)=1;end if;
    else
     if j.provider='anilist'then select min(id)into med from public.manga where anilist_id=external::integer having count(*)=1;
     else select min(id)into med from public.manga where mal_id=external::integer having count(*)=1;end if;
    end if;
    resolved:=med is not null;
   end if;
   if manual is not null then
    if resolved or old.identity_resolved then raise exception 'MAPPING_ALREADY_RESOLVED'; end if;
    if (medium='anime'and not exists(select 1 from public.anime where id=manual))or(medium='manga'and not exists(select 1 from public.manga where id=manual))then raise exception 'INVALID_MAPPING';end if;
    med:=manual;
   end if;
   if med is null then disposition:='unmatched';detail:='Catalogue identity requires review';
   else
    if inc->>'unit_id'is not null and not exists(select 1 from public.catalogue_units u where u.id=(inc->>'unit_id')::uuid and u.medium=medium and(case medium when 'anime'then u.anime_id else u.manga_id end)=med and(not(inc?'progress_label')or u.label=inc->>'progress_label'))then
     disposition:='invalid';detail:='Source unit does not belong to the matched title';
    else
     cur:=public._import_v2_row(uid::text,medium,med);
     fields:=case when cur is null then '[]'::jsonb else public._import_v2_changed(cur,inc,medium)end;
     disposition:=case when cur is null then 'new'when jsonb_array_length(fields)=0 then 'existing'else 'changes'end;
     if medium='anime'then select left(coalesce(title_english,title_romaji,title_native,title),500)into title from public.anime where id=med;
     else select left(coalesce(title_english,title_romaji,title_native,title),500)into title from public.manga where id=med;end if;
    end if;
   end if;
  elsif manual is not null then raise exception 'INVALID_MAPPING'; end if;
  insert into public.library_import_items(job_id,provider,external_id,medium,disposition,request_hash,detail,media_id,title,incoming,current_values,changed_fields,expected_revision,expected_lifecycle,identity_resolved,manual_resolved,baseline_tombstones)
  values(j.id,j.provider,external,medium,disposition,h,detail,med,title,inc,cur,fields,(cur->>'server_revision')::bigint,(cur->>'lifecycle_id')::uuid,resolved,manual is not null,public._import_v2_tombstones(uid::text,medium,med))
  on conflict on constraint library_import_items_pkey do update set disposition=excluded.disposition,request_hash=excluded.request_hash,detail=excluded.detail,media_id=excluded.media_id,title=excluded.title,incoming=excluded.incoming,
   current_values=excluded.current_values,changed_fields=excluded.changed_fields,expected_revision=excluded.expected_revision,expected_lifecycle=excluded.expected_lifecycle,identity_resolved=excluded.identity_resolved,manual_resolved=excluded.manual_resolved,baseline_tombstones=excluded.baseline_tombstones;
 end loop;
 foreach m in array array['anime','manga']loop
  if coalesce((p_exhausted_media->>m)::boolean,false)then j.exhausted_media:=j.exhausted_media||jsonb_build_object(m,true);end if;
 end loop;
 complete:=not exists(select 1 from jsonb_array_elements_text(j.selection->'media')s(medium)where not coalesce((j.exhausted_media->>s.medium)::boolean,false));
 update public.library_import_jobs set exhausted_media=j.exhausted_media,counters=public._import_v2_counts(j.id),phase=case when complete then 'reviewing'else 'preparing'end,updated_at=clock_timestamp()where id=j.id;
 return public._import_v2_outcome(j.id);
end;$$;

create function public.apply_import_chunk_v2(p_job_id uuid,p_action_id text,p_decisions jsonb)returns jsonb
language plpgsql security definer set search_path=public,extensions as $$
#variable_conflict use_variable
declare uid uuid:=auth.uid();j public.library_import_jobs%rowtype;i public.library_import_items%rowtype;d jsonb;fields jsonb;cur jsonb;t jsonb;after_row jsonb;h text;dh text;
 action text;medium text;external text;effects text[]:=array[]::text[];outcome jsonb;receipt jsonb;
begin
 if uid is null then raise exception 'UNAUTHENTICATED';end if;
 perform pg_advisory_xact_lock(hashtextextended('kuro.library.account:'||uid::text,0));
 select *into j from public.library_import_jobs where id=p_job_id and user_id=uid for update;
 if not found then raise exception 'NOT_AUTHORIZED';end if;
 if j.contract_version<>2 then raise exception 'CONTRACT_VERSION_MISMATCH';end if;
 if p_action_id is null or length(p_action_id)not between 8 and 128 or jsonb_typeof(p_decisions)is distinct from 'array'or jsonb_array_length(p_decisions)not between 1 and 100 then raise exception 'INVALID_DECISIONS';end if;
 h:=encode(digest(p_decisions::text,'sha256'),'hex');receipt:=j.apply_receipts->(p_action_id||':'||h);
 if receipt is not null then
  if receipt->>'hash'<>h then raise exception 'IDEMPOTENCY_CONFLICT';end if;
  return receipt->'response';
 end if;
 if not j.history_available then raise exception 'HISTORY_UNAVAILABLE';end if;
 if j.phase not in('reviewing','applying')then raise exception 'JOB_NOT_APPLYING';end if;
 if exists(select 1 from jsonb_array_elements_text(j.selection->'media')s(medium)where not coalesce((j.exhausted_media->>s.medium)::boolean,false))then raise exception 'SOURCE_INCOMPLETE';end if;
 for d in select value from jsonb_array_elements(p_decisions)order by value->>'medium',value->>'external_id'loop
  medium:=d->>'medium';external:=d->>'external_id';action:=d->>'action';fields:=coalesce(d->'fields','[]');
  if medium is null or medium not in('anime','manga')or external is null or action is null or action not in('add','keep','update','defer')or jsonb_typeof(fields)<>'array'
    or exists(select 1 from jsonb_array_elements(fields)e where jsonb_typeof(e)<>'string'or(e#>>'{}')not in('status','progress','score','notes','privacy','volumes_progress','repeat_count','dates','custom_lists','source_options'))then raise exception 'INVALID_DECISION';end if;
  select *into i from public.library_import_items where job_id=j.id and provider=j.provider and library_import_items.medium=medium and external_id=external for update;
  if not found then raise exception 'UNKNOWN_REVIEW_ITEM';end if;
  dh:=encode(digest(d::text,'sha256'),'hex');
  if i.decision_hash is not null then
   if i.decision_hash<>dh or i.decision_action_id<>p_action_id then raise exception 'DECISION_ALREADY_FINAL';end if;
   continue;
  end if;
  if (i.manual_resolved and action<>'defer'and(d->>'resolved_media_id')is distinct from i.media_id::text)
   or(d->>'resolved_media_id'is not null and(d->>'resolved_media_id')is distinct from i.media_id::text)then raise exception 'UNREVIEWED_MAPPING';end if;
  if i.disposition='source_changed'and action<>'defer'then raise exception 'SOURCE_CHANGED';end if;
  if action='defer'then
   update public.library_import_items set terminal=true,decision_hash=dh,decision_action_id=p_action_id,
    disposition=case when disposition in('invalid','unmatched','source_changed','conflict')then disposition else 'conflict'end,
    detail=coalesce(detail,'Deferred for review')where job_id=j.id and provider=j.provider and library_import_items.medium=medium and external_id=external;
   continue;
  end if;
  if i.disposition in('invalid','unmatched','source_changed')or i.media_id is null then raise exception 'ITEM_REQUIRES_REVIEW';end if;
  if (d->>'expected_revision')is distinct from i.expected_revision::text or(d->>'expected_lifecycle')is distinct from i.expected_lifecycle::text then raise exception 'REVIEW_BASELINE_MISMATCH';end if;
  cur:=public._import_v2_row(uid::text,medium,i.media_id,true);
  if (cur->>'server_revision')is distinct from i.expected_revision::text or(cur->>'lifecycle_id')is distinct from i.expected_lifecycle::text
    or (cur is null and public._import_v2_tombstones(uid::text,medium,i.media_id)is distinct from i.baseline_tombstones)then
   update public.library_import_items set disposition='conflict',terminal=true,detail='Library entry changed since review',decision_hash=dh,decision_action_id=p_action_id where job_id=j.id and provider=j.provider and library_import_items.medium=medium and external_id=external;
   continue;
  end if;
  if action='keep'then
   if cur is null then raise exception 'KEEP_REQUIRES_EXISTING';end if;
   update public.library_import_items set disposition='unchanged',terminal=true,decision_hash=dh,decision_action_id=p_action_id where job_id=j.id and provider=j.provider and library_import_items.medium=medium and external_id=external;
   continue;
  end if;
  if(action='add'and cur is not null)or(action='update'and cur is null)then raise exception 'INVALID_DECISION';end if;
  if action='add'then fields:=to_jsonb(array['status','progress','score','notes','privacy','volumes_progress','repeat_count','dates','custom_lists','source_options']);end if;
  t:=public._import_v2_target(cur,i.incoming,fields,medium);
  if t is not distinct from cur then
   update public.library_import_items set disposition='unchanged',terminal=true,decision_hash=dh,decision_action_id=p_action_id where job_id=j.id and provider=j.provider and library_import_items.medium=medium and external_id=external;
   continue;
  end if;
  after_row:=public._import_v2_store(uid::text,medium,i.media_id,t,cur is null);
  update public.library_import_items set disposition=case when cur is null then 'added'else 'updated'end,terminal=true,decision_hash=dh,decision_action_id=p_action_id,
   before_image=cur,after_image=after_row,post_revision=(after_row->>'server_revision')::bigint,post_lifecycle=(after_row->>'lifecycle_id')::uuid,applied_effect=true
   where job_id=j.id and provider=j.provider and library_import_items.medium=medium and external_id=external;
  if not(medium=any(effects))then effects:=array_append(effects,medium);end if;
 end loop;
 perform public._import_v2_publish(j.id,uid,effects);
 update public.library_import_jobs set counters=public._import_v2_counts(j.id),phase='applying',updated_at=clock_timestamp()where id=j.id;
 outcome:=public._import_v2_outcome(j.id);
 update public.library_import_jobs set apply_receipts=apply_receipts||jsonb_build_object(p_action_id||':'||h,jsonb_build_object('hash',h,'response',outcome))where id=j.id;
 return outcome;
end;$$;

create function public.finish_library_import_v2(p_job_id uuid)returns jsonb
language plpgsql security definer set search_path=public,extensions as $$
#variable_conflict use_variable
declare uid uuid:=auth.uid();j public.library_import_jobs%rowtype;
begin
 if uid is null then raise exception 'UNAUTHENTICATED';end if;
 perform pg_advisory_xact_lock(hashtextextended('kuro.library.account:'||uid::text,0));
 select *into j from public.library_import_jobs where id=p_job_id and user_id=uid for update;
 if not found then raise exception 'NOT_AUTHORIZED';end if;
 if j.contract_version<>2 then raise exception 'CONTRACT_VERSION_MISMATCH';end if;
 if j.phase in('ready','failed')then return public._import_v2_outcome(j.id);end if;
 if j.phase not in('reviewing','applying')then raise exception 'JOB_NOT_FINALIZING';end if;
 if exists(select 1 from jsonb_array_elements_text(j.selection->'media')s(medium)where not coalesce((j.exhausted_media->>s.medium)::boolean,false))then raise exception 'SOURCE_INCOMPLETE';end if;
 if exists(select 1 from public.library_import_items where job_id=j.id and not terminal)then raise exception 'DECISIONS_INCOMPLETE';end if;
 update public.library_import_jobs set phase='ready',state=case when exists(select 1 from public.library_import_items where job_id=j.id and disposition in('conflict','source_changed','invalid','unmatched'))then 'ready_with_issues'else 'ready'end,
 counters=public._import_v2_counts(j.id),completed_at=clock_timestamp(),updated_at=clock_timestamp()where id=j.id;
 perform public._import_v2_prune(uid);
 return public._import_v2_outcome(j.id);
end;$$;
create function public.import_job_status_v2(p_job_id uuid)returns jsonb
language plpgsql stable security definer set search_path=public,extensions as $$
#variable_conflict use_variable
declare uid uuid:=auth.uid();version integer;
begin
 if uid is null then raise exception 'UNAUTHENTICATED';end if;
 select contract_version into version from public.library_import_jobs where id=p_job_id and user_id=uid;
 if not found then raise exception 'NOT_AUTHORIZED';end if;
 if version<>2 then raise exception 'CONTRACT_VERSION_MISMATCH';end if;
 return public._import_v2_outcome(p_job_id);
end;$$;
create function public._import_v2_cursor(p_value jsonb)returns text language sql immutable set search_path=public,extensions as $$
 select encode(convert_to(p_value::text,'UTF8'),'base64')
$$;
create function public._import_v2_decode(p_value text)returns jsonb language plpgsql immutable set search_path=public,extensions as $$
begin
 if p_value is null then return null;end if;
 if length(p_value)>1024 then raise exception 'INVALID_CURSOR';end if;
 return convert_from(decode(p_value,'base64'),'UTF8')::jsonb;
exception when others then raise exception 'INVALID_CURSOR';
end;$$;
create function public.import_jobs_page_v2(p_cursor text default null,p_limit integer default 50)returns jsonb
language plpgsql stable security definer set search_path=public,extensions as $$
#variable_conflict use_variable
declare uid uuid:=auth.uid();c jsonb;at timestamptz;id uuid;rows jsonb;next text;last_row public.library_import_jobs%rowtype;
begin
 if uid is null then raise exception 'UNAUTHENTICATED';end if;
 if p_limit is null or p_limit not between 1 and 50 then raise exception 'INVALID_LIMIT';end if;
 c:=public._import_v2_decode(p_cursor);
 if c is not null then
  begin at:=(c->>'created_at')::timestamptz;id:=(c->>'id')::uuid;if at is null or id is null then raise exception 'INVALID_CURSOR';end if;
  exception when others then raise exception 'INVALID_CURSOR';end;
 end if;
 select coalesce(jsonb_agg(public._import_v2_outcome(q.id)order by q.created_at desc,q.id desc),'[]')into rows from
  (select j.id,j.created_at from public.library_import_jobs j where user_id=uid and contract_version=2 and(at is null or(j.created_at,j.id)<(at,id))order by j.created_at desc,j.id desc limit p_limit)q;
 select *into last_row from public.library_import_jobs j where user_id=uid and contract_version=2 and(at is null or(j.created_at,j.id)<(at,id))order by j.created_at desc,j.id desc offset p_limit-1 limit 1;
 if found and exists(select 1 from public.library_import_jobs j where user_id=uid and contract_version=2 and(j.created_at,j.id)<(last_row.created_at,last_row.id))then
  next:=public._import_v2_cursor(jsonb_build_object('created_at',last_row.created_at::text,'id',last_row.id));
 end if;
 return jsonb_build_object('jobs',rows,'next_cursor',next);
end;$$;
create function public.import_items_page_v2(p_job_id uuid,p_cursor text default null,p_limit integer default 50)returns jsonb
language plpgsql stable security definer set search_path=public,extensions as $$
#variable_conflict use_variable
declare uid uuid:=auth.uid();j public.library_import_jobs%rowtype;c jsonb;m text;e text;rows jsonb;next text;last_item public.library_import_items%rowtype;
begin
 if uid is null then raise exception 'UNAUTHENTICATED';end if;
 select *into j from public.library_import_jobs where id=p_job_id and user_id=uid;
 if not found then raise exception 'NOT_AUTHORIZED';end if;
 if j.contract_version<>2 then raise exception 'CONTRACT_VERSION_MISMATCH';end if;
 if not j.history_available then raise exception 'HISTORY_UNAVAILABLE';end if;
 if p_limit is null or p_limit not between 1 and 50 then raise exception 'INVALID_LIMIT';end if;
 c:=public._import_v2_decode(p_cursor);m:=c->>'medium';e:=c->>'external_id';
 if c is not null and(m is null or e is null or m not in('anime','manga'))then raise exception 'INVALID_CURSOR';end if;
 select coalesce(jsonb_agg(jsonb_build_object('medium',q.medium,'external_id',q.external_id,'media_id',q.media_id,'title',coalesce(q.title,'Unknown title'),
  'incoming',q.incoming,'current',q.current_values- 'server_revision'-'lifecycle_id','expected_revision',q.expected_revision,'expected_lifecycle',q.expected_lifecycle,
  'disposition',q.disposition,'detail',q.detail,'changed_fields',q.changed_fields,'undo_disposition',q.undo_disposition)order by q.medium,q.external_id),'[]')into rows
 from(select *from public.library_import_items i where job_id=j.id and(m is null or(i.medium,i.external_id)>(m,e))order by i.medium,i.external_id limit p_limit)q;
 select *into last_item from public.library_import_items i where job_id=j.id and(m is null or(i.medium,i.external_id)>(m,e))order by i.medium,i.external_id offset p_limit-1 limit 1;
 if found and exists(select 1 from public.library_import_items i where job_id=j.id and(i.medium,i.external_id)>(last_item.medium,last_item.external_id))then next:=public._import_v2_cursor(jsonb_build_object('medium',last_item.medium,'external_id',last_item.external_id));end if;
 return jsonb_build_object('items',rows,'next_cursor',next);
end;$$;
create function public.cancel_library_import_v2(p_job_id uuid)returns jsonb
language plpgsql security definer set search_path=public,extensions as $$
#variable_conflict use_variable
declare uid uuid:=auth.uid();j public.library_import_jobs%rowtype;
begin
 if uid is null then raise exception 'UNAUTHENTICATED';end if;
 perform pg_advisory_xact_lock(hashtextextended('kuro.library.account:'||uid::text,0));
 select *into j from public.library_import_jobs where id=p_job_id and user_id=uid for update;
 if not found then raise exception 'NOT_AUTHORIZED';end if;
 if j.contract_version<>2 then raise exception 'CONTRACT_VERSION_MISMATCH';end if;
 if j.phase in('ready','failed','cancelled','undoing','undone')then return public._import_v2_outcome(j.id);end if;
 update public.library_import_jobs set phase='cancelled',state='cancelled',completed_at=clock_timestamp(),updated_at=clock_timestamp()where id=j.id;
 perform public._import_v2_prune(uid);
 return public._import_v2_outcome(j.id);
end;$$;

create function public.undo_library_import_chunk_v2(p_job_id uuid,p_action_id text,p_cursor text default null,p_limit integer default 100)returns jsonb
language plpgsql security definer set search_path=public,extensions as $$
#variable_conflict use_variable
declare uid uuid:=auth.uid();j public.library_import_jobs%rowtype;i public.library_import_items%rowtype;c jsonb;cur jsonb;m text;e text;last_m text;last_e text;
 next text;key text:=coalesce(p_cursor,'@first');h text;receipt jsonb;outcome jsonb;effects text[]:=array[]::text[];reason text;reverted integer:=0;skipped integer:=0;
begin
 if uid is null then raise exception 'UNAUTHENTICATED';end if;
 perform pg_advisory_xact_lock(hashtextextended('kuro.library.account:'||uid::text,0));
 select *into j from public.library_import_jobs where id=p_job_id and user_id=uid for update;
 if not found then raise exception 'NOT_AUTHORIZED';end if;
 if j.contract_version<>2 then raise exception 'CONTRACT_VERSION_MISMATCH';end if;
 if p_action_id is null or length(p_action_id)not between 8 and 128 or p_limit is null or p_limit not between 1 and 100 then raise exception 'INVALID_UNDO';end if;
 if not j.history_available then raise exception 'HISTORY_UNAVAILABLE';end if;
 if j.undo_action_id is not null and j.undo_action_id<>p_action_id then raise exception 'IDEMPOTENCY_CONFLICT';end if;
 h:=encode(digest(jsonb_build_object('cursor',p_cursor,'limit',p_limit)::text,'sha256'),'hex');receipt:=j.undo_receipts->key;
 if receipt is not null then
  if receipt->>'hash'<>h then raise exception 'IDEMPOTENCY_CONFLICT';end if;
  return receipt->'response';
 end if;
 if j.phase='undone'then raise exception 'UNDO_ALREADY_FINISHED';end if;
 if p_cursor is distinct from j.undo_next_cursor then raise exception 'INVALID_UNDO_CURSOR';end if;
 c:=public._import_v2_decode(p_cursor);m:=c->>'medium';e:=c->>'external_id';
 if c is not null and(m is null or e is null or m not in('anime','manga'))then raise exception 'INVALID_CURSOR';end if;
 -- Stop remaining application before the first compensation write, under the
 -- same account/job locks. Already committed effects remain independently owned.
 update public.library_import_jobs set phase='undoing',state='cancelled',undo_action_id=p_action_id,updated_at=clock_timestamp()where id=j.id;
 for i in select *from public.library_import_items x where job_id=j.id and applied_effect and(m is null or(x.medium,x.external_id)>(m,e))order by x.medium,x.external_id limit p_limit for update loop
  last_m:=i.medium;last_e:=i.external_id;reason:=null;
  cur:=public._import_v2_row(uid::text,i.medium,i.media_id,true);
  if cur is null then reason:='removed';
  elsif(cur->>'lifecycle_id')is distinct from i.post_lifecycle::text then reason:='replaced';
  elsif(cur->>'server_revision')is distinct from i.post_revision::text then reason:='edited';end if;
  if reason is null then
   if i.before_image is null then
    if i.medium='anime'then delete from public.anime_user_lists where user_id=uid::text and anime_id=i.media_id;
    else delete from public.manga_user_lists where user_id=uid::text and manga_id=i.media_id;end if;
   else perform public._import_v2_store(uid::text,i.medium,i.media_id,i.before_image,false);end if;
   reason:='reverted';reverted:=reverted+1;
   if not(i.medium=any(effects))then effects:=array_append(effects,i.medium);end if;
  else skipped:=skipped+1;end if;
  update public.library_import_items set undo_disposition=reason where job_id=j.id and provider=j.provider and medium=i.medium and external_id=i.external_id;
 end loop;
 if last_m is not null and exists(select 1 from public.library_import_items x where job_id=j.id and applied_effect and(x.medium,x.external_id)>(last_m,last_e))then next:=public._import_v2_cursor(jsonb_build_object('medium',last_m,'external_id',last_e));end if;
 perform public._import_v2_publish(j.id,uid,effects);
 update public.library_import_jobs set undo_reverted=undo_reverted+reverted,undo_skipped=undo_skipped+skipped,undo_next_cursor=next,
  phase=case when next is null then 'undone'else 'undoing'end,completed_at=case when next is null then clock_timestamp()else completed_at end,updated_at=clock_timestamp()where id=j.id;
 outcome:=jsonb_build_object('job',public._import_v2_outcome(j.id),'reverted',j.undo_reverted+reverted,'skipped',j.undo_skipped+skipped,'next_cursor',next);
 update public.library_import_jobs set undo_receipts=undo_receipts||jsonb_build_object(key,jsonb_build_object('hash',h,'response',outcome))where id=j.id;
 if next is null then perform public._import_v2_prune(uid);end if;
 return outcome;
end;$$;


-- v1 keeps its original contract but cannot bypass v2 review decisions.
create or replace function public.start_library_import_v1(
  p_provider text,
  p_source_kind text,
  p_medium_filter text,
  p_idempotency_key text,
  p_payload_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_job public.library_import_jobs%rowtype;
begin
  perform pg_advisory_xact_lock(hashtextextended('kuro.library.account:'||auth.uid()::text,0));
  if v_uid is null then
    raise exception 'UNAUTHENTICATED';
  end if;
  if p_provider not in ('anilist', 'myanimelist')
     or p_source_kind not in ('account', 'export')
     or p_medium_filter not in ('anime', 'manga', 'both')
     or p_idempotency_key is null or length(p_idempotency_key) < 8
     or p_payload_hash is null or length(p_payload_hash) < 8 then
    raise exception 'INVALID_PAYLOAD';
  end if;
  -- OAuth/PKCE is qualified by the connector. Account and file sources enter the
  -- same owner-scoped structured job; neither endpoint stores provider tokens.

  select * into v_job
  from public.library_import_jobs
  where user_id = v_uid and idempotency_key = p_idempotency_key;

  if v_job.id is not null then
    if v_job.contract_version<>1 then raise exception 'CONTRACT_VERSION_MISMATCH'; end if;
    if v_job.payload_hash <> p_payload_hash or v_job.provider <> p_provider or v_job.source_kind <> p_source_kind or v_job.medium_filter <> p_medium_filter then
      raise exception 'IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object('job_id', v_job.id, 'state', v_job.state, 'resumed', true, 'home_revision', v_job.home_revision);
  end if;

  if exists (
    select 1 from public.library_import_jobs
    where user_id = v_uid and provider = p_provider 
      and state in ('queued', 'running')
  ) then
    raise exception 'IMPORT_ALREADY_ACTIVE';
  end if;

  insert into public.library_import_jobs
    (user_id, provider, source_kind, medium_filter, idempotency_key, payload_hash, state)
  values
    (v_uid, p_provider, p_source_kind, p_medium_filter, p_idempotency_key, p_payload_hash, 'running')
  returning * into v_job;

  insert into public.library_import_baselines(job_id, medium, media_id, lifecycle_id, server_revision)
  select v_job.id, 'anime', anime_id, lifecycle_id, server_revision from public.anime_user_lists
    where user_id = v_uid::text and p_medium_filter in ('anime', 'both')
  union all
  select v_job.id, 'manga', manga_id, lifecycle_id, server_revision from public.manga_user_lists
    where user_id = v_uid::text and p_medium_filter in ('manga', 'both');

  return jsonb_build_object('job_id', v_job.id, 'state', v_job.state, 'resumed', false, 'home_revision', 0);
end;
$$;


-- v1 keeps its original contract but cannot bypass v2 review decisions.
create or replace function public.apply_import_chunk_v1(p_job_id uuid, p_items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_job public.library_import_jobs%rowtype;
  v_item jsonb;
  v_medium text;
  v_external text;
  v_media_id integer;
  v_status text;
  v_progress integer;
  v_notes text;
  v_added integer := 0;
  v_updated_count integer := 0;
  v_conflict integer := 0;
  v_unmatched integer := 0;
  v_unchanged integer := 0;
  v_list_type text;
  v_updated timestamptz;
  v_local_progress integer;
  v_local_notes text;
  v_baseline public.library_import_baselines%rowtype;
  v_current_revision bigint;
  v_current_lifecycle uuid;
  v_request_hash text;
  v_prior_hash text;
  v_prior_disposition text;
  v_disposition text;
  v_written integer;
  v_ref_found boolean;
  v_unavailable jsonb;
begin
  perform pg_advisory_xact_lock(hashtextextended('kuro.library.account:'||auth.uid()::text,0));
  if v_uid is null then
    raise exception 'UNAUTHENTICATED';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) > 100 then
    raise exception 'INVALID_PAYLOAD';
  end if;

  select * into v_job from public.library_import_jobs where id = p_job_id and user_id = v_uid for update;
  if v_job.id is null then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if v_job.contract_version<>1 then raise exception 'CONTRACT_VERSION_MISMATCH'; end if;
  if v_job.state not in ('queued', 'running', 'ready', 'ready_with_issues') then raise exception 'JOB_NOT_RUNNING'; end if;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_medium := lower(v_item->>'medium');
    v_external := v_item->>'external_id';
    if v_medium not in ('anime', 'manga') or v_external is null or v_external !~ '^[0-9]{1,10}$'
       or (v_job.medium_filter <> 'both' and v_medium <> v_job.medium_filter) then raise exception 'INVALID_ITEM'; end if;
    if length(coalesce(v_item->>'source_list_options',''))>16384 then raise exception 'OPTIONS_TOO_LARGE'; end if;
    v_unavailable:='[]'::jsonb;
    if nullif(v_item->>'source_list_options','') is not null then
      begin
        v_unavailable:=coalesce((v_item->>'source_list_options')::jsonb->'unavailable_fields','[]'::jsonb);
        if jsonb_typeof(v_unavailable)<>'array' then raise exception 'INVALID_SOURCE_OPTIONS'; end if;
      exception when others then raise exception 'INVALID_SOURCE_OPTIONS'; end;
    end if;
    if v_item->>'normalized_rating' is not null and (v_item->>'normalized_rating')::integer not between 1 and 10 then raise exception 'INVALID_RATING'; end if;
    v_request_hash := encode(digest(v_item::text, 'sha256'), 'hex');
    select request_hash, disposition into v_prior_hash, v_prior_disposition from public.library_import_items
      where job_id = v_job.id and provider = v_job.provider and external_id = v_external and medium = v_medium;
    if found then
      if v_prior_hash is distinct from v_request_hash then raise exception 'IDEMPOTENCY_CONFLICT'; end if;
      continue; -- A terminal item's write and count are committed together; replay changes neither.
    end if;
    if v_job.state in ('ready', 'ready_with_issues') then raise exception 'JOB_ALREADY_FINISHED'; end if;
    v_media_id := null;
    select case when unresolved then null when v_medium='anime' then anime_id else manga_id end
      into v_media_id from public.provider_entry_refs
      where provider=v_job.provider and medium=v_medium and external_id=v_external;
    v_ref_found := found;
    if not v_ref_found and v_external ~ '^[0-9]+$' and v_medium = 'anime' and v_job.provider = 'anilist' then
      select min(a.id) into v_media_id from public.anime a
      where a.anilist_id = v_external::integer
      having count(*)=1;
    elsif not v_ref_found and v_external ~ '^[0-9]+$' and v_medium = 'manga' and v_job.provider = 'anilist' then
      select min(m.id) into v_media_id from public.manga m
      where m.anilist_id = v_external::integer
      having count(*)=1;
    elsif not v_ref_found and v_external ~ '^[0-9]+$' and v_medium = 'anime' and v_job.provider = 'myanimelist' then
      select min(a.id) into v_media_id from public.anime a where a.mal_id = v_external::integer having count(*)=1;
    elsif not v_ref_found and v_external ~ '^[0-9]+$' and v_medium = 'manga' and v_job.provider = 'myanimelist' then
      select min(m.id) into v_media_id from public.manga m where m.mal_id = v_external::integer having count(*)=1;
    end if;

    if v_media_id is null then
      v_unmatched := v_unmatched + 1;
      insert into public.library_import_items (job_id, provider, external_id, medium, disposition, request_hash, detail)
      values (v_job.id, v_job.provider, coalesce(v_external, ''), coalesce(v_medium, ''), 'unmatched', v_request_hash, 'catalogue id not found')
      on conflict (job_id, provider, external_id, medium) do update set disposition = 'unmatched';
      continue;
    end if;

    v_status := lower(coalesce(v_item->>'status', ''));
    v_list_type := case v_status
      when 'watching' then 'WATCHING'
      when 'current' then case when v_medium = 'manga' then 'READING' else 'WATCHING' end
      when 'reading' then 'READING'
      when 'completed' then 'COMPLETED'
      when 'planning' then 'PLANNING'
      when 'plan to watch' then 'PLANNING'
      when 'plan to read' then 'PLANNING'
      when 'dropped' then 'DROPPED'
      when 'paused' then 'PAUSED'
      when 'on-hold' then 'PAUSED'
      when 'on hold' then 'PAUSED'
      when 'repeating' then case when v_medium = 'manga' then 'READING' else 'WATCHING' end
      else null
    end;
    v_progress := coalesce((v_item->>'progress')::integer, 0);
    v_notes := v_item->>'notes';
    if coalesce(v_item->>'score_raw', '') ~ '^[0-9]+(\.[0-9]+)?$'
       and (v_item->>'score_raw')::numeric = 0 then
      v_item := v_item || jsonb_build_object('score_raw', null);
    end if;

    if v_medium = 'anime' then
      select updated_at, progress, notes, server_revision, lifecycle_id into v_updated, v_local_progress, v_local_notes, v_current_revision, v_current_lifecycle
      from public.anime_user_lists where user_id = v_uid::text and anime_id = v_media_id
      for update;
    else
      select updated_at, progress, notes, server_revision, lifecycle_id into v_updated, v_local_progress, v_local_notes, v_current_revision, v_current_lifecycle
      from public.manga_user_lists where user_id = v_uid::text and manga_id = v_media_id
      for update;
    end if;

    select * into v_baseline from public.library_import_baselines
      where job_id = v_job.id and medium = v_medium and media_id = v_media_id;
    if (v_baseline.media_id is not null and (v_current_revision is distinct from v_baseline.server_revision
          or v_current_lifecycle is distinct from v_baseline.lifecycle_id))
       or (v_baseline.media_id is null and v_current_lifecycle is not null)
       or exists (select 1 from public.list_entry_tombstones where user_id = v_uid::text and medium = v_medium
          and media_id = v_media_id and removed_at >= v_job.created_at) then
      v_conflict := v_conflict + 1;
      insert into public.library_import_items (job_id, provider, external_id, medium, disposition, request_hash)
      values (v_job.id, v_job.provider, v_external, v_medium, 'conflict', v_request_hash)
      on conflict (job_id, provider, external_id, medium) do update set disposition = 'conflict';
      continue;
    end if;

    if v_list_type is null then
      v_unmatched := v_unmatched + 1;
      insert into public.library_import_items(job_id, provider, external_id, medium, disposition, request_hash, detail)
      values(v_job.id, v_job.provider, v_external, v_medium, 'unmatched', v_request_hash, 'unsupported status');
      continue;
    end if;

    if v_medium = 'anime' then
      insert into public.anime_user_lists
        (user_id, anime_id, list_type, progress, notes, score_raw, score_scale, repeat_count, started_raw, finished_raw, entry_private, source_custom_lists, source_hidden, source_list_options, rating)
      values (
        v_uid::text, v_media_id, v_list_type, v_progress, v_notes,
        nullif(v_item->>'score_raw', '')::numeric, v_item->>'score_scale',
        coalesce((v_item->>'repeat_count')::integer, 0), v_item->>'started_raw', v_item->>'finished_raw', coalesce((v_item->>'private')::boolean, false),
        coalesce(v_item->'custom_lists', '[]'::jsonb), coalesce((v_item->>'hidden_from_status_lists')::boolean, false), v_item->>'source_list_options',coalesce((v_item->>'normalized_rating')::integer,case when v_item->>'score_scale'='POINT_10' and nullif(v_item->>'score_raw','')::numeric between 1 and 10 then round((v_item->>'score_raw')::numeric)::integer end)
      )
      on conflict (user_id, anime_id) do update set
        list_type = excluded.list_type,
        progress = case when v_item ? 'progress' and not(v_unavailable ? 'progress') then excluded.progress else public.anime_user_lists.progress end,
        notes = coalesce(excluded.notes, public.anime_user_lists.notes),
        score_raw = coalesce(excluded.score_raw, public.anime_user_lists.score_raw),
        score_scale = coalesce(excluded.score_scale, public.anime_user_lists.score_scale),
        repeat_count = case when v_item ? 'repeat_count' and not(v_unavailable ? 'repeat_count') then excluded.repeat_count else public.anime_user_lists.repeat_count end,
        started_raw = coalesce(excluded.started_raw, public.anime_user_lists.started_raw),
        finished_raw = coalesce(excluded.finished_raw, public.anime_user_lists.finished_raw),
        entry_private = case when v_item ? 'private' and not(v_unavailable ? 'private') then excluded.entry_private else public.anime_user_lists.entry_private end,
        source_custom_lists = case when v_item ? 'custom_lists' and not(v_unavailable ? 'custom_lists') then excluded.source_custom_lists else public.anime_user_lists.source_custom_lists end,
        source_hidden = case when v_item ? 'hidden_from_status_lists' and not(v_unavailable ? 'hidden_from_status_lists') then excluded.source_hidden else public.anime_user_lists.source_hidden end,
        source_list_options = coalesce(excluded.source_list_options, public.anime_user_lists.source_list_options),
        rating = coalesce(excluded.rating,public.anime_user_lists.rating)
      where public.anime_user_lists.server_revision = v_baseline.server_revision
        and public.anime_user_lists.lifecycle_id = v_baseline.lifecycle_id;
    else
      insert into public.manga_user_lists
        (user_id, manga_id, list_type, progress, notes, score_raw, score_scale, repeat_count, volumes_progress, started_raw, finished_raw, entry_private, source_custom_lists, source_hidden, source_list_options, rating)
      values (
        v_uid::text, v_media_id, v_list_type, v_progress, v_notes,
        nullif(v_item->>'score_raw', '')::numeric, v_item->>'score_scale',
        coalesce((v_item->>'repeat_count')::integer, 0),
        nullif(v_item->>'volumes_progress', '')::integer,
        v_item->>'started_raw', v_item->>'finished_raw', coalesce((v_item->>'private')::boolean, false),
        coalesce(v_item->'custom_lists', '[]'::jsonb), coalesce((v_item->>'hidden_from_status_lists')::boolean, false), v_item->>'source_list_options',coalesce((v_item->>'normalized_rating')::integer,case when v_item->>'score_scale'='POINT_10' and nullif(v_item->>'score_raw','')::numeric between 1 and 10 then round((v_item->>'score_raw')::numeric)::integer end)
      )
      on conflict (user_id, manga_id) do update set
        list_type = excluded.list_type,
        progress = case when v_item ? 'progress' and not(v_unavailable ? 'progress') then excluded.progress else public.manga_user_lists.progress end,
        notes = coalesce(excluded.notes, public.manga_user_lists.notes),
        score_raw = coalesce(excluded.score_raw, public.manga_user_lists.score_raw),
        score_scale = coalesce(excluded.score_scale, public.manga_user_lists.score_scale),
        repeat_count = case when v_item ? 'repeat_count' and not(v_unavailable ? 'repeat_count') then excluded.repeat_count else public.manga_user_lists.repeat_count end,
        volumes_progress = coalesce(excluded.volumes_progress, public.manga_user_lists.volumes_progress),
        started_raw = coalesce(excluded.started_raw, public.manga_user_lists.started_raw),
        finished_raw = coalesce(excluded.finished_raw, public.manga_user_lists.finished_raw),
        entry_private = case when v_item ? 'private' and not(v_unavailable ? 'private') then excluded.entry_private else public.manga_user_lists.entry_private end,
        source_custom_lists = case when v_item ? 'custom_lists' and not(v_unavailable ? 'custom_lists') then excluded.source_custom_lists else public.manga_user_lists.source_custom_lists end,
        source_hidden = case when v_item ? 'hidden_from_status_lists' and not(v_unavailable ? 'hidden_from_status_lists') then excluded.source_hidden else public.manga_user_lists.source_hidden end,
        source_list_options = coalesce(excluded.source_list_options, public.manga_user_lists.source_list_options),
        rating = coalesce(excluded.rating,public.manga_user_lists.rating)
      where public.manga_user_lists.server_revision = v_baseline.server_revision
        and public.manga_user_lists.lifecycle_id = v_baseline.lifecycle_id;
    end if;

    get diagnostics v_written = row_count;
    if v_written = 0 then
      v_conflict := v_conflict + 1;
      insert into public.library_import_items(job_id, provider, external_id, medium, disposition, request_hash)
      values(v_job.id, v_job.provider, v_external, v_medium, 'conflict', v_request_hash);
      continue;
    end if;
    if v_updated is null then
      v_disposition := 'added';
      v_added := v_added + 1;
    else
      v_disposition := 'updated';
      v_updated_count := v_updated_count + 1;
    end if;

    insert into public.library_import_items (job_id, provider, external_id, medium, disposition, request_hash)
    values (v_job.id, v_job.provider, v_external, v_medium, v_disposition, v_request_hash)
    on conflict (job_id, provider, external_id, medium) do update set disposition = 'applied';

    insert into public.provider_entry_refs (provider, external_id, medium, anime_id, manga_id, unresolved)
    values (
      v_job.provider, v_external, v_medium,
      case when v_medium = 'anime' then v_media_id else null end,
      case when v_medium = 'manga' then v_media_id else null end,
      false
    )
    on conflict (provider, external_id, medium) do nothing;
  end loop;

  update public.library_import_jobs
    set counters = coalesce(counters, '{}'::jsonb) || jsonb_build_object(
          'added', coalesce((counters->>'added')::integer, 0) + v_added,
          'updated', coalesce((counters->>'updated')::integer, 0) + v_updated_count,
          'conflict', coalesce((counters->>'conflict')::integer, 0) + v_conflict,
          'unmatched', coalesce((counters->>'unmatched')::integer, 0) + v_unmatched,
          'unchanged', coalesce((counters->>'unchanged')::integer, 0) + v_unchanged
        ),
        updated_at = now()
  where id = v_job.id;

  if v_added + v_updated_count > 0 then
    insert into public.home_publications(user_id, medium, revision)
    select v_uid::text, medium, 1 from (select distinct lower(value->>'medium') medium from jsonb_array_elements(p_items)) media
    on conflict(user_id, medium) do update set revision = public.home_publications.revision + 1;
    update public.library_import_jobs j set home_revision = p.revision from public.home_publications p
      where j.id = v_job.id and p.user_id = v_uid::text and p.medium = case when v_job.medium_filter = 'both' then 'anime' else v_job.medium_filter end;
  end if;

  return jsonb_build_object(
    'applied', v_added + v_updated_count,
    'added', v_added,
    'updated', v_updated_count,
    'conflict', v_conflict,
    'unmatched', v_unmatched,
    'unchanged', v_unchanged
  );
end;
$$;


-- v1 keeps its original contract but cannot bypass v2 review decisions.
create or replace function public.finish_library_import_v1(p_job_id uuid, p_exhausted boolean)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_job public.library_import_jobs%rowtype;
  v_state text;
begin
  perform pg_advisory_xact_lock(hashtextextended('kuro.library.account:'||auth.uid()::text,0));
  if v_uid is null then
    raise exception 'UNAUTHENTICATED';
  end if;
  select * into v_job from public.library_import_jobs where id = p_job_id and user_id = v_uid for update;
  if v_job.id is null then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if v_job.contract_version<>1 then raise exception 'CONTRACT_VERSION_MISMATCH'; end if;
  if v_job.state not in ('queued','running','ready','ready_with_issues') then
    raise exception 'JOB_NOT_RUNNING';
  end if;
  if v_job.state in ('ready','ready_with_issues') then
    return public.import_job_status_v1(p_job_id);
  end if;
  if not coalesce(p_exhausted, false) then
    v_state := 'running';
  elsif coalesce((v_job.counters->>'unmatched')::integer, 0) > 0
     or coalesce((v_job.counters->>'conflict')::integer, 0) > 0 then
    v_state := 'ready_with_issues';
  else
    v_state := 'ready';
  end if;
  update public.library_import_jobs set state = v_state, updated_at = now() where id = v_job.id;
  return jsonb_build_object('state', v_state, 'home_revision', v_job.home_revision, 'home_revisions', jsonb_build_object('anime',coalesce((select revision from public.home_publications where user_id=v_uid::text and medium='anime'),0),'manga',coalesce((select revision from public.home_publications where user_id=v_uid::text and medium='manga'),0)), 'counters', v_job.counters);
end;
$$;


-- v1 keeps its original contract but cannot bypass v2 review decisions.
create or replace function public.import_job_status_v1(p_job_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_job public.library_import_jobs%rowtype;
begin
  if v_uid is null then
    raise exception 'UNAUTHENTICATED';
  end if;
  select * into v_job from public.library_import_jobs where id = p_job_id and user_id = v_uid;
  if v_job.id is null then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if v_job.contract_version<>1 then raise exception 'CONTRACT_VERSION_MISMATCH'; end if;
  return jsonb_build_object(
    'job_id', v_job.id,
    'state', v_job.state,
    'provider', v_job.provider,
    'source_kind', v_job.source_kind,
    'counters', v_job.counters,
    'discovered_total', v_job.discovered_total,
    'home_revision', v_job.home_revision,
    'home_revisions', jsonb_build_object('anime',coalesce((select revision from public.home_publications where user_id=v_uid::text and medium='anime'),0),'manga',coalesce((select revision from public.home_publications where user_id=v_uid::text and medium='manga'),0)),
    'sanitized_error', v_job.sanitized_error,
    'retry_after', v_job.retry_after
  );
end;
$$;

DO $restrict$
DECLARE helper regprocedure;
BEGIN
 FOR helper IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname LIKE '\_import\_v2\_%' ESCAPE '\' LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated',helper);
 END LOOP;
END;
$restrict$;
revoke all on function public.start_library_import_v2(jsonb,text) from public,anon;
grant execute on function public.start_library_import_v2(jsonb,text) to authenticated;
revoke all on function public.prepare_import_chunk_v2(uuid,jsonb,jsonb) from public,anon;
grant execute on function public.prepare_import_chunk_v2(uuid,jsonb,jsonb) to authenticated;
revoke all on function public.apply_import_chunk_v2(uuid,text,jsonb) from public,anon;
grant execute on function public.apply_import_chunk_v2(uuid,text,jsonb) to authenticated;
revoke all on function public.finish_library_import_v2(uuid) from public,anon;
grant execute on function public.finish_library_import_v2(uuid) to authenticated;
revoke all on function public.import_job_status_v2(uuid) from public,anon;
grant execute on function public.import_job_status_v2(uuid) to authenticated;
revoke all on function public.import_jobs_page_v2(text,integer) from public,anon;
grant execute on function public.import_jobs_page_v2(text,integer) to authenticated;
revoke all on function public.import_items_page_v2(uuid,text,integer) from public,anon;
grant execute on function public.import_items_page_v2(uuid,text,integer) to authenticated;
revoke all on function public.cancel_library_import_v2(uuid) from public,anon;
grant execute on function public.cancel_library_import_v2(uuid) to authenticated;
revoke all on function public.undo_library_import_chunk_v2(uuid,text,text,integer) from public,anon;
grant execute on function public.undo_library_import_chunk_v2(uuid,text,text,integer) to authenticated;
commit;
