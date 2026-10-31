import {handleApply} from "file:///Users/max/Kuro-Anime-App/supabase/functions/concierge-apply/handler.ts";
import {FakeSupabase,conciergeSchema} from "file:///Users/max/Kuro-Anime-App/supabase/functions/_shared/test_fake_supabase.ts";
const u="11111111-1111-4111-8111-111111111111";
const db=new FakeSupabase(conciergeSchema(),u);
const rpc=db.rpc.bind(db);
db.rpc=(fn,args)=>fn==="check_concierge_rate_limit"?Promise.resolve({data:null,error:{message:"rate-limit database unavailable"}}):rpc(fn,args);
const req=new Request("https://fixture.invalid",{method:"POST",headers:{Authorization:"Bearer fixture","Content-Type":"application/json"},body:JSON.stringify({items:[{mediaType:"ANIME",mediaId:7,status:"PLANNING",action:"add"}]})});
const res=await handleApply(req,{client:()=>db});console.log(JSON.stringify({status:res.status,body:await res.json(),rows:db.rows("anime_user_lists")}));
