// COMPILE-TIME ONLY (never imported or executed): asserts that the call shapes
// adapters.ts relies on still type-check against the REAL supabase-js package
// (`@2` floats, so this guards against upstream drift). Run with:
//   deno check supabase/functions/delete-account/real_client_shapes.ts   (needs esm.sh)
//
// Proven here: `c.storage` and `c.auth` are assignable to the adapter interfaces and the
// exact from()/delete().in()/rpc()/storage/auth calls compile with the fields adapters.ts reads.
// NOT proven: whole-object assignability of `from()`/`rpc()` (TS2589 "excessively deep"
// on the full client), or any runtime behavior against PostgREST/Storage/GoTrue.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import type { AdminClientLike, UserClientLike } from "./adapters.ts";

const c = createClient("http://localhost", "unused");

export const storage: AdminClientLike["storage"] = c.storage;
export const adminAuth: AdminClientLike["auth"] = c.auth;
export const userAuth: UserClientLike["auth"] = c.auth;

export async function shapes() {
  const barrier = await c.rpc("begin_account_deletion", { p_user_id: "x" });
  const clubs = await c.rpc("delete_account_club_memberships", { p_user_id: "x" });
  const textRows = await c.from("anime_user_lists").delete().in("user_id", ["x", "X"]);
  const deleted = await c.from("profiles").delete().eq("id", "x");
  const rpc = await c.rpc("delete_user_concierge_data", { p_user_id: "x" });
  const listed = await c.storage.from("media").list("p", { limit: 100, offset: 0 });
  const removed = await c.storage.from("media").remove(["p/a"]);
  const authDeleted = await c.auth.admin.deleteUser("x");
  const me = await c.auth.getUser();
  const results: { error: { message: string } | null }[] = [barrier, clubs, textRows, deleted, rpc, listed, removed, authDeleted];
  const barrierData: unknown = barrier.data;
  const names = listed.data as { name: string; id?: string | null }[] | null;
  const user: { id: string } | null | undefined = me.data?.user;
  return [results, barrierData, names, user];
}
