/**
 * Request handling and the recommendation run of `concierge-recommend` (F51, 2026-10-05), separated from
 * index.ts so the production flow runs against an injected client, fetch and clock in Deno tests.
 *
 * Module map: router.ts (deterministic primary routing + German vibe folding), rail_policy.ts (item
 * building, secondary ranking/choice), catalog_repository.ts (every catalog/cache/flag read, mode cache,
 * run logs, retrieve-assist seed), narration.ts (Groq blurbs behind kill switch + budgets),
 * curated_copy.ts (EN/DE rail copy, curator note). Groq is narration only: nothing here routes or
 * selects on an LLM answer.
 *
 * Contract (unchanged unless marked): POST only (405). Rate limiter kind `recommend` checked before auth.
 *   CHANGED (F32): the limiter is a required gate (_shared/rate_limit_gate.ts): denial 429 + Retry-After;
 *   an error, missing or unrecognised result (or a rejected limiter call) 503 + Retry-After with no catalog,
 *   search, cache or narration work. Unauthenticated -> 401. Body `{ text (<= 5000, else 400), scope?,
 *   limit? (3..20, default 8), narrate?, debugNarration? }`. Response `{ success, locale, curatorNote,
 *   categories, modes[2], sets[2], items (flattened, deduplicated), message, narrated, constraints?
 *   (only when a constraint was found), assist? (only when rag_assist_v1 is on), narrationError? (only
 *   with debugNarration) }`; any thrown error -> 500 `{ error: "Internal error", message }`.
 * Run state with a request lifetime lives in one `RunState` (seed query/override, which the bare-title
 * route and the retrieve-assist fallback may set, and the assist flags). Request-count invariants kept:
 * user top genres read once per run; mode cache saved after routing and again only when the chosen
 * secondary differs; at most 5 secondary candidates built in parallel, each rail built once (F73: the
 * fallback secondary only when there is no candidate). CHANGED (F76): a non-finite `limit` is 8.
 */
import { interpretRateLimit, rateLimitBlockedResponse } from "../_shared/rate_limit_gate.ts";
import { type CatalogRepository, type SupabaseLike, supabaseCatalogRepository } from "./catalog_repository.ts";
import { buildCuratorNote, curatedCopyForMode, emptyRecommendationMessage, type Locale } from "./curated_copy.ts";
import {
  applyBlurbs,
  groqNarrate,
  NARRATION_MAX_ITEMS,
  type NarrationItem,
  narrateWithBudget,
  supabaseNarrationBudget,
} from "./narration.ts";
import {
  type BuiltRail,
  buildItemsFromRows,
  chooseSecondary,
  compileQuality,
  curatedFetchLimit,
  decisionFromRanking,
  diversifyItems,
  emptyMediaContext,
  evaluateSecondary,
  failedSecondary,
  filterByConstraints,
  mapCuratedRowToItem,
  mergeRail,
  mkPick,
  type ModePick,
  perTypeLimit,
  preferredSecondaryIds,
  railIdFor,
  railTotals,
  rankSecondaryCandidates,
  type RailItem,
  type RouterDecision,
  type SecondaryCandidateEvaluation,
  secondaryContext,
} from "./rail_policy.ts";
import {
  anchorModes,
  type ConciergeMode,
  defaultModes,
  extractConstraints,
  inferCategories,
  inferGimmickTagIds,
  inferLanguage,
  inferMediaType,
  inferQualityFloor,
  inferRequiredGenres,
  inferSeedQuery,
  isClassicIntent,
  type MediaType,
  normalizePromptForCache,
  parseModesFromConfig,
  routePrimaryMode,
  type SeedOverride,
  uniq,
  type UserConstraints,
} from "./router.ts";

export interface RecommendPlatform {
  /** Client for this caller, or null when SUPABASE_URL / an API key env var is missing. */
  client(authHeader: string): SupabaseLike | null;
  /** Environment lookup (read per request): SUPABASE_URL, GROQ_API_KEY, GROQ_MODEL. */
  env(name: "SUPABASE_URL" | "GROQ_API_KEY" | "GROQ_MODEL"): string | undefined;
  /** HTTP transport for Groq and concierge-retrieve-assist. */
  fetch(url: string, init: RequestInit): Promise<Response>;
  /** Clock for the mode-cache TTL (ms since epoch). */
  now(): number;
}

function json(res: unknown, init: ResponseInit = {}) {
  return new Response(JSON.stringify(res), {
    ...init,
    headers: { "Content-Type": "application/json", ...(init.headers ?? {}) },
  });
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

function inferRequestMarket(req: Request): string {
  const cfCountry = req.headers.get("cf-ipcountry")?.trim().toUpperCase();
  if (cfCountry && /^[A-Z]{2}$/.test(cfCountry)) return cfCountry;

  const acceptLanguage = req.headers.get("accept-language") ?? "";
  const first = acceptLanguage.split(",")[0]?.trim() ?? "";
  const region = first.match(/-[A-Za-z]{2}\b/)?.[0]?.slice(1).toUpperCase();
  if (region && /^[A-Z]{2}$/.test(region)) return region;
  return "US";
}

function inferLocale(req: Request, market: string): Locale {
  const m = (market || "").trim().toUpperCase();
  if (["DE", "AT", "CH"].includes(m)) return "de";
  const acceptLanguage = (req.headers.get("accept-language") ?? "").trim().toLowerCase();
  if (acceptLanguage.startsWith("de")) return "de";
  return "en";
}

export async function handleRecommend(req: Request, platform: RecommendPlatform): Promise<Response> {
  try {
    if (req.method !== "POST") return json({ error: "Method not allowed" }, { status: 405 });

    const authHeader = req.headers.get("Authorization") ?? "";
    const supabaseUrl = platform.env("SUPABASE_URL");
    const client = platform.client(authHeader);
    if (!client || !supabaseUrl) {
      return json({ error: "Missing SUPABASE_URL or a Supabase API key env (SUPABASE_ANON_KEY or SUPABASE_SERVICE_ROLE_KEY)" }, { status: 500 });
    }

    // Auth + rate-limit in parallel (both use the same client).
    const ip = clientIp(req);
    const [rlResult, userResult] = await Promise.all([
      Promise.resolve(
        client.rpc("check_concierge_rate_limit", {
          p_kind: "recommend",
          p_ip: ip,
          p_window_seconds: null,
          p_max_user: null,
          p_max_ip: null,
        }),
      ).catch((error: unknown) => ({ data: null, error })),
      client.auth.getUser(),
    ]);

    const blocked = rateLimitBlockedResponse(interpretRateLimit(rlResult), json);
    if (blocked) return blocked;

    const userData = userResult.data;
    const userErr = userResult.error;
    if (userErr || !userData?.user) return json({ error: "Unauthorized" }, { status: 401 });

    const body = await req.json().catch(() => ({}));
    const text: string = String(body?.text ?? "");
    if (text.length > 5000) {
      return json({ error: "Text too long (max 5000 chars)" }, { status: 400 });
    }

    const repo = supabaseCatalogRepository({ client, supabaseUrl, authHeader, fetch: platform.fetch, now: platform.now });
    return json(
      await runRecommend(
        {
          text,
          scope: String(body?.scope ?? "both"),
          // F76: a limit that is not a finite number is the default 8 (before: NaN rails, empty items).
          limit: Number.isFinite(Number(body?.limit ?? 8)) ? Math.max(3, Math.min(20, Number(body?.limit ?? 8))) : 8,
          narrate: Boolean(body?.narrate ?? false),
          debugNarration: Boolean(body?.debugNarration ?? false),
          userId: userData.user.id,
          market: inferRequestMarket(req),
          locale: inferLocale(req, inferRequestMarket(req)),
        },
        {
          repo,
          narrationBudget: supabaseNarrationBudget(client),
          narrationProvider: (opts) => groqNarrate({ ...opts, fetch: platform.fetch }),
          groqApiKey: () => platform.env("GROQ_API_KEY"),
          groqModel: () => platform.env("GROQ_MODEL") ?? "openai/gpt-oss-20b",
        },
      ),
    );
  } catch (e) {
    const err = e as Error;
    return json({ error: "Internal error", message: err?.message ?? String(e) }, { status: 500 });
  }
}

export type RecommendRequest = {
  text: string;
  scope: string;
  limit: number;
  narrate: boolean;
  debugNarration: boolean;
  /** Verified JWT user (never the body). */
  userId: string;
  market: string;
  locale: Locale;
};

export type RecommendDeps = {
  repo: CatalogRepository;
  narrationBudget: ReturnType<typeof supabaseNarrationBudget>;
  narrationProvider: Parameters<typeof narrateWithBudget>[3];
  groqApiKey: () => string | undefined;
  groqModel: () => string;
};

/** Request-lifetime state written during the run (seed adoption, retrieval-assist outcome). */
type RunState = {
  seedQuery: string | null;
  seedOverride: SeedOverride | null;
  ragAssistUsed: boolean;
  ragSeedEntityId: string | null;
};

/** The deterministic recommendation run, then optional narration. Returns the response body. */
export async function runRecommend(r: RecommendRequest, deps: RecommendDeps) {
  const { text, userId, locale } = r;
  const { repo } = deps;

  const categories = inferCategories(text);
  const gimmickTagIds = inferGimmickTagIds(text);
  const requiredGenres = inferRequiredGenres(text);
  const constraints = extractConstraints(text);
  const userExcludedGenres = constraints.excluded_genres;
  const quality = inferQualityFloor(text);

  const allowGimmicks = gimmickTagIds.length > 0 || /\b(slime)\b/.test(text.toLowerCase());
  const lang = inferLanguage(text);
  const mediaType = inferMediaType(text, r.scope);
  const state: RunState = { seedQuery: inferSeedQuery(text), seedOverride: null, ragAssistUsed: false, ragSeedEntityId: null };

  // Config, tag mapping and editorial tag boosts are independent.
  const [conciergeCfg, focusTagIds, tagBoosts] = await Promise.all([
    repo.conciergeConfig(),
    repo.tagIdsForAnilistIds(gimmickTagIds),
    repo.editorialTagBoosts(),
  ]);

  const configuredModes = parseModesFromConfig(conciergeCfg);
  const modes = configuredModes.length ? configuredModes : defaultModes();
  // deno-lint-ignore no-explicit-any
  const tagBoostByTag = new Map<number, any>((tagBoosts ?? []).map((t: any) => [t.tag_id, t]));

  const modeById = new Map<string, ConciergeMode>(modes.map((m) => [m.id, m]));
  const { classicsMode, premiumMode } = anchorModes(modeById);
  const classicsId = classicsMode?.id ?? "classics_expanded";
  const anchors = { classicsId, premiumId: premiumMode?.id };

  const routerCfg = conciergeCfg?.router_llm ?? {};
  const cacheTtlDays = Number(routerCfg?.cache_ttl_days ?? 30);

  const ragAssistEnabled = await repo.featureFlagEnabled("rag_assist_v1", userId, r.market);
  const promptNorm = normalizePromptForCache(text);

  // Read once, awaited by ranking, rail diversification and the curator note.
  const userTopGenresPromise: Promise<string[]> = repo.userTopGenres(userId);

  const rankSecondary = async (primaryId: string) =>
    rankSecondaryCandidates({
      text,
      primaryId,
      modeById,
      classicsId,
      requiredGenres,
      userExcludedGenres,
      constraints,
      topGenres: await userTopGenresPromise,
    });

  // --- Mode decision: cache (prevents repeated spend and stabilizes routing) or the deterministic chain.
  const decideModes = async (): Promise<RouterDecision> => {
    const cached = await repo.loadModeCache(userId, promptNorm, cacheTtlDays);
    if (cached) {
      // Rehydrate ranked alternatives on cache hits so we do not lock users
      // into a stale single secondary rail for the full cache TTL window.
      const ranked = await rankSecondary(cached.primaryId);
      cached.secondaryCandidates = uniq([cached.secondaryId, ...ranked.map((x) => x.id)]).slice(0, 8);
      return cached;
    }
    // Deterministic primary chain (seed -> DB-verified bare title -> classic -> gateway -> hidden gems ->
    // strong genre -> scored fallback) lives in router.ts.
    const route = await routePrimaryMode(
      {
        text,
        seedQuery: state.seedQuery,
        mediaType,
        modeById,
        classicsId,
        premiumId: premiumMode?.id,
        requiredGenres,
        userExcludedGenres,
        constraints,
      },
      (query, mt) => repo.searchTitles(query, mt, 6),
    );
    if (route.bareSeed) {
      state.seedQuery = route.bareSeed.query;
      state.seedOverride = route.bareSeed.override;
    }
    const dec = decisionFromRanking({ ...route, usedLLM: false }, await rankSecondary(route.primaryId), anchors);
    await repo.saveModeCache(userId, promptNorm, dec, cacheTtlDays);
    return dec;
  };

  const decision = await decideModes();

  const modePicks: ModePick[] = [];
  const primaryMode = modeById.get(decision.primaryId) ?? null;
  const primaryCopy = curatedCopyForMode(locale, decision.primaryId, primaryMode?.title ?? decision.primaryId);
  modePicks.push(mkPick(decision.primaryId, primaryCopy.displayTitle, decision.primaryConfidence, decision.primaryReason));

  // --- Rail building (curated rail when configured, algorithmic fill/fallback, similar-to-seed).
  const both = (mt: MediaType) => mediaType === mt || mediaType === "BOTH";

  const fetchCurated = async (mode: ConciergeMode, total: number): Promise<RailItem[]> => {
    const avoidGenres = await userTopGenresPromise;
    // Fetch extra to compensate for post-filtering by user constraints.
    const perType = perTypeLimit(mediaType, curatedFetchLimit(total, constraints));
    const animeRid = railIdFor(mode, "ANIME");
    const mangaRid = railIdFor(mode, "MANGA");
    const [animeRows, mangaRows] = await Promise.all([
      both("ANIME") && animeRid ? repo.curatedRailCards(animeRid, perType) : [],
      both("MANGA") && mangaRid ? repo.curatedRailCards(mangaRid, perType) : [],
    ]);
    const a = diversifyItems(filterByConstraints(Array.isArray(animeRows) ? animeRows.map(mapCuratedRowToItem) : [], constraints), avoidGenres);
    const m = diversifyItems(filterByConstraints(Array.isArray(mangaRows) ? mangaRows.map(mapCuratedRowToItem) : [], constraints), avoidGenres);
    return mergeRail(mediaType, a, m, total);
  };

  const fetchSeedFromRag = async (): Promise<SeedOverride | null> => {
    if (!ragAssistEnabled || !state.seedQuery) return null;
    const ragFormat = constraints.format === "MOVIE" || constraints.format === "ONA" || constraints.format === "OVA" ? constraints.format : null;
    const seed = await repo.ragSeed({
      query: state.seedQuery,
      locale: lang,
      mediaType: mediaType === "BOTH" ? null : mediaType,
      excludedGenres: userExcludedGenres,
      format: ragFormat,
      yearMin: constraints.year_min,
      yearMax: constraints.year_max,
    });
    if (!seed) return null;
    state.ragAssistUsed = true;
    state.ragSeedEntityId = seed.entityId;
    return { mt: seed.mt, mediaId: seed.mediaId, title: seed.title };
  };

  const buildSimilarToSeedRail = async (total: number): Promise<BuiltRail> => {
    // Only build when we have a decent seed title.
    const pickSeed = async (mt: MediaType) => {
      const { data: seeds, error: seedErr } = await repo.searchTitles(state.seedQuery, mt, 6);
      if (seedErr || !Array.isArray(seeds) || seeds.length === 0) return null;
      const top = seeds[0];
      if ((top?.score ?? 0) < 0.35) return null;
      return { mt, mediaId: Number(top.media_id), title: String(top.title_raw ?? top.title ?? "").trim() };
    };

    const seed = state.seedOverride
      ? state.seedOverride
      : mediaType === "MANGA"
      ? await pickSeed("MANGA")
      : mediaType === "ANIME"
      ? await pickSeed("ANIME")
      : (await pickSeed("ANIME")) ?? (await pickSeed("MANGA"));
    const ragSeed = (!seed || !Number.isFinite(seed.mediaId) || seed.mediaId <= 0) ? await fetchSeedFromRag() : null;
    if (ragSeed) state.seedOverride = ragSeed;
    const effectiveSeed = state.seedOverride ?? seed;
    if (!effectiveSeed || !Number.isFinite(effectiveSeed.mediaId) || effectiveSeed.mediaId <= 0) {
      return { title: "Similar", items: [] };
    }

    const avoidGenres = await userTopGenresPromise;
    const perType = perTypeLimit(mediaType, total);
    const q = compileQuality(quality, null);
    const seedId = effectiveSeed.mediaId;
    const [animeRows, mangaRows] = await Promise.all([
      both("ANIME") ? repo.similarCandidates("ANIME", seedId, allowGimmicks) : [],
      both("MANGA") ? repo.similarCandidates("MANGA", seedId, allowGimmicks) : [],
    ]);
    const [ctxAnime, ctxManga] = await Promise.all([
      both("ANIME") ? repo.mediaContext("ANIME", animeRows.map((x) => x.media_id), tagBoostByTag) : emptyMediaContext(),
      both("MANGA") ? repo.mediaContext("MANGA", mangaRows.map((x) => x.media_id), tagBoostByTag) : emptyMediaContext(),
    ]);
    const opts = { limit: perType, requiredGenres, excludeGenres: userExcludedGenres, avoidGenres, quality: q, constraints };
    const a = both("ANIME") ? buildItemsFromRows("ANIME", animeRows, ctxAnime, opts) : [];
    const m = both("MANGA") ? buildItemsFromRows("MANGA", mangaRows, ctxManga, opts) : [];

    const title = effectiveSeed.title || state.seedQuery || "seed";
    return { title: `Similar to "${title}"`, items: mergeRail(mediaType, a, m, total) };
  };

  const buildAlgorithmicRail = async (mode: ConciergeMode | null, total: number): Promise<RailItem[]> => {
    const avoidGenres = await userTopGenresPromise;
    const perType = perTypeLimit(mediaType, total);
    const modeRequired = uniq([...(mode?.required_genres ?? []), ...requiredGenres]);
    const modeExcluded = uniq([...(mode?.exclude_genres ?? []), ...userExcludedGenres]);
    const q = compileQuality(quality, mode);
    const pCats = uniq([...categories, ...(mode?.required_genres ?? [])]);
    const cats = pCats.length ? pCats : (categories.length ? categories : null);

    const [animeRows, mangaRows] = await Promise.all([
      both("ANIME") ? repo.premiumCandidates("ANIME", cats, allowGimmicks, focusTagIds) : [],
      both("MANGA") ? repo.premiumCandidates("MANGA", cats, allowGimmicks, focusTagIds) : [],
    ]);
    const [ctxAnime, ctxManga] = await Promise.all([
      both("ANIME") ? repo.mediaContext("ANIME", animeRows.map((x) => x.media_id), tagBoostByTag) : emptyMediaContext(),
      both("MANGA") ? repo.mediaContext("MANGA", mangaRows.map((x) => x.media_id), tagBoostByTag) : emptyMediaContext(),
    ]);
    const opts = {
      limit: perType,
      requiredGenres: modeRequired,
      excludeGenres: modeExcluded,
      avoidGenres,
      classicYearMax: mode?.classic_year_max,
      quality: q,
      prioritizeClassicBoost: (mode?.id ?? "").includes("classic"),
      constraints,
    };
    const a = both("ANIME") ? buildItemsFromRows("ANIME", animeRows, ctxAnime, opts) : [];
    const m = both("MANGA") ? buildItemsFromRows("MANGA", mangaRows, ctxManga, opts) : [];
    return mergeRail(mediaType, a, m, total);
  };

  const buildRailItems = async (modeId: string, total: number): Promise<BuiltRail> => {
    if (modeId === "similar_to_seed") {
      return await buildSimilarToSeedRail(total);
    }
    const mode = modeById.get(modeId) ?? null;
    // Curated rail if configured; fall back to algorithmic if empty/unavailable.
    // If curated returns fewer than requested, fill the remainder algorithmically (still one-shot).
    if (mode?.rail_id) {
      try {
        const curated = await fetchCurated(mode, total);
        if (curated.length > 0) {
          if (curated.length >= total) return { title: mode.title, items: curated.slice(0, total) };

          const algo = await buildAlgorithmicRail(mode, total);
          const seen = new Set(curated.map((it: RailItem) => `${it.mediaType}|${it.mediaId}`));
          const filled = [...curated];
          for (const it of algo) {
            if (filled.length >= total) break;
            const k = `${it.mediaType}|${it.mediaId}`;
            if (seen.has(k)) continue;
            seen.add(k);
            filled.push(it);
          }
          return { title: mode.title, items: filled };
        }
      } catch {
        // ignore
      }
    }
    const items = await buildAlgorithmicRail(mode, total);
    return { title: mode?.title ?? modeId, items };
  };

  // --- Exactly 2 rails: primary + diversified secondary (no hard classics anchor).
  const totals = railTotals(r.limit);
  const explicitClassicIntent = isClassicIntent(text);
  const preferred = preferredSecondaryIds(decision, anchors, explicitClassicIntent);

  const primaryBuilt = await buildRailItems(decision.primaryId, totals.primaryTotal);
  const secCtx = secondaryContext(decision.primaryId, primaryBuilt.items, preferred, totals, classicsId, explicitClassicIntent);

  const secondaryCandidateResults: SecondaryCandidateEvaluation[] = await Promise.all(
    preferred.map(async (modeId): Promise<SecondaryCandidateEvaluation> => {
      try {
        const built = await buildRailItems(modeId, totals.secondaryTotal);
        return { modeId, built, eval: evaluateSecondary(modeId, built, secCtx) };
      } catch {
        return failedSecondary(modeId);
      }
    }),
  );

  // F73: the fallback secondary is built only when there is no candidate at all. Before, it was always
  // built first (usually `preferred[0]` a second time, and an error in that duplicate build failed the
  // whole request although the candidate build of the same mode is caught).
  const buildFallbackSecondary = async (): Promise<SecondaryCandidateEvaluation> => {
    const modeId = premiumMode?.id ?? classicsId;
    const built = await buildRailItems(modeId, totals.secondaryTotal);
    return { modeId, built, eval: evaluateSecondary(modeId, built, secCtx) };
  };
  const secondaryCandidates = secondaryCandidateResults.length > 0 ? secondaryCandidateResults : [await buildFallbackSecondary()];
  const chosen = chooseSecondary(secondaryCandidates, secCtx, promptNorm);
  const chosenSecondaryId = chosen.modeId;
  const chosenSecondaryBuilt = chosen.built;
  const chosenEval = chosen.eval;

  const secondaryMode = modeById.get(chosenSecondaryId) ?? null;
  const secondaryCopy = curatedCopyForMode(locale, chosenSecondaryId, secondaryMode?.title ?? chosenSecondaryBuilt.title);
  const secondaryConfidence = chosenEval.acceptable ? 0.82 : 0.64;
  const secondaryReason = chosenEval.acceptable ? "diversified-secondary" : "fallback-secondary";

  if (chosenSecondaryId !== decision.secondaryId) {
    await repo.saveModeCache(userId, promptNorm, {
      ...decision,
      secondaryId: chosenSecondaryId,
      secondaryCandidates: uniq([chosenSecondaryId, ...decision.secondaryCandidates]),
    }, cacheTtlDays);
  }

  modePicks.push(mkPick(chosenSecondaryId, secondaryCopy.displayTitle, secondaryConfidence, secondaryReason));

  const curatorNote = buildCuratorNote({
    locale,
    primaryModeId: decision.primaryId,
    primaryModeTitle: primaryMode?.title ?? primaryBuilt.title,
    constraints,
    ragUsed: state.ragAssistUsed,
    seedTitle: state.seedOverride?.title ?? null,
    avoidedGenres: await userTopGenresPromise,
  });

  // deno-lint-ignore no-explicit-any
  const sets: any[] = [
    {
      id: decision.primaryId,
      title: primaryCopy.displayTitle,
      internalTitle: primaryBuilt.title,
      displayTitle: primaryCopy.displayTitle,
      displaySubtitle: primaryCopy.displaySubtitle,
      curatorNote,
      locale,
      modeId: decision.primaryId,
      confidence: modePicks[0].confidence,
      reason: modePicks[0].reason,
      items: primaryBuilt.items,
    },
    {
      id: chosenSecondaryId,
      title: secondaryCopy.displayTitle,
      internalTitle: chosenSecondaryBuilt.title,
      displayTitle: secondaryCopy.displayTitle,
      displaySubtitle: secondaryCopy.displaySubtitle,
      curatorNote,
      locale,
      modeId: chosenSecondaryId,
      confidence: modePicks[1].confidence,
      reason: modePicks[1].reason,
      items: chosenSecondaryBuilt.items,
    },
  ];

  // Flatten for backwards compatibility + narration (same item objects as in sets[]).
  const allItems: RailItem[] = [];
  const seen = new Set<string>();
  for (const s of sets) {
    for (const it of (s?.items ?? [])) {
      const key = `${it.mediaType}|${it.mediaId}`;
      if (seen.has(key)) continue;
      seen.add(key);
      allItems.push(it);
    }
  }

  await repo.logRecommendRun({
    inputChars: text.length,
    itemsCount: allItems.length,
    secondaryItemsCount: chosenSecondaryBuilt.items.length,
    routerTelemetry: JSON.stringify({
      primary_mode_id: decision.primaryId,
      secondary_mode_id: chosenSecondaryId,
      secondary_candidates_count: preferred.length,
      secondary_overlap_ratio: Number(chosenEval.overlapRatio.toFixed(4)),
      secondary_overlap_count: chosenEval.overlapCount,
      secondary_item_count: chosenSecondaryBuilt.items.length,
      secondary_acceptable: chosenEval.acceptable,
    }),
  });

  // Backwards-compat: older clients can show the curator note in plain text.
  const message = sets.length === 0 ? emptyRecommendationMessage(locale) : curatorNote;

  // Optional narration (pure presentation layer): never changes which items are returned.
  const packed: NarrationItem[] = allItems.slice(0, NARRATION_MAX_ITEMS).map((it) => ({
    id: `${it.mediaType}|${it.mediaId}`,
    title: it.title,
    year: it.year,
    format: it.format,
    signals: Array.isArray(it.signals) ? it.signals : [],
  }));
  const narration = await narrateWithBudget(
    {
      requested: r.narrate,
      debug: r.debugNarration,
      apiKey: r.narrate ? deps.groqApiKey() : undefined,
      model: deps.groqModel(),
      lang,
      userText: text,
      globalBudgetConfig: conciergeCfg?.global_llm_budget ?? null,
    },
    packed,
    deps.narrationBudget,
    deps.narrationProvider,
  );
  applyBlurbs(allItems, narration.blurbs);

  return {
    success: true,
    locale,
    curatorNote,
    categories,
    modes: modePicks,
    sets,
    // Backwards compat: clients that only understand `items` still get a useful response.
    items: allItems,
    message,
    narrated: narration.narrated,
    // Constraint info for WhyThisSheet and debugging.
    constraints: constraintsBlock(constraints),
    assist: ragAssistEnabled
      ? {
        ragUsed: state.ragAssistUsed,
        seedEntityId: state.ragSeedEntityId ?? undefined,
      }
      : undefined,
    ...(r.debugNarration ? { narrationError: narration.error } : {}),
  };
}

function constraintsBlock(constraints: UserConstraints) {
  return constraints.why.length > 0
    ? {
      excluded_genres: constraints.excluded_genres.length > 0 ? constraints.excluded_genres : undefined,
      format: constraints.format ?? undefined,
      max_episodes: constraints.max_episodes ?? undefined,
      min_episodes: constraints.min_episodes ?? undefined,
      year_min: constraints.year_min ?? undefined,
      year_max: constraints.year_max ?? undefined,
      why: constraints.why,
    }
    : undefined;
}
