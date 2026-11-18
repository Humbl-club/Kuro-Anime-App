import sys,json,pathlib,time,datetime
sys.path.insert(0,'/tmp');import kuro_prod_remediation_20261109 as m
p=m.ROOT/'docs/backend-cold-2026-11-09';private=pathlib.Path('/Users/max/.codex/release-runs/kuro-load-20261109-r6');deadline=time.monotonic()+900
while not (private/'LOAD_STARTED').exists():
 if (private/'DONE').exists():raise SystemExit(0)
 if time.monotonic()>deadline:raise RuntimeError('Onset did not start')
 time.sleep(.2)
start_at=datetime.datetime.fromisoformat((private/'LOAD_STARTED').read_text())
while (datetime.datetime.now(datetime.timezone.utc)-start_at).total_seconds()<90:
 if (private/'DONE').exists():raise SystemExit(0)
 time.sleep(.5)
f=json.loads((private/'fixture.json').read_text());actors=[a for size in [2000,100,25] for a in f['accounts'] if a['librarySize']==size][:50];assert len(actors)==50
ids=','.join("'"+a['id']+"'" for a in actors)
check=m.sql("select count(*) as n from auth.users where id in ("+ids+") and raw_app_meta_data->>'kuro_load_fixture'='"+f['runId']+"'");assert check[0]['n']==50
values=','.join("('"+a['id']+"'::uuid,now()+interval '1microsecond'*"+str(i)+",null,null)" for i,a in enumerate(actors))
m.sql('insert into public.taste_profile_recompute_queue(user_id,requested_at,processed_at,last_error) values'+values+' on conflict(user_id) do update set requested_at=excluded.requested_at,processed_at=null,last_error=null;',False)
queued_at=datetime.datetime.now(datetime.timezone.utc).isoformat()
r=m.sql('explain(analyze,buffers,format json) select public.drain_taste_recompute_queue();',False)[0]['QUERY PLAN'][0]
m.write(p/'worker-controlled-backlog-cold1.json',{'queued_at':queued_at,'fixture_accounts_requeued':50,'large_libraries_included':5,'fixture_only_queue_changes':True,'manual_worker_execution_ms':r['Execution Time'],'plan':r,'natural_cron_left_active':True})
print('Controlled50-account backlog queued during20rps; worker execution ms',r['Execution Time'],flush=True)
