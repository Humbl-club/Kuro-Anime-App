import sys,pathlib,json,datetime,hashlib,re,os,time,subprocess,base64
sys.path.insert(0,'/tmp');import kuro_prod_remediation_20261109 as m
ROOT=m.ROOT;P=ROOT/'docs/backend-cold-2026-11-09';PRIVATE=pathlib.Path('/Users/max/.codex/release-runs/kuro-load-20261109-r6');manifest=json.loads((P/'deployment-manifest.json').read_text())
def utc():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def dt(s):return datetime.datetime.fromisoformat(s.replace('Z','+00:00'))
def write(n,r):m.write(P/n,r)
def hashes():
 for x in manifest['workload_source_files']+manifest['files'][1:3]:assert hashlib.sha256((ROOT/x['path']).read_bytes()).hexdigest()==x['sha256'],x['path']
 source=ROOT/manifest['deployed_migration'];assert hashlib.sha256(source.read_bytes()).hexdigest()==manifest['deployed_migration_sha256']
 for x in json.loads((P/'inspector-private-schema-adaptation.json').read_text())['files']:assert hashlib.sha256((ROOT/x['path']).read_bytes()).hexdigest()==x['sha256']
def onset_gate(report):
 script="const fs=require('node:fs');const C=require("+json.dumps(str(ROOT/'scripts/load/backend_cold_gate.js'))+");const f=JSON.parse(fs.readFileSync(process.argv[1]));const r=JSON.parse(fs.readFileSync(process.argv[2]));fs.writeFileSync(process.argv[3],JSON.stringify(C.evaluateColdStage(r,f.accounts),null,2));"
 r=subprocess.run(['node','-e',script,str(PRIVATE/'fixture.json'),str(report),str(P/'cold1-onset-gates.json')],cwd=ROOT,capture_output=True,text=True);assert r.returncode==0,'Cold acceptance evaluator failed';return json.loads((P/'cold1-onset-gates.json').read_text())
def intervening_cron(state,onset):
 query="select r.runid,r.jobid,j.jobname,r.status,r.start_time,r.end_time from cron.job_run_details r left join cron.job j using(jobid) where r.start_time<'"+onset+"'::timestamptz and (r.end_time>='"+state['checked_at']+"'::timestamptz or (r.end_time is null and r.status not in ('succeeded','failed'))) order by r.start_time"
 rows=m.sql(query)
 receipt={'checked_at':utc(),'interval_start':state['checked_at'],'interval_end_exclusive':onset,'overlapping_executions':rows,'pass':len(rows)==0,'conservative_policy':'Any overlapping cron execution disqualifies onset; includes executions begun before interval and still active.'}
 write('cron-between-cache-and-onset.json',receipt)
 return receipt['pass']
assert not (PRIVATE/'RESTART_REQUESTED.json').exists() and not (PRIVATE/'DONE').exists() and not (PRIVATE/'STOP').exists()
assert (PRIVATE/'DB_OBSERVER_READY').exists(),'Primary DB safety observer must be armed before restart'
hashes();assert json.loads((P/'fixture-final-shape-r6.json').read_text())['total_rows']==13750
fixtures=json.loads((PRIVATE/'fixture.json').read_text());assert len(fixtures['accounts'])==100 and all(a.get('seeded') for a in fixtures['accounts'])
assert set(a['librarySize'] for a in fixtures['accounts'] if a.get('clubId'))=={0,25,100,2000}
expires=[json.loads(base64.urlsafe_b64decode(a['token'].split('.')[1]+'==='))['exp'] for a in fixtures['accounts']];assert min(expires)>time.time()+1200
edge=json.loads((P/'edge-redeployment-receipt.json').read_text());assert edge['complete'] and edge['other_functions_and_auth_unchanged']
live=m.request('/functions');assert all(next(x['version'] for x in live if x['slug']==f['slug'])==f['after_version'] for f in edge['functions'])
route=subprocess.run(['route','-n','get','default'],capture_output=True,text=True).stdout;assert re.findall(r'interface:\s*(\S+)',route)==['en0']
before=m.sql('select pg_postmaster_start_time() as started')[0]['started'];assert m.request('/postgrest')['db_pool']==3
inspector=json.loads((P/'inspector-install-receipt.json').read_text());assert inspector['created_by_this_approved_experiment'] and inspector['actual_client_namespace_denials']==4 and inspector['not_in_data_api_or_extra_search_path']
controller={'started_at':utc(),'restart_requests':1,'profiles':[],'complete':False,'cold_state_verified':False,'load_started':False,'no_catalogue_pre_warm_calls':True,'prior_postmaster_start':before};write('cold1-sequence.json',controller)
marker={'requested_at':utc(),'one_request_only':True,'prior_postmaster_start':before}
with (PRIVATE/'RESTART_REQUESTED.json').open('x') as f:json.dump(marker,f)
restart={'requested_at':marker['requested_at'],'request_count':1,'polls':[],'ready':False};write('restart-receipt.json',restart)
try:
 print('Sending ONE approved restart request',flush=True)
 try:
  response=m.request('/restart','POST');restart['acknowledged_at']=utc();restart['acknowledgement']=response
 except Exception as e:
  restart['ack_error_type']=type(e).__name__;restart['ack_error_http']=re.findall(r'Management HTTP (\d+)',str(e));print('Restart acknowledgement unavailable; reconcile by new postmaster, do NOT resend',flush=True)
 write('restart-receipt.json',restart);deadline=time.monotonic()+300;state=None;last_notice=0
 while time.monotonic()<deadline:
  row={'checked_at':utc()}
  try:
   health=m.request('/health?services=auth,rest&timeout_ms=1000');row['health']=[{k:x.get(k) for k in ['name','healthy','status']} for x in health]
   if len(health)==2 and all(x['healthy'] for x in health):
    candidate=m.sql((P/'READ-CACHE-STATE-PRIVATE.sql').read_text(),False)[0]['cold_state'];row['postmaster_started_at']=candidate['postmaster_started_at'];row['public_cached_blocks']=candidate['public_cached_blocks']
    if dt(candidate['postmaster_started_at'])>dt(before):
     state=candidate;restart['ready']=True;restart['first_ready_observed_at']=utc();restart['new_postmaster_started_at']=candidate['postmaster_started_at'];restart['maintenance_elapsed_seconds']=(dt(restart['first_ready_observed_at'])-dt(marker['requested_at'])).total_seconds();restart['polls'].append(row);break
  except Exception as e:row['error_type']=type(e).__name__;row['http']=re.findall(r'Management HTTP (\d+)',str(e))
  restart['polls'].append(row);write('restart-receipt.json',restart)
  if time.monotonic()-last_notice>20:print('Waiting for restarted Auth/REST readiness; no application probes',flush=True);last_notice=time.monotonic()
  time.sleep(2)
 write('restart-receipt.json',restart)
 if state is None:
  controller['failure']='Restart readiness/new postmaster not established; no further restart';raise RuntimeError(controller['failure'])
 write('cold-state-at-readiness.json',state)
 if state['public_cached_blocks']!=0:
  controller['failure']='NOT COLD: public/TOAST data already resident at first verified readiness';controller['cached_blocks_at_first_ready']=state['public_cached_blocks'];raise RuntimeError(controller['failure'])
 controller['cold_state_verified']=True
 # No network or application-data operation between this zero-buffer observation and launch.
 profiles=[('cold1-onset-20rps',20,600),('cold1-spike-40rps',40,60),('cold1-recovery-20rps',20,90)]
 for name,rps,duration in profiles:
  if (PRIVATE/'STOP').exists():raise RuntimeError('Safety STOP exists')
  hashes()
  output=P/(name+'.json');cmd=['node',str(ROOT/'scripts/load_test_backend.js'),'--production','--transport=node','--fixture='+str(PRIVATE/'fixture.json'),'--output='+str(output),'--rps='+str(rps),'--duration='+str(duration),'--vus=100','--stop-file='+str(PRIVATE/'STOP')]
  print('START '+name,flush=True);launched_at=utc();proc=subprocess.Popen(cmd,cwd=ROOT)
  if name=='cold1-onset-20rps':
   launch_gap=(dt(launched_at)-dt(state['checked_at'])).total_seconds();controller['launch_gap_seconds']=launch_gap;controller['load_started']=True;controller['approximate_load_started_at']=launched_at
   if not (0<=launch_gap<=5):proc.terminate();proc.wait();raise RuntimeError('Launch outside5-second cold observation budget')
   (PRIVATE/'LOAD_STARTED').write_text(launched_at)
  while proc.poll() is None:
   if name=='cold1-onset-20rps' or controller['load_started']:
    hb=PRIVATE/'DB_HEARTBEAT'
    age=time.time()-float(hb.read_text()) if hb.exists() else (dt(utc())-dt(controller['approximate_load_started_at'])).total_seconds()
    if age>25 and not (PRIVATE/'STOP').exists():(PRIVATE/'STOP').write_text('Successful DB safety heartbeat stale beyond25seconds')
   time.sleep(1)
  rc=proc.wait();data=json.loads(output.read_text()) if output.exists() else {};entry={'name':name,'exit_code':rc,'pass':data.get('summary',{}).get('pass',False),'started_at':data.get('startedAt'),'finished_at':data.get('finishedAt'),'output':output.name}
  if name=='cold1-onset-20rps':
   exact_gap=(dt(data['startedAt'])-dt(state['checked_at'])).total_seconds();entry['exact_onset_gap_seconds']=exact_gap;gate=onset_gate(output);entry['cold_extra_gates_passed']=gate['pass'];entry['no_intervening_cron']=intervening_cron(state,data['startedAt']);entry['pass']=entry['pass'] and gate['pass'] and 0<=exact_gap<=5 and entry['no_intervening_cron']
  controller['profiles'].append(entry);write('cold1-sequence.json',controller)
  if rc or not entry['pass'] or (PRIVATE/'STOP').exists():break
 controller['complete']=len(controller['profiles'])==3 and all(x['pass'] for x in controller['profiles'])
except Exception as e:
 controller['controller_error']=str(e)[:240];print('Cold sequence stopped:',controller['controller_error'],flush=True)
finally:
 controller['finished_at']=utc();write('cold1-sequence.json',controller);(PRIVATE/'DONE').write_text(controller['finished_at']);print('Cold sequence ended; complete='+str(controller['complete']),flush=True)
sys.exit(0 if controller['complete'] else 1)
