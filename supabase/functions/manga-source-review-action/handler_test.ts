// Controlled handler: an import-secret caller can approve a pending review; a caller
// without that secret is rejected. Enrichment is the injected fetch and writes nothing.
import { assertEquals } from "jsr:@std/assert@1";
import { handleReviewAction, type ReviewDeps } from "./handler.ts";

const SECRET = "test-secret";
const MANGADEX_ID = "a1b2c3d4e5f67890a1b2c3d4e5f67890";

type Op = { op: "read" | "update" | "upsert"; table: string; body?: Record<string, unknown> };

function reviewClient() {
  const ops: Op[] = [];
  const row = {
    id: 9,
    provider: "mangadex",
    manga_id: 42,
    query_title: "Blue Box",
    candidate_payload: { sample: [{ id: "cccccccccccccccccccccccccccccccc" }, { id: "dddddddddddddddddddddddddddddddd" }] },
    reason: "ambiguous_title_strict",
    status: "pending",
  };
  function from(table: string) {
    return {
      select() {
        return this;
      },
      eq() {
        return this;
      },
      maybeSingle() {
        ops.push({ op: "read", table });
        return Promise.resolve({ data: table === "manga_source_link_review" ? row : null, error: null });
      },
      update(body: Record<string, unknown>) {
        return {
          eq() {
            ops.push({ op: "update", table, body });
            return Promise.resolve({ error: null });
          },
        };
      },
      upsert(body: Record<string, unknown>) {
        ops.push({ op: "upsert", table, body });
        return Promise.resolve({ error: null });
      },
    };
  }
  return { client: { from }, ops };
}

Deno.test("admin approve is accepted, an unauthorized caller is rejected, and enrichment does not write", async () => {
  const created: string[] = [];
  const fetched: Array<{ url: string; body: string }> = [];
  const { client, ops } = reviewClient();
  const deps: ReviewDeps = {
    env: (name) => ({
      IMPORT_SECRET: SECRET,
      SUPABASE_URL: "https://project.supabase.co",
      SUPABASE_SERVICE_ROLE_KEY: "service-key",
      SUPABASE_ANON_KEY: "anon-key",
    })[name],
    createClient: (url, key) => {
      created.push(`${url}:${key}`);
      return client;
    },
    fetch: (url, init) => {
      fetched.push({ url, body: String(init?.body ?? "") });
      return Promise.resolve(new Response(JSON.stringify({ success: true, results: { chapters_upserted: 0 } }), { status: 200 }));
    },
  };

  const rejected = await handleReviewAction(
    new Request("http://local/manga-source-review-action", {
      method: "POST",
      headers: { "content-type": "application/json", "x-import-secret": "not-the-secret" },
      body: JSON.stringify({ reviewId: 9, action: "approve", mangaDexId: MANGADEX_ID }),
    }),
    deps,
  );
  assertEquals(rejected.status, 401);
  assertEquals(await rejected.json(), { error: "Unauthorized" });
  assertEquals(created, []);
  assertEquals(fetched, []);
  assertEquals(ops, []);

  const accepted = await handleReviewAction(
    new Request("http://local/manga-source-review-action", {
      method: "POST",
      headers: { "content-type": "application/json", "x-import-secret": SECRET },
      body: JSON.stringify({ reviewId: 9, action: "approve", mangaDexId: MANGADEX_ID, triggerEnrich: true }),
    }),
    deps,
  );
  const body = await accepted.json();
  assertEquals(accepted.status, 200);
  assertEquals(body.success, true);
  assertEquals(body.action, "approve");
  assertEquals(body.reviewId, 9);
  assertEquals(body.mangaId, 42);
  assertEquals(body.mangaDexId, MANGADEX_ID);
  assertEquals(body.enrich.ok, true);
  assertEquals(created, ["https://project.supabase.co:service-key"]);
  assertEquals(fetched.length, 1);
  assertEquals(fetched[0].url, "https://project.supabase.co/functions/v1/manga-chapter-enrich");
  const enrichBody = JSON.parse(fetched[0].body);
  assertEquals(enrichBody.forceMangaId, 42);
  assertEquals(enrichBody.limit, 1);

  const tables = ops.map((op) => op.table);
  assertEquals(tables.includes("chapters"), false);
  assertEquals(tables.includes("manga"), false);
  assertEquals(ops.filter((op) => op.op === "upsert").map((op) => op.table), ["manga_source_links"]);
  assertEquals(ops.find((op) => op.op === "upsert")?.body?.provider_media_id, MANGADEX_ID);
  assertEquals(ops.find((op) => op.op === "upsert")?.body?.mapping_method, "review_approved");
  assertEquals(ops.find((op) => op.op === "update")?.body, { status: "approved" });
});
