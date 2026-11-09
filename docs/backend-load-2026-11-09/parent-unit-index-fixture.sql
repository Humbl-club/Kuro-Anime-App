-- Disposable local PostgreSQL only. Never execute this fixture in a hosted project.
\set ON_ERROR_STOP on
set jit=off;
create table public.episodes(id integer primary key,anime_id integer,number integer,title text);
create table public.chapters(id integer primary key,manga_id integer,number integer,title text);
alter table public.episodes enable row level security;
alter table public.chapters enable row level security;
create policy fixture_deny on public.episodes using(false);
create policy fixture_deny on public.chapters using(false);
insert into public.episodes select i,i%1000,case when i%7=0 then null else i/1000 end,repeat(md5(i::text),16) from generate_series(1,52000)i;
insert into public.chapters select i,i%1000,case when i%7=0 then null else i/1000 end,repeat(md5(i::text),16) from generate_series(1,10000)i;
create unique index idx_episodes_anime_id_number_unique on public.episodes(anime_id,number) where number is not null;
create unique index idx_chapters_manga_id_number_unique on public.chapters(manga_id,number) where number is not null;
analyze public.episodes;
analyze public.chapters;
create temporary table lookup_baseline(name text,rows jsonb,plan jsonb);
do $$declare t text;p text;j jsonb;r jsonb;begin
 for t,p in values('episodes','anime_id'),('chapters','manga_id') loop
  execute format('select jsonb_agg(to_jsonb(x) order by id) from(select id,number,title from public.%I where %I=19)x',t,p) into r;
  execute format('explain(analyze,buffers,format json) select id,number,title from public.%I where %I=19',t,p) into j;
  assert j::text like '%Seq Scan%', 'Baseline must reproduce missing parent-index scan';
  insert into lookup_baseline values(t,r,j);
 end loop;
end$$;
