\set ON_ERROR_STOP on
-- Same session as fixture and exact prepared migration; superuser is local only.
do $$declare t text;p text;idx text;j jsonb;r jsonb;b jsonb;n integer;begin
 for t,p,idx in values('episodes','anime_id','idx_episodes_anime_parent_v1'),('chapters','manga_id','idx_chapters_manga_parent_v1') loop
  execute format('select jsonb_agg(to_jsonb(x) order by id) from(select id,number,title from public.%I where %I=19)x',t,p) into r;
  select rows,plan into b,j from lookup_baseline where name=t;
  assert r=b,'Parent result set changed';
  select count(*) into n from jsonb_array_elements(r) x where x->>'number' is null;
  assert n>0,'Unknown episode/chapter numbers must remain visible';
  execute format('explain(analyze,buffers,format json) select id,number,title from public.%I where %I=19',t,p) into j;
  assert j::text like '%'||idx||'%', 'Actual parent read must use the new index';
  raise notice '% parent read after: %',t,j;
  execute format('explain(format json) delete from public.%I where %I=19',t,p) into j;
  assert j::text like '%'||idx||'%', 'Importer parent delete must use new index without a number guard';
 end loop;
end$$;
select name,plan as before_plan from lookup_baseline order by name;
select '10 assertions passed (2 baseline, 2 parity, 2 NULL preservation, 2 indexed reads, 2 indexed delete plans)' as result;
