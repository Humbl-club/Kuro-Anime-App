"use strict";
// Alternative generator transport. JWTs go through stdin, never argv/files/logs.
const { spawn: nativeSpawn } = require("node:child_process");
const { ORIGIN } = require("./backend_workload");
function makeCurlFetch({ spawn = nativeSpawn } = {}) {
  return async function curlFetch(url, init = {}) {
    const target = new URL(url);
    if (target.origin !== ORIGIN || target.username || target.password) {
      throw new Error("Curl transport origin refused");
    }
    if (init.signal?.aborted) {
      throw new DOMException("Deadline", "TimeoutError");
    }
    return await new Promise((resolve, reject) => {
      const args = [
        "--disable",
        "--http2",
        "--silent",
        "--show-error",
        "--max-time",
        "8",
        "--dump-header",
        "-",
        "--url",
        target.href,
        "--config",
        "-",
      ];
      const child = spawn("/usr/bin/curl", args, {
        stdio: ["pipe", "pipe", "pipe"],
      });
      const chunks = [];
      let bytes = 0, settled = false;
      const finish = (error, result) => {
        if (settled) return;
        settled = true;
        init.signal?.removeEventListener("abort", abort);
        error ? reject(error) : resolve(result);
      };
      const abort = () => {
        child.kill("SIGTERM");
        finish(new DOMException("Deadline", "TimeoutError"));
      };
      init.signal?.addEventListener("abort", abort, { once: true });
      child.stdout.on("data", (part) => {
        bytes += part.length;
        if (bytes > 4 * 1024 * 1024) {
          child.kill("SIGTERM");
          finish(new Error("Curl response size limit"));
        } else chunks.push(part);
      });
      // Drain but never log stderr: arbitrary diagnostic text is not evidence metadata.
      child.stderr.resume();
      child.on("error", () => finish(new Error("Curl process unavailable")));
      child.on("close", (code) => {
        if (settled) return;
        if (code !== 0) {
          finish(
            code === 28
              ? new DOMException("Deadline", "TimeoutError")
              : new Error("Curl transport failed"),
          );
          return;
        }
        try {
          let raw = Buffer.concat(chunks).toString("utf8"), header;
          // Handle an interim HTTP 100 response without interpreting body as headers.
          do {
            const split = raw.indexOf("\r\n\r\n");
            if (split < 0) throw new Error("Missing HTTP headers");
            header = raw.slice(0, split);
            raw = raw.slice(split + 4);
          } while (/^HTTP\/\S+ 1\d\d\b/.test(header));
          const status = /^HTTP\/(1\.0|1\.1|2|3) (\d{3})\b/.exec(header);
          if (!status) throw new Error("Invalid HTTP status");
          const upstream =
            /^x-envoy-upstream-service-time:\s*(\d+(?:\.\d+)?)\s*$/im.exec(
              header,
            );
          const headers = { "x-kuro-load-http-version": status[1] };
          if (upstream) headers["x-envoy-upstream-service-time"] = upstream[1];
          finish(
            null,
            new Response(raw, { status: Number(status[2]), headers }),
          );
        } catch {
          finish(new Error("Curl response parse failed"));
        }
      });
      const lines = ["request = " + JSON.stringify(init.method || "GET")];
      for (const [name, value] of Object.entries(init.headers || {})) {
        lines.push("header = " + JSON.stringify(name + ": " + value));
      }
      if (init.body !== undefined) {
        lines.push("data-binary = " + JSON.stringify(String(init.body)));
      }
      child.stdin.on("error", () => finish(new Error("Curl input failed")));
      child.stdin.end(lines.join("\n") + "\n");
    });
  };
}
module.exports = { makeCurlFetch };
