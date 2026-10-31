// Resolve budget acquisition (F65, review R4–R6). Dormant endpoint; this does not call Groq.
//
// A reservation is acquired only when the RPC returns `allowed: true` (a boolean).
// `allowed: false` is a denial and creates no reservation. Any other shape, error or throw
// is unavailable. Finalize only scopes that were acquired, exactly once. A denied or failed
// global reserve must not call `llm_global_budget_finalize`: that RPC subtracts from the
// shared day's aggregate, including reservations that belong to other requests.

export type BudgetVerdict = "acquired" | "denied" | "unavailable";

export function interpretBudget(
  result: { data?: unknown; error?: unknown } | null | undefined,
): BudgetVerdict {
  if (!result || result.error) return "unavailable";
  const data = result.data;
  if (!data || typeof data !== "object") return "unavailable";
  const allowed = (data as { allowed?: unknown }).allowed;
  if (allowed === true) return "acquired";
  if (allowed === false) return "denied";
  return "unavailable";
}

export interface ResolveBudgetClient {
  rpc(fn: string, args?: Record<string, unknown>): PromiseLike<{ data?: unknown; error?: unknown }>;
}

async function readRpc(
  call: PromiseLike<{ data?: unknown; error?: unknown }>,
): Promise<{ data?: unknown; error?: unknown }> {
  try {
    return await call;
  } catch (error) {
    return { data: null, error };
  }
}

async function finalize(
  client: ResolveBudgetClient,
  fn: string,
  args: Record<string, unknown>,
): Promise<void> {
  try {
    await client.rpc(fn, args);
  } catch {
    // A finalize error must not hide the resolve outcome or finalize the other scope twice.
  }
}

export interface ResolveBudgetOutcome<T> {
  status: number;
  body: Record<string, unknown>;
  value?: T;
}

const unavailable = {
  status: 503,
  body: { success: false, error: "Budget unavailable", retryable: true },
};

/**
 * Reserves the user budget, then config + global budget, then `run` (the provider).
 * Releases only the scopes this call acquired.
 */
export async function withResolveBudget<T>(
  client: ResolveBudgetClient,
  reserved: number,
  model: string,
  run: () => Promise<{ value: T; actualTokens: number }>,
): Promise<ResolveBudgetOutcome<T>> {
  const user = interpretBudget(await readRpc(client.rpc("llm_budget_reserve", {
    p_reserved_tokens: reserved,
    p_max_daily_tokens: null,
    p_max_daily_calls: null,
    p_model: model,
  })));
  if (user === "unavailable") return unavailable;
  if (user === "denied") {
    return { status: 200, body: { success: true, choices: [], budget_exceeded: true } };
  }

  const scopes = { user: true, global: false };
  let actual = 0;
  let released = false;
  const release = async () => {
    if (released) return;
    released = true;
    if (scopes.user) {
      await finalize(client, "llm_budget_finalize", {
        p_reserved_tokens: reserved,
        p_actual_tokens: actual,
        p_model: model,
      });
    }
    if (scopes.global) {
      await finalize(client, "llm_global_budget_finalize", {
        p_reserved_tokens: reserved,
        p_actual_tokens: actual,
      });
    }
  };

  try {
    const cfg = await readRpc(client.rpc("get_concierge_config"));
    if (cfg.error) {
      await release();
      return unavailable;
    }
    const globalBudget = (cfg.data as {
      global_llm_budget?: { daily_tokens?: unknown; daily_calls?: unknown };
    } | null)?.global_llm_budget ?? null;
    const globalDailyTokens = Number(globalBudget?.daily_tokens ?? 250000);
    const globalDailyCalls = Number(globalBudget?.daily_calls ?? 600);
    const global = interpretBudget(await readRpc(client.rpc("llm_global_budget_reserve", {
      p_reserved_tokens: reserved,
      p_max_daily_tokens: Number.isFinite(globalDailyTokens) ? globalDailyTokens : 250000,
      p_max_daily_calls: Number.isFinite(globalDailyCalls) ? globalDailyCalls : 600,
    })));
    if (global === "unavailable") {
      await release();
      return unavailable;
    }
    if (global === "denied") {
      await release();
      return {
        status: 200,
        body: { success: true, choices: [], budget_exceeded: true, global_budget_exceeded: true },
      };
    }
    scopes.global = true;
    const outcome = await run();
    actual = outcome.actualTokens;
    await release();
    return { status: 200, body: { success: true }, value: outcome.value };
  } catch {
    await release();
    return { status: 500, body: { success: false, error: "Resolve failed", retryable: true } };
  }
}
