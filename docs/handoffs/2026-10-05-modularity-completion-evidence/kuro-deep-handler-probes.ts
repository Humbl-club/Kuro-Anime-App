import {handleApply} from "file:///Users/max/Kuro-Anime-App/supabase/functions/concierge-apply/handler.ts";
import {handleUndo} from "file:///Users/max/Kuro-Anime-App/supabase/functions/concierge-undo/handler.ts";
import {FakeSupabase,conciergeSchema} from "file:///Users/max/Kuro-Anime-App/supabase/functions/_shared/test_fake_supabase.ts";
const u="11111111-1111-4111-8111-111111111111";
const req=(body:unknown)=>new Request("https://fixture.invalid",{method:"POST",headers:{Authorization:"Bearer fixture","Content-Type":"application/json"},body:JSON.stringify(body)});
async function call(fn:typeof handleApply|typeof handleUndo,body:unknown,db:FakeSupabase){const r=await fn(req(body),{client:()=>db});return {status:r.status,body:await r.json()};}
for(const fault of ["import_session_items:insert","import_sessions:update"]){
 const db=new FakeSupabase(conciergeSchema(),u);db.faults.set(fault,"injected returned database error");
 const apply=await call(handleApply,{items:[{mediaType:"ANIME",mediaId:7,status:"PLANNING",action:"add"}]},db);
 db.faults.clear();const undo=await call(handleUndo,{sessionId:apply.body.sessionId},db);
 console.log(JSON.stringify({probe:fault,apply,undo,remainingRows:db.rows("anime_user_lists"),sessions:db.rows("import_sessions")}));
}
{
 const db=new FakeSupabase(conciergeSchema(),u);db.seed("anime_user_lists",[{user_id:u,anime_id:7,list_type:"WATCHING",progress:3}]);
 const apply=await call(handleApply,{items:[{mediaType:"ANIME",mediaId:7,status:"WATCHING",action:"update",progressEpisodes:5,expectedExisting:{status:"WATCHING",progress_episodes:1}},{mediaType:"MANGA",mediaId:9,status:"READING",action:"add"}]},db);
 const undo=await call(handleUndo,{sessionId:apply.body.sessionId},db);
 console.log(JSON.stringify({probe:"partial-import",apply,undo,remainingManga:db.rows("manga_user_lists"),sessions:db.rows("import_sessions")}));
}
{
 const db=new FakeSupabase(conciergeSchema(),u);const apply=await call(handleApply,{items:[{mediaType:"ANIME",mediaId:7,status:"PLANNING",action:"add"}]},db);
 db.faults.set("anime_user_lists:delete","transient delete failure");const first=await call(handleUndo,{sessionId:apply.body.sessionId},db);
 db.faults.clear();const retry=await call(handleUndo,{sessionId:apply.body.sessionId},db);
 console.log(JSON.stringify({probe:"partial-undo-retry",first,retry,remainingRows:db.rows("anime_user_lists"),sessions:db.rows("import_sessions")}));
}
for(const id of [0,-4,null]){
 const db=new FakeSupabase(conciergeSchema(),u);const apply=await call(handleApply,{items:[{mediaType:"ANIME",mediaId:id,status:"PLANNING",action:"add"}]},db);
 console.log(JSON.stringify({probe:"invalid-identifier",input:id,apply,remainingRows:db.rows("anime_user_lists")}));
}
