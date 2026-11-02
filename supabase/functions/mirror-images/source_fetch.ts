// Bounded source fetch for mirror-images (F66). One timeout covers headers, the
// body, and every redirect hop. Response-size cap, HTTPS host allowlist, and
// manual redirects. A redirect whose target is not on the allowlist fails
// closed and the body is not read.

/** AniList CDN host written by the catalog importers (`coverImage` / `bannerImage` / character / staff). */
export const APPROVED_SOURCE_HOSTS: ReadonlySet<string> = new Set(["s4.anilist.co"]);

export const DEFAULT_MAX_IMAGE_BYTES = 5 * 1024 * 1024;
export const DEFAULT_FETCH_TIMEOUT_MS = 10_000;
const MAX_REDIRECTS = 3;

export type FetchFailureReason =
  | "invalid_url"
  | "unapproved_host"
  | "redirect_unapproved"
  | "timeout"
  | "oversized"
  | "http_error"
  | "content_type";

export type BoundedImage =
  | { ok: true; bytes: Uint8Array; contentType: string; extension: string }
  | { ok: false; reason: FetchFailureReason };

export function classifySourceUrl(raw: string): { ok: true; url: URL } | { ok: false; reason: "invalid_url" | "unapproved_host" } {
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    return { ok: false, reason: "invalid_url" };
  }
  if (url.protocol !== "https:" || !APPROVED_SOURCE_HOSTS.has(url.hostname)) {
    return { ok: false, reason: "unapproved_host" };
  }
  return { ok: true, url };
}

export async function fetchBoundedImage(
  sourceUrl: string,
  deps: {
    fetch: (input: string, init?: RequestInit) => Promise<Response>;
    timeoutMs: number;
    maxBytes: number;
  },
): Promise<BoundedImage> {
  // One budget for every redirect hop and the body. A later hop must not arm a
  // fresh timeout, including after this budget has already expired.
  const controller = new AbortController();
  const deadline = Date.now() + Math.max(0, deps.timeoutMs);
  const timer = deadline > Date.now()
    ? setTimeout(() => controller.abort(), deadline - Date.now())
    : undefined;
  if (timer === undefined) controller.abort();

  const timedOut = () => controller.signal.aborted || Date.now() >= deadline;

  try {
    let current = sourceUrl;
    for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
      if (timedOut()) return { ok: false, reason: "timeout" };

      const classified = classifySourceUrl(current);
      if (!classified.ok) {
        return { ok: false, reason: hop === 0 ? classified.reason : "redirect_unapproved" };
      }

      let response: Response;
      try {
        response = await deps.fetch(current, { method: "GET", redirect: "manual", signal: controller.signal });
      } catch {
        return { ok: false, reason: timedOut() ? "timeout" : "http_error" };
      }
      if (timedOut()) {
        cancelBody(response.body);
        return { ok: false, reason: "timeout" };
      }

      if (response.status >= 300 && response.status < 400) {
        cancelBody(response.body);
        const location = response.headers.get("location");
        if (!location) return { ok: false, reason: "redirect_unapproved" };
        let next: URL;
        try {
          next = new URL(location, current);
        } catch {
          return { ok: false, reason: "redirect_unapproved" };
        }
        if (next.protocol !== "https:" || !APPROVED_SOURCE_HOSTS.has(next.hostname)) {
          return { ok: false, reason: "redirect_unapproved" };
        }
        current = next.toString();
        continue;
      }

      if (!response.ok) {
        cancelBody(response.body);
        return { ok: false, reason: "http_error" };
      }

      const contentType = response.headers.get("content-type");
      const extension = extensionFor(contentType);
      if (!extension || !contentType) {
        cancelBody(response.body);
        return { ok: false, reason: "content_type" };
      }

      const body = await readBounded(response, deps.maxBytes, controller.signal);
      if (body === "timeout") return { ok: false, reason: "timeout" };
      if (body === "oversized") return { ok: false, reason: "oversized" };
      if (body === "read_error") return { ok: false, reason: "http_error" };
      if (body.byteLength === 0) return { ok: false, reason: "http_error" };
      return { ok: true, bytes: body, contentType, extension };
    }
    return { ok: false, reason: "redirect_unapproved" };
  } catch {
    return { ok: false, reason: timedOut() ? "timeout" : "http_error" };
  } finally {
    if (timer !== undefined) clearTimeout(timer);
  }
}

function extensionFor(contentType: string | null): string | null {
  if (!contentType) return null;
  const ct = contentType.toLowerCase();
  if (!ct.startsWith("image/")) return null;
  if (ct.includes("png")) return "png";
  if (ct.includes("webp")) return "webp";
  if (ct.includes("avif")) return "avif";
  if (ct.includes("jpeg") || ct.includes("jpg")) return "jpg";
  return null;
}

function cancelBody(body: ReadableStream<Uint8Array> | null | undefined): void {
  if (!body) return;
  body.cancel().catch(() => {});
}

async function readBounded(
  response: Response,
  maxBytes: number,
  signal: AbortSignal,
): Promise<Uint8Array | "oversized" | "timeout" | "read_error"> {
  if (signal.aborted) {
    cancelBody(response.body);
    return "timeout";
  }
  const declared = Number(response.headers.get("content-length"));
  if (Number.isFinite(declared) && declared > maxBytes) {
    cancelBody(response.body);
    return "oversized";
  }
  if (!response.body) {
    try {
      const buf = new Uint8Array(await response.arrayBuffer());
      if (signal.aborted) return "timeout";
      return buf.byteLength > maxBytes ? "oversized" : buf;
    } catch {
      return signal.aborted ? "timeout" : "read_error";
    }
  }

  const reader = response.body.getReader();
  let onAbort: () => void = () => {};
  const aborted = new Promise<void>((resolve) => {
    onAbort = () => {
      reader.cancel().catch(() => {});
      resolve();
    };
  });
  if (signal.aborted) onAbort();
  else signal.addEventListener("abort", onAbort);

  try {
    const chunks: Uint8Array[] = [];
    let total = 0;
    while (true) {
      const next = reader.read().then(
        (result) => ({ kind: "chunk" as const, result }),
        (_error: unknown) => ({ kind: "error" as const }),
      );
      const winner = await Promise.race([
        next,
        aborted.then(() => ({ kind: "timeout" as const })),
      ]);
      if (winner.kind === "timeout" || signal.aborted) {
        reader.cancel().catch(() => {});
        return "timeout";
      }
      if (winner.kind === "error") {
        reader.cancel().catch(() => {});
        return "read_error";
      }
      const { done, value } = winner.result;
      if (done) break;
      total += value.byteLength;
      if (total > maxBytes) {
        reader.cancel().catch(() => {});
        return "oversized";
      }
      chunks.push(value);
    }
    if (signal.aborted) {
      reader.cancel().catch(() => {});
      return "timeout";
    }
    const out = new Uint8Array(total);
    let offset = 0;
    for (const chunk of chunks) {
      out.set(chunk, offset);
      offset += chunk.byteLength;
    }
    return out;
  } catch {
    reader.cancel().catch(() => {});
    return signal.aborted ? "timeout" : "read_error";
  } finally {
    signal.removeEventListener("abort", onAbort);
  }
}
