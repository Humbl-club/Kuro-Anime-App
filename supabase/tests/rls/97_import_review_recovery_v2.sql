-- Actual v2 owner path: review-only staging, fields-only approval, immutable
-- receipts, both streams, exact tracking/score semantics, guarded compensation.
-- @requires table public.anime_user_lists
-- @requires table public.manga_user_lists
-- @requires table public.library_import_jobs
-- @requires function public.start_library_import_v2(jsonb,text)
\set ON_ERROR_STOP on
\o /dev/null
begin;
select tests.make_user(970),tests.make_user(971);
insert into public.anime(id,title_romaji,mal_id)values
 (797001,'Planning anime',897001),(797004,'Existing identical anime',897004),
 (797005,'Held anime',897005),(797006,'Contradictory duplicate',897006),
 (797007,'Manual existing title',null),(797008,'Later edit',897008),(797009,'Review race',897009),
 (797010,'Manual new title',null),(797012,'Manual alternate new title',null);
insert into public.manga(id,title_romaji,mal_id)values
 (797002,'Planning manga',897002),(797003,'Precise retained manga',897003);
insert into public.catalogue_units(id,medium,manga_id,label,order_key,edition_key)values
 ('97097097-0970-4970-8970-970970970970','manga',797003,'4.5',4.5,'special-edition');
select tests.as_user(tests.uid(970));
insert into public.manga_user_lists(user_id,manga_id,list_type,progress,unit_id,progress_label,score_raw,score_scale,rating,notes,repeat_count,entry_private,source_hidden,source_custom_lists,started_raw,finished_raw)values
 (tests.uid(970)::text,797003,'READING',4,'97097097-0970-4970-8970-970970970970','4.5',80,'POINT_100',8,'Kuro note',2,true,true,'["Kuro"]','2025-01-02','2025-04-03');
insert into public.anime_user_lists(user_id,anime_id,list_type,progress,notes,score_raw,score_scale,rating)values
 (tests.uid(970)::text,797004,'WATCHING',3,'same',8,'MAL_10',8),
 (tests.uid(970)::text,797007,'WATCHING',6,'keep manual',null,null,null),
 (tests.uid(970)::text,797008,'WATCHING',2,null,null,null,null);
select public.start_library_import_v2('{"provider":"myanimelist","source_kind":"export","source_identity":"controlled.xml","media":["anime","manga"],"statuses":[]}'::jsonb,'v2-review-action-970')as started \gset
select :'started'::jsonb->>'job_id'as job \gset
select tests.eq('v2 job starts in preparation',:'started'::jsonb->>'phase','preparing');
select tests.eq('start replay keeps the same job',public.start_library_import_v2('{"provider":"myanimelist","source_kind":"export","source_identity":"controlled.xml","media":["manga","anime"],"statuses":[]}'::jsonb,'v2-review-action-970')->>'job_id',:'job');
select tests.raises('start replay rejects changed selection',$q$select public.start_library_import_v2('{"provider":"myanimelist","source_kind":"export","source_identity":"changed.xml","media":["anime","manga"]}'::jsonb,'v2-review-action-970')$q$,'%IDEMPOTENCY_CONFLICT%');
select tests.raises('v1 cannot apply to a v2 job',format($q$select public.apply_import_chunk_v1(%L::uuid,'[]'::jsonb)$q$,:'job'),'%CONTRACT_VERSION_MISMATCH%');
select public.prepare_import_chunk_v2(:'job'::uuid,'[
 {"medium":"anime","external_id":"897001","values":{"status":"plan_to_watch","progress":0}},
 {"medium":"manga","external_id":"897002","values":{"status":"plan_to_read","progress":0}},
 {"medium":"manga","external_id":"897003","values":{"status":"on_hold","progress":7,"score_raw":"0","score_scale":"MAL_10","notes":"provider note","private":false,"hidden_from_status_lists":false,"custom_lists":["Provider"],"started_raw":"2026-01-01","unavailable_fields":["finished_raw"]}},
 {"medium":"anime","external_id":"897004","values":{"status":"watching","progress":3,"notes":"same","score_raw":"8","score_scale":"MAL_10"}},
 {"medium":"anime","external_id":"897005","values":{"status":"on_hold","progress":4,"custom_lists":["First"]}},
 {"medium":"anime","external_id":"897006","values":{"status":"watching","progress":1}},
 {"medium":"anime","external_id":"897999","title":"Unresolved source label","values":{"status":"watching","progress":1}},
 {"medium":"anime","external_id":"897998","title":"Unresolved new label","values":{"status":"watching","progress":1}},
 {"medium":"anime","external_id":"897008","values":{"status":"watching","progress":5}},
 {"medium":"anime","external_id":"897009","values":{"status":"watching","progress":2}},
 {"medium":"anime","external_id":"3000000000","values":{"status":"watching"}}
]'::jsonb,'{"anime":true}'::jsonb)as staged \gset
select tests.eq('staging changes no existing precise tracking',
 (select jsonb_build_array(list_type,progress,progress_label,score_raw,score_scale,notes,server_revision)from public.manga_user_lists where manga_id=797003),
 '["READING",4,"4.5",80,"POINT_100","Kuro note",1]'::jsonb);
select tests.eq('staging adds no new Library titles',(select count(*)from public.anime_user_lists where anime_id in(797001,797005)),0::bigint);
select tests.eq('one completed stream cannot hide another incomplete stream',:'staged'::jsonb->>'phase','preparing');
select tests.raises('application is blocked before all selected source streams finish',format($q$select public.apply_import_chunk_v2(%L::uuid,'v2-first-approval-970','[{"medium":"anime","external_id":"897001","action":"add","fields":[]}]'::jsonb)$q$,:'job'),'%JOB_NOT_APPLYING%');
select public.import_items_page_v2(:'job'::uuid,null,50)as review \gset
select tests.eq('overflow becomes an invalid review disposition, not a cast exception',
 (select e->>'disposition'from jsonb_array_elements(:'review'::jsonb->'items')e where e->>'external_id'='3000000000'),'invalid');
select tests.eq('identical effective values are classified existing',
 (select e->>'disposition'from jsonb_array_elements(:'review'::jsonb->'items')e where e->>'external_id'='897004'),'existing');
select tests.eq('unmatched review retains the source title',
 (select e->>'title'from jsonb_array_elements(:'review'::jsonb->'items')e where e->>'external_id'='897999'),'Unresolved source label');
-- Compatible duplicate memberships combine. Contradictory core values poison
-- the canonical review item rather than choosing the last appearance.
select public.prepare_import_chunk_v2(:'job'::uuid,'[
 {"medium":"anime","external_id":"897005","values":{"status":"on_hold","progress":4,"custom_lists":["Second"]}},
 {"medium":"anime","external_id":"897006","values":{"status":"completed","progress":9}}
]'::jsonb,'{"manga":true}'::jsonb)as complete_stage \gset
select tests.eq('reviewing requires both source streams exhausted',:'complete_stage'::jsonb->>'phase','reviewing');
select public.import_items_page_v2(:'job'::uuid,null,50)as review2 \gset
select tests.eq('compatible source memberships are unioned once',
 (select e->'incoming'->'custom_lists'from jsonb_array_elements(:'review2'::jsonb->'items')e where e->>'external_id'='897005'),'["First","Second"]'::jsonb);
select tests.eq('contradictory source duplicate requires review',
 (select e->>'disposition'from jsonb_array_elements(:'review2'::jsonb->'items')e where e->>'external_id'='897006'),'source_changed');
select tests.raises('source_changed cannot bypass review with add',format($q$select public.apply_import_chunk_v2(%L::uuid,'v2-poison-approval-970','[{"medium":"anime","external_id":"897006","action":"add","fields":[]}]'::jsonb)$q$,:'job'),'%SOURCE_CHANGED%');
select tests.raises('a resolved catalogue identity cannot be overridden',format($q$select public.prepare_import_chunk_v2(%L::uuid,'[{"medium":"anime","external_id":"897001","resolved_media_id":797010,"values":{"status":"plan_to_watch","progress":0}}]'::jsonb,'{}'::jsonb)$q$,:'job'),'%MAPPING_ALREADY_RESOLVED%');
select public.prepare_import_chunk_v2(:'job'::uuid,'[
 {"medium":"anime","external_id":"897999","resolved_media_id":797007,"values":{"status":"watching","progress":1}},
 {"medium":"anime","external_id":"897998","resolved_media_id":797012,"values":{"status":"watching","progress":1}}
]'::jsonb,'{}'::jsonb);
select public.import_items_page_v2(:'job'::uuid,null,50)as matched_review \gset
select tests.eq('manual matching an existing title captures a fresh review baseline',
 (select e->>'expected_revision'from jsonb_array_elements(:'matched_review'::jsonb->'items')e where e->>'external_id'='897999'),'1');
select tests.eq('manual matching shows actual current values before approval',
 (select e->'current'->>'progress'from jsonb_array_elements(:'matched_review'::jsonb->'items')e where e->>'external_id'='897999'),'6');
select tests.raises('Apply cannot install an unreviewed manual identity',format($q$select public.apply_import_chunk_v2(%L::uuid,'v2-wrong-mapping-970','[{"medium":"anime","external_id":"897998","resolved_media_id":797007,"action":"add","fields":[]}]'::jsonb)$q$,:'job'),'%UNREVIEWED_MAPPING%');
-- An unattempted manual target can change, but the old approval must never
-- target its replacement merely because both missing-row baselines are null.
select public.prepare_import_chunk_v2(:'job'::uuid,'[{"medium":"anime","external_id":"897998","resolved_media_id":797010,"values":{"status":"watching","progress":1}}]'::jsonb);
select tests.raises('manual approval without target seal cannot use a replacement match',format($q$select public.apply_import_chunk_v2(%L::uuid,'v2-absent-match-970','[{"medium":"anime","external_id":"897998","action":"add","fields":[]}]'::jsonb)$q$,:'job'),'%UNREVIEWED_MAPPING%');
select tests.raises('old manual target cannot approve the newly staged match',format($q$select public.apply_import_chunk_v2(%L::uuid,'v2-stale-match-970','[{"medium":"anime","external_id":"897998","resolved_media_id":797012,"action":"add","fields":[]}]'::jsonb)$q$,:'job'),'%UNREVIEWED_MAPPING%');
select tests.eq('rejected stale match added neither target',(select count(*)from public.anime_user_lists where anime_id in(797010,797012)),0::bigint);
-- Same-target review replay retains the original revision even after an edit.
update public.anime_user_lists set notes='new manual note'where anime_id=797007;
select public.prepare_import_chunk_v2(:'job'::uuid,'[{"medium":"anime","external_id":"897999","resolved_media_id":797007,"values":{"status":"watching","progress":1}}]'::jsonb);
select tests.eq('same-target manual replay cannot refresh the reviewed baseline',
 (select expected_revision from public.library_import_items where job_id=:'job'::uuid and external_id='897999'),1::bigint);
-- Restore the edit through a fresh review expectation is deliberately avoided:
-- the first approval must conflict and leave the new note intact.
-- A later edit and an add/remove after a missing-row review both conflict.
update public.anime_user_lists set progress=3 where anime_id=797008;
insert into public.anime_user_lists(user_id,anime_id,list_type,progress)values(tests.uid(970)::text,797009,'WATCHING',2);
delete from public.anime_user_lists where anime_id=797009;
select public.import_items_page_v2(:'job'::uuid,null,50)as decision_review \gset
select jsonb_agg(jsonb_build_object('medium',e->>'medium','external_id',e->>'external_id','fields','[]'::jsonb,
 'expected_revision',e->'expected_revision','expected_lifecycle',e->'expected_lifecycle','resolved_media_id',e->'media_id',
 'action',case when e->>'external_id' in('3000000000','897006')then 'defer'when e->>'external_id' in('897003','897004','897999')then 'keep'else 'add'end)order by e->>'medium',e->>'external_id')as decisions
from jsonb_array_elements(:'decision_review'::jsonb->'items')e \gset
select jsonb_agg(e.value order by e.ordinality)as decisions_first from jsonb_array_elements(:'decisions'::jsonb)with ordinality e(value,ordinality)where e.ordinality<=5 \gset
select jsonb_agg(e.value order by e.ordinality)as decisions_second from jsonb_array_elements(:'decisions'::jsonb)with ordinality e(value,ordinality)where e.ordinality>5 \gset
select public.apply_import_chunk_v2(:'job'::uuid,'v2-approved-action-970',:'decisions_first'::jsonb)as applied_first \gset
select public.apply_import_chunk_v2(:'job'::uuid,'v2-approved-action-970',:'decisions_second'::jsonb)as applied \gset
select tests.eq('disjoint chunks share one immutable confirmation action',(:'applied'::jsonb->'counts'->>'pending')::integer,0);
select tests.eq('an earlier lost chunk response stays exact after subsequent chunks',public.apply_import_chunk_v2(:'job'::uuid,'v2-approved-action-970',:'decisions_first'::jsonb),:'applied_first'::jsonb);
select tests.eq('default keep preserves all existing Kuro fields',
 (select jsonb_build_array(list_type,progress,progress_label,unit_id,score_raw,score_scale,rating,notes,entry_private,source_hidden,source_custom_lists,server_revision)from public.manga_user_lists where manga_id=797003),
 '["READING",4,"4.5","97097097-0970-4970-8970-970970970970",80,"POINT_100",8,"Kuro note",true,true,["Kuro"],1]'::jsonb);
select tests.eq('explicit keep and identical items count unchanged',(:'applied'::jsonb->'counts'->>'unchanged')::integer,2);
select tests.eq('all valid new statuses and manual new identity add',(:'applied'::jsonb->'counts'->>'added')::integer,4);
select tests.eq('later edit and tombstone race plus source_changed count conflicts',(:'applied'::jsonb->'counts'->>'conflict')::integer,4);
select tests.eq('later edit is preserved',(select progress from public.anime_user_lists where anime_id=797008),3);
select tests.eq('reviewed-missing add/remove is not silently recreated',(select count(*)from public.anime_user_lists where anime_id=797009),0::bigint);
select tests.eq('manual matching does not mutate global provider identities',(select count(*)from public.provider_entry_refs where provider='myanimelist'and external_id in('897998','897999')),0::bigint);
select tests.eq('lost response replays the original complete chunk response',public.apply_import_chunk_v2(:'job'::uuid,'v2-approved-action-970',:'decisions_second'::jsonb),:'applied'::jsonb);
select tests.raises('attempted approval body cannot be rewritten',format($q$select public.apply_import_chunk_v2(%L::uuid,'v2-approved-action-970','[{"medium":"anime","external_id":"897001","action":"keep","fields":[]}]'::jsonb)$q$,:'job'),'%DECISION_ALREADY_FINAL%');
select public.finish_library_import_v2(:'job'::uuid)as finished \gset
select tests.eq('source finalization keeps projection readiness honest',:'finished'::jsonb->>'projection_ready','false');
select tests.eq('saved result is durable and terminal',:'finished'::jsonb->>'phase','ready');
select tests.eq('official planning and hold aliases survive in Library',
 (select jsonb_agg(list_type order by anime_id)from public.anime_user_lists where anime_id in(797001,797005)), '["PLANNING","PAUSED"]'::jsonb);
select tests.raises('terminal job cannot reopen with a new approval action',format($q$select public.apply_import_chunk_v2(%L::uuid,'v2-new-terminal-action','[{"medium":"anime","external_id":"897001","action":"add","fields":[]}]'::jsonb)$q$,:'job'),'%JOB_NOT_APPLYING%');
-- Paged owner-only results and precise cursor roundtrips.
select public.import_items_page_v2(:'job'::uuid,null,3)as page1 \gset
select public.import_items_page_v2(:'job'::uuid,:'page1'::jsonb->>'next_cursor',3)as page2 \gset
select tests.eq('item paging returns bounded pages',jsonb_array_length(:'page1'::jsonb->'items'),3);
select tests.ok('item pages have no repeated identity',not exists(select 1 from jsonb_array_elements(:'page1'::jsonb->'items')a join jsonb_array_elements(:'page2'::jsonb->'items')b on(a->>'medium',a->>'external_id')=(b->>'medium',b->>'external_id')));
select tests.as_user(tests.uid(971));
select tests.raises('outsider cannot read private results',format('select public.import_items_page_v2(%L::uuid)',:'job'),'%NOT_AUTHORIZED%');
select tests.raises('outsider cannot stop the import',format('select public.cancel_library_import_v2(%L::uuid)',:'job'),'%NOT_AUTHORIZED%');
select tests.eq('outsider job list is empty',jsonb_array_length(public.import_jobs_page_v2()->'jobs'),0);
select tests.as_user(tests.uid(970));
-- Edit one added title; replace another with identical fields. Guarded Undo must
-- skip both and restore/remove only the two untouched committed lifetimes.
update public.anime_user_lists set notes='new Kuro edit'where anime_id=797001;
delete from public.anime_user_lists where anime_id=797005;
insert into public.anime_user_lists(user_id,anime_id,list_type,progress)values(tests.uid(970)::text,797005,'PAUSED',4);
select public.undo_library_import_chunk_v2(:'job'::uuid,'v2-undo-action-970',null,2)as undo1 \gset
select tests.eq('first bounded Undo uses the same immutable response on retry',public.undo_library_import_chunk_v2(:'job'::uuid,'v2-undo-action-970',null,2),:'undo1'::jsonb);
select tests.raises('Undo cursor cannot be skipped ahead',format($q$select public.undo_library_import_chunk_v2(%L::uuid,'v2-undo-action-970',encode(convert_to('{"medium":"manga","external_id":"999999"}','UTF8'),'base64'),2)$q$,:'job'),'%INVALID_UNDO_CURSOR%');
select public.undo_library_import_chunk_v2(:'job'::uuid,'v2-undo-action-970',:'undo1'::jsonb->>'next_cursor',2)as undo2 \gset
select tests.eq('guarded Undo cumulative reverted is correct',(:'undo2'::jsonb->>'reverted')::integer,2);
select tests.eq('guarded Undo cumulative skipped is correct',(:'undo2'::jsonb->>'skipped')::integer,2);
select tests.eq('bounded Undo reaches undone',:'undo2'::jsonb->'job'->>'phase','undone');
select tests.eq('later edits survive compensation',(select notes from public.anime_user_lists where anime_id=797001),'new Kuro edit');
select tests.eq('replacement lifetimes survive compensation',(select progress from public.anime_user_lists where anime_id=797005),4);
select tests.eq('unchanged/kept entries are not part of Undo',(select progress from public.anime_user_lists where anime_id=797007),6);

-- A fresh review can explicitly approve a subset of existing fields. Zero score
-- must not relabel retained 80/POINT_100; unchanged progress retains exact unit.
select public.start_library_import_v2('{"provider":"myanimelist","source_kind":"export","source_identity":"update.xml","media":["manga"]}'::jsonb,'v2-field-review-970')->>'job_id'as fields_job \gset
select public.prepare_import_chunk_v2(:'fields_job'::uuid,'[{"medium":"manga","external_id":"897003","values":{"status":"on_hold","progress":4,"score_raw":"0","score_scale":"MAL_10","notes":"must stay Kuro","private":false,"hidden_from_status_lists":false,"started_raw":"2026-01-01","unavailable_fields":["finished_raw"]}}]'::jsonb,'{"manga":true}');
select public.import_items_page_v2(:'fields_job'::uuid)->'items'->0 as field_review \gset
select jsonb_build_array(jsonb_build_object('medium','manga','external_id','897003','action','update','fields','["status","progress","score","privacy","dates"]'::jsonb,
 'expected_revision',:'field_review'::jsonb->'expected_revision','expected_lifecycle',:'field_review'::jsonb->'expected_lifecycle'))as field_decision \gset
select public.apply_import_chunk_v2(:'fields_job'::uuid,'v2-fields-approval-970',:'field_decision'::jsonb)as field_apply \gset
select tests.eq('approved subset preserves unapproved note, memberships, repeats and precise tracking',
 (select jsonb_build_array(list_type,progress,unit_id,progress_label,notes,source_custom_lists,repeat_count,score_raw,score_scale,rating,entry_private,source_hidden,started_raw,finished_raw)from public.manga_user_lists where manga_id=797003),
 '["PAUSED",4,"97097097-0970-4970-8970-970970970970","4.5","Kuro note",["Kuro"],2,80,"POINT_100",8,false,false,"2026-01-01","2025-04-03"]'::jsonb);
select public.finish_library_import_v2(:'fields_job'::uuid);
select public.undo_library_import_chunk_v2(:'fields_job'::uuid,'v2-fields-undo-970')as fields_undo \gset
select tests.eq('guarded existing-entry Undo restores the exact before-image',
 (select jsonb_build_array(list_type,progress,unit_id,progress_label,score_raw,score_scale,rating,entry_private,source_hidden,started_raw,finished_raw)from public.manga_user_lists where manga_id=797003),
 '["READING",4,"97097097-0970-4970-8970-970970970970","4.5",80,"POINT_100",8,true,true,"2025-01-02","2025-04-03"]'::jsonb);

-- Identical update has no Library/Home revision change, while a changed integer
-- progress clears obsolete precise metadata and Undo recovers it faithfully.
select public.start_library_import_v2('{"provider":"myanimelist","source_kind":"export","source_identity":"noop.xml","media":["manga"]}'::jsonb,'v2-noop-review-970')->>'job_id'as noop_job \gset
select public.prepare_import_chunk_v2(:'noop_job'::uuid,'[{"medium":"manga","external_id":"897003","values":{"status":"reading","progress":4}}]'::jsonb,'{"manga":true}');
select public.import_items_page_v2(:'noop_job'::uuid)->'items'->0 as noop_review \gset
select server_revision as before_noop from public.manga_user_lists where manga_id=797003 \gset
select revision as before_noop_home from public.home_publications where user_id=tests.uid(970)::text and medium='manga' \gset
select jsonb_build_array(jsonb_build_object('medium','manga','external_id','897003','action','update','fields','["status","progress"]'::jsonb,
 'expected_revision',:'noop_review'::jsonb->'expected_revision','expected_lifecycle',:'noop_review'::jsonb->'expected_lifecycle'))as noop_decision \gset
select public.apply_import_chunk_v2(:'noop_job'::uuid,'v2-noop-approval-970',:'noop_decision'::jsonb)as noop_apply \gset
select tests.eq('identical effective input is counted unchanged',(:'noop_apply'::jsonb->'counts'->>'unchanged')::integer,1);
select tests.eq('identical import does not bump the Library revision',(select server_revision from public.manga_user_lists where manga_id=797003),:'before_noop'::bigint);
select tests.eq('identical import does not bump Home publication',(select revision from public.home_publications where user_id=tests.uid(970)::text and medium='manga'),:'before_noop_home'::bigint);
select public.finish_library_import_v2(:'noop_job'::uuid);
select public.start_library_import_v2('{"provider":"myanimelist","source_kind":"export","source_identity":"progress.xml","media":["manga"]}'::jsonb,'v2-progress-review-970')->>'job_id'as progress_job \gset
select public.prepare_import_chunk_v2(:'progress_job'::uuid,'[{"medium":"manga","external_id":"897003","values":{"status":"reading","progress":7,"notes":"not approved"}}]'::jsonb,'{"manga":true}');
select public.import_items_page_v2(:'progress_job'::uuid)->'items'->0 as progress_review \gset
select jsonb_build_array(jsonb_build_object('medium','manga','external_id','897003','action','update','fields','["progress"]'::jsonb,
 'expected_revision',:'progress_review'::jsonb->'expected_revision','expected_lifecycle',:'progress_review'::jsonb->'expected_lifecycle'))as progress_decision \gset
select public.apply_import_chunk_v2(:'progress_job'::uuid,'v2-progress-approval-970',:'progress_decision'::jsonb);
select tests.eq('changed approved progress clears obsolete unit/label and preserves unapproved notes',
 (select jsonb_build_array(progress,unit_id,progress_label,notes)from public.manga_user_lists where manga_id=797003),'[7,null,null,"Kuro note"]'::jsonb);
-- Stop after partial commitment: saved data remains and a new chunk is refused.
select public.cancel_library_import_v2(:'progress_job'::uuid)as stopped \gset
select tests.eq('stop preserves the committed progress',(select progress from public.manga_user_lists where manga_id=797003),7);
select tests.eq('cancel replay is idempotent',public.cancel_library_import_v2(:'progress_job'::uuid),:'stopped'::jsonb);
select tests.raises('cancel prevents subsequent application',format($q$select public.apply_import_chunk_v2(%L::uuid,'v2-after-stop-970','[{"medium":"manga","external_id":"897003","action":"keep","fields":[]}]'::jsonb)$q$,:'progress_job'),'%JOB_NOT_APPLYING%');
select public.undo_library_import_chunk_v2(:'progress_job'::uuid,'v2-progress-undo-970');
select tests.eq('Undo of a partially cancelled import restores precise progress',
 (select jsonb_build_array(progress,unit_id,progress_label)from public.manga_user_lists where manga_id=797003),'[4,"97097097-0970-4970-8970-970970970970","4.5"]'::jsonb);
-- A positive approved score updates raw/scale/rating together without touching
-- an unapproved position. A fresh reviewed re-add after an earlier removal is
-- allowed; only removals occurring after this review are conflicts.
select public.start_library_import_v2('{"provider":"myanimelist","source_kind":"export","source_identity":"score.xml","media":["anime","manga"]}'::jsonb,'v2-score-review-970')->>'job_id'as score_job \gset
select tests.raises('source preparation enforces the100item bound',format($q$select public.prepare_import_chunk_v2(%L::uuid,(select jsonb_agg('{"medium":"anime","external_id":"897009","values":{"status":"watching"}}'::jsonb)from generate_series(1,101)),'{}'::jsonb)$q$,:'score_job'),'%INVALID_PAYLOAD%');
select public.prepare_import_chunk_v2(:'score_job'::uuid,'[
 {"medium":"manga","external_id":"897003","values":{"status":"reading","progress":7,"score_raw":"6","score_scale":"MAL_10","normalized_rating":6}},
 {"medium":"anime","external_id":"897009","values":{"status":"watching","progress":2}}
]'::jsonb,'{"anime":true,"manga":true}');
select public.import_items_page_v2(:'score_job'::uuid)as score_review \gset
select jsonb_agg(jsonb_build_object('medium',e->>'medium','external_id',e->>'external_id','action',case when e->>'medium'='manga'then 'update'else 'add'end,
 'fields',case when e->>'medium'='manga'then '["score"]'::jsonb else '[]'::jsonb end,
 'expected_revision',e->'expected_revision','expected_lifecycle',e->'expected_lifecycle'))as score_decisions from jsonb_array_elements(:'score_review'::jsonb->'items')e \gset
select public.apply_import_chunk_v2(:'score_job'::uuid,'v2-score-approval-970',:'score_decisions'::jsonb)as score_applied \gset
select tests.eq('positive approved score is one coupled value with unapproved precise progress preserved',
 (select jsonb_build_array(score_raw,score_scale,rating,progress,unit_id,progress_label)from public.manga_user_lists where manga_id=797003),
 '[6,"MAL_10",6,4,"97097097-0970-4970-8970-970970970970","4.5"]'::jsonb);
select tests.eq('explicit new review may re-add a title removed before this review',(select progress from public.anime_user_lists where anime_id=797009),2);
select public.finish_library_import_v2(:'score_job'::uuid);
select public.undo_library_import_chunk_v2(:'score_job'::uuid,'v2-score-undo-970');
select tests.eq('score compensation restores its original scale and normalized value',
 (select jsonb_build_array(score_raw,score_scale,rating)from public.manga_user_lists where manga_id=797003),'[80,"POINT_100",8]'::jsonb);
-- Unavailable progress protects the complete precise group, even if an
-- untrusted source supplies a different label alongside the unavailable marker.
select public.start_library_import_v2('{"provider":"myanimelist","source_kind":"export","source_identity":"unavailable.xml","media":["manga"]}'::jsonb,'v2-unavailable-review-970')->>'job_id'as unavailable_job \gset
select public.prepare_import_chunk_v2(:'unavailable_job'::uuid,'[{"medium":"manga","external_id":"897003","values":{"status":"reading","progress":7,"progress_label":"9.5","unavailable_fields":["progress"]}}]'::jsonb,'{"manga":true}');
select public.import_items_page_v2(:'unavailable_job'::uuid)->'items'->0 as unavailable_review \gset
select public.apply_import_chunk_v2(:'unavailable_job'::uuid,'v2-unavailable-approval-970',jsonb_build_array(jsonb_build_object('medium','manga','external_id','897003','action','update','fields','["progress"]'::jsonb,'expected_revision',:'unavailable_review'::jsonb->'expected_revision','expected_lifecycle',:'unavailable_review'::jsonb->'expected_lifecycle')));
select tests.eq('unavailable progress preserves integer, unit and fractional label',
 (select jsonb_build_array(progress,unit_id,progress_label)from public.manga_user_lists where manga_id=797003),'[4,"97097097-0970-4970-8970-970970970970","4.5"]'::jsonb);
select public.finish_library_import_v2(:'unavailable_job'::uuid);
-- Compatible duplicate fields still form one validated progress group:
-- a later label cannot be attached to the earlier unit by a fast-path merge.
select public.start_library_import_v2('{"provider":"myanimelist","source_kind":"export","source_identity":"duplicate-unit.xml","media":["anime","manga"]}'::jsonb,'v2-duplicate-unit-970')->>'job_id'as duplicate_unit_job \gset
select public.prepare_import_chunk_v2(:'duplicate_unit_job'::uuid,'[{"medium":"manga","external_id":"897003","values":{"status":"reading","progress":4,"unit_id":"97097097-0970-4970-8970-970970970970"}}]'::jsonb);
select public.prepare_import_chunk_v2(:'duplicate_unit_job'::uuid,'[{"medium":"manga","external_id":"897003","values":{"status":"reading","progress":4,"progress_label":"9.5"}}]'::jsonb,'{"anime":true,"manga":true}');
select public.import_items_page_v2(:'duplicate_unit_job'::uuid)->'items'->0 as duplicate_unit_review \gset
select tests.eq('merged duplicate unit and label must agree with catalogue identity',:'duplicate_unit_review'::jsonb->>'disposition','invalid');
select tests.raises('merged incompatible precision cannot be approved',format($q$select public.apply_import_chunk_v2(%L::uuid,'v2-duplicate-unit-approval',jsonb_build_array(jsonb_build_object('medium','manga','external_id','897003','action','update','fields','["progress"]'::jsonb,'expected_revision',%L::jsonb->'expected_revision','expected_lifecycle',%L::jsonb->'expected_lifecycle')))$q$,:'duplicate_unit_job',:'duplicate_unit_review',:'duplicate_unit_review'),'%ITEM_REQUIRES_REVIEW%');
select tests.eq('rejected duplicate precision keeps the actual Library unit and label',
 (select jsonb_build_array(progress,unit_id,progress_label)from public.manga_user_lists where manga_id=797003),'[4,"97097097-0970-4970-8970-970970970970","4.5"]'::jsonb);
select public.cancel_library_import_v2(:'duplicate_unit_job'::uuid);
-- Once review is ready, an optional new privacy leg cannot silently expand a
-- frozen privacy decision. The item becomes defer-only, preserving Library.
select public.start_library_import_v2('{"provider":"myanimelist","source_kind":"export","source_identity":"consent.xml","media":["manga"]}'::jsonb,'v2-consent-review-970')->>'job_id'as consent_job \gset
select public.prepare_import_chunk_v2(:'consent_job'::uuid,'[{"medium":"manga","external_id":"897003","values":{"status":"reading","private":false,"unavailable_fields":["hidden_from_status_lists"]}}]'::jsonb,'{"manga":true}');
select public.import_items_page_v2(:'consent_job'::uuid)->'items'->0 as consent_review \gset
select public.prepare_import_chunk_v2(:'consent_job'::uuid,'[{"medium":"manga","external_id":"897003","values":{"status":"reading","private":false,"hidden_from_status_lists":false}}]'::jsonb);
select tests.eq('post-coverage optional field expansion is source_changed',
 (select disposition from public.library_import_items where job_id=:'consent_job'::uuid),'source_changed');
select tests.raises('old privacy approval cannot apply an unseen source field',format($q$select public.apply_import_chunk_v2(%L::uuid,'v2-consent-approval-970',jsonb_build_array(jsonb_build_object('medium','manga','external_id','897003','action','update','fields','["privacy"]'::jsonb,'expected_revision',%L::jsonb->'expected_revision','expected_lifecycle',%L::jsonb->'expected_lifecycle')))$q$,:'consent_job',:'consent_review',:'consent_review'),'%SOURCE_CHANGED%');
select tests.eq('rejected expanded approval preserves both privacy legs',
 (select jsonb_build_array(entry_private,source_hidden)from public.manga_user_lists where manga_id=797003),'[true,true]'::jsonb);
select public.cancel_library_import_v2(:'consent_job'::uuid);
-- A compatible duplicate can add known optional values where an earlier source
-- appearance disclosed their absence; the core tracking values remain equal.
select public.start_library_import_v2('{"provider":"myanimelist","source_kind":"export","source_identity":"optional.xml","media":["anime"]}'::jsonb,'v2-optional-review-970')->>'job_id'as optional_job \gset
select public.prepare_import_chunk_v2(:'optional_job'::uuid,'[{"medium":"anime","external_id":"897001","values":{"status":"watching","progress":3,"custom_lists":["A"],"unavailable_fields":["notes"]}}]'::jsonb,'{}');
select public.prepare_import_chunk_v2(:'optional_job'::uuid,'[{"medium":"anime","external_id":"897001","values":{"status":"watching","progress":3,"notes":"known source note","custom_lists":["B"]}}]'::jsonb,'{"anime":true}');
select public.import_items_page_v2(:'optional_job'::uuid)->'items'->0 as optional_review \gset
select tests.eq('missing optional evidence does not manufacture a source contradiction',:'optional_review'::jsonb->>'disposition','changes');
select tests.eq('known optional evidence and valid memberships merge canonically',
 jsonb_build_array(:'optional_review'::jsonb->'incoming'->'notes',:'optional_review'::jsonb->'incoming'->'custom_lists'),
 '["known source note",["A","B"]]'::jsonb);
select public.cancel_library_import_v2(:'optional_job'::uuid);
-- The new schema and version fence do not disable the retained v1 contract for
-- a legacy job. It can still ingest a new title using its original response shape.
select tests.reset();
insert into public.anime(id,title_romaji,mal_id)values(797011,'Legacy compatibility',897011);
select tests.as_user(tests.uid(970));
select public.start_library_import_v1('myanimelist','export','anime','v1-retained-job-970','v1-retained-payload-970')->>'job_id'as legacy_job \gset
select public.apply_import_chunk_v1(:'legacy_job'::uuid,'[{"medium":"anime","external_id":"897011","status":"watching","progress":1}]'::jsonb)as legacy_applied \gset
select tests.eq('retained v1 job still applies through its original contract',:'legacy_applied'::jsonb->>'added','1');
select tests.eq('retained v1 finalization response remains compatible',public.finish_library_import_v1(:'legacy_job'::uuid,true)->>'state','ready');
-- Terminal maintenance retains exactly the latest ten detailed histories;
-- summaries survive and older jobs advertise the missing compensation history.
DO $$DECLARE n integer; job uuid; BEGIN
 FOR n IN 1..12 LOOP
  job:=(public.start_library_import_v2(jsonb_build_object('provider','myanimelist','source_kind','export','source_identity','retention-'||n,'media',jsonb_build_array('anime')), 'v2-retention-970-'||n)->>'job_id')::uuid;
  PERFORM public.cancel_library_import_v2(job);
 END LOOP;
END;$$;
select tests.eq('latest ten terminal jobs retain detailed history',
 (select count(*)from public.library_import_jobs where user_id=tests.uid(970)and contract_version=2 and history_available and phase in('ready','cancelled','failed','undone')),10::bigint);
select tests.eq('older jobs explicitly report unavailable history',public.import_job_status_v2(:'job'::uuid)->>'history_available','false');
select tests.eq('pruning retains original result counts',public.import_job_status_v2(:'job'::uuid)->'counts'->>'added','4');
select tests.raises('pruned history cannot pretend Undo is available',format($q$select public.undo_library_import_chunk_v2(%L::uuid,'v2-pruned-undo-970')$q$,:'job'),'%HISTORY_UNAVAILABLE%');
select public.import_jobs_page_v2(null,3)as jobs_page1 \gset
select public.import_jobs_page_v2(:'jobs_page1'::jsonb->>'next_cursor',3)as jobs_page2 \gset
select tests.eq('job history pages are bounded',jsonb_array_length(:'jobs_page1'::jsonb->'jobs'),3);
select tests.ok('opaque job cursors never duplicate a job',not exists(select 1 from jsonb_array_elements(:'jobs_page1'::jsonb->'jobs')a join jsonb_array_elements(:'jobs_page2'::jsonb->'jobs')b on a->>'job_id'=b->>'job_id'));
select tests.ok('private normalization helpers are not an alternate writer API',not has_function_privilege('authenticated','public._import_v2_store(text,text,integer,jsonb,boolean)','EXECUTE'));
select tests.reset();
rollback;
