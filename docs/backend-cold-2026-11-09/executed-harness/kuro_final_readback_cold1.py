import sys,pathlib,json,datetime,hashlib,re
sys.path.insert(0,'/tmp');import kuro_prod_remediation_20261109 as m
p=m.ROOT/'docs/backend-cold-2026-11-09';clean=json.loads((p/'cleanup-verification-r6.json').read_text());assert clean['passed']
assert pathlib.Path('/Users/max/.codex/release-runs/kuro-load-20261109-r6/DONE').exists()
r={'checked_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'project':m.request('')['status'],'auth':m.auth_summary(m.request('/config/auth')),'fixture_cleanup_verified':True,'load_running':False}
previous=json.loads((p/'approved-preflight.json').read_text());assert r['auth']==previous['auth'];r['selected_auth_unchanged_since_pre_deployment']=True
r['edge_bundles']=[]
for slug in ['concierge-parse','concierge-recommend']:
 bundle=m.request('/functions/'+slug+'/body',raw=True);expected=(pathlib.Path('/Users/max/.codex/release-runs/kuro-cold-20261109/approved-run')/(slug+'-after.eszip')).read_bytes();assert hashlib.sha256(bundle).hexdigest()==hashlib.sha256(expected).hexdigest();r['edge_bundles'].append({'slug':slug,'sha256':hashlib.sha256(bundle).hexdigest(),'matches_downloaded_source_verified_deployment':True})
r['functions']=[{k:x.get(k) for k in ['slug','version','status','verify_jwt']} for x in m.request('/functions') if x['slug'] in m.SLUGS]
assert next(x for x in r['functions'] if x['slug']=='concierge-recommend')['version']==56
assert all(x['verify_jwt'] for x in r['functions'])
assert {x['slug']:(x['version'],x['verify_jwt']) for x in r['functions'] if x['slug'] not in ['concierge-recommend','concierge-parse']}=={x['slug']:(x['version'],x['verify_jwt']) for x in previous['functions'] if x['slug'] not in ['concierge-recommend','concierge-parse']}
assert next(x for x in r['functions'] if x['slug']=='concierge-parse')['version']==50
r['other_selected_functions_unchanged_since_pre_deployment']=True
pool=m.request('/postgrest');r['api_configuration']={k:pool.get(k) for k in ['db_pool','max_rows','db_schema','db_extra_search_path','db_pool_acquisition_timeout','db_pool_max_lifetime','db_pool_max_idletime']};assert pool['db_pool']==3
r['migration_history']=m.sql("select version,name,md5(statements[1]) as md5 from supabase_migrations.schema_migrations where version in ('20261108120159','20261108120211','20261109001251','20261109003243','20261109100800','20261109123758') order by version")
assert len(r['migration_history'])==6
for x in r['migration_history']:
 f=next((m.ROOT/'supabase/migrations').glob(x['version']+'*.sql'));assert hashlib.md5(f.read_bytes()).hexdigest()==x['md5']
q="select proname,prosrc,proconfig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and proname in ('recompute_user_taste_profile','drain_taste_recompute_queue')"
defs=m.sql(q);old=json.loads((m.PRIVATE/'taste-worker-definitions-before.json').read_text());math=next(x for x in defs if x['proname']=='recompute_user_taste_profile');assert math['prosrc']==re.search(r'AS (\$[A-Za-z_0-9]*\$)([\s\S]*?)\1',next(x['definition'] for x in old if x['proname']==math['proname']),re.I).group(2);source=(m.ROOT/'supabase/migrations/20261109003243_taste_worker_latency_v1.sql').read_text();assert next(x['prosrc'] for x in defs if x['proname']=='drain_taste_recompute_queue')==re.search(r'AS \$function\$([\s\S]*?)\$function\$;',source).group(1)
r['worker_math_and_source_verified']=True
r['worker_grants']=m.sql("select p.oid::regprocedure::text as name,has_function_privilege('anon',p.oid,'execute') as anon,has_function_privilege('authenticated',p.oid,'execute') as authenticated,has_function_privilege('service_role',p.oid,'execute') as server from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and proname in ('recompute_user_taste_profile','drain_taste_recompute_queue')");assert len(r['worker_grants'])==2 and all(not x['anon'] and not x['authenticated'] and x['server'] for x in r['worker_grants'])
r['job']=m.sql("select jobid,jobname,schedule,active,username from cron.job where jobid=37");assert r['job'][0]['schedule']=='* * * * *'
r['health']=m.sql("select count(*) filter(where wait_event_type='Lock') as lock_waiters,count(*) filter(where state='active' and pid<>pg_backend_pid() and query_start<now()-interval '30 seconds') as long_queries from pg_stat_activity where datname=current_database()")
assert r['health'][0]['lock_waiters']==0 and r['health'][0]['long_queries']==0
r['jit']=m.sql("select current_setting('jit') as jit")[0]['jit'];assert r['jit']=='off'
r['security_advisors']=m.advisor_summary(m.request('/advisors/security'));r['performance_advisors']=m.advisor_summary(m.request('/advisors/performance'));assert not r['security_advisors']['errors'] and not r['performance_advisors']['errors']
r['search_settings']=m.sql("select proname,proconfig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and proname in ('search_anime_page','search_manga_page')");assert len(r['search_settings'])==2 and all('pg_trgm.similarity_threshold=0.35' in x['proconfig'] for x in r['search_settings'])
r['temporary_inspector_absent']=m.sql("select not exists(select 1 from pg_extension where extname='pg_buffercache') as extension_absent,not exists(select 1 from pg_namespace where nspname='kuro_cold_inspection') as schema_absent")[0];assert all(r['temporary_inspector_absent'].values())
r['postmaster_started_at']=m.sql('select pg_postmaster_start_time() as started')[0]['started']
r['cold_capacity_qualified']=False;r['cold_load_offered_starts']=0
m.write(p/'final-live-state-cold1.json',r);print('Production source/history, pool3, worker grants/job, auth and health verified; no advisor ERRORs')
