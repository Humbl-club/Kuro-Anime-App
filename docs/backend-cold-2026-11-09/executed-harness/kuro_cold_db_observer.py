import sys,time,json,datetime,pathlib,hashlib,re,subprocess
sys.path.insert(0,'/tmp');import kuro_prod_remediation_20261109 as m
import time as _gate_time
from pathlib import Path as _GatePath
_gate_root=_GatePath('/Users/max/.codex/release-runs/kuro-load-20261109-r6')
# Bound DB monitoring independently of the shared helper's90second timeout.
import urllib.request
_monitor_token=m.token()
def bounded_sql(query):
 req=urllib.request.Request(m.BASE+'/database/query',data=json.dumps({'query':query,'read_only':True}).encode(),method='POST',headers={'Authorization':'Bearer '+_monitor_token,'Content-Type':'application/json'})
 with urllib.request.urlopen(req,timeout=6) as response:return json.loads(response.read())
(_gate_root/'DB_OBSERVER_READY').write_text(datetime.datetime.now(datetime.timezone.utc).isoformat())
while not (_gate_root/'LOAD_STARTED').exists():
 if (_gate_root/'DONE').exists():raise SystemExit(0)
 _gate_time.sleep(.1)

name=sys.argv[1];duration=int(sys.argv[2]);out=m.ROOT/'docs/backend-cold-2026-11-09'/('db-'+name+'.json');stop=pathlib.Path('/Users/max/.codex/release-runs/kuro-load-20261109-r6/STOP')
q="""select now() as checked_at, (select setting::int from pg_settings where name='max_connections') as max_connections,
 count(*) as connections,count(*) filter(where state='active' and pid<>pg_backend_pid()) as active,
 count(*) filter(where wait_event_type='Lock') as lock_waiters,
 coalesce(max(extract(epoch from(now()-query_start))) filter(where state='active' and pid<>pg_backend_pid()),0) as oldest_active_seconds,
 (select deadlocks from pg_stat_database where datname=current_database()) as deadlocks,
 (select temp_bytes from pg_stat_database where datname=current_database()) as temp_bytes,
 (select blks_read from pg_stat_database where datname=current_database()) as blks_read,
 (select blks_hit from pg_stat_database where datname=current_database()) as blks_hit
 from pg_stat_activity where datname=current_database()"""
rows=[];bad=0;errors=0;start=time.monotonic();done=pathlib.Path('/Users/max/.codex/release-runs/kuro-load-20261109-r6/DONE')
while True:
 try:
  row=bounded_sql(q)[0];rows.append(row)
  route=subprocess.run(['route','-n','get','default'],capture_output=True,text=True,timeout=3).stdout
  interface=re.findall(r'interface:\s*(\S+)',route)
  row['generator_interface']=interface[0] if interface else None
  if interface!=['en0']:stop.write_text('Wired default route changed');row['safety_stop']=True
  bad=bad+1 if row['active']>=35 or row['connections']>=52 or (row['lock_waiters']>5 and float(row['oldest_active_seconds'])>5) else 0
  if bad>=2:stop.write_text('Database connection/lock pressure');row['safety_stop']=True
  m.write(out,{'profile':name,'samples':rows,'stopped':stop.exists()})
  errors=0
  heartbeat=_gate_root/'DB_HEARTBEAT.tmp';heartbeat.write_text(str(time.time()));heartbeat.replace(_gate_root/'DB_HEARTBEAT')
 except Exception as e:
  errors+=1
  if errors>=2:stop.write_text('Database monitor unavailable')
  rows.append({'checked_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'monitor_error_type':type(e).__name__});m.write(out,{'profile':name,'samples':rows,'stopped':stop.exists()})
 if time.monotonic()-start>=duration or done.exists():break
 time.sleep(10)
print('Database monitor complete:',name,'samples',len(rows),flush=True)
