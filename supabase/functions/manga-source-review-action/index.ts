// manga-source-review-action (slug unchanged). Thin entry: env, one service-role
// client, and fetch. The admin request flow is handleReviewAction.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { handleReviewAction } from "./handler.ts";

serve((req) =>
  handleReviewAction(req, {
    env: (name) => Deno.env.get(name),
    createClient: (url, key) => createClient(url, key, { auth: { persistSession: false } }),
    fetch: (input, init) => fetch(input, init),
  })
);
