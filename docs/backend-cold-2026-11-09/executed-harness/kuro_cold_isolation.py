import sys,json,pathlib,urllib.request,urllib.error,time,datetime
sys.path.insert(0,'/tmp');import kuro_prod_remediation_20261109 as m
import time as _gate_time
from pathlib import Path as _GatePath
_gate_root=_GatePath('/Users/max/.codex/release-runs/kuro-load-20261109-r6')
while not (_gate_root/'LOAD_STARTED').exists():
 if (_gate_root/'DONE').exists():raise SystemExit(0)
 _gate_time.sleep(.1)

while (datetime.datetime.now(datetime.timezone.utc)-datetime.datetime.fromisoformat((_gate_root/'LOAD_STARTED').read_text())).total_seconds()<120:
 if (_gate_root/'DONE').exists():raise SystemExit(0)
 _gate_time.sleep(.5)
f=json.loads(pathlib.Path('/Users/max/.codex/release-runs/kuro-load-20261109-r6/fixture.json').read_text());owner=f['accounts'][99];outsider=f['accounts'][0];checks=[]
def call(path,actor,body=None):
 req=urllib.request.Request(f['origin']+path,method='POST' if body is not None else 'GET',data=None if body is None else json.dumps(body).encode(),headers={'apikey':f['anonKey'],'Authorization':'Bearer '+actor['token'],'Content-Type':'application/json'})
 t=time.monotonic()
 try:
  with urllib.request.urlopen(req,timeout=10) as r:code=r.status;data=json.loads(r.read())
 except urllib.error.HTTPError as e:code=e.code;data=json.loads(e.read())
 return code,data,round((time.monotonic()-t)*1000,2)
p='/rest/v1/anime_user_lists?user_id=eq.'+owner['id']+'&select=anime_id&limit=1'
code,data,ms=call(p,owner);checks.append({'name':'owner can read own seeded library','passed':code==200 and len(data)==1,'http_status':code,'latency_ms':ms})
code,data,ms=call(p,outsider);checks.append({'name':'outsider cannot read another library during load','passed':code==200 and data==[],'http_status':code,'latency_ms':ms})
club=f['clubs'][0]['id']
code,data,ms=call('/rest/v1/rpc/fetch_club_bundle_loading',owner,{'p_club_id':club});checks.append({'name':'nonmember club bundle refused during load','passed':code in (400,403) and data.get('code')=='P0001' and 'NOT_A_MEMBER' in data.get('message',''),'http_status':code,'latency_ms':ms})
code,data,ms=call('/rest/v1/rpc/fetch_club_bundle_loading',outsider,{'p_club_id':club});checks.append({'name':'actual club owner still receives bundle','passed':code==200 and data.get('club',{}).get('id')==club,'http_status':code,'latency_ms':ms})
g=m.sql("select p.oid::regprocedure::text as name,has_function_privilege('anon',p.oid,'execute') as anon,has_function_privilege('authenticated',p.oid,'execute') as authenticated,has_function_privilege('service_role',p.oid,'execute') as server from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and proname in ('upsert_rec_edges','rate_limit_hit','llm_global_budget_reserve','llm_global_budget_finalize','check_email_exists')")
checks.append({'name':'five existing privileged RPC revokes preserved','passed':len(g)==5 and all(not x['anon'] and not x['authenticated'] and x['server'] for x in g)})
r={'checked_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'checks':checks,'effective_grants':g,'passed':all(x['passed'] for x in checks)}
m.write(m.ROOT/'docs/backend-cold-2026-11-09/isolation-under-load-cold1.json',r);print(json.dumps(checks));assert r['passed']
