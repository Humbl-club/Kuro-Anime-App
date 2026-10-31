import { assertEquals } from "jsr:@std/assert@1";
import { interpretBudget, withResolveBudget, type ResolveBudgetClient } from "./resolve_budget.ts";

Deno.test("budget verdict requires a boolean allowed", () => {
  assertEquals(interpretBudget({ data: { allowed: true }, error: null }), "acquired");
  assertEquals(interpretBudget({ data: { allowed: false }, error: null }), "denied");
  assertEquals(interpretBudget({ data: {}, error: null }), "unavailable");
  assertEquals(interpretBudget({ data: { allowed: "false" }, error: null }), "unavailable");
  assertEquals(interpretBudget({ data: null, error: { message: "down" } }), "unavailable");
  assertEquals(interpretBudget(null), "unavailable");
});

type Call = { fn: string; args: Record<string, unknown> };

function scripted(steps: Record<string, { data?: unknown; error?: unknown } | "throw">): {
  client: ResolveBudgetClient;
  calls: Call[];
} {
  const calls: Call[] = [];
  return {
    calls,
    client: {
      rpc(fn: string, args: Record<string, unknown> = {}) {
        calls.push({ fn, args });
        const step = steps[fn];
        if (step === "throw" || step == null) return Promise.reject(new Error(fn));
        return Promise.resolve(step);
      },
    },
  };
}

const reserved = 585;
const model = "test-model";

Deno.test("a denied global reservation finalizes only the user reservation and does not call the provider", async () => {
  let providerCalls = 0;
  const { client, calls } = scripted({
    llm_budget_reserve: { data: { allowed: true }, error: null },
    get_concierge_config: { data: { global_llm_budget: { daily_tokens: 250000, daily_calls: 600 } }, error: null },
    llm_global_budget_reserve: { data: { allowed: false }, error: null },
    llm_budget_finalize: { data: { success: true }, error: null },
  });
  const outcome = await withResolveBudget(client, reserved, model, async () => {
    providerCalls += 1;
    return { value: "ran", actualTokens: reserved };
  });
  assertEquals(providerCalls, 0);
  assertEquals(outcome.body.global_budget_exceeded, true);
  assertEquals(calls.filter((call) => call.fn === "llm_global_budget_finalize"), []);
  const userFinalize = calls.filter((call) => call.fn === "llm_budget_finalize");
  assertEquals(userFinalize.length, 1);
  assertEquals(userFinalize[0].args.p_actual_tokens, 0);
});

Deno.test("a config failure after the user reservation releases only that reservation", async () => {
  let providerCalls = 0;
  const { client, calls } = scripted({
    llm_budget_reserve: { data: { allowed: true }, error: null },
    get_concierge_config: "throw",
    llm_budget_finalize: { data: { success: true }, error: null },
  });
  const outcome = await withResolveBudget(client, reserved, model, async () => {
    providerCalls += 1;
    return { value: "ran", actualTokens: reserved };
  });
  assertEquals(outcome.status, 503);
  assertEquals(providerCalls, 0);
  assertEquals(calls.filter((call) => call.fn === "llm_global_budget_reserve"), []);
  assertEquals(calls.filter((call) => call.fn === "llm_global_budget_finalize"), []);
  assertEquals(calls.filter((call) => call.fn === "llm_budget_finalize").length, 1);
});

Deno.test("malformed user or global budget data does not call the provider", async () => {
  for (const malformed of [{}, { allowed: "false" }]) {
    let providerCalls = 0;
    const user = scripted({
      llm_budget_reserve: { data: malformed, error: null },
    });
    const userOutcome = await withResolveBudget(user.client, reserved, model, async () => {
      providerCalls += 1;
      return { value: "ran", actualTokens: 1 };
    });
    assertEquals(userOutcome.status, 503);
    assertEquals(providerCalls, 0);
    assertEquals(user.calls.some((call) => call.fn === "llm_budget_finalize"), false);

    providerCalls = 0;
    const global = scripted({
      llm_budget_reserve: { data: { allowed: true }, error: null },
      get_concierge_config: { data: {}, error: null },
      llm_global_budget_reserve: { data: malformed, error: null },
      llm_budget_finalize: { data: { success: true }, error: null },
    });
    const globalOutcome = await withResolveBudget(global.client, reserved, model, async () => {
      providerCalls += 1;
      return { value: "ran", actualTokens: 1 };
    });
    assertEquals(globalOutcome.status, 503);
    assertEquals(providerCalls, 0);
    assertEquals(global.calls.filter((call) => call.fn === "llm_global_budget_finalize"), []);
    assertEquals(global.calls.filter((call) => call.fn === "llm_budget_finalize").length, 1);
  }
});

Deno.test("a provider throw releases both acquired reservations once and does not charge usage", async () => {
  const { client, calls } = scripted({
    llm_budget_reserve: { data: { allowed: true }, error: null },
    get_concierge_config: { data: {}, error: null },
    llm_global_budget_reserve: { data: { allowed: true }, error: null },
    llm_budget_finalize: { data: { success: true }, error: null },
    llm_global_budget_finalize: { data: { success: true }, error: null },
  });
  const outcome = await withResolveBudget(client, reserved, model, () => {
    throw new Error("provider down");
  });
  assertEquals(outcome.status, 500);
  const user = calls.filter((call) => call.fn === "llm_budget_finalize");
  const global = calls.filter((call) => call.fn === "llm_global_budget_finalize");
  assertEquals(user.length, 1);
  assertEquals(global.length, 1);
  assertEquals(user[0].args.p_actual_tokens, 0);
  assertEquals(global[0].args.p_actual_tokens, 0);
});
