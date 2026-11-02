#!/usr/bin/env bash
# Exact current-query qualification on the audited migration fixture. No hosted writes.
# Global table rows default to 1M across accounts; the selected account has 5000 entries.
# This is PostgreSQL query evidence, NOT concurrent-client capacity or production proof.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
source "$here/guard_env.sh"
kuro_db_guard_env || exit 2
rows="${KURO_EXPLAIN_ROWS:-1000000}"
case "$rows" in *[!0-9]*|'') echo 'KURO_EXPLAIN_ROWS must be an integer'; exit 64;; esac
[ "$rows" -ge 5000 ] && [ "$rows" -le 10000000 ] || exit 64
out="${KURO_EXPLAIN_REPORT:-$repo/docs/handoffs/2026-10-07-home-series-evidence/repairs/db/explain-exact-1m.txt}"
mkdir -p "$(dirname "$out")"
tmp="$(mktemp -d /tmp/kuro-explain.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
python_bin="${KURO_PYTHON:-python3}"
"$python_bin" - "$repo" "$tmp/qualification.sql" "$rows" <<'PYCODE'
from pathlib import Path
import hashlib,re,sys
repo=Path(sys.argv[1]); target=Path(sys.argv[2]); rows=int(sys.argv[3])
source=repo/'supabase/prepared-migrations/20261007040000_series_home_foundation_v1.sql'
text=source.read_text()
def body(name):
    start=text.index('create or replace function public.'+name+'(')
    return text[start:text.index('\n$$;',start)]
home=body('home_bundle_v1'); start=home.index('    with resume_page as materialized ('); end=home.index('    select coalesce(jsonb_agg',start)
active=home[start:end]+'select * from page order by updated_at desc,media_id desc limit 12;'
collection=body('collection_series_page_v1'); start=collection.index('    with rows as (');end=collection.index('\n  else',start)
collection=collection[start:end].replace('    into v_rows','')
sub={'v_user':"'abcdef00-0000-4000-8000-000000000001'",'v_cursor_at':'null::timestamptz','v_cursor_id':'null::integer',
     'v_cursor_key':'null::text','v_query':"''",'p_status':'null::text','v_limit':'12'}
def resolved(sql):
    for key,value in sub.items(): sql=re.sub(r'\b'+key+r'\b',value,sql)
    return sql
users=(rows+4999)//5000
seed=fr"""\set ON_ERROR_STOP on
\i {repo}/supabase/tests/lib/00_test_helpers.sql
\echo EXACT_SCHEMA_FIXTURE_SOURCE_SHA256={hashlib.sha256(source.read_bytes()).hexdigest()}
\echo GLOBAL_ROWS={rows} SELECTED_ACCOUNT_ROWS=5000
set statement_timeout='180s';
select tests.make_user(n) from generate_series(1,{users}) n;
insert into public.anime(id,title_romaji,episodes,status,banner_image)
select 9700000+n,'Fixture '||n,24,'RELEASING','https://fixture.invalid/art/'||n from generate_series(1,100000) n;
insert into public.series(id,medium,title,continuity) select md5('series-'||n)::uuid,'anime','Approved '||n,'verified' from generate_series(1,2500)n;
insert into public.series_sections(id,series_id,kind,ordinal,name,sort_order,provenance) select md5('section-'||n)::uuid,md5('series-'||((n-1)/2+1))::uuid,'season',(n-1)%2+1,'Season '||((n-1)%2+1),(n-1)%2+1,'fixture' from generate_series(1,5000)n;
insert into public.series_entry_spans(series_id,section_id,medium,anime_id) select md5('series-'||((n-1)/2+1))::uuid,md5('section-'||n)::uuid,'anime',9700000+n from generate_series(1,5000)n;
insert into public.artwork_materials(image_digest,image_url,base_color,deep_color,wash_color,edge_color,ink_color,is_current,content_revision,extraction_version,contrast)
select md5('current-'||n),'https://fixture.invalid/art/'||n,'#34433E','#1E2925','#FFFEF8','#52605A','#FFFFFF',true,'fixture-v1','fixture-v1','fixture' from generate_series(1,5000) n;
insert into public.artwork_materials(image_digest,image_url,base_color,deep_color,wash_color,edge_color,ink_color,is_current,content_revision,extraction_version,contrast)
select md5('historic-'||n),'https://fixture.invalid/art/'||n,'#34433E','#1E2925','#FFFEF8','#52605A','#FFFFFF',false,'fixture-v0','fixture-v0','fixture' from generate_series(1,5000) n;
insert into public.anime_user_lists(user_id,anime_id,list_type,progress,updated_at)
select tests.uid(((n-1)/5000+1)::integer)::text,9700000+((n-1)%5000+1),case when n%5=0 then 'PLANNING' else 'WATCHING' end,3,
       timestamptz '2026-01-01'+((n%5000)||' seconds')::interval from generate_series(1,{rows}) n;
analyze public.anime; analyze public.anime_user_lists; analyze public.artwork_materials;
analyze public.series; analyze public.series_sections; analyze public.series_entry_spans;
\echo ACTUAL_INDEX_DEFINITIONS
select indexname,indexdef from pg_indexes where tablename in ('anime_user_lists','series_entry_spans','artwork_materials') order by indexname;
begin;
select tests.as_user(tests.uid(1));
\echo USER_ROLE_AND_SCOPE
select current_user,auth.uid();
\echo HOME_ACTUAL_ACTIVE_CTE
"""
# The catalogue IDs were fixture shifted; queries reference actual card rows, no stronger index.
queries='EXPLAIN (ANALYZE,BUFFERS,SETTINGS,FORMAT TEXT) '+resolved(active)
queries+='\n\echo DETAIL_PK_ROW\nEXPLAIN (ANALYZE,BUFFERS,SETTINGS,FORMAT TEXT) select l.server_revision,l.lifecycle_id,l.progress,l.progress_label,l.list_type,l.rating,l.notes,l.unit_id from public.anime_user_lists l where l.user_id=auth.uid()::text and l.anime_id=9700001;'
sub['v_limit']='30'
queries+='\n\echo COLLECTION_ACTUAL_GROUP_PAGE\nEXPLAIN (ANALYZE,BUFFERS,SETTINGS,FORMAT TEXT) '+resolved(collection)
queries+='\nrollback;\n'
target.write_text(seed+queries)
PYCODE
"$here/run_local_db_tests.sh" --no-tests --qualification-sql "$tmp/qualification.sql" --qualification-report "$out" --report-dir "$tmp/replay" >"$out.harness.log" 2>&1
printf 'Wrote exact-query qualification: %s\n' "$out"
