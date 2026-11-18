// Keyed IP bucket for `check_concierge_rate_limit` (every Concierge caller; contact-submit keys its own buckets).
//
// The limiter RPC is callable with the anon key and builds its bucket as 'ip:' || p_ip || ':' || kind || ':' || window.
// A raw client address therefore lets anyone fill a known address's buckets and block everybody behind it.
// Handlers pass `await limiterIpBucket(clientIp, secret)` instead: an HMAC-SHA-256 under a server secret, so a third
// party cannot compute the bucket of a victim address.
//
// Secret: the same one contact-submit uses (`CONTACT_IP_HASH_SECRET`, falling back to `SUPABASE_SERVICE_ROLE_KEY`,
// which every Edge Function already has). The domain prefix below keeps the two key spaces apart, so no new owner
// secret is required; setting CONTACT_IP_HASH_SECRET stays recommended so the key is independent of the service key.

/** Version/domain prefix of the bucket value; also makes the value impossible to confuse with a raw address. */
export const LIMITER_IP_PREFIX = "c1:";

/** The HMAC secret from an env getter: CONTACT_IP_HASH_SECRET, else SUPABASE_SERVICE_ROLE_KEY, else undefined. */
export function limiterSecretFromEnv(get: (name: string) => string | undefined): string | undefined {
  const dedicated = get("CONTACT_IP_HASH_SECRET");
  if (dedicated) return dedicated;
  const service = get("SUPABASE_SERVICE_ROLE_KEY");
  return service ? service : undefined;
}

/**
 * HMAC-SHA-256 bucket value (`c1:` + 32 hex chars) for a client address; null when no address is known (the limiter
 * then keys on the user only, as before). Throws when an address exists but there is no secret: callers sit inside
 * their fail-closed handler paths, and a raw-IP fallback would reopen the bucket-targeting hole.
 */
export async function limiterIpBucket(ip: string | null | undefined, secret: string | undefined): Promise<string | null> {
  const address = typeof ip === "string" ? ip.trim().toLowerCase() : "";
  if (address.length === 0) return null;
  if (!secret) throw new Error("limiter IP secret is not configured");
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", key, enc.encode(`concierge-ip:${address}`)));
  return LIMITER_IP_PREFIX + Array.from(sig.slice(0, 16), (b) => b.toString(16).padStart(2, "0")).join("");
}
