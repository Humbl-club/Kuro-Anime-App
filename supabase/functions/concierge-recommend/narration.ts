// Narration of concierge-recommend: the ONLY server-side LLM use, and presentation only (F51, 2026-10-05).
// Routing and rail selection never depend on it; a failed, denied or disabled narration leaves the
// deterministic recommendations untouched (no blurbs).
//
// `sanitizeForLLM`, `groqNarrate` and `clampBlurb` came from index.ts. The Groq transport receives
// injected `fetch` and bounds headers plus body by one eight-second deadline. `narrateWithBudget` is the
// bounded budget adapter that replaces the inline reserve/finalize block. CHANGED (F32 cross-function
// rule "budget errors fail closed for paid calls"; reservation accounting):
//   - the kill switch (`is_flag_enabled('llm_enabled')`), the per-user reserve (`llm_budget_reserve`)
//     and the global reserve (`llm_global_budget_reserve`) must each ANSWER yes; an RPC error or a
//     missing `allowed` no longer lets a paid call through (before, an error read as "allowed");
//   - a reservation is released (`*_finalize`) exactly once and only if it was taken (the SQL reserves
//     only when `allowed`); before, a denied user budget released BOTH budgets it never reserved, and a
//     denied global budget released the user reservation twice, and `finalize` subtracts from the
//     day's in-flight reservations of other requests (`greatest(0, reserved_tokens - r)`).
// Unchanged: `narrated` is true once the provider call was attempted (also when it then failed),
// `narrationError` is only returned under `debugNarration`, usage falls back to the reservation.

/** Strip common LLM prompt-injection patterns from user-supplied text before interpolation. */
export function sanitizeForLLM(text: string): string {
  return text
    // Strip common injection patterns
    .replace(/\b(ignore|disregard|forget)\s+(all\s+)?(previous|above|prior)\s+(instructions?|prompts?|rules?|context)/gi, '[filtered]')
    .replace(/\b(you\s+are\s+now|new\s+instructions?|system\s*:)/gi, '[filtered]')
    .replace(/\b(act\s+as|pretend\s+(to\s+be|you\s+are)|role\s*play)/gi, '[filtered]')
    // Strip markdown/HTML injection attempts
    .replace(/```[\s\S]*?```/g, '')
    .replace(/<[^>]+>/g, '')
    // Limit length
    .slice(0, 2000)
    // Trim whitespace
    .trim();
}

export async function groqNarrate(opts: {
  /** Injected transport (index.ts passes the global fetch; tests pass a controlled one). */
  fetch: (url: string, init: RequestInit) => Promise<Response>;
  apiKey: string;
  model: string;
  lang: "de" | "en";
  userText: string;
  debug?: boolean;
  /** One deadline covers headers and body; short overrides are for controlled tests. */
  timeoutMs?: number;
  items: Array<{ id: string; title: string; year?: number | null; format?: string | null; signals: string[] }>;
}): Promise<{ blurbs: Record<string, string>; usageTotal: number | null }> {
  const url = "https://api.groq.com/openai/v1/chat/completions";
  // NOTE: Groq's GPT-OSS models sometimes return empty `content` if the system prompt is too "policy-like".
  // Keep the system prompt extremely short and drive style via a single user instruction.
  const system =
    opts.lang === "de"
      ? `Gib nur JSON zurück: {"blurbs":{"ANIME|123":"...", "MANGA|456":"..."}}`
      : `Return JSON only: {"blurbs":{"ANIME|123":"...", "MANGA|456":"..."}}`;

  const safeUserText = sanitizeForLLM(opts.userText);
  const user =
    opts.lang === "de"
      ? `User prompt: ${safeUserText}\n\nItems:\n${opts.items
          .map((it) => `- ${it.id}: ${it.title} (${it.year ?? "?"}) ${it.format ?? ""} [${it.signals.join(", ")}]`)
          .join("\n")}\n\nSchreibe pro Item genau einen kurzen, spoilerfreien Satz. Gib nur JSON zurück: {"blurbs":{"ANIME|123":"...", "MANGA|456":"..."}}`
      : `User prompt: ${safeUserText}\n\nItems:\n${opts.items
          .map((it) => `- ${it.id}: ${it.title} (${it.year ?? "?"}) ${it.format ?? ""} [${it.signals.join(", ")}]`)
          .join("\n")}\n\nWrite one short, spoiler-free sentence per item. Return JSON only: {"blurbs":{"ANIME|123":"...", "MANGA|456":"..."}}`;

  const controller = new AbortController();
  let timer: ReturnType<typeof setTimeout> | undefined;
  const deadline = new Promise<never>((_, reject) => {
    timer = setTimeout(() => {
      controller.abort();
      reject(new Error("Groq narration timed out"));
    }, opts.timeoutMs ?? 8_000);
  });
  let res: Response;
  // deno-lint-ignore no-explicit-any
  let jsonRes: any;
  try {
    [res, jsonRes] = await Promise.race([
      deadline,
      (async () => {
        const response = await opts.fetch(url, {
          signal: controller.signal,
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${opts.apiKey}`,
          },
          body: JSON.stringify({
            model: opts.model,
            // Keep this deterministic and tiny. We're only writing 5–10 single-sentence blurbs.
            temperature: 0.2,
            // We only need short JSON blurbs; keeping this low improves latency/cost.
            max_tokens: 260,
            messages: [
              { role: "system", content: system },
              { role: "user", content: user },
            ],
          }),
        });
        controller.signal.throwIfAborted();
        const body = await response.json().catch(() => null);
        controller.signal.throwIfAborted();
        return [response, body] as const;
      })(),
    ]);
  } finally {
    clearTimeout(timer);
  }
  if (!res.ok) {
    throw new Error(`Groq error: ${res.status} ${JSON.stringify(jsonRes)?.slice(0, 300)}`);
  }

  const usageTotal = Number(
    jsonRes?.usage?.total_tokens ??
      ((Number(jsonRes?.usage?.prompt_tokens ?? 0) || 0) + (Number(jsonRes?.usage?.completion_tokens ?? 0) || 0)),
  );
  const usage = Number.isFinite(usageTotal) && usageTotal > 0 ? usageTotal : null;

  const content = jsonRes?.choices?.[0]?.message?.content;
  if (typeof content !== "string" || !content.trim()) {
    if (opts.debug) {
      throw new Error(
        `Groq narration missing content. status=${res.status} body_snippet=${JSON.stringify(jsonRes)?.slice(0, 600)}`,
      );
    }
    return { blurbs: {}, usageTotal: usage };
  }
  try {
    // Be forgiving: some models wrap JSON in text/code fences.
    const start = content.indexOf("{");
    const end = content.lastIndexOf("}");
    const candidate = start >= 0 && end > start ? content.slice(start, end + 1) : content;
    const parsed = JSON.parse(candidate);
    const blurbs = parsed?.blurbs;
    if (blurbs && typeof blurbs === "object") return { blurbs, usageTotal: usage };
  } catch {
    // ignore
  }
  if (opts.debug) {
    throw new Error(`Groq narration JSON parse failed. content_snippet=${content.slice(0, 400)}`);
  }
  return { blurbs: {}, usageTotal: usage };
}

export function clampBlurb(s: string, maxWords: number, maxChars: number) {
  const trimmed = s.replace(/\s+/g, " ").trim();
  if (!trimmed) return "";
  const words = trimmed.split(" ");
  const clippedWords = words.slice(0, maxWords).join(" ");
  const clippedChars = clippedWords.slice(0, maxChars).trim();
  return clippedChars.replace(/[,\s]+$/g, "").trim();
}

/** One item offered for narration (`id` is `${mediaType}|${mediaId}`). */
export type NarrationItem = { id: string; title: string; year?: number | null; format?: string | null; signals: string[] };

/** Kill switch and budget RPCs over the caller's client (the user budget is keyed by auth.uid()). */
export interface NarrationBudget {
  /** `is_flag_enabled('llm_enabled')`: true only when the RPC answered true (an error reads as off). */
  llmEnabled(): Promise<boolean>;
  /** `llm_budget_reserve`: true only when a reservation was taken (`allowed === true`). */
  reserveUser(tokens: number, model: string): Promise<boolean>;
  /** `llm_global_budget_reserve`: true only when a reservation was taken. */
  reserveGlobal(tokens: number, maxDailyTokens: number, maxDailyCalls: number): Promise<boolean>;
  finalizeUser(reserved: number, actual: number, model: string): Promise<void>;
  finalizeGlobal(reserved: number, actual: number): Promise<void>;
}

/** Supabase-js client bound to one request's Authorization header (structurally untyped). */
// deno-lint-ignore no-explicit-any
type SupabaseLike = any;

export function supabaseNarrationBudget(client: SupabaseLike): NarrationBudget {
  // deno-lint-ignore no-explicit-any
  const answered = (r: any) => !r?.error && r?.data != null ? r.data : null;
  return {
    async llmEnabled() {
      try {
        return answered(await client.rpc("is_flag_enabled", { p_key: "llm_enabled" })) === true;
      } catch {
        return false;
      }
    },
    async reserveUser(tokens, model) {
      try {
        const data = answered(
          await client.rpc("llm_budget_reserve", {
            p_reserved_tokens: tokens,
            p_max_daily_tokens: null,
            p_max_daily_calls: null,
            p_model: model,
          }),
        );
        return data?.allowed === true;
      } catch {
        return false;
      }
    },
    async reserveGlobal(tokens, maxDailyTokens, maxDailyCalls) {
      try {
        const data = answered(
          await client.rpc("llm_global_budget_reserve", {
            p_reserved_tokens: tokens,
            p_max_daily_tokens: maxDailyTokens,
            p_max_daily_calls: maxDailyCalls,
          }),
        );
        return data?.allowed === true;
      } catch {
        return false;
      }
    },
    async finalizeUser(reserved, actual, model) {
      try {
        await client.rpc("llm_budget_finalize", { p_reserved_tokens: reserved, p_actual_tokens: actual, p_model: model });
      } catch {
        // best-effort
      }
    },
    async finalizeGlobal(reserved, actual) {
      try {
        await client.rpc("llm_global_budget_finalize", { p_reserved_tokens: reserved, p_actual_tokens: actual });
      } catch {
        // best-effort
      }
    },
  };
}

/** The narration provider call (groqNarrate with its transport bound). */
export type NarrationProvider = (opts: Omit<Parameters<typeof groqNarrate>[0], "fetch">) => ReturnType<typeof groqNarrate>;

export type NarrationRequest = {
  /** Body `narrate`. */
  requested: boolean;
  /** Body `debugNarration`. */
  debug: boolean;
  /** GROQ_API_KEY; narration is skipped without it. */
  apiKey: string | undefined;
  /** GROQ_MODEL ?? "openai/gpt-oss-20b". */
  model: string;
  lang: "de" | "en";
  userText: string;
  /** `get_concierge_config().global_llm_budget` ({ daily_tokens, daily_calls }). */
  globalBudgetConfig: unknown;
};

export type NarrationResult = { narrated: boolean; blurbs: Record<string, string>; error: string | null };

/** Items offered for narration (the first of the flattened response items). */
export const NARRATION_MAX_ITEMS = 8;
const MAX_COMPLETION_TOKENS = 260;
const BUDGET_EXCEEDED = "LLM budget exceeded";

/** Tokens reserved for one narration call (prompt estimate + completion cap, clamped to 160..9000). */
export function narrationReserveTokens(userText: string, items: NarrationItem[]): number {
  const promptChars = 1200 + userText.length + JSON.stringify(items).length;
  return Math.min(9000, Math.max(160, Math.ceil(promptChars / 4) + MAX_COMPLETION_TOKENS));
}

function globalLimits(cfg: unknown): { dailyTokens: number; dailyCalls: number } {
  // deno-lint-ignore no-explicit-any
  const g = cfg as any;
  const dailyTokens = Number(g?.daily_tokens ?? 250000);
  const dailyCalls = Number(g?.daily_calls ?? 600);
  return {
    dailyTokens: Number.isFinite(dailyTokens) ? dailyTokens : 250000,
    dailyCalls: Number.isFinite(dailyCalls) ? dailyCalls : 600,
  };
}

/**
 * Optional narration behind the kill switch and both budgets. Never throws; the caller keeps its
 * deterministic items whatever happens here and only adds the returned blurbs.
 */
export async function narrateWithBudget(
  req: NarrationRequest,
  items: NarrationItem[],
  budget: NarrationBudget,
  provider: NarrationProvider,
): Promise<NarrationResult> {
  const off: NarrationResult = { narrated: false, blurbs: {}, error: null };
  if (!req.requested) return off;
  // Global kill-switch: keep core recommendations deterministic if disabled.
  if (!(await budget.llmEnabled())) return off;
  if (!req.apiKey) return off;

  const reserveTokens = narrationReserveTokens(req.userText, items);
  // Reserve the per-user budget, then the global budget (prevents "many users" abuse).
  if (!(await budget.reserveUser(reserveTokens, req.model))) return { ...off, error: BUDGET_EXCEEDED };
  const g = globalLimits(req.globalBudgetConfig);
  if (!(await budget.reserveGlobal(reserveTokens, g.dailyTokens, g.dailyCalls))) {
    await budget.finalizeUser(reserveTokens, 0, req.model);
    return { ...off, error: BUDGET_EXCEEDED };
  }

  // Both reservations are held: release each exactly once, with the actual usage (0 on failure).
  let actual = 0;
  try {
    const { blurbs, usageTotal } = await provider({
      apiKey: req.apiKey,
      model: req.model,
      lang: req.lang,
      userText: req.userText,
      debug: req.debug,
      items,
    });
    // Finalize with actual usage if available; else treat reserve as actual.
    actual = usageTotal ?? reserveTokens;
    return { narrated: true, blurbs, error: null };
  } catch (e) {
    return { narrated: true, blurbs: {}, error: (e as Error)?.message ?? String(e) };
  } finally {
    await budget.finalizeUser(reserveTokens, actual, req.model);
    await budget.finalizeGlobal(reserveTokens, actual);
  }
}

/** Adds the returned blurbs to the (shared) response items in place, clamped to 18 words / 180 chars. */
// deno-lint-ignore no-explicit-any
export function applyBlurbs(items: any[], blurbs: Record<string, string>): void {
  for (const it of items) {
    const key = `${it.mediaType}|${it.mediaId}`;
    const b = blurbs[key];
    if (typeof b === "string" && b.trim()) it.blurb = clampBlurb(b, 18, 180);
  }
}
