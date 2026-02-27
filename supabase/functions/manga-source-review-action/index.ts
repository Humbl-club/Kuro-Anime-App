import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type ReviewAction = "approve" | "reject";

interface ReviewActionPayload {
  reviewId?: number;
  action?: ReviewAction;
  mangaDexId?: string | null;
  triggerEnrich?: boolean;
  languages?: string[];
  includeFallbackAllLanguages?: boolean;
  timeBudgetMs?: number;
}

interface ReviewRow {
  id: number;
  provider: string;
  manga_id: number | null;
  query_title: string | null;
  candidate_payload: unknown;
  reason: string;
  status: string;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders() });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const importSecret = Deno.env.get("IMPORT_SECRET");
  const requestSecret = req.headers.get("x-import-secret");
  if (!importSecret || requestSecret !== importSecret) {
    return json({ error: "Unauthorized" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: "Server misconfigured" }, 500);
  }

  const payload = await req.json().catch(() => ({} as ReviewActionPayload));
  const reviewId = Number(payload.reviewId);
  if (!Number.isFinite(reviewId) || reviewId <= 0) {
    return json({ error: "reviewId must be a positive integer" }, 400);
  }

  const action: ReviewAction = payload.action === "reject" ? "reject" : "approve";
  const supabase = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });

  const { data: reviewRow, error: reviewError } = await supabase
    .from("manga_source_link_review")
    .select("id,provider,manga_id,query_title,candidate_payload,reason,status")
    .eq("id", reviewId)
    .maybeSingle();

  if (reviewError) {
    return json({ error: `Failed to read review row: ${reviewError.message}` }, 500);
  }
  if (!reviewRow) {
    return json({ error: "Review row not found" }, 404);
  }

  const review = reviewRow as ReviewRow;
  if (review.status !== "pending") {
    return json({ error: `Review row is already ${review.status}` }, 409);
  }

  if (action === "reject") {
    const { error: rejectError } = await supabase
      .from("manga_source_link_review")
      .update({ status: "rejected" })
      .eq("id", review.id);

    if (rejectError) {
      return json({ error: `Failed to reject review row: ${rejectError.message}` }, 500);
    }

    return json({
      success: true,
      action: "reject",
      reviewId: review.id,
      status: "rejected",
    });
  }

  if (!review.manga_id) {
    return json({ error: "Review row has no manga_id; cannot approve" }, 400);
  }

  const mangaDexId = resolveApprovedMangaDexId(payload.mangaDexId, review.candidate_payload);
  if (!mangaDexId) {
    return json({
      error: "Ambiguous candidates. Provide mangaDexId explicitly to approve this row.",
      reviewId: review.id,
    }, 400);
  }

  const providerUrl = `https://mangadex.org/title/${mangaDexId}`;
  const { error: upsertError } = await supabase
    .from("manga_source_links")
    .upsert(
      {
        manga_id: review.manga_id,
        provider: "mangadex",
        provider_media_id: mangaDexId,
        provider_url: providerUrl,
        mapping_method: "review_approved",
        confidence: 1.0,
        status: "active",
      },
      { onConflict: "manga_id,provider" },
    );

  if (upsertError) {
    return json({ error: `Failed to upsert approved mapping: ${upsertError.message}` }, 500);
  }

  const { error: approveError } = await supabase
    .from("manga_source_link_review")
    .update({ status: "approved" })
    .eq("id", review.id);

  if (approveError) {
    return json({ error: `Mapping saved but review status update failed: ${approveError.message}` }, 500);
  }

  const triggerEnrich = payload.triggerEnrich ?? true;
  let enrichResult: Record<string, unknown> | null = null;

  if (triggerEnrich) {
    enrichResult = await triggerImmediateEnrich({
      supabaseUrl,
      serviceRoleKey,
      importSecret,
      mangaId: review.manga_id,
      languages: normalizeLanguages(payload.languages),
      includeFallbackAllLanguages: payload.includeFallbackAllLanguages ?? true,
      timeBudgetMs: clampTimeBudget(payload.timeBudgetMs),
    });
  }

  return json({
    success: true,
    action: "approve",
    reviewId: review.id,
    mangaId: review.manga_id,
    mangaDexId,
    enrich: enrichResult,
  });
});

function resolveApprovedMangaDexId(
  explicitId: string | null | undefined,
  candidatePayload: unknown,
): string | null {
  const normalizedExplicit = normalizeMangaDexId(explicitId);
  if (normalizedExplicit) return normalizedExplicit;

  const payload = (candidatePayload ?? {}) as Record<string, unknown>;
  const sample = Array.isArray(payload.sample) ? payload.sample : [];
  const ids = Array.from(
    new Set(
      sample
        .map((row) => {
          const record = (row ?? {}) as Record<string, unknown>;
          return normalizeMangaDexId(record.id as string | null | undefined);
        })
        .filter((id): id is string => Boolean(id)),
    ),
  );

  return ids.length === 1 ? ids[0] : null;
}

function normalizeMangaDexId(raw: string | null | undefined): string | null {
  const value = String(raw ?? "").trim();
  if (!value) return null;
  if (!/^[0-9a-fA-F-]{16,}$/.test(value)) return null;
  return value.toLowerCase();
}

function normalizeLanguages(input?: string[]): string[] {
  const source = Array.isArray(input) ? input : ["en", "de"];
  const normalized = source
    .map((value) => String(value ?? "").trim().toLowerCase())
    .map((value) => value.slice(0, 2))
    .filter((value) => value.length === 2);
  const unique = Array.from(new Set(normalized));
  return unique.length > 0 ? unique : ["en", "de"];
}

function clampTimeBudget(value: number | undefined): number {
  if (typeof value !== "number" || Number.isNaN(value)) return 45_000;
  return Math.max(8_000, Math.min(120_000, Math.trunc(value)));
}

async function triggerImmediateEnrich(args: {
  supabaseUrl: string;
  serviceRoleKey: string;
  importSecret: string;
  mangaId: number;
  languages: string[];
  includeFallbackAllLanguages: boolean;
  timeBudgetMs: number;
}) {
  const response = await fetch(`${args.supabaseUrl}/functions/v1/manga-chapter-enrich`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${Deno.env.get("SUPABASE_ANON_KEY") ?? args.serviceRoleKey}`,
      "x-import-secret": args.importSecret,
    },
    body: JSON.stringify({
      limit: 1,
      scheduleSafe: false,
      timeBudgetMs: args.timeBudgetMs,
      languages: args.languages,
      includeFallbackAllLanguages: args.includeFallbackAllLanguages,
      forceMangaId: args.mangaId,
      lockTtlSeconds: 900,
    }),
  });

  const raw = await response.text();
  let parsed: unknown = null;
  try {
    parsed = JSON.parse(raw);
  } catch {
    parsed = null;
  }

  return {
    ok: response.ok,
    status: response.status,
    body: parsed ?? raw.slice(0, 800),
  };
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(),
      "Content-Type": "application/json",
    },
  });
}

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-import-secret",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
}
