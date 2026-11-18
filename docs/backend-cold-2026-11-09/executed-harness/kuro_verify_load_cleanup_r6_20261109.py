import sys,pathlib,json,datetime
sys.path.insert(0,'/tmp');import kuro_prod_remediation_20261109 as m
f=json.loads(pathlib.Path('/Users/max/.codex/release-runs/kuro-load-20261109-r6/fixture.json').read_text());assert len(f['accounts'])==100 and all(a.get('deleted') for a in f['accounts'])
ids=','.join("'"+a['id']+"'" for a in f['accounts']);clubs=','.join("'"+c['id']+"'" for c in f['clubs'])
cols=m.sql("select c.table_name,c.column_name,c.data_type from information_schema.columns c join information_schema.tables t using(table_schema,table_name) where c.table_schema='public' and t.table_type='BASE TABLE' and (c.column_name in ('user_id','created_by') or c.table_name='profiles' and c.column_name='id') and c.data_type in ('text','uuid') order by c.table_name,c.column_name")
# All identifiers are drawn from the catalog and strictly quoted, never client input.
def qi(x):return '"'+x.replace('"','""')+'"'
parts=[]
for c in cols:
 table=c['table_name'];column=c['column_name'];parts.append("select '"+table+'.'+column+"' as relation,count(*) as remaining from public."+qi(table)+' where '+qi(column)+' in ('+ids+')')
r=m.sql('begin read only;'+ ' union all '.join(parts)+';commit;',False)
auth=m.sql('select count(*) as remaining from auth.users where id in ('+ids+')')[0]['remaining']
clubrows=m.sql('select count(*) as remaining from public.clubs where id in ('+clubs+')')[0]['remaining']
retained=[x for x in r if x['relation']=='account_deletion_barriers.user_id']
unexpected=[x for x in r if x['remaining'] and x['relation']!='account_deletion_barriers.user_id']
result={'checked_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'accounts_removed':100,'auth_rows_remaining':auth,'exact_fixture_clubs_remaining':clubrows,'application_tables_checked':len(r),'application_rows':r,'intentionally_retained_security_guards':retained,'retention_reason':'Existing deletion barriers outlive Auth for stale-token protection and are purged by existing seven-day policy; do not remove them as test litter.','unexpected_remaining':unexpected,'passed':not unexpected and auth==0 and clubrows==0}
m.write(m.ROOT/'docs/backend-cold-2026-11-09/cleanup-verification-r6.json',result)
print(json.dumps({k:v for k,v in result.items() if k!='application_rows'}));assert result['passed']
