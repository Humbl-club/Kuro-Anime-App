// Offline tests for the catalogue source HTTP client and the polite client text mode (Task 2).
// Run: cd supabase/functions/_shared && deno test --no-prompt catalogue/
import { strict as assert } from "node:assert";
import { PoliteLimiter } from "../polite_fetch.ts";
import { CATALOGUE_USER_AGENT } from "./field_groups.ts";
import { createSourceClient } from "./source_http.ts";
import { createPoliteClient } from "../polite_fetch.ts";

function recorder(body: string, contentType = "application/json") {
  const seen: { url: string; headers: Record<string, string> }[] = [];
  const fetch = (input: string | URL | Request, init?: RequestInit) => {
    seen.push({ url: String(input), headers: { ...(init?.headers as Record<string, string>) } });
    return Promise.resolve(new Response(body, { status: 200, headers: { "content-type": contentType } }));
  };
  return { seen, fetch: fetch as typeof globalThis.fetch };
}

const fast = { sleep: () => Promise.resolve(), now: () => 0, random: () => 0 };

Deno.test("userAgentOnEveryRequest", async () => {
  assert.equal(CATALOGUE_USER_AGENT, "Kuro-Catalogue/1.0 (+https://kuro-legal.vercel.app/kontakt.html)");
  for (const source of ["wikidata", "ann", "mangaupdates", "pageviews"] as const) {
    const r = recorder(source === "ann" ? "<ann/>" : "{}");
    const client = createSourceClient(source, new PoliteLimiter(0), { ...fast, fetch: r.fetch });
    await client.request("https://example.test/a", {});
    await client.request("https://example.test/b", { method: "POST", body: { q: 1 } });
    assert.equal(r.seen.length, 2, source);
    for (const call of r.seen) assert.equal(call.headers["User-Agent"], CATALOGUE_USER_AGENT, source);
  }
});

Deno.test("textModeReturnsBody", async () => {
  const xml = "<?xml version=\"1.0\"?><ann><anime id=\"1\"/></ann>";
  const r = recorder(xml, "text/xml");
  const client = createSourceClient("ann", new PoliteLimiter(0), { ...fast, fetch: r.fetch });
  const res = await client.request("https://example.test/api.xml", {});
  assert.equal(res.status, 200);
  assert.equal(res.text, xml);
  assert.equal(res.json, null);
});

Deno.test("sources other than ann answer in json", async () => {
  const r = recorder("{\"a\":1}");
  const client = createSourceClient("wikidata", new PoliteLimiter(0), { ...fast, fetch: r.fetch });
  const res = await client.request("https://example.test/sparql", {});
  assert.deepEqual(res.json, { a: 1 });
  assert.equal(res.text, undefined);
});

Deno.test("jsonModeUnchangedForExistingCallers", async () => {
  const r = recorder("{\"a\":1}");
  const client = createPoliteClient({ limiter: new PoliteLimiter(0), ...fast, fetch: r.fetch });
  const res = await client.request("https://example.test/x", {});
  // Exactly the previous shape: no text key, the legacy intake User-Agent, JSON accept header.
  assert.deepEqual(res, { status: 200, json: { a: 1 } });
  assert.ok(!("text" in res));
  assert.equal(r.seen[0].headers["User-Agent"], "Kuro-Intake/1.0 (+https://kuro.app)");
  assert.equal(r.seen[0].headers["Accept"], "application/json");
});

Deno.test("text mode does not parse non-json bodies and keeps an empty body as empty text", async () => {
  const r = recorder("");
  const client = createPoliteClient({ limiter: new PoliteLimiter(0), ...fast, fetch: r.fetch, responseType: "text" });
  const res = await client.request("https://example.test/x", {});
  assert.equal(res.text, "");
  assert.equal(res.json, null);
});
