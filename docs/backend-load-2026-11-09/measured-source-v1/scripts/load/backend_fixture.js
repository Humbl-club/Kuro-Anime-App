'use strict';
// Creates/removes only accounts recorded by this run. Never imports customer accounts.
const fs=require('node:fs'),path=require('node:path');const {randomUUID}=require('node:crypto');const {setTimeout:sleep}=require('node:timers/promises');
const {ORIGIN}=require('./backend_workload');
async function manage(mode,file,{anonKey,serviceKey,accounts=100,fetcher=fetch}={}){
 if(!['setup','cleanup'].includes(mode)||!anonKey||!serviceKey||!Number.isInteger(accounts)||accounts<1||accounts>100)throw new Error('Bounded fixture mode, credentials and account count required');
 fs.mkdirSync(path.dirname(file),{recursive:true,mode:0o700});
 let f=fs.existsSync(file)?JSON.parse(fs.readFileSync(file,'utf8')):{origin:ORIGIN,runId:'kuro-load-'+new Date().toISOString().replace(/[^0-9TZ]/g,'')+'-'+randomUUID().slice(0,8),anonKey,accounts:[],clubs:[],media:{}};
 if(f.origin!==ORIGIN||!f.runId?.startsWith('kuro-load-')||f.accounts.length>100||f.accounts.some(a=>!a.email.startsWith(f.runId+'-')))throw new Error('Invalid disposable inventory');
 const save=()=>fs.writeFileSync(file,JSON.stringify(f,null,2)+'\n',{mode:0o600});save();let lastStart=0;
 const call=async(p,body,{token=serviceKey,method='POST',prefer,allowNotFound=false}={})=>{
  const wait=250-(Date.now()-lastStart);if(wait>0)await sleep(wait);lastStart=Date.now();
  const res=await fetcher(ORIGIN+p,{method,headers:{apikey:anonKey,Authorization:'Bearer '+token,'Content-Type':'application/json',...(prefer?{Prefer:prefer}:{})},...(body===undefined?{}:{body:JSON.stringify(body)}),signal:AbortSignal.timeout(15000)});
  const txt=await res.text();let data=null;try{data=txt?JSON.parse(txt):null;}catch{}
  if(res.status===404&&allowNotFound)return null;
  if(!res.ok)throw new Error('Fixture '+p.split('?')[0]+' HTTP '+res.status+' '+(data?.code||data?.error_code||''));return data;
 };
 if(mode==='setup'){
  for(const medium of ['anime','manga'])if((f.media[medium]?.length||0)<2000){
   const rows=[];for(let offset=0;offset<2000;offset+=1000){rows.push(...await call('/rest/v1/'+medium+'?select=id&is_adult=eq.false&order=popularity.desc.nullslast,id.desc&limit=1000&offset='+offset,undefined,{method:'GET'}));}
   f.media[medium]=[...new Set(rows.map(x=>x.id))];if(f.media[medium].length<1400)throw new Error('Catalogue paging did not return enough distinct seed titles');save();
  }
  for(let i=0;i<accounts;i++){
   let a=f.accounts[i];if(a?.deleted)throw new Error('A cleaned fixture cannot be reused');if(a?.seeded)continue;
   if(a?.id){const u=await call('/auth/v1/admin/users/'+a.id,undefined,{method:'GET'});if(u.email?.toLowerCase()!==a.email.toLowerCase()||u.app_metadata?.kuro_load_fixture!==f.runId)throw new Error('Fixture ownership mismatch');}
   if(!a){a={email:f.runId+'-'+i+'@example.invalid',librarySize:i%20<4?0:i%20<14?25:i%20<19?100:2000,password:'Load-'+randomUUID()+'-aA9!'};f.accounts.push(a);save();}
   if(!a.id){const u=await call('/auth/v1/admin/users',{email:a.email,password:a.password,email_confirm:true,app_metadata:{kuro_load_fixture:f.runId}});a.id=u.id;save();}
   if(!a.token){const t=await call('/auth/v1/token?grant_type=password',{email:a.email,password:a.password},{token:anonKey});a.token=t.access_token;delete a.password;save();}
   await call('/rest/v1/profiles?on_conflict=id',[{id:a.id,display_name:'Load fixture '+i}],{prefer:'resolution=ignore-duplicates,return=minimal'});
   for(const medium of ['anime','manga']){
    const size=medium==='anime'?Math.ceil(a.librarySize*.7):Math.floor(a.librarySize*.3);
    if(f.media[medium].length<size)throw new Error('Catalogue row cap would truncate fixture');
    const rows=f.media[medium].slice(0,size).map((id,j)=>({user_id:a.id,[medium+'_id']:id,list_type:j%4===0?(medium==='anime'?'WATCHING':'READING'):j%4===1?'PLANNING':'COMPLETED',progress:j%4<2?0:5,rating:j%4===2?8:null,notes:'Disposable '+f.runId}));
    for(let j=0;j<rows.length;j+=250)await call('/rest/v1/'+medium+'_user_lists?on_conflict=user_id,'+medium+'_id',rows.slice(j,j+250),{prefer:'resolution=ignore-duplicates,return=minimal'});
   }
   if(a.librarySize){const [e]=await call('/rest/v1/anime_user_lists?user_id=eq.'+a.id+'&select=anime_id,lifecycle_id,server_revision,progress&order=anime_id&limit=1',undefined,{method:'GET'});a.writeEntry={mediaId:e.anime_id,lifecycleId:e.lifecycle_id,revision:e.server_revision,position:e.progress};}
   a.seeded=true;save();if(i%10===9)console.log('Provisioned '+(i+1)+' disposable accounts');
  }
  if(accounts===100){
   for(let group=0;group<5;group++){
    const owner=f.accounts[group*10];if(!f.clubs[group]){const result=await call('/rest/v1/rpc/create_club',{p_name:f.runId+' club '+group,p_description:'Disposable capacity fixture',p_sharing_level:'progress'},{token:owner.token});const c=result.club||result;f.clubs[group]={id:c.id||c.club_id,inviteCode:c.invite_code};if(!f.clubs[group].id||!f.clubs[group].inviteCode)throw new Error('Club identity not returned');owner.clubId=f.clubs[group].id;save();}
    for(let j=1;j<10;j++){const a=f.accounts[group*10+j];if(a.clubId)continue;await call('/rest/v1/rpc/join_club',{p_invite_code:f.clubs[group].inviteCode},{token:a.token});a.clubId=f.clubs[group].id;save();}
   }
  }
  return {runId:f.runId,accounts:f.accounts.length,seeded:f.accounts.filter(x=>x.seeded).length,libraryRows:f.accounts.reduce((n,a)=>n+a.librarySize,0),clubs:f.clubs.length};
 }
 const cleanup=[];
 // Members first, then owners: exact fixture inventory only. No broad users listing.
 for(const a of [...f.accounts].reverse()){
  if(a.deleted||!a.id)continue;
  const u=await call('/auth/v1/admin/users/'+a.id,undefined,{method:'GET',allowNotFound:true});
  if(!u){a.deleted=true;delete a.token;save();cleanup.push({accountIndex:f.accounts.indexOf(a),route:'already-absent',authAbsent:true});continue;}
  if(u.id!==a.id||u.email?.toLowerCase()!==a.email.toLowerCase()||u.app_metadata?.kuro_load_fixture!==f.runId)throw new Error('Cleanup provenance mismatch; refusing deletion');
  if(a.token){const who=await call('/auth/v1/user',undefined,{method:'GET',token:a.token});if(who.id!==a.id)throw new Error('Cleanup token identity mismatch');}
  let route='delete-account';try{await call('/functions/v1/delete-account',{confirm:'true'},{token:a.token});}catch{route='admin-exact-id';await call('/auth/v1/admin/users/'+a.id,undefined,{method:'DELETE'});}
  const res=await fetcher(ORIGIN+'/auth/v1/admin/users/'+a.id,{headers:{apikey:anonKey,Authorization:'Bearer '+serviceKey},signal:AbortSignal.timeout(15000)});
  if(res.status!==404)throw new Error('Exact fixture account cleanup not confirmed');a.deleted=true;delete a.token;save();cleanup.push({accountIndex:f.accounts.indexOf(a),route,authAbsent:true});
 }
 return {runId:f.runId,accountsRemoved:f.accounts.filter(x=>x.deleted).length,cleanup};
}
if(require.main===module){const [mode,file]=process.argv.slice(2);manage(mode,file,{anonKey:process.env.SUPABASE_ANON_KEY,serviceKey:process.env.SUPABASE_SERVICE_ROLE_KEY,accounts:Number(process.env.KURO_LOAD_ACCOUNTS||100)}).then(r=>console.log(JSON.stringify(r))).catch(e=>{console.error(e.message);process.exitCode=1;});}
module.exports={manage};
