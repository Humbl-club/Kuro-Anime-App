import { handleApply } from "file:///Users/max/Kuro-Anime-App/supabase/functions/concierge-apply/handler.ts";
import { handleUndo } from "file:///Users/max/Kuro-Anime-App/supabase/functions/concierge-undo/handler.ts";
import { conciergeSchema, FakeSupabase } from "file:///Users/max/Kuro-Anime-App/supabase/functions/_shared/test_fake_supabase.ts";
const user = "11111111-1111-4111-8111-111111111111";
function request(body: unknown) { return new Request("https://example.test", {method:"POST", headers:{Authorization:"Bearer jwt", "Content-Type":"application/json"},body:JSON.stringify(body)}); }
for (const scenario of ["later-rating", "conflicted-item", "deleted-after-import"]) {
  const db = new FakeSupabase(conciergeSchema(), user);
  db.seed("anime_user_lists", [{user_id:user,anime_id:7,list_type:"WATCHING",progress:3,rating:8,notes:"original",verdict:null}]);
  const items = scenario === "conflicted-item" ? [
    {mediaType:"ANIME",mediaId:7,status:"WATCHING",action:"update",progressEpisodes:5,expectedExisting:{status:"WATCHING",progress_episodes:1}},
    {mediaType:"MANGA",mediaId:9,status:"READING",action:"add"}
  ] : [{mediaType:"ANIME",mediaId:7,status:"WATCHING",action:"update",progressEpisodes:5,rating:9,expectedExisting:{status:"WATCHING",progress_episodes:3}}];
  const applied = await (await handleApply(request({items}), {client:()=>db})).json();
  if (scenario === "later-rating") db.tables.get("anime_user_lists")![0].rating = 10;
  if (scenario === "conflicted-item") db.tables.get("anime_user_lists")![0].progress = 6;
  if (scenario === "deleted-after-import") db.tables.set("anime_user_lists", []);
  const beforeUndo = structuredClone(db.rows("anime_user_lists"));
  const result = await (await handleUndo(request({sessionId:applied.sessionId}), {client:()=>db})).json();
  console.log(JSON.stringify({scenario,conflicts:applied.conflicts,beforeUndo,afterUndo:db.rows("anime_user_lists"),result}));
}
