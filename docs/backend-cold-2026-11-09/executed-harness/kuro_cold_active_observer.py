import sys,json,time,datetime,pathlib,hashlib,re
sys.path.insert(0,'/tmp');import kuro_prod_remediation_20261109 as m
import time as _gate_time
from pathlib import Path as _GatePath
_gate_root=_GatePath('/Users/max/.codex/release-runs/kuro-load-20261109-r6')
while not (_gate_root/'LOAD_STARTED').exists():
 if (_gate_root/'DONE').exists():raise SystemExit(0)
 _gate_time.sleep(.1)

name=sys.argv[1];duration=int(sys.argv[2]);private=pathlib.Path('/Users/max/.codex/release-runs/kuro-load-20261109-r6');start=time.monotonic();samples=[];saved=[]
while True:
 q="select pid,leader_pid,backend_type,application_name,state,wait_event_type,wait_event,extract(epoch from(now()-query_start))::float8 as age_seconds,query,pg_blocking_pids(pid) as blockers from pg_stat_activity where datname=current_database() and state='active' and pid<>pg_backend_pid()"
 rows=m.sql(q);interesting=any(x['age_seconds']>1.5 for x in rows)
 if interesting:
  stamp=datetime.datetime.now(datetime.timezone.utc).isoformat();m.write(m.PRIVATE/(name+'-active-'+str(len(saved))+'.json'),{'at':stamp,'active':rows},True);public=[]
  for x in rows:
   raw=x.pop('query');x['query_sha256']=hashlib.sha256(raw.encode()).hexdigest();x['function_references']=sorted(set(re.findall(r'public[.\"]+([a-z_][a-z_0-9]*)',raw)));public.append(x)
  saved.append({'at':stamp,'active':public});m.write(m.ROOT/('docs/backend-cold-2026-11-09/active-'+name+'.json'),saved)
 if time.monotonic()-start>=duration or (private/'DONE').exists():break
 time.sleep(2)
print('Active captures',name,len(saved),flush=True)
