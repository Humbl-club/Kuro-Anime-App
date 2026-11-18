import sys,pathlib,json,time,datetime
sys.path.insert(0,'/tmp');import kuro_prod_remediation_20261109 as m
import time as _gate_time
from pathlib import Path as _GatePath
_gate_root=_GatePath('/Users/max/.codex/release-runs/kuro-load-20261109-r6')
while not (_gate_root/'LOAD_STARTED').exists():
 if (_gate_root/'DONE').exists():raise SystemExit(0)
 _gate_time.sleep(.1)
_gate_time.sleep(10)

p=m.ROOT/'docs/backend-cold-2026-11-09';private=pathlib.Path('/Users/max/.codex/release-runs/kuro-load-20261109-r6');fixture=json.loads((private/'fixture.json').read_text());ids=','.join("'"+a['id']+"'" for a in fixture['accounts']);start=datetime.datetime.now(datetime.timezone.utc).isoformat();rows=[]
while True:
 cron=m.sql("select runid,status,start_time,end_time,round(extract(epoch from(end_time-start_time))::numeric,4) as duration_seconds from cron.job_run_details where jobid=37 and start_time>='"+start+"'::timestamptz order by start_time")
 q=m.sql("select count(*) filter(where processed_at is null) as pending,count(*) filter(where processed_at is not null) as processed,count(*) filter(where last_error is not null) as errors from public.taste_profile_recompute_queue where user_id in ("+ids+")")
 batches=m.sql("select updated_at as computed_at,count(*) as profiles from public.user_taste_profiles where user_id in ("+ids+") and updated_at>='"+start+"'::timestamptz group by updated_at order by updated_at")
 row={'checked_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'queue':q[0],'profile_computation_batches':batches};rows.append(row)
 m.write(p/'worker-under-load-cold1.json',{'observed_from':start,'cron_runs':cron,'observations':rows})
 if (private/'DONE').exists():break
 time.sleep(20)
print('Worker observer done; cron executions',len(cron),flush=True)
