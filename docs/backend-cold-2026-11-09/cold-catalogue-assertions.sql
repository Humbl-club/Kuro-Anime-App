\set ON_ERROR_STOP on
set search_path=public,extensions;
set jit=off;
create table cold_test.assertions(name text,passed boolean);
do $$declare c record;j jsonb;p jsonb;begin
for c in select * from cold_test.cases order by (name not like '%-30'),name loop
execute 'explain(analyze,buffers,format json) '||c.query into p;
execute 'select coalesce(jsonb_agg(to_jsonb(s)),''[]''::jsonb) from ('||c.query||')s' into j;
assert j=c.before_rows,'Index changed rows/order: '||c.name;
update cold_test.cases set after_plan=p where name=c.name;
insert into cold_test.assertions values('identical rows/order '||c.name,true);
if c.name like '%-30' then
 raise notice 'FOOTPRINT % before:% after:%',c.name,c.before_plan,p;
 assert p::text like '%_cold_v1%', 'Expected exact order index: '||c.name;
 assert (p->0->'Plan'->>'Shared Hit Blocks')::int+(p->0->'Plan'->>'Shared Read Blocks')::int < ((c.before_plan->0->'Plan'->>'Shared Hit Blocks')::int+(c.before_plan->0->'Plan'->>'Shared Read Blocks')::int),'Logical page work did not decrease: '||c.name;
 insert into cold_test.assertions values('actual index and fewer logical pages '||c.name,true);
elsif c.name='realm-cozy' then
 assert p::text like '%idx_realm_mood_cold_v1%','Realm covering index missing from actual plan';
 insert into cold_test.assertions values('actual realm covering index used',true);
end if;
end loop;end$$;
do $$declare med text;q text;old jsonb;new jsonb;c jsonb;flag text;begin
foreach med in array array['anime','manga'] loop
foreach q in array array[null,'','a','na','Naruto','naroto','One Piece','Berserk','berser','Fate/stay','日本語','  Berserk ','%','a_b','"dragon ball"','Love','solo','abcde'] loop
 execute format('select coalesce(jsonb_agg(to_jsonb(s)),''[]''::jsonb) from cold_test.old_search_%I_page($1,30)s',med) into old using q;
 execute format('select coalesce(jsonb_agg(to_jsonb(s)),''[]''::jsonb) from public.search_%I_page($1,30)s',med) into new using q;
 assert old=new,'Search ranking changed: '||med||coalesce(q,'<null>');
 insert into cold_test.assertions values('search parity '||med||coalesce(q,'<null>'),true);
end loop;
foreach flag in array array['p_trending','p_new_season','p_classics','p_hidden_gems'] loop
 execute format('select coalesce(jsonb_agg(to_jsonb(s)),''[]''::jsonb) from cold_test.old_search_%I_page(p_query=>'''',%I=>true)s',med,flag) into old;
 execute format('select coalesce(jsonb_agg(to_jsonb(s)),''[]''::jsonb) from public.search_%I_page(p_query=>'''',%I=>true)s',med,flag) into new;
 assert old=new,'Search flag changed';insert into cold_test.assertions values('search flag '||med||flag,true);
end loop;
q:=case when med='anime' then 'Naruto' else 'Berserk' end;
execute format('select jsonb_agg(to_jsonb(s)) from cold_test.old_search_%I_page($1,10)s',med) into old using q;c:=old->-1;assert c is not null;
execute format('select coalesce(jsonb_agg(to_jsonb(s)),''[]''::jsonb) from cold_test.old_search_%I_page($1,10,$2,$3,$4)s',med) into old using q,(c->>'rank')::float8,(c->>'popularity')::int,(c->>'id')::int;
execute format('select coalesce(jsonb_agg(to_jsonb(s)),''[]''::jsonb) from public.search_%I_page($1,10,$2,$3,$4)s',med) into new using q,(c->>'rank')::float8,(c->>'popularity')::int,(c->>'id')::int;
assert old=new and jsonb_array_length(old)>0;insert into cold_test.assertions values('search cursor '||med,true);
end loop;end$$;
-- Match the real floating comparison, including the float4 representation below .35 double.
select set_config('pg_trgm.similarity_threshold','0.35',false);
do $$declare bad int;begin
select count(*) into bad from generate_series(1,80)a cross join generate_series(1,80)b
where (similarity(left(md5(a::text),a%20+1)||' naruto',left(md5(b::text),b%20+1)||' naruto')>=0.35) is distinct from
((left(md5(a::text),a%20+1)||' naruto') operator(extensions.%) (left(md5(b::text),b%20+1)||' naruto'));
assert bad=0,'Fuzzy prefilter must exactly match score boundary';
assert not ('0.35'::real >= 0.35), 'Float boundary must not round acceptance upward';
insert into cold_test.assertions values('6400 fuzzy pairs and .35 float4 boundary',true);
end$$;
-- Added indexes must survive real concurrent MV refresh and keep ordered rows unchanged.
refresh materialized view concurrently mv_anime_trending;
refresh materialized view concurrently mv_manga_trending;
refresh materialized view concurrently mv_anime_top_rated;
refresh materialized view concurrently mv_manga_top_rated;
refresh materialized view concurrently media_realm_membership;
do $$declare c record;j jsonb;begin
for c in select * from cold_test.cases order by (name not like '%-30'),name loop
execute 'select coalesce(jsonb_agg(to_jsonb(s)),''[]''::jsonb) from ('||c.query||')s' into j;
assert j=c.before_rows,'Refresh changed deterministic case '||c.name;insert into cold_test.assertions values('post-refresh parity '||c.name,true);
end loop;
assert (select count(*)=5 and bool_and(i.indisvalid and i.indisready) from pg_index i join pg_class pc on pc.oid=i.indexrelid where pc.relname like '%_cold_v1');
insert into cold_test.assertions values('five new indexes valid/ready after concurrent refresh',true);
end$$;
select count(*) as passed_assertions from cold_test.assertions;
select name,before_plan->0->'Plan'->>'Shared Hit Blocks' as before_hit,before_plan->0->'Plan'->>'Shared Read Blocks' as before_read,after_plan->0->'Plan'->>'Shared Hit Blocks' as after_hit,after_plan->0->'Plan'->>'Shared Read Blocks' as after_read from cold_test.cases where name like '%-30' or name='realm-cozy' order by name;
select c.relname,pg_relation_size(c.oid) as bytes from pg_class c where c.relname like '%_cold_v1' order by relname;
