import sys,re,json,time,datetime,pathlib
sys.path.insert(0,'/tmp');import kuro_prod_remediation_20261109 as m
import time as _gate_time
from pathlib import Path as _GatePath
_gate_root=_GatePath('/Users/max/.codex/release-runs/kuro-load-20261109-r6')
while not (_gate_root/'LOAD_STARTED').exists():
 if (_gate_root/'DONE').exists():raise SystemExit(0)
 _gate_time.sleep(.1)

out=m.ROOT/'docs/backend-cold-2026-11-09/resources-capacity-sequence-cold1.json';d={'samples':[],'observer_errors':[],'cadence_seconds':60,'provider_cache_note':'Approximately minute-cached metrics; samples are not independent high-frequency observations.'};done=pathlib.Path('/Users/max/.codex/release-runs/kuro-load-20261109-r6/DONE');start=time.monotonic()
while True:
 try:
  raw=m.request('/analytics/endpoints/metrics',raw=True).decode();values={}
  for line in raw.splitlines():
   if not line or line[0]=='#':continue
   key=line.split('{',1)[0].split(' ',1)[0]
   if key.startswith(('node_cpu_seconds_total','node_memory_','node_vmstat_pswp','node_load','node_disk_io_time_seconds_total')):
    label,value=line.rsplit(' ',1);values[label]=float(value)
  d['samples'].append({'checked_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'metrics':values})
 except Exception as e:d['observer_errors'].append({'observed_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'error':str(e)[:180]})
 m.write(out,d)
 if time.monotonic()-start>900 or done.exists():break
 time.sleep(60)
print('Host capture done, errors',len(d['observer_errors']))
