import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type Candidate = {
  media_type: "ANIME" | "MANGA";
  media_id: number;
  title_raw: string;
  variant_type?: string;
  score?: number;
  year?: number;
  format?: string;
};

type Parsed = {
  mediaTypeHint?: string | null;
  status?: string | null;
  progressEpisodes?: number | null;
  progressChapters?: number | null;
  progressVolumes?: number | null;
  seasonNumber?: number | null;
  episodeInSeason?: number | null;
  caughtUp?: boolean | null;
  lastEpisode?: boolean | null;
  completed?: boolean | null;
  yearMention?: number | null;
};

type ResolveItem = {
  raw: string;
  normalized?: string;
  parsed?: Parsed;
  candidates: Candidate[];
};

function json(res: unknown, init: ResponseInit = {}) {
  return new Response(JSON.stringify(res), {
    ...init,
    headers: { "Content-Type": "application/json", ...(init.headers ?? {}) },
  });
}

function clampInt(v: unknown, min: number, max: number) {
  const n = Math.floor(Number(v));
  if (!Number.isFinite(n)) return null;
  return Math.max(min, Math.min(max, n));
}

/** Strip common LLM prompt-injection patterns from user-supplied text before interpolation. */
function sanitizeForLLM(text: string): string {
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

function extractJsonObject(text: string): any | null {
  const s = String(text || "");
  const start = s.indexOf("{");
  const end = s.lastIndexOf("}");
  if (start < 0 || end < 0 || end <= start) return null;
  const candidate = s.slice(start, end + 1);
  try {
    return JSON.parse(candidate);
  } catch {
    return null;
  }
}

async function groqResolve(opts: {
  apiKey: string;
  model: string;
  items: Array<{ raw: string; parsed: Parsed; options: Array<{ id: string; title: string; variant?: string; score?: number; year?: number; format?: string }> }>;
}): Promise<{ resolved: any | null; usageTotal: number | null }> {
  const url = "https://api.groq.com/openai/v1/chat/completions";

  const system = `Return JSON only: {"choices":[{"i":0,"pick":0,"confidence":0.0,"reason":""}]}`;

  const user = `You are resolving user-entered anime/manga titles to one of the provided options.

Rules:
- You MUST pick from the options for each item: pick is an integer index into that item's options array (0-based).
- If none match, set pick to -1.
- If the user explicitly says watched/saw/schaue/geschaut => prefer ANIME; read/lese/gelesen => prefer MANGA.
- If seasonNumber is present, prefer an option whose title includes that season (e.g., "Season 2", "2nd Season") IF the base title also matches.
- If the user mentions a year (yearMention in parsed), prefer the option whose year matches that year.
- DO NOT hallucinate. Only choose from options.
- Output must be valid JSON ONLY, matching:
  {"choices":[{"i":number,"pick":number,"confidence":number,"reason":string}...]}

Items:
${opts.items
  .map((it, idx) =>
    `#${idx} raw="${sanitizeForLLM(it.raw)}" parsed=${JSON.stringify(it.parsed ?? {})}\noptions:\n${it.options
      .map((o, j) => `  [${j}] ${o.id} ${o.title}${o.year ? ` [${o.year}]` : ""}${o.format ? ` ${o.format}` : ""}${o.variant ? ` (${o.variant})` : ""}${typeof o.score === "number" ? ` score=${o.score.toFixed(3)}` : ""}`)
      .join("\n")}`,
  )
  .join("\n\n")}`;

  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${opts.apiKey}`,
    },
    body: JSON.stringify({
      model: opts.model,
      temperature: 0.0,
      // Keep this tiny; output is a small JSON object.
      max_tokens: 220,
      messages: [
        { role: "system", content: system },
        { role: "user", content: user },
      ],
    }),
  });

  const jsonRes = await res.json().catch(() => null);
  if (!res.ok) {
    throw new Error(`Groq error: ${res.status} ${JSON.stringify(jsonRes)?.slice(0, 300)}`);
  }

  const usageTotal = Number(
    jsonRes?.usage?.total_tokens ??
      ((Number(jsonRes?.usage?.prompt_tokens ?? 0) || 0) + (Number(jsonRes?.usage?.completion_tokens ?? 0) || 0)),
  );
  const usage = Number.isFinite(usageTotal) && usageTotal > 0 ? usageTotal : null;

  const content = jsonRes?.choices?.[0]?.message?.content ?? "";
  const parsed = extractJsonObject(content);
  return { resolved: parsed ?? null, usageTotal: usage };
}

function clientIp(req: Request): string | null {
  const xf = req.headers.get("x-forwarded-for");
  if (xf) {
    const first = xf.split(",")[0]?.trim();
    if (first) return first;
  }
  const real = req.headers.get("x-real-ip")?.trim();
  if (real) return real;
  const cf = req.headers.get("cf-connecting-ip")?.trim();
  if (cf) return cf;
  return null;
}

serve(async (req) => {
  try {
    if (req.method !== "POST") return json({ error: "Method not allowed" }, { status: 405 });

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnon = Deno.env.get("SUPABASE_ANON_KEY");
    const supabaseService = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const supabaseKey = supabaseAnon ?? supabaseService;
    if (!supabaseUrl || !supabaseKey) {
      return json({ error: "Missing SUPABASE_URL or a Supabase API key env (SUPABASE_ANON_KEY or SUPABASE_SERVICE_ROLE_KEY)" }, { status: 500 });
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const client = createClient(supabaseUrl, supabaseKey, {
      global: { headers: authHeader ? { Authorization: authHeader } : {} },
    });

    const { data: userData, error: userErr } = await client.auth.getUser();
    if (userErr || !userData?.user) return json({ error: "Unauthorized" }, { status: 401 });

    // Server-side rate limiting (per-user + per-IP).
    const ip = clientIp(req);
    const { data: rl } = await client.rpc("check_concierge_rate_limit", {
      p_kind: "resolve",
      p_ip: ip,
      p_window_seconds: null,
      p_max_user: null,
      p_max_ip: null,
    });
    if (rl && rl.allowed === false) {
      return json(
        { error: "Rate limited", retry_after_s: rl.retry_after_s ?? 30 },
        { status: 429, headers: { "Retry-After": String(rl.retry_after_s ?? 30) } },
      );
    }

    // Global kill-switch: if disabled, just don't resolve (user can pick manually).
    const { data: llmEnabled } = await client.rpc("is_flag_enabled", { p_key: "llm_enabled" });
    if (llmEnabled === false) return json({ success: true, choices: [], disabled: true });

    const groqKey = Deno.env.get("GROQ_API_KEY");
    const model = Deno.env.get("GROQ_MODEL_RESOLVE") ?? Deno.env.get("GROQ_MODEL") ?? "openai/gpt-oss-20b";
    if (!groqKey) return json({ error: "Missing GROQ_API_KEY secret" }, { status: 500 });

    const body = await req.json().catch(() => ({}));
    const items: ResolveItem[] = Array.isArray(body?.items) ? body.items : [];
    const maxCandidates = clampInt(body?.maxCandidates, 2, 10) ?? 6;

    if (items.length === 0) return json({ success: true, choices: [] });

    const packed = items.slice(0, 20).map((it) => {
      const raw = String(it?.raw ?? "").slice(0, 300);
      const parsed: Parsed = it?.parsed ?? {};
      const options = (Array.isArray(it?.candidates) ? it.candidates : [])
        .slice(0, maxCandidates)
        .map((c) => ({
          id: `${String(c.media_type).toUpperCase()}|${Number(c.media_id)}`,
          title: String(c.title_raw ?? "").slice(0, 120),
          variant: String(c.variant_type ?? ""),
          score: typeof c.score === "number" ? c.score : undefined,
          year: typeof c.year === "number" ? c.year : undefined,
          format: typeof c.format === "string" && c.format ? c.format : undefined,
        }));
      return { raw, parsed, options };
    });

    // Budget guardrails. We reserve before the LLM call, then finalize with actual usage if available.
    const maxCompletion = 220;
    const promptChars =
      1400 + // small constant for prompt framing
      packed.reduce((sum, it) => sum + it.raw.length + JSON.stringify(it.options).length + JSON.stringify(it.parsed ?? {}).length, 0);
    const reserveTokens = Math.min(8000, Math.max(120, Math.ceil(promptChars / 4) + maxCompletion));

    const { data: budget } = await client.rpc("llm_budget_reserve", {
      p_reserved_tokens: reserveTokens,
      // Nulls => defaults from public.concierge_config.
      p_max_daily_tokens: null,
      p_max_daily_calls: null,
      p_model: model,
    });
    if (budget && budget.allowed === false) {
      return json({ success: true, choices: [], budget_exceeded: true });
    }

    // Global budget (prevents "many users" abuse).
    const { data: cfg } = await client.rpc("get_concierge_config");
    const globalBudget = cfg?.global_llm_budget ?? null;
    const globalDailyTokens = Number(globalBudget?.daily_tokens ?? 250000);
    const globalDailyCalls = Number(globalBudget?.daily_calls ?? 600);
    const { data: gBudget } = await client.rpc("llm_global_budget_reserve", {
      p_reserved_tokens: reserveTokens,
      p_max_daily_tokens: Number.isFinite(globalDailyTokens) ? globalDailyTokens : 250000,
      p_max_daily_calls: Number.isFinite(globalDailyCalls) ? globalDailyCalls : 600,
    });
    if (gBudget && gBudget.allowed === false) {
      // Release per-user reservation (best-effort).
      try {
        await client.rpc("llm_budget_finalize", { p_reserved_tokens: reserveTokens, p_actual_tokens: 0, p_model: model });
      } catch {
        // ignore
      }
      return json({ success: true, choices: [], budget_exceeded: true, global_budget_exceeded: true });
    }

    const { resolved, usageTotal } = await groqResolve({ apiKey: groqKey, model, items: packed });
    const choices = Array.isArray(resolved?.choices) ? resolved.choices : [];

    // Validate and map.
    const out: any[] = [];
    for (const c of choices) {
      const i = clampInt(c?.i, 0, packed.length - 1);
      if (i == null) continue;
      const pick = clampInt(c?.pick, -1, packed[i].options.length - 1);
      if (pick == null) continue;
      const confidence = Math.max(0, Math.min(1, Number(c?.confidence ?? 0)));
      const reason = String(c?.reason ?? "").slice(0, 240);
      const opt = pick >= 0 ? packed[i].options[pick] : null;
      out.push({
        i,
        pick,
        confidence,
        reason,
        chosen: opt ? { id: opt.id, title: opt.title, year: opt.year ?? null, format: opt.format ?? null } : null,
      });
    }

    try {
      const actual = usageTotal ?? reserveTokens;
      await client.rpc("llm_budget_finalize", {
        p_reserved_tokens: reserveTokens,
        p_actual_tokens: actual,
        p_model: model,
      });
      await client.rpc("llm_global_budget_finalize", {
        p_reserved_tokens: reserveTokens,
        p_actual_tokens: actual,
      });
    } catch {
      // best-effort
    }

    return json({ success: true, choices: out });
  } catch (e) {
    return json({ success: false, error: e?.message ?? String(e) }, { status: 500 });
  }
});
