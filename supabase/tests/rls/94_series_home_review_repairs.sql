-- Independent-review regression contracts: immutable replay, unit ownership, exact
-- provider namespaces, imported baseline protection and stable season metadata.
-- @requires table public.anime_user_lists
-- @requires table public.manga_user_lists
-- @requires table public.anime
-- @requires table public.manga
\set ON_ERROR_STOP on
\o /dev/null
begin;
select tests.make_user(94), tests.make_user(95), tests.make_user(940);
insert into public.anime(id, title_romaji, anilist_id) values
 (794001, 'Correct external anime', 794002), (794002, 'Internal collision anime', 794009),
 (794003, 'Season two', 794003), (794004, 'Concurrent edit', 794004);
insert into public.manga(id, title_romaji, anilist_id) values
 (794005, 'Correct external manga', 794006), (794006, 'Internal collision manga', 794099);
select tests.as_user(tests.uid(94));
insert into public.anime_user_lists(user_id, anime_id, list_type, progress) values
 (tests.uid(94)::text, 794004, 'WATCHING', 2);
select public.start_library_import_v1('anilist','export','both','repair-action-94','repair-payload-94')->>'job_id' as job \gset
select public.apply_import_chunk_v1(:'job'::uuid, jsonb_build_array(
 jsonb_build_object('medium','anime','external_id','794002','status','watching','progress',3,'notes','owner private','private',true),
 jsonb_build_object('medium','manga','external_id','794006','status','reading','progress',5)
)) as applied \gset
select tests.eq('anime external ID beats an unrelated internal PK', (select count(*) from public.anime_user_lists where anime_id=794001), 1::bigint);
select tests.eq('wrong anime was never added', (select count(*) from public.anime_user_lists where anime_id=794002), 0::bigint);
select tests.eq('manga external ID beats an unrelated internal PK', (select count(*) from public.manga_user_lists where manga_id=794005), 1::bigint);
select tests.eq('private notes remain owner-only list data', (select notes from public.anime_user_lists where anime_id=794001), 'owner private');
select tests.eq('entry privacy retained', (select entry_private from public.anime_user_lists where anime_id=794001), true);
select tests.eq('no import notes become comments', (select count(*) from public.title_comments where media_id=794001), 0::bigint);
select public.apply_import_chunk_v1(:'job'::uuid, jsonb_build_array(
 jsonb_build_object('medium','anime','external_id','794002','status','watching','progress',3,'notes','owner private','private',true),
 jsonb_build_object('medium','manga','external_id','794006','status','reading','progress',5)
)) as replay \gset
select tests.eq('chunk retry adds no duplicate counts', (:'replay'::jsonb->>'added')::integer, 0);
select tests.eq('unique added counters stay at two', (public.import_job_status_v1(:'job'::uuid)->'counters'->>'added')::integer, 2);
select tests.eq('both-media Home publication includes manga', (select revision from public.home_publications where medium='manga'), 1::bigint);
update public.anime_user_lists set list_type='DROPPED' where anime_id=794004;
select public.apply_import_chunk_v1(:'job'::uuid, '[{"medium":"anime","external_id":"794004","status":"watching","progress":2}]') as conflict \gset
select tests.eq('status-only concurrent edit conflicts despite equal progress', (:'conflict'::jsonb->>'conflict')::integer,1);
select tests.eq('local dropped state remains', (select list_type from public.anime_user_lists where anime_id=794004),'DROPPED');
select public.finish_library_import_v1(:'job'::uuid,true);
select tests.eq('ready job start is a replay', (public.start_library_import_v1('anilist','export','both','repair-action-94','repair-payload-94')->>'resumed')::boolean,true);
-- Receipt hash stays the request hash after another progress edit.
select lifecycle_id::text as life, server_revision as rev from public.anime_user_lists where anime_id=794001 \gset
select jsonb_build_array(jsonb_build_object('mutation_id','94949494-9494-4494-8494-949494949494',
 'medium','anime','media_id',794001,'lifecycle_id',:'life','base_revision',:rev,'status','PAUSED')) as body \gset
select public.apply_progress_mutations_v1(:'body'::jsonb) as status_write \gset
select tests.eq('status-only mutation applies', :'status_write'::jsonb->'items'->0->>'outcome','applied');
update public.anime_user_lists set progress=9 where anime_id=794001;
select tests.eq('unchanged status-only retry ignores later progress', public.apply_progress_mutations_v1(:'body'::jsonb)->'items'->0->>'outcome','already_applied');
select tests.eq('same ID different base revision is rejected', public.apply_progress_mutations_v1(jsonb_build_array((:'body'::jsonb->0)||jsonb_build_object('base_revision',:rev+1)))->'items'->0->>'outcome','rejected_payload');
select tests.reset();
insert into public.catalogue_units(id, medium, anime_id, label, order_key) values
 ('94949494-9494-4494-8494-949494949495','anime',794003,'1',1);
select tests.as_user(tests.uid(94));
select tests.eq('foreign season unit is not accepted', public.apply_progress_mutations_v1(jsonb_build_array(jsonb_build_object(
 'mutation_id','94949494-9494-4494-8494-949494949496','medium','anime','media_id',794001,'lifecycle_id',:'life',
 'base_revision',(select server_revision from public.anime_user_lists where anime_id=794001),'position',10,
 'unit_id','94949494-9494-4494-8494-949494949495')))->'items'->0->>'outcome','invalid_target');
select tests.reset();
insert into public.series(id,medium,title,continuity) values ('94949494-9494-4494-8494-949494949497','anime','Continuity','verified');
insert into public.series_sections(id,series_id,kind,ordinal,name,sort_order,provenance) values
 ('94949494-9494-4494-8494-949494949498','94949494-9494-4494-8494-949494949497','season',1,'Season 1',1,'fixture'),
 ('94949494-9494-4494-8494-949494949499','94949494-9494-4494-8494-949494949497','season',2,'Season 2',2,'fixture');
insert into public.series_entry_spans(series_id,section_id,medium,anime_id) values
 ('94949494-9494-4494-8494-949494949497','94949494-9494-4494-8494-949494949498','anime',794001),
 ('94949494-9494-4494-8494-949494949497','94949494-9494-4494-8494-949494949499','anime',794003);
select tests.as_user(tests.uid(94));
update public.anime_user_lists set list_type='WATCHING' where anime_id=794001;
insert into public.anime_user_lists(user_id,anime_id,list_type,progress) values(tests.uid(94)::text,794003,'WATCHING',1);
select tests.eq('one active Home card for two approved seasons', jsonb_array_length(public.home_bundle_v1('anime')->'active'),1);
select tests.eq('selected season resolves its own catalogue title', public.series_detail_bundle_v1('anime',794001,'94949494-9494-4494-8494-949494949499')->'header'->>'title','Season two');
select tests.eq('selected season resolves its own progress', (public.series_detail_bundle_v1('anime',794001,'94949494-9494-4494-8494-949494949499')->'user'->>'progress')::integer,1);
select tests.eq('season browse never advances first-season progress', (select progress from public.anime_user_lists where anime_id=794001),9);
select tests.eq('finish publishes revision floors for BOTH Home media',
  (public.import_job_status_v1(:'job'::uuid)->'home_revisions') ?& array['anime','manga'],true);
select tests.reset();
insert into public.catalogue_units(medium,anime_id,label,order_key,available,edition_key)
select 'anime',794003,n::text,n,true,'' from generate_series(2,45) n;
select tests.as_user(tests.uid(94));
select public.series_units_page_v1('anime',794003,null,null,null,null,20) as page1 \gset
select tests.eq('episode page is bounded to twenty',jsonb_array_length(:'page1'::jsonb->'items'),20);
select tests.eq('episode page has deterministic cursor',(:'page1'::jsonb->'next') is not null,true);
select public.series_units_page_v1('anime',794003,null,null,
 (:'page1'::jsonb->'next'->>'order')::numeric,(:'page1'::jsonb->'next'->>'id')::uuid,20) as page2 \gset
select tests.eq('second episode page has no duplicate first rows',(:'page2'::jsonb->'items'->0->>'order_key')::integer,21);
select tests.eq('initial detail unit cursor uses same deterministic ordering',
 (public.series_detail_bundle_v1('anime',794003)->'units'->19->>'order_key')::integer,20);
select tests.eq('detail exposes its actual final-unit page cursor',
 (public.series_detail_bundle_v1('anime',794003)->'units_next'->>'order')::integer,20);
select id::text as correct_unit from public.catalogue_units where anime_id=794003 and order_key=5 \gset
update public.anime_user_lists set unit_id=:'correct_unit',progress_label='5.5' where anime_id=794003;
select public.apply_progress_mutations_v1(jsonb_build_array(jsonb_build_object(
 'mutation_id','94949494-9494-4494-8494-949494949402','medium','anime','media_id',794003,
 'lifecycle_id',(select lifecycle_id from public.anime_user_lists where anime_id=794003),
 'base_revision',(select server_revision from public.anime_user_lists where anime_id=794003),'status','PAUSED')));
select tests.eq('status-only write retains the exact source unit',
 (select unit_id::text from public.anime_user_lists where anime_id=794003),:'correct_unit');
select tests.eq('status-only write retains fractional chapter label',
 (select progress_label from public.anime_user_lists where anime_id=794003),'5.5');
update public.anime_user_lists set list_type='WATCHING' where anime_id=794003;

select tests.raises('direct SDK unit write also checks title ownership',
 $q$update public.anime_user_lists set unit_id='94949494-9494-4494-8494-949494949495' where anime_id=794001$q$,'%INVALID_UNIT_OWNER%');
select public.apply_progress_mutations_v1(jsonb_build_array(jsonb_build_object(
 'mutation_id','94949494-9494-4494-8494-949494949401','medium','anime','media_id',794001,'lifecycle_id',:'life',
 'base_revision',1,'position',10))) as conflict_receipt \gset
select tests.eq('stale revision returns conflict',:'conflict_receipt'::jsonb->'items'->0->>'outcome','conflict');
select tests.eq('lost conflict response replay stays conflict, never success',public.apply_progress_mutations_v1(jsonb_build_array(jsonb_build_object(
 'mutation_id','94949494-9494-4494-8494-949494949401','medium','anime','media_id',794001,'lifecycle_id',:'life',
 'base_revision',1,'position',10)))->'items'->0->>'outcome','conflict');
-- Two disjoint event pages retain every source day and stable ID.
select tests.reset();
insert into public.release_events(medium,anime_id,kind,precision,source_local_date,source_zone,status,evidence)
select 'anime',794003,'Episode '||n,'day',(current_date+1)::text,'Asia/Tokyo','scheduled','fixture' from generate_series(1,45)n;
select tests.as_user(tests.uid(94));
select public.home_events_page_v1('anime',7,20,null) as dates1 \gset
select tests.eq('Coming Up page stays bounded',jsonb_array_length(:'dates1'::jsonb->'items'),20);
select tests.eq('Coming Up count retains all tracked releases',(:'dates1'::jsonb->>'total')::integer,45);
select tests.eq('source day remains a day rather than midnight',:'dates1'::jsonb->'items'->0->>'precision','day');
select tests.eq('day precision never fabricates instant',:'dates1'::jsonb->'items'->0->>'at',null::text);
select public.home_events_page_v1('anime',7,20,:'dates1'::jsonb->>'next_cursor') as dates2 \gset
select tests.eq('Coming Up second page also bounded',jsonb_array_length(:'dates2'::jsonb->'items'),20);
select tests.eq('Coming Up cursor pages have no repeated IDs',(select count(*) from jsonb_array_elements(:'dates1'::jsonb->'items')a
 join jsonb_array_elements(:'dates2'::jsonb->'items')b on a->>'event_id'=b->>'event_id'),0::bigint);
select tests.reset();
-- Real legacy ingestion writes feed the new bounded units/releases without fictional chapter dates.
insert into public.chapters(id,manga_id,number,title,release_date) values(794090,794005,5,'Source chapter',current_date+2);
select tests.eq('legacy chapter creates exactly one canonical unit',(select count(*) from public.catalogue_units where manga_id=794005 and edition_key='legacy_catalogue' and order_key=5),1::bigint);
select tests.eq('legacy date-only source stays date-only',(select precision from public.release_events where source_identity='legacy:manga:794090:794005:5'),'day');
update public.chapters set manga_id=794006,number=6 where id=794090;
select tests.eq('source remap withdraws the old release',(select status from public.release_events where source_identity='legacy:manga:794090:794005:5'),'withdrawn');
select tests.eq('source remap preserves old unit identity safely',(select available from public.catalogue_units where manga_id=794005 and edition_key='legacy_catalogue' and order_key=5),false);
select tests.eq('source remap creates the new target once',(select count(*) from public.catalogue_units where manga_id=794006 and order_key=6),1::bigint);
-- Named data obeys BOTH members' disclosure ranks; removal revokes the same public RPC.
select tests.as_user(tests.uid(94));
select public.create_club('Repair room','privacy contract','progress')->>'club_id' as room \gset
select invite_code as code from public.clubs where id=:'room' \gset
select tests.as_user(tests.uid(95));select public.join_club(:'code');
insert into public.anime_user_lists(user_id,anime_id,list_type,progress,entry_private) values(tests.uid(95)::text,794003,'WATCHING',7,false);
select public.upsert_title_comment_scoped_v1('ANIME',794003,'Private club thought','story');
select tests.as_user(tests.uid(94));
select tests.eq('club mate tracking is initially visible',jsonb_array_length(public.friend_activity_page_v1('ANIME',794003)->'friends_tracking'),1);
select tests.eq('spoiler metadata reaches private reader',public.friend_activity_page_v1('ANIME',794003)->'comments'->0->>'spoiler_scope','story');
update public.club_members set sharing_level='private' where club_id=:'room' and user_id=tests.uid(94);
select tests.eq('viewer downgrade hides peer activity',jsonb_array_length(public.friend_activity_page_v1('ANIME',794003)->'friends_tracking'),0);
select tests.eq('viewer downgrade hides peer comments',jsonb_array_length(public.friend_activity_page_v1('ANIME',794003)->'comments'),0);
update public.club_members set sharing_level='progress' where club_id=:'room' and user_id=tests.uid(94);
select tests.as_user(tests.uid(95));update public.anime_user_lists set entry_private=true where anime_id=794003;
select tests.as_user(tests.uid(94));
select tests.eq('private provider entry never contributes named tracking',jsonb_array_length(public.friend_activity_page_v1('ANIME',794003)->'friends_tracking'),0);
select public.leave_club(:'room');
select tests.eq('club removal immediately hides peer comments',jsonb_array_length(public.friend_activity_page_v1('ANIME',794003)->'comments'),0);

select tests.reset();
insert into public.anime(id,title_romaji) select 795000+n,'Large continuity '||n from generate_series(1,55)n;
insert into public.series_entry_spans(series_id,section_id,medium,anime_id)
select '94949494-9494-4494-8494-949494949497','94949494-9494-4494-8494-949494949498','anime',795000+n from generate_series(1,55)n;
select tests.as_user(tests.uid(94));
insert into public.anime_user_lists(user_id,anime_id,list_type,progress)
select tests.uid(94)::text,795000+n,'WATCHING',1 from generate_series(1,55)n;
select (select g from jsonb_array_elements(public.collection_series_page_v1('anime','WATCHING','Large continuity')->'groups')g
 where g->>'group_key'='94949494-9494-4494-8494-949494949497') as large_group \gset
select tests.eq('large Collection child array is bounded',jsonb_array_length(:'large_group'::jsonb->'children'),50);
select tests.eq('large Collection group retains total',(:'large_group'::jsonb->>'child_count')::integer,55);
select public.collection_series_children_v1('anime','94949494-9494-4494-8494-949494949497','WATCHING','Large continuity',
 (:'large_group'::jsonb->>'children_next')::integer) as remaining_children \gset
select tests.eq('large Collection group exposes its remaining five children',jsonb_array_length(:'remaining_children'::jsonb->'children'),5);
select tests.eq('Collection child pages never duplicate IDs',(select count(*) from jsonb_array_elements(:'large_group'::jsonb->'children')a
 join jsonb_array_elements(:'remaining_children'::jsonb->'children')b on a->>'media_id'=b->>'media_id'),0::bigint);
select tests.as_user(tests.uid(95));
select tests.eq('another account cannot page private Collection children',jsonb_array_length(public.collection_series_children_v1('anime',
 '94949494-9494-4494-8494-949494949497','WATCHING','Large continuity')->'children'),0);

select tests.as_user(tests.uid(94));
select tests.eq('finish replay cannot reopen an exhausted import',
 public.finish_library_import_v1(:'job'::uuid,false)->>'state','ready_with_issues');
update public.anime_user_lists set entry_private=true,source_hidden=true,repeat_count=3,
 source_custom_lists='["Favourites"]',source_list_options='{"old":"kept"}' where anime_id=794001;
select public.start_library_import_v1('anilist','export','anime','unavailable-94','unavailable-hash-94')->>'job_id' as unavailable_job \gset
select public.apply_import_chunk_v1(:'unavailable_job'::uuid,'[{"medium":"anime","external_id":"794002","status":"watching","progress":9,
 "private":false,"custom_lists":[],"hidden_from_status_lists":false,
 "source_list_options":"{\"unavailable_fields\":[\"private\",\"custom_lists\",\"hidden_from_status_lists\"]}"}]');
select tests.eq('unsupported source privacy cannot publish a previously private entry',
 (select entry_private from public.anime_user_lists where anime_id=794001),true);
select tests.eq('unsupported source hidden flag cannot clear local preference',
 (select source_hidden from public.anime_user_lists where anime_id=794001),true);
select tests.eq('unsupported source custom lists survive merge',
 (select source_custom_lists from public.anime_user_lists where anime_id=794001),'["Favourites"]'::jsonb);
select tests.eq('absent repeat count survives merge',
 (select repeat_count from public.anime_user_lists where anime_id=794001),3);
select public.finish_library_import_v1(:'unavailable_job'::uuid,true);
select tests.reset();
insert into public.anime(id,title_romaji,anilist_id) values(794010,'Unresolved provider target',794012);
select tests.raises('catalogue uniqueness rejects a duplicate provider identity',
 $q$insert into public.anime(id,title_romaji,anilist_id) values(794011,'Duplicate provider target',794012)$q$,
 '%anime_anilist_id_key%');
-- A reviewed unresolved reference must stop even an otherwise matching catalogue
-- fallback, until the source owner deliberately resolves that exact namespace.
insert into public.provider_entry_refs(provider,external_id,medium,unresolved)
values('anilist','794012','anime',true);
select tests.as_user(tests.uid(94));
select public.start_library_import_v1('anilist','export','anime','ambiguous-94','ambiguous-hash-94')->>'job_id' as ambiguous_job \gset
select tests.eq('unresolved provider reference stays unmatched despite catalogue fallback',
 (public.apply_import_chunk_v1(:'ambiguous_job'::uuid,'[{"medium":"anime","external_id":"794012","status":"watching","progress":1}]')->>'unmatched')::integer,1);
select tests.eq('unresolved target writes neither internal row',
 (select count(*) from public.anime_user_lists where anime_id in(794010,794011)),0::bigint);
select public.finish_library_import_v1(:'ambiguous_job'::uuid,true);
select tests.reset();
insert into public.release_events(medium,anime_id,kind,precision,status,evidence)
select 'anime',794003,'Announced unit '||n,'unknown','announced','fixture' from generate_series(1,45)n;
select tests.as_user(tests.uid(94));
select public.home_pending_page_v1('anime',20,null) as pending1 \gset
select public.home_pending_page_v1('anime',20,:'pending1'::jsonb->>'next_cursor') as pending2 \gset
select tests.eq('pending announcements bounded before JSON aggregation',jsonb_array_length(:'pending1'::jsonb->'items'),20);
select tests.eq('pending count is full eligible window',(:'pending1'::jsonb->>'total')::integer,45);
select tests.eq('pending second page has no repeated event IDs',(select count(*) from jsonb_array_elements(:'pending1'::jsonb->'items')a
 join jsonb_array_elements(:'pending2'::jsonb->'items')b on a->>'event_id'=b->>'event_id'),0::bigint);
select tests.eq('initial Home includes independent pending cursor',
 public.home_bundle_v1('anime')->>'pending_cursor' is not null,true);
-- User95 legitimately tracks this same public title from the club test above.
-- Use a third empty account to prove the pager cannot borrow another library.
select tests.as_user(tests.uid(940));
select tests.eq('empty account pending pager cannot derive another account follows/library',
 jsonb_array_length(public.home_pending_page_v1('anime')->'items'),0);
select tests.reset();
-- Metadata-bearing season retains its stable UUID on rename; adding a split cour
-- emits one coherent section despite two source spans.
insert into public.detail_copy(medium,anime_id,section_id,locale,premise,provenance,review_state)
values('anime',794003,'94949494-9494-4494-8494-949494949499','en','Season-specific premise','fixture','approved');
insert into public.mapping_revisions(id,series_id,state,source,rule_revision)
values('94949494-9494-4494-8494-949494949410','94949494-9494-4494-8494-949494949497','proposed','fixture','r2');
insert into public.mapping_revision_spans(revision_id,medium,anime_id,section_kind,section_ordinal,section_name,sort_order)
select '94949494-9494-4494-8494-949494949410','anime',sp.anime_id,sec.kind,sec.ordinal,
 case when sec.ordinal=2 then 'Renamed season two' else sec.name end,sec.sort_order
from public.series_entry_spans sp join public.series_sections sec on sec.id=sp.section_id
where sp.series_id='94949494-9494-4494-8494-949494949497';
insert into public.mapping_revision_spans(revision_id,medium,anime_id,section_kind,section_ordinal,section_name,sort_order)
values('94949494-9494-4494-8494-949494949410','anime',794002,'season',3,'Split cour',3),
 ('94949494-9494-4494-8494-949494949410','anime',794004,'season',3,'Split cour',3);
select public.publish_mapping_revision('94949494-9494-4494-8494-949494949410');
select tests.eq('rename retains metadata section identity',
 (select section_id::text from public.detail_copy where anime_id=794003),'94949494-9494-4494-8494-949494949499');
select tests.eq('split cour creates one logical section',
 (select count(*) from public.series_sections where series_id='94949494-9494-4494-8494-949494949497' and sort_order=3),1::bigint);
select tests.eq('split cour retains both distinct source children',
 (select count(*) from public.series_entry_spans where anime_id in(794002,794004)),2::bigint);
select tests.reset();
rollback;
