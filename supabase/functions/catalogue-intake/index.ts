// catalogue-intake: raw records and id crosswalk from sources that allow Kuro's use (Wikidata, ANN,
// MangaUpdates, Wikimedia pageviews). PREPARED, NOT DEPLOYED, NOT SCHEDULED. Deploy with
// --no-verify-jwt like the other IMPORT_SECRET functions (pg_cron cannot send JWTs).
// Orchestration: handler.ts. Source clients are created once per isolate so each limiter's spacing
// holds across requests.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { PoliteLimiter } from "../_shared/polite_fetch.ts";
import { createSourceClient } from "../_shared/catalogue/source_http.ts";
import { handleRequest } from "./handler.ts";

// Spacing per source (plan Global Constraints): WDQS >= 1 s, ANN >= 1.1 s (published limit 1/s),
// MangaUpdates >= 1.1 s, Wikimedia REST >= 100 ms.
const clients = {
  wikidata: createSourceClient("wikidata", new PoliteLimiter(1_000)),
  ann: createSourceClient("ann", new PoliteLimiter(1_100)),
  mangaupdates: createSourceClient("mangaupdates", new PoliteLimiter(1_100)),
  pageviews: createSourceClient("pageviews", new PoliteLimiter(100)),
};

serve((req) =>
  handleRequest(req, {
    secret: Deno.env.get("IMPORT_SECRET"),
    buildDeps: () => {
      const url = Deno.env.get("SUPABASE_URL");
      const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
      if (!url || !key) throw new Error("Server misconfigured");
      return { supabase: createClient(url, key), clients };
    },
  })
);
