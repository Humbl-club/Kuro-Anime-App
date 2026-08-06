// Realm Graph Stage 2b — Groq descriptor writer.
// Spec: docs/superpowers/specs/2026-08-02-realm-descriptor-groq-pipeline-design.md
//
// Auth: x-import-secret == IMPORT_SECRET (mirror-images / bulk-import pattern).
// Body:
//   { "media_type": "ANIME"|"MANGA", "media_id": number }
//   OR { "batch": true, "limit": 1..25 }  — drain media_realm_llm_pending
//
// Writes via upsert_media_realm_llm (service role). No secrets in response.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

const TONE_VOCAB = new Set([
  "whimsical", "melancholic", "brutal", "cozy", "cerebral", "kinetic",
  "tender", "eerie", "absurd", "earnest", "dark", "warm",
  "bleak", "playful", "solemn", "lush", "gritty", "dreamlike",
  "frantic", "intimate", "epic", "quiet", "hysterical", "meditative",
]);
const REGISTERS = new Set(["family", "general", "seinen-otaku", "arthouse"]);
const PACINGS = new Set(["slow-burn", "steady", "relentless"]);
const TOP_TAGS = 8;
const SYNOPSIS_TRIM = 600;
const BATCH_MAX = 25;

type MediaType = "ANIME" | "MANGA";

type RealmEntry = { realm: string; weight: number };

type WorkItem = {
  media_type: MediaType;
  media_id: number;
  title: string | null;
  genres: string[];
  tags: Array<{ name: string; rank: number }>;
  average_score: number | null;
  year: number | null;
  format: string | null;
  episodes: number | null;
  chapters: number | null;
  source: string | null;
  description_normalized: string | null;
  synopsis_enhanced: string | null;
  membership: RealmEntry[];
};

type DescriptorRow = {
  media_type: MediaType;
  media_id: number;
  realms: RealmEntry[];
  tone: string[];
  register: string;
  pacing: string;
  confidence: number;
  descriptor: string;
  model: string;
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function sanitizeForLLM(text: string): string {
  return text
    .replace(/\b(ignore|disregard|forget)\s+(all\s+)?(previous|above|prior)\s+(instructions?|prompts?|rules?|context)/gi, "[filtered]")
    .replace(/\b(you\s+are\s+now|new\s+instructions?|system\s*:)/gi, "[filtered]")
    .replace(/\b(act\s+as|pretend\s+(to\s+be|you\s+are)|role\s*play)/gi, "[filtered]")
    .replace(/```[\s\S]*?```/g, "")
    .replace(/<[^>]+>/g, "")
    .slice(0, 2000)
    .trim();
}

function charLen(s: string): number {
  return [...s].length;
}

function trim600(text: string | null | undefined): string | null {
  if (!text) return null;
  return charLen(text) > SYNOPSIS_TRIM ? [...text].slice(0, SYNOPSIS_TRIM).join("") : text;
}

function extractJsonObject(raw: string): unknown {
  const trimmed = raw.trim();
  try {
    return JSON.parse(trimmed);
  } catch {
    const start = trimmed.indexOf("{");
    const end = trimmed.lastIndexOf("}");
    if (start >= 0 && end > start) {
      return JSON.parse(trimmed.slice(start, end + 1));
    }
    throw new Error("response is not valid JSON");
  }
}

async function loadRealmNames(supabase: SupabaseClient): Promise<Set<string>> {
  const { data, error } = await supabase.from("realm_meta").select("realm");
  if (error) throw new Error(`realm_meta: ${error.message}`);
  return new Set((data ?? []).map((r: { realm: string }) => r.realm));
}

function normalizeParsed(parsed: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = { ...parsed };

  // tone: accept "a, b" or "a b" strings
  if (typeof out.tone === "string") {
    out.tone = out.tone.split(/[,|]/).map((s) => s.trim().toLowerCase()).filter(Boolean);
  }
  if (Array.isArray(out.tone)) {
    out.tone = out.tone
      .map((w) => typeof w === "string" ? w.trim().toLowerCase() : w)
      .filter((w) => typeof w === "string" && w.length > 0)
      .slice(0, 3);
  }

  // realms: accept [{name, score}] aliases
  if (Array.isArray(out.realms)) {
    out.realms = out.realms.slice(0, 3).map((entry) => {
      if (!entry || typeof entry !== "object") return entry;
      const e = entry as Record<string, unknown>;
      const realm = typeof e.realm === "string"
        ? e.realm
        : (typeof e.name === "string" ? e.name : "");
      let weight = typeof e.weight === "number"
        ? e.weight
        : (typeof e.score === "number" ? e.score : NaN);
      if (Number.isFinite(weight) && weight > 1 && weight <= 100) weight = weight / 100;
      return { realm, weight };
    });
  }

  if (typeof out.register === "string") out.register = out.register.trim().toLowerCase();
  if (typeof out.pacing === "string") {
    out.pacing = out.pacing.trim().toLowerCase().replace(/\s+/g, "-");
  }
  if (typeof out.confidence === "string" && out.confidence.trim() !== "") {
    const n = Number(out.confidence);
    if (Number.isFinite(n)) out.confidence = n;
  }
  if (typeof out.confidence === "number" && out.confidence > 1 && out.confidence <= 100) {
    out.confidence = out.confidence / 100;
  }
  return out;
}

function validateDescriptor(
  mediaType: MediaType,
  mediaId: number,
  parsedIn: Record<string, unknown>,
  realmNames: Set<string>,
  model: string,
): { ok: true; row: DescriptorRow } | { ok: false; errors: string[] } {
  const errors: string[] = [];
  const parsed = normalizeParsed(parsedIn);

  const realmsRaw = parsed.realms;
  if (!Array.isArray(realmsRaw) || realmsRaw.length < 1 || realmsRaw.length > 3) {
    errors.push("realms must be an array of 1..3 entries");
  }
  const realms: RealmEntry[] = [];
  const seenRealms = new Set<string>();
  if (Array.isArray(realmsRaw)) {
    for (let i = 0; i < realmsRaw.length; i++) {
      const entry = realmsRaw[i] as Record<string, unknown>;
      if (!entry || typeof entry !== "object") {
        errors.push(`realms[${i}] must be an object`);
        continue;
      }
      const realm = typeof entry.realm === "string" ? entry.realm : "";
      const weight = typeof entry.weight === "number" ? entry.weight : NaN;
      if (!realm || !realmNames.has(realm)) errors.push(`realms[${i}].realm invalid: ${realm}`);
      if (!Number.isFinite(weight) || weight < 0 || weight > 1) errors.push(`realms[${i}].weight invalid`);
      if (seenRealms.has(realm)) errors.push(`duplicate realm ${realm}`);
      seenRealms.add(realm);
      realms.push({ realm, weight });
    }
  }
  realms.sort((a, b) => b.weight - a.weight || a.realm.localeCompare(b.realm));

  const toneRaw = parsed.tone;
  const tone: string[] = [];
  const seenTone = new Set<string>();
  if (!Array.isArray(toneRaw) || toneRaw.length < 1 || toneRaw.length > 3) {
    errors.push(`tone must be 1..3 words (got ${JSON.stringify(toneRaw)})`);
  } else {
    for (const w of toneRaw) {
      if (typeof w !== "string" || !TONE_VOCAB.has(w)) errors.push(`tone word invalid: ${w}`);
      else if (seenTone.has(w)) errors.push(`duplicate tone ${w}`);
      else {
        seenTone.add(w);
        tone.push(w);
      }
    }
  }

  const register = typeof parsed.register === "string" ? parsed.register : "";
  const pacing = typeof parsed.pacing === "string" ? parsed.pacing : "";
  const confidence = typeof parsed.confidence === "number" ? parsed.confidence : NaN;
  const descriptor = typeof parsed.descriptor === "string" ? parsed.descriptor.trim() : "";

  if (!REGISTERS.has(register)) errors.push("register invalid");
  if (!PACINGS.has(pacing)) errors.push("pacing invalid");
  if (!Number.isFinite(confidence) || confidence < 0 || confidence > 1) errors.push("confidence invalid");
  if (charLen(descriptor) < 100 || charLen(descriptor) > 600) {
    errors.push(`descriptor length ${charLen(descriptor)} not in 100..600`);
  }

  if (errors.length) return { ok: false, errors };
  return {
    ok: true,
    row: {
      media_type: mediaType,
      media_id: mediaId,
      realms,
      tone,
      register,
      pacing,
      confidence,
      descriptor,
      model,
    },
  };
}

async function loadWorkItem(
  supabase: SupabaseClient,
  mediaType: MediaType,
  mediaId: number,
): Promise<WorkItem> {
  const table = mediaType === "ANIME" ? "anime" : "manga";
  const cols = mediaType === "ANIME"
    ? "id,title_english,title_romaji,genres,average_score,season_year,start_date_year,format,episodes,source,description_normalized,synopsis_enhanced,synopsis_enhanced_state"
    : "id,title_english,title_romaji,genres,average_score,start_date_year,format,chapters,source,description_normalized,synopsis_enhanced,synopsis_enhanced_state";

  const { data: base, error: baseErr } = await supabase
    .from(table)
    .select(cols)
    .eq("id", mediaId)
    .maybeSingle();
  if (baseErr) throw new Error(`${table}: ${baseErr.message}`);
  if (!base) throw new Error(`title not found: ${mediaType}:${mediaId}`);

  const tagTable = mediaType === "ANIME" ? "anime_tags" : "manga_tags";
  const fk = mediaType === "ANIME" ? "anime_id" : "manga_id";
  const { data: tagRows, error: tagErr } = await supabase
    .from(tagTable)
    .select(`${fk},rank,tags(name)`)
    .eq(fk, mediaId);
  if (tagErr) throw new Error(`${tagTable}: ${tagErr.message}`);

  const tags = (tagRows ?? [])
    .map((r: any) => ({ name: r.tags?.name as string, rank: r.rank ?? 0 }))
    .filter((t: { name: string }) => !!t.name)
    .sort((a: { rank: number; name: string }, b: { rank: number; name: string }) =>
      b.rank - a.rank || a.name.localeCompare(b.name))
    .slice(0, TOP_TAGS);

  const { data: memRows, error: memErr } = await supabase
    .from("media_realm_membership")
    .select("realm,weight")
    .eq("media_type", mediaType)
    .eq("media_id", mediaId)
    .order("weight", { ascending: false });
  if (memErr) throw new Error(`membership: ${memErr.message}`);

  const b = base as any;
  return {
    media_type: mediaType,
    media_id: mediaId,
    title: b.title_english || b.title_romaji || null,
    genres: Array.isArray(b.genres) ? b.genres : [],
    tags,
    average_score: b.average_score ?? null,
    year: mediaType === "ANIME"
      ? (b.season_year ?? b.start_date_year ?? null)
      : (b.start_date_year ?? null),
    format: b.format ?? null,
    episodes: mediaType === "ANIME" ? (b.episodes ?? null) : null,
    chapters: mediaType === "MANGA" ? (b.chapters ?? null) : null,
    source: b.source ?? null,
    description_normalized: trim600(b.description_normalized),
    synopsis_enhanced: b.synopsis_enhanced_state === "ready" ? trim600(b.synopsis_enhanced) : null,
    membership: (memRows ?? []).map((r: any) => ({ realm: r.realm, weight: r.weight })),
  };
}

function buildPrompt(item: WorkItem, realmNames: string[]): { system: string; user: string } {
  const system =
    'Return ONLY a JSON object. Example shape: {"realms":[{"realm":"quiet-melancholy","weight":0.8}],"tone":["melancholic","quiet"],"register":"general","pacing":"slow-burn","confidence":0.82,"descriptor":"...100-600 chars..."}. tone MUST be a JSON array of 1-3 strings. No markdown.';

  const synopsis = item.synopsis_enhanced || item.description_normalized || "";
  const user = [
    "You write Kuro editorial descriptors for anime/manga.",
    "Voice: quiet, adult, specific. 1-2 sentences: what it IS and who it's for, in realm language.",
    "Banned: 'This anime/manga is about', genre laundry lists, hype words, spoilers beyond the synopsis.",
    "Use tags + current membership as evidence; confirm or gently correct realms. Be honest about confidence.",
    `Allowed realms (use exact slugs): ${realmNames.join(", ")}`,
    `Allowed tone words (exact): ${[...TONE_VOCAB].join(", ")}`,
    `register one of: ${[...REGISTERS].join(", ")}`,
    `pacing one of: ${[...PACINGS].join(", ")}`,
    "",
    `Title: ${sanitizeForLLM(item.title ?? "")}`,
    `Type: ${item.media_type} | format: ${item.format ?? "?"} | year: ${item.year ?? "?"} | score: ${item.average_score ?? "?"}`,
    `Genres: ${item.genres.join(", ")}`,
    `Top tags: ${item.tags.map((t) => `${t.name}(${t.rank})`).join(", ")}`,
    `Current membership: ${JSON.stringify(item.membership.slice(0, 4))}`,
    `Synopsis: ${sanitizeForLLM(synopsis)}`,
  ].join("\n");

  return { system, user };
}

async function callGroq(
  apiKey: string,
  model: string,
  system: string,
  user: string,
): Promise<string> {
  // Fail-fast on 429 — do NOT sleep inside the edge request. Supabase Functions
  // idle-timeout is 150s; sleeping here caused IDLE_TIMEOUT 504s while the Mac
  // worker already owns cool-down. Transient empty responses get one short retry.
  let lastErr = "Groq failed";
  for (let attempt = 0; attempt < 2; attempt++) {
    const res = await fetch("https://api.groq.com/openai/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model,
        temperature: 0.3,
        max_tokens: 700,
        messages: [
          { role: "system", content: system },
          { role: "user", content: user },
        ],
      }),
    });
    const body = await res.json().catch(() => null);
    if (res.status === 429) {
      throw new Error(`Groq HTTP 429: ${JSON.stringify(body)?.slice(0, 220)}`);
    }
    if (!res.ok) {
      throw new Error(`Groq HTTP ${res.status}: ${JSON.stringify(body)?.slice(0, 300)}`);
    }
    const content = body?.choices?.[0]?.message?.content;
    if (typeof content === "string" && content.trim()) return content;
    lastErr = "Groq returned empty content";
    await new Promise((r) => setTimeout(r, 800));
  }
  throw new Error(lastErr);
}

async function generateOne(
  supabase: SupabaseClient,
  groqKey: string,
  groqModel: string,
  modelId: string,
  realmNames: Set<string>,
  mediaType: MediaType,
  mediaId: number,
): Promise<DescriptorRow> {
  const item = await loadWorkItem(supabase, mediaType, mediaId);
  const { system, user } = buildPrompt(item, [...realmNames].sort());

  let lastErrors: string[] = [];
  for (let attempt = 0; attempt < 2; attempt++) {
    const nudge = attempt === 0
      ? user
      : `${user}\n\nPrevious output failed validation: ${lastErrors.join("; ")}. Return ONLY valid JSON matching the schema.`;
    let raw: string;
    try {
      raw = await callGroq(groqKey, groqModel, system, nudge);
    } catch (e) {
      // Propagate rate-limits immediately (no validation retry burn).
      throw e;
    }
    let parsed: Record<string, unknown>;
    try {
      parsed = extractJsonObject(raw) as Record<string, unknown>;
    } catch (e) {
      lastErrors = [(e as Error).message];
      continue;
    }
    const result = validateDescriptor(mediaType, mediaId, parsed, realmNames, modelId);
    if (result.ok) return result.row;
    lastErrors = result.errors;
  }
  throw new Error(`validation failed after retry: ${lastErrors.join("; ")}`);
}

async function upsertRows(supabase: SupabaseClient, rows: DescriptorRow[]): Promise<void> {
  if (rows.length === 0) return;
  for (let i = 0; i < rows.length; i += 100) {
    const chunk = rows.slice(i, i + 100);
    const { error } = await supabase.rpc("upsert_media_realm_llm", { p_rows: chunk });
    if (error) throw new Error(`upsert: ${error.message}`);
  }
}

async function fetchPending(
  supabase: SupabaseClient,
  limit: number,
): Promise<Array<{ media_type: MediaType; media_id: number }>> {
  const { data, error } = await supabase
    .from("media_realm_llm_pending")
    .select("media_type,media_id")
    .order("popularity", { ascending: false })
    .order("media_type", { ascending: true })
    .order("media_id", { ascending: true })
    .limit(limit);
  if (error) throw new Error(`pending: ${error.message}`);
  return (data ?? []) as Array<{ media_type: MediaType; media_id: number }>;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-import-secret",
      },
    });
  }

  const importSecret = Deno.env.get("IMPORT_SECRET");
  const reqSecret = req.headers.get("x-import-secret");
  if (!importSecret || reqSecret !== importSecret) {
    return json({ error: "Unauthorized" }, 401);
  }

  const groqKey = Deno.env.get("GROQ_API_KEY");
  // Do NOT reuse GROQ_MODEL (concierge narration often uses gpt-oss, which
  // returns empty content on structured JSON). Prefer a dedicated realm model.
  const groqModel = Deno.env.get("GROQ_MODEL_REALM")
    || "llama-3.3-70b-versatile";
  if (!groqKey) return json({ error: "Missing GROQ_API_KEY" }, 500);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) return json({ error: "Missing Supabase env" }, 500);
  const supabase = createClient(supabaseUrl, serviceKey);

  const payload = await req.json().catch(() => ({} as Record<string, unknown>));
  const modelId = `groq-${groqModel}`;

  try {
    const realmNames = await loadRealmNames(supabase);

    if (payload.batch === true) {
      const limit = Math.min(
        BATCH_MAX,
        Math.max(1, Number.isFinite(Number(payload.limit)) ? Math.floor(Number(payload.limit)) : 10),
      );
      const pending = await fetchPending(supabase, limit);
      const results: Array<{ media_type: string; media_id: number; ok: boolean; error?: string }> = [];
      const rows: DescriptorRow[] = [];
      for (const p of pending) {
        try {
          const row = await generateOne(
            supabase,
            groqKey,
            groqModel,
            modelId,
            realmNames,
            p.media_type,
            p.media_id,
          );
          rows.push(row);
          results.push({ media_type: p.media_type, media_id: p.media_id, ok: true });
        } catch (e) {
          const msg = (e as Error).message?.slice(0, 300) || "failed";
          console.error(`[realm-describe] fail ${p.media_type}:${p.media_id}`, e);
          results.push({
            media_type: p.media_type,
            media_id: p.media_id,
            ok: false,
            error: msg,
          });
          // Stop batch on rate-limit so remaining titles aren't wasted burns.
          if (msg.includes("429") || /rate limit/i.test(msg)) break;
        }
      }
      // One upsert call per batch (≤25 rows) so the 600/hr RPC budget can drain ~15k/hr.
      if (rows.length > 0) await upsertRows(supabase, rows);
      return json({
        success: true,
        batch: true,
        attempted: results.length,
        ok: results.filter((r) => r.ok).length,
        failed: results.filter((r) => !r.ok).length,
        results,
      });
    }

    const mediaType = payload.media_type;
    const mediaId = Number(payload.media_id);
    if (mediaType !== "ANIME" && mediaType !== "MANGA") {
      return json({ error: "media_type must be ANIME or MANGA" }, 400);
    }
    if (!Number.isInteger(mediaId) || mediaId < 1) {
      return json({ error: "media_id must be a positive integer" }, 400);
    }

    const row = await generateOne(
      supabase,
      groqKey,
      groqModel,
      modelId,
      realmNames,
      mediaType,
      mediaId,
    );
    await upsertRows(supabase, [row]);
    return json({ success: true, descriptor: row });
  } catch (e) {
    console.error("[realm-describe]", e);
    const msg = (e as Error).message?.slice(0, 500) || "failed";
    const status = msg.includes("429") || /rate limit/i.test(msg) ? 429 : 500;
    return json({ error: msg }, status);
  }
});
