"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const { EventEmitter } = require("node:events");
const { PassThrough } = require("node:stream");
const { makeCurlFetch } = require("./backend_curl_fetch");
const { ORIGIN } = require("./backend_workload");
function fakeSpawn(reply, code = 0) {
  let observed;
  const spawn = (binary, args) => {
    const child = new EventEmitter();
    child.stdin = new PassThrough();
    child.stdout = new PassThrough();
    child.stderr = new PassThrough();
    child.kill = () => {
      observed.killed = true;
    };
    observed = { binary, args, input: "", child };
    child.stdin.on("data", (x) => {
      observed.input += x;
    });
    child.stdin.on("finish", () => {
      if (reply !== null) {
        setImmediate(() => {
          child.stdout.end(reply);
          child.emit("close", code);
        });
      }
    });
    return child;
  };
  return { spawn, observed: () => observed };
}
test("curl keeps credentials in stdin and only exposes numeric upstream/version headers", async () => {
  const f = fakeSpawn(
    'HTTP/2 200\r\nx-envoy-upstream-service-time: 4\r\nset-cookie: private-value\r\n\r\n{"active":[]}',
  );
  const r = await makeCurlFetch(f)(ORIGIN + "/rest/v1/rpc/home_bundle_v1", {
    method: "POST",
    headers: { Authorization: "Bearer test-credential" },
    body: '{"p_medium":"anime"}',
  });
  assert.equal(r.status, 200);
  assert.deepEqual(await r.json(), { active: [] });
  assert.equal(r.headers.get("x-envoy-upstream-service-time"), "4");
  assert.equal(r.headers.get("x-kuro-load-http-version"), "2");
  assert.equal(r.headers.get("set-cookie"), null);
  assert.ok(!JSON.stringify(f.observed().args).includes("test-credential"));
  assert.ok(f.observed().input.includes("Bearer test-credential"));
  assert.ok(
    !f.observed().args.includes("--location") &&
      !f.observed().args.includes("--insecure"),
  );
});
test("curl refuses any other origin before spawning", async () => {
  const f = fakeSpawn("");
  await assert.rejects(
    makeCurlFetch(f)("https://example.invalid/"),
    /origin refused/,
  );
  assert.equal(f.observed(), undefined);
});
test("curl cancellation terminates the child without retrying", async () => {
  const f = fakeSpawn(null);
  const controller = new AbortController();
  const result = makeCurlFetch(f)(ORIGIN + "/rest/v1/rpc/home_bundle_v1", {
    signal: controller.signal,
  });
  controller.abort();
  await assert.rejects(result, (e) => e.name === "TimeoutError");
  assert.equal(f.observed().killed, true);
});
