-- Read-only investigation of candidate behavior. All writes are disposable fixture
-- data; observational outputs intentionally capture defects rather than bless them.
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
\ir /Users/max/Kuro-Anime-App/supabase/tests/lib/00_test_helpers.sql
begin;
select tests.make_user(981);
insert into public.anime(id,title_romaji,mal_id) values
 (798101,'Underscore planning',998101), (798103,'Underscore hold',998103),
 (798105,'Zero-score scale',998105), (798106,'Identical reimport',998106),
 (798107,'Pre-baseline Kuro edit',998107);
insert into public.manga(id,title_romaji,mal_id) values
 (798102,'Underscore read planning',998102), (798104,'Precise import',998104);
insert into public.catalogue_units(id,medium,manga_id,label,order_key,edition_key)
values ('98198198-1981-4981-8981-981981981981','manga',798104,'4.5',4.5,'special-edition');
select tests.as_user(tests.uid(981));
insert into public.manga_user_lists(user_id,manga_id,list_type,progress,unit_id,progress_label)
values(tests.uid(981)::text,798104,'READING',4,'98198198-1981-4981-8981-981981981981','4.5');
insert into public.anime_user_lists(user_id,anime_id,list_type,progress,score_raw,score_scale,rating,notes) values
 (tests.uid(981)::text,798105,'WATCHING',6,80,'POINT_100',8,'preserve-score'),
 (tests.uid(981)::text,798107,'WATCHING',12,90,'POINT_100',9,'deliberate Kuro note');
-- One real job/stream: namespace mappings resolve, statuses alone are rejected.
select public.start_library_import_v1('myanimelist','export','both','repro-statuses-981','payload-statuses-981')->>'job_id' as statuses_job \gset
select public.apply_import_chunk_v1(:'statuses_job'::uuid,'[
 {"medium":"anime","external_id":"998101","status":"plan_to_watch","progress":0},
 {"medium":"manga","external_id":"998102","status":"plan_to_read","progress":0},
 {"medium":"anime","external_id":"998103","status":"on_hold","progress":4}
]'::jsonb) as statuses_result \gset
select jsonb_build_object('case','official_underscore_statuses','response',:'statuses_result'::jsonb,
 'dispositions',(select jsonb_agg(jsonb_build_object('medium',medium,'external_id',external_id,'disposition',disposition,'detail',detail)order by external_id)from public.library_import_items where job_id=:'statuses_job'::uuid));
select public.finish_library_import_v1(:'statuses_job'::uuid,true);

select public.start_library_import_v1('myanimelist','export','both','repro-precision-score-981','payload-precision-score-981')->>'job_id' as changes_job \gset
select jsonb_build_object('case','precision_before','row',jsonb_build_object('progress',progress,'unit_id',unit_id,'label',progress_label,'revision',server_revision)) from public.manga_user_lists where manga_id=798104;
select jsonb_build_object('case','score_before','row',jsonb_build_object('raw',score_raw,'scale',score_scale,'rating',rating,'revision',server_revision))from public.anime_user_lists where anime_id=798105;
select jsonb_build_object('case','prebaseline_before','row',jsonb_build_object('status',list_type,'progress',progress,'notes',notes,'rating',rating,'revision',server_revision))from public.anime_user_lists where anime_id=798107;
select public.apply_import_chunk_v1(:'changes_job'::uuid,'[
 {"medium":"manga","external_id":"998104","status":"reading","progress":7},
 {"medium":"anime","external_id":"998105","status":"watching","score_raw":"0","score_scale":"MAL_10"},
 {"medium":"anime","external_id":"998107","status":"planning","progress":1,"notes":"provider note","normalized_rating":4}
]'::jsonb) as changes_result \gset
select jsonb_build_object('case','precision_score_prebaseline_response','response',:'changes_result'::jsonb);
select jsonb_build_object('case','precision_after','row',jsonb_build_object('progress',progress,'unit_id',unit_id,'label',progress_label,'revision',server_revision))from public.manga_user_lists where manga_id=798104;
select jsonb_build_object('case','score_after','row',jsonb_build_object('raw',score_raw,'scale',score_scale,'rating',rating,'revision',server_revision))from public.anime_user_lists where anime_id=798105;
select jsonb_build_object('case','prebaseline_after','row',jsonb_build_object('status',list_type,'progress',progress,'notes',notes,'rating',rating,'revision',server_revision))from public.anime_user_lists where anime_id=798107;
select public.finish_library_import_v1(:'changes_job'::uuid,true);

select public.start_library_import_v1('myanimelist','export','anime','repro-identical-first-981','payload-identical-981')->>'job_id' as initial_job \gset
select public.apply_import_chunk_v1(:'initial_job'::uuid,'[{"medium":"anime","external_id":"998106","status":"watching","progress":3,"notes":"same"}]'::jsonb)as first_result \gset
select jsonb_build_object('case','identical_first','response',:'first_result'::jsonb,'row',jsonb_build_object('status',list_type,'progress',progress,'notes',notes,'revision',server_revision),
 'home_revision',(select revision from public.home_publications where user_id=tests.uid(981)::text and medium='anime'))from public.anime_user_lists where anime_id=798106;
select public.finish_library_import_v1(:'initial_job'::uuid,true);
select public.start_library_import_v1('myanimelist','export','anime','repro-identical-second-981','payload-identical-981')->>'job_id' as identical_job \gset
select public.apply_import_chunk_v1(:'identical_job'::uuid,'[{"medium":"anime","external_id":"998106","status":"watching","progress":3,"notes":"same"}]'::jsonb)as identical_result \gset
select jsonb_build_object('case','identical_reimport','response',:'identical_result'::jsonb,'row',jsonb_build_object('status',list_type,'progress',progress,'notes',notes,'revision',server_revision),
 'home_revision',(select revision from public.home_publications where user_id=tests.uid(981)::text and medium='anime'))from public.anime_user_lists where anime_id=798106;
select public.finish_library_import_v1(:'identical_job'::uuid,true);

-- Isolate an accepted decimal external ID outside int32. Catch the exception so
-- the other observational evidence remains available; no catalogue match exists.
select public.start_library_import_v1('myanimelist','export','anime','repro-overflow-981','payload-overflow-981')->>'job_id' as overflow_job \gset
select tests.reset();
create temp table observed_overflow(error_state text,error_message text);
grant insert,select on observed_overflow to authenticated;
select tests.as_user(tests.uid(981));
select set_config('tests.overflow_job',:'overflow_job',true);
do $$begin
 perform public.apply_import_chunk_v1(current_setting('tests.overflow_job')::uuid,'[{"medium":"anime","external_id":"3000000000","status":"watching"}]'::jsonb);
 insert into observed_overflow values(null,'no exception');
exception when others then insert into observed_overflow values(sqlstate,sqlerrm); end;$$;
select jsonb_build_object('case','external_id_overflow','state',error_state,'message',error_message)from observed_overflow;
select tests.reset();
rollback;
