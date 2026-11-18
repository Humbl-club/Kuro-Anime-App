import sys,json,pathlib,datetime,hashlib
sys.path.insert(0,'/tmp');import kuro_prod_remediation_20261109 as m
p=m.ROOT/'docs/backend-cold-2026-11-09';private=pathlib.Path('/Users/max/.codex/release-runs/kuro-cold-20261109/approved-run')
cols="p.oid::regprocedure::text as signature,p.proname,p.prosrc,p.proconfig,p.proacl::text as acl,p.prosecdef,p.prorettype::text"
rows=m.sql('select '+cols+" from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('search_anime_page','search_manga_page','discover_bundle','discover_mood_v1','_discover_page_v1','catalogue_search_blob_v1') order by proname")
before=json.loads((private/'reader-before.json').read_text());assert len(rows)==len(before)==6
for a,b in zip(rows,before):
 for k in ['signature','proname','prosrc','acl','prosecdef','prorettype']:assert a[k]==b[k],(a['proname'],k)
 if a['proname'] not in ['search_anime_page','search_manga_page']:assert a['proconfig']==b['proconfig']
m.write(p/'final-reader-parity.json',{'checked_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'six_bodies_signatures_returns_acl_security_unchanged':True,'readers':[{'signature':x['signature'],'body_sha256':hashlib.sha256(x['prosrc'].encode()).hexdigest(),'proconfig':x['proconfig']} for x in rows]})
cases=[]
for table,metric in [('mv_anime_trending','trending'),('mv_manga_trending','trending'),('mv_anime_top_rated','average_score'),('mv_manga_top_rated','average_score')]:
 query=f"select id,title_english,title_romaji,title_native,genres,is_adult,{metric} from public.{table} where coalesce(is_adult,false)=false and not('Hentai'=any(coalesce(genres,'{{}}'::text[]))) and not('Ecchi'=any(coalesce(genres,'{{}}'::text[])))"
 if 'anime' in table:query+=" and coalesce(format,'') not in ('SPECIAL','MUSIC','TV_SHORT')"
 if metric=='average_score':query+=' and coalesce(average_score,0)>=80'
 query+=f' order by coalesce({metric},0) desc,id desc limit30';query=query.replace('limit30','limit 30');cases.append((table,query))
cases.append(('realm-cozy',"select media_id,sum(weight)::real as w from public.media_realm_membership where media_type='ANIME' and realm=any(array['slice-of-life-iyashikei','food-craft','family-generations']) and weight>=0.25::real group by media_id order by media_id"))
def walk(x):
 yield x
 for child in x.get('Plans',[]):yield from walk(child)
results=[]
for name,query in cases:
 result=m.sql("begin read only;set local statement_timeout='8s';explain(analyze,buffers,format json) "+query+';commit;',False)[0]['QUERY PLAN'][0]
 indexes=sorted(set(x['Index Name'] for x in walk(result['Plan']) if 'Index Name' in x));nodes=[{k:x[k] for k in ['Node Type','Relation Name','Index Name','Shared Hit Blocks','Shared Read Blocks','Heap Fetches','Actual Rows'] if k in x} for x in walk(result['Plan'])]
 results.append({'name':name,'query':query,'execution_ms':result['Execution Time'],'planning_ms':result['Planning Time'],'indexes':indexes,'root_shared_hit_blocks':result['Plan'].get('Shared Hit Blocks'),'root_shared_read_blocks':result['Plan'].get('Shared Read Blocks'),'nodes':nodes,'plan':result})
 m.write(p/'post-deployment-inner-plans.json',{'checked_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'purpose':'Bounded read-only production inner-query diagnostics after cold attempt/cleanup; no forced plans, no cold/HTTP/capacity claim. No data mutations.','results':results})
print(json.dumps([{'name':x['name'],'indexes':x['indexes'],'execution_ms':x['execution_ms'],'blocks':x['root_shared_hit_blocks']+x['root_shared_read_blocks']} for x in results]))
