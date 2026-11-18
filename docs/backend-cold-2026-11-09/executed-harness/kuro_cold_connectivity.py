import sys,json,pathlib,time,datetime,urllib.request,concurrent.futures
sys.path.insert(0,'/tmp');import kuro_prod_remediation_20261109 as m
import time as _gate_time
from pathlib import Path as _GatePath
_gate_root=_GatePath('/Users/max/.codex/release-runs/kuro-load-20261109-r6')
while not (_gate_root/'LOAD_STARTED').exists():
 if (_gate_root/'DONE').exists():raise SystemExit(0)
 _gate_time.sleep(.1)

p=m.ROOT/'docs/backend-cold-2026-11-09';f=json.loads(pathlib.Path('/Users/max/.codex/release-runs/kuro-load-20261109-r6/fixture.json').read_text());rows=[];start=time.monotonic()
def call(origin,path,headers):
 t=time.monotonic()
 try:
  with urllib.request.urlopen(urllib.request.Request(origin+path,headers=headers),timeout=8) as r:status=r.status;r.read(2048)
  return {'ms':round((time.monotonic()-t)*1000,2),'status':status}
 except Exception as e:return {'ms':round((time.monotonic()-t)*1000,2),'error_type':type(e).__name__}
with concurrent.futures.ThreadPoolExecutor(2) as pool:
 while time.monotonic()-start<900:
  at=datetime.datetime.now(datetime.timezone.utc).isoformat();a=pool.submit(call,f['origin'],'/auth/v1/health',{'apikey':f['anonKey']});b=pool.submit(call,'https://api.supabase.com','/v1/projects/'+m.PROJECT,{'Authorization':'Bearer '+m.token()})
  rows.append({'at':at,'auth_health':a.result(),'management_project':b.result()});m.write(p/'connectivity-control-cold1.json',{'samples':rows,'scope':'Independent HTTPS control requests; no library/database workload, no automatic traffic retries. R7 controls alongside unchanged load; inspect numeric upstream timing to distinguish API/network delay.'})
  
  if pathlib.Path('/Users/max/.codex/release-runs/kuro-load-20261109-r6/DONE').exists():break
  time.sleep(10)
print('Control probes complete',flush=True)
