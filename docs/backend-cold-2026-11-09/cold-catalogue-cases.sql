\set ON_ERROR_STOP on
set search_path=public,extensions;
set jit=off;
create table cold_test.cases(name text primary key,query text,before_rows jsonb,before_plan jsonb,after_plan jsonb);
do $$declare t text;metric text;lim int;q text;begin
for t,metric in values('mv_anime_trending','trending'),('mv_manga_trending','trending'),('mv_anime_top_rated','average_score'),('mv_manga_top_rated','average_score') loop
foreach lim in array array[30,1,60] loop
q:=format('select id,title_english,title_romaji,title_native,genres,is_adult,%I from public.%I where coalesce(is_adult,false)=false and not(''Hentai''=any(coalesce(genres,''{}''::text[]))) and not(''Ecchi''=any(coalesce(genres,''{}''::text[]))) %s %s order by coalesce(%I,0) desc,id desc limit %s',metric,t,
case when t like '%anime%' then 'and coalesce(format,'''') not in (''SPECIAL'',''MUSIC'',''TV_SHORT'')' else '' end,
case when metric='average_score' then 'and coalesce(average_score,0)>=80' else '' end,metric,lim);
insert into cold_test.cases(name,query) values(t||'-'||lim,q);
end loop;end loop;
insert into cold_test.cases(name,query) values('realm-cozy','select media_id,sum(weight)::real as w from public.media_realm_membership where media_type=''ANIME'' and realm=any(array[''realm-1'',''realm-3'']) and weight>=0.25::real group by media_id order by media_id');
end$$;
do $$declare c record;j jsonb;p jsonb;begin
for c in select * from cold_test.cases order by (name not like '%-30'),name loop
execute 'explain(analyze,buffers,format json) '||c.query into p;
execute 'select coalesce(jsonb_agg(to_jsonb(s)),''[]''::jsonb) from ('||c.query||')s' into j;
update cold_test.cases set before_rows=j,before_plan=p where name=c.name;
end loop;end$$;
