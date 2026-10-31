-- Source producer/disclosure/edition regression contract. Disposable fixture only.
-- NOT RUN until a fresh current-source PostgreSQL fixture can start; never a live probe.
-- series_enrichment_jobs is the migration's subject: absence must FAIL, not prerequisite-BLOCK.
-- @requires table public.club_membership_signals
\set ON_ERROR_STOP on
\o /dev/null
begin;
select tests.make_user(n) from generate_series(96,118)n;
insert into public.anime(id,title_romaji,anilist_id,description,banner_image)
values(795001,'Producer fixture',795901,'A sourced story. A longer synopsis.','https://s4.anilist.co/producer.png');
insert into public.manga(id,title_romaji,description,cover_image_large)
values(795002,'Edition fixture','A manga story.','https://s4.anilist.co/manga.png');
select tests.eq('catalogue change enqueues exactly one source job',
 (select count(*) from public.series_enrichment_jobs where medium='anime' and media_id=795001),1::bigint);
select source_revision as source_rev from public.series_enrichment_jobs where medium='anime' and media_id=795001 \gset
select tests.eq('unclaimed null lease cannot finish',
 public.finish_series_enrichment_v1('anime',795001,:'source_rev',null,'{"synopsis":"bad"}')->>'outcome','superseded');
select tests.eq('unclaimed job did not write story',(select count(*) from public.detail_copy where anime_id=795001),0::bigint);
update public.series_enrichment_jobs set due_at=now()+interval '1 day' where medium='manga' and media_id=795002;
select public.claim_series_enrichment_v1(1) as claim \gset
select tests.eq('claim is bounded to one',jsonb_array_length(:'claim'::jsonb),1);
select :'claim'::jsonb->0->>'lease_token' as token \gset
select tests.eq('wrong lease cannot publish',
 public.finish_series_enrichment_v1('anime',795001,:'source_rev','95959595-9595-4595-8595-959595959595')->>'outcome','superseded');
select tests.eq('failed extraction schedules retry without deleting last good',
 public.finish_series_enrichment_v1('anime',795001,:'source_rev',:'token',p_error=>'TimeoutError')->>'outcome','retry');
select tests.eq('retry starts at sixty seconds',
 (select due_at>=now()+interval '60 seconds' and attempts=1 and lease_token is null
  from public.series_enrichment_jobs where medium='anime' and media_id=795001),true);
update public.series_enrichment_jobs set due_at=now() where medium='anime' and media_id=795001;
select public.claim_series_enrichment_v1(1) as claim2 \gset
select :'claim2'::jsonb->0->>'lease_token' as token2 \gset
select tests.eq('retry gets a new claim token',:'token2'<>:'token',true);
select tests.eq('old claim is rejected after reclaim',
 public.finish_series_enrichment_v1('anime',795001,:'source_rev',:'token')->>'outcome','superseded');
select jsonb_build_object('image_url','https://s4.anilist.co/producer.png','digest',repeat('a',64),
 'base','#123456','deep','#112233','wash','#fefefe','edge','#aabbcc','ink','#ffffff','contrast',8) as material \gset
select tests.raises('low-contrast material rejected',
 format('select public.finish_series_enrichment_v1(%L,795001,%L,%L,p_material=>%L::jsonb)',
  'anime',:'source_rev',:'token2',(:'material'::jsonb||'{"contrast":2}')::text),'%INVALID_MATERIAL%');
select tests.eq('current claim publishes sourced copy and material',
 public.finish_series_enrichment_v1('anime',795001,:'source_rev',:'token2',
  '{"premise":"A sourced story.","synopsis":"A sourced story. A longer synopsis."}',:'material'::jsonb,
  '[{"source_id":"88","role":"op","song_title":"Opening","artist":"Artist"}]')->>'outcome','applied');
select tests.eq('material identity is current exactly once',
 (select count(*) from public.artwork_materials where image_url='https://s4.anilist.co/producer.png' and is_current),1::bigint);
select tests.eq('themes remain search candidates rather than invented Spotify IDs',
 (select match_state='search' and external_url is null from public.theme_links where anime_id=795001),true);
select tests.eq('finish cannot reuse consumed claim',
 public.finish_series_enrichment_v1('anime',795001,:'source_rev',:'token2')->>'outcome','superseded');
insert into public.detail_copy(medium,anime_id,locale,premise,synopsis,provenance,review_state)
values('anime',795001,'en','Curated story.','Curated full story.','editorial_review','approved');
select tests.as_user(tests.uid(96));
select tests.eq('reviewed story takes priority over source bridge',
 public.series_detail_bundle_v1('anime',795001)->'copy'->>'synopsis','Curated full story.');
select tests.denied('end user cannot claim enrichment jobs','select public.claim_series_enrichment_v1(1)');
select tests.denied('enrichment job payload not readable by user','select * from public.series_enrichment_jobs');
select tests.reset();
update public.anime set description='New source revision.' where id=795001;
select tests.eq('source change schedules fresh extraction',
 (select source_revision<>:'source_rev' and lease_token is null and attempts=0 from public.series_enrichment_jobs
  where medium='anime' and media_id=795001),true);
select tests.eq('old source snapshot cannot replace new story',
 public.finish_series_enrichment_v1('anime',795001,:'source_rev',:'token2','{"synopsis":"stale"}')->>'outcome','superseded');
select tests.eq('pending enrichment retains approved copy',
 (select synopsis from public.detail_copy where anime_id=795001 and review_state='approved'),'Curated full story.');
insert into public.theme_links(anime_id,role,song_title,match_state,evidence)
values(795001,'ed','Reviewed ending','verified','curated fixture');
select public.claim_series_enrichment_v1(1) as refreshed \gset
select :'refreshed'::jsonb->0->>'lease_token' as token3,
 :'refreshed'::jsonb->0->>'source_revision' as source_rev3 \gset
select public.finish_series_enrichment_v1('anime',795001,:'source_rev3',:'token3',p_themes=>null);
select tests.eq('unknown theme match retains prior bridge row',
 (select count(*) from public.theme_links where anime_id=795001 and source_identity is not null),1::bigint);
update public.series_enrichment_jobs set due_at=now() where medium='anime' and media_id=795001;
select public.claim_series_enrichment_v1(1) as known_empty \gset
select public.finish_series_enrichment_v1('anime',795001,:'source_rev3',(:'known_empty'::jsonb->0->>'lease_token')::uuid,p_themes=>'[]');
select tests.eq('known empty authoritative set retires old producer themes',
 (select count(*) from public.theme_links where anime_id=795001 and source_identity is not null),0::bigint);
select tests.eq('known empty set preserves reviewed links',
 (select count(*) from public.theme_links where anime_id=795001 and match_state='verified'),1::bigint);
update public.series_enrichment_jobs set due_at=now() where medium='manga' and media_id=795002;
select public.claim_series_enrichment_v1(1) as manga_claim \gset
select :'manga_claim'::jsonb->0->>'lease_token' as manga_token,
 :'manga_claim'::jsonb->0->>'source_revision' as manga_rev \gset
select tests.raises('cross-URL digest cannot mutate prior artwork identity',
 format('select public.finish_series_enrichment_v1(%L,795002,%L,%L,p_material=>%L::jsonb)',
  'manga',:'manga_rev',:'manga_token',(:'material'::jsonb||'{"image_url":"https://s4.anilist.co/manga.png"}')::text),
 '%INVALID_MATERIAL_IDENTITY%');
select tests.eq('separate URL and digest retain distinct current palettes',
 public.finish_series_enrichment_v1('manga',795002,:'manga_rev',:'manga_token',p_material=>
  :'material'::jsonb||jsonb_build_object('image_url','https://s4.anilist.co/manga.png','digest',repeat('b',64)))->>'outcome','applied');
insert into public.anime(id,title_romaji) values(795003,'Deleted queued title');
select tests.eq('new catalogue title queues a producer job',
 (select count(*) from public.series_enrichment_jobs where medium='anime' and media_id=795003),1::bigint);
delete from public.anime where id=795003;
select tests.eq('catalogue deletion removes its queued job',
 (select count(*) from public.series_enrichment_jobs where medium='anime' and media_id=795003),0::bigint);
select tests.eq('deleted title cannot consume a subsequent claim',jsonb_array_length(public.claim_series_enrichment_v1(20)),0);

-- Exact decimals and independent editions: no interleaved translations or Double cursor.
insert into public.catalogue_units(medium,manga_id,label,order_key,edition_key,source_provenance,available)
select 'manga',795002,n::text,n,'edition-'||lpad(n::text,3,'0'),'source fixture',true from generate_series(1,55)n;
insert into public.catalogue_units(medium,manga_id,label,order_key,edition_key,source_provenance,available)
values('manga',795002,'1.000000000000000001',1.000000000000000001,'edition-001','source fixture',true),
 ('manga',795002,'1.000000000000000002',1.000000000000000002,'edition-001','source fixture',true);
select tests.as_user(tests.uid(96));
select public.series_editions_page_v1('manga',795002) as editions1 \gset
select tests.eq('edition index is bounded',jsonb_array_length(:'editions1'::jsonb->'items'),50);
select tests.eq('edition overflow gives independent keyset',:'editions1'::jsonb->>'next','edition-050');
select tests.eq('remaining editions are reachable',
 jsonb_array_length(public.series_editions_page_v1('manga',795002,null,:'editions1'::jsonb->>'next')->'items'),5);
select public.series_units_page_v1('manga',795002,null,'edition-001',null,null,2) as exact1 \gset
select tests.eq('unit cursor retains exact decimal string',:'exact1'::jsonb->'next'->>'order','1.000000000000000001');
select tests.eq('cursor JSON type is string',jsonb_typeof(:'exact1'::jsonb->'next'->'order'),'string');
select tests.eq('no fractional unit is skipped by subsequent cursor',
 public.series_units_page_v1('manga',795002,null,'edition-001',
  (:'exact1'::jsonb->'next'->>'order')::numeric,(:'exact1'::jsonb->'next'->>'id')::uuid,2)->'items'->0->>'label','1.000000000000000002');
select tests.eq('initial detail uses one source edition',
 public.series_detail_bundle_v1('manga',795002)->>'edition','edition-001');
select tests.eq('initial detail edition index bounded',
 jsonb_array_length(public.series_detail_bundle_v1('manga',795002)->'editions'),50);
select tests.reset();

-- Two real-sized clubs: own comment remains editable when it falls outside first20.
insert into public.clubs(id,name,created_by,sharing_level) values
 ('95959595-9595-4595-8595-959595959591','First',tests.uid(96),'status'),
 ('95959595-9595-4595-8595-959595959592','Second',tests.uid(96),'status');
insert into public.club_members(club_id,user_id,role,sharing_level) values
 ('95959595-9595-4595-8595-959595959591',tests.uid(96),'owner',null),
 ('95959595-9595-4595-8595-959595959592',tests.uid(96),'owner',null);
insert into public.club_members(club_id,user_id,sharing_level)
select case when n<108 then '95959595-9595-4595-8595-959595959591'::uuid
 else '95959595-9595-4595-8595-959595959592'::uuid end,tests.uid(n),null from generate_series(97,118)n;
insert into public.title_comments(user_id,media_type,media_id,text,created_at)
select tests.uid(n),'ANIME',795001,'Private club thought '||n,case when n=96 then now()-interval '1 day' else now() end
from generate_series(96,118)n;
insert into public.anime_user_lists(user_id,anime_id,list_type,progress)
select tests.uid(n)::text,795001,'WATCHING',3 from generate_series(97,118)n;
select id::text as own_comment from public.title_comments where user_id=tests.uid(96) \gset
select tests.as_user(tests.uid(97));
select tests.eq('default null member level inherits club for direct reads',
 (select count(*) from public.title_comments where user_id=tests.uid(96) and media_id=795001),1::bigint);
select public.toggle_comment_reaction(:'own_comment','up');
select tests.as_user(tests.uid(96));
select public.friend_activity_page_v1('ANIME',795001) as activity \gset
select tests.eq('private discussion first page bounded',jsonb_array_length(:'activity'::jsonb->'comments'),20);
select tests.eq('own comment is pinned outside first page',:'activity'::jsonb->'own_comment'->>'id',:'own_comment');
select tests.eq('pinned own reaction count is real',(:'activity'::jsonb->'own_comment'->>'up_count')::integer,1);
select tests.eq('status visibility hides episode count',:'activity'::jsonb->'friends_tracking'->0->>'progress',null::text);
select revision as signal_before from public.club_membership_signals
 where user_id=tests.uid(96) and club_id='95959595-9595-4595-8595-959595959591' \gset
select tests.reset();
update public.anime_user_lists set entry_private=true where user_id=tests.uid(97)::text and anime_id=795001;
select tests.as_user(tests.uid(96));
select tests.eq('private list entry removed from friend tracking',
 (select count(*) from jsonb_array_elements(public.friend_activity_page_v1('ANIME',795001)->'friends_tracking')f
  where f->>'user_id'=tests.uid(97)::text),0::bigint);
select tests.eq('list privacy notifies the viewers own metadata row',
 (select revision>:signal_before from public.club_membership_signals
  where user_id=tests.uid(96) and club_id='95959595-9595-4595-8595-959595959591'),true);
select tests.eq('viewer cannot read peer metadata signal',
 (select count(*) from public.club_membership_signals where user_id=tests.uid(97)),0::bigint);
select tests.reset();
update public.club_members set sharing_level='private' where user_id=tests.uid(97);
select tests.as_user(tests.uid(96));
select tests.eq('direct RLS hides downgraded peer comment',
 (select count(*) from public.title_comments where user_id=tests.uid(97) and media_id=795001),0::bigint);
select tests.eq('paged private discussion also hides downgraded peer',
 (select count(*) from jsonb_array_elements(public.friend_activity_page_v1('ANIME',795001)->'comments')c
  where c->>'user_id'=tests.uid(97)::text),0::bigint);
select tests.as_user(tests.uid(96));
select public.remove_club_member('95959595-9595-4595-8595-959595959591',tests.uid(97));
select tests.as_user(tests.uid(97));
select tests.eq('removed user has no remaining membership authority',
 public.is_club_member('95959595-9595-4595-8595-959595959591'),false);
select tests.eq('removed user loses the club discussion',
 (select count(*) from public.title_comments where user_id=tests.uid(96) and media_id=795001),0::bigint);
select tests.eq('removed user receives terminal membership signal',
 (select state from public.club_membership_signals where user_id=tests.uid(97)
  and club_id='95959595-9595-4595-8595-959595959591'),'removed');
select tests.reset();
rollback;
