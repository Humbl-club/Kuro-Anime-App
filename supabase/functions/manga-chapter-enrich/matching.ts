// Deterministic identity matching for manga-chapter-enrich.
// Title and candidate selection only: no fetch and no Supabase.
// Scores, confidence floors, and collision tie-breaks are the moved rules.
import { normalizeText } from "../_shared/normalization.ts";

export const DEFAULT_TITLE_SIMILARITY_FLOOR = 0.85;
export const COLLISION_TIEBREAK_MIN_SCORE = 0.82;
export const COLLISION_TIEBREAK_MIN_MARGIN = 0.03;
const COLLISION_ENGLISH_HIGH_SIM = 0.93;
const COLLISION_ENGLISH_MED_SIM = 0.86;

export type MappingMethod = "al_link" | "mal_link" | "title_strict" | "title_fuzzy";
export type MatcherMode = "strict" | "fuzzy_v2";

export interface CandidateRow {
  id: number;
  anilist_id: number | null;
  mal_id: number | null;
  title_english: string | null;
  title_romaji: string | null;
  title_native: string | null;
  title_synonyms: string[] | null;
  status: string | null;
  chapters: number | null;
  last_synced_at: string | null;
  chapter_row_count: number;
  priority_class: number;
}

export interface MangaDexManga {
  id: string;
  attributes?: {
    title?: Record<string, string>;
    altTitles?: Array<Record<string, string>>;
    links?: Record<string, string>;
  };
}

export interface MappingResolution {
  mapped: boolean;
  method?: MappingMethod;
  confidence?: number;
  mangaDexId?: string;
  rejectedMangaDexIds?: string[];
  providerUrl?: string;
  queryTitle?: string | null;
  reason?: string;
  sample?: unknown[];
}

export interface TitleMatchMetrics {
  skipped_ambiguous: number;
  skipped_low_confidence: number;
  fuzzy_attempted: number;
  fuzzy_auto_mapped: number;
}

export interface FuzzyCandidateScore {
  manga: MangaDexManga;
  score: number;
  titleSimilarity: number;
  tokenOverlap: number;
  aliasExact: number;
  hardConflict: boolean;
}

export interface CollisionCandidateScore extends FuzzyCandidateScore {
  integerChapterCoverage: number;
  integerChapterCoverageScore: number;
  editionPenalty: number;
  languagePenalty: number;
  englishTitleSimilarity: number;
  englishTitleBoost: number;
}

export function primaryTitle(candidate: CandidateRow): string {
  return candidate.title_english
    ?? candidate.title_romaji
    ?? candidate.title_native
    ?? "Unknown title";
}

export function allCandidateTitles(candidate: CandidateRow): string[] {
  const raw = [
    candidate.title_english,
    candidate.title_romaji,
    candidate.title_native,
    ...(candidate.title_synonyms ?? []),
  ];
  return Array.from(
    new Set(
      raw
        .map((value) => String(value ?? "").trim())
        .filter((value) => value.length > 0),
    ),
  );
}

export function normalizeLinkedExternalId(value: string | undefined): string | null {
  if (!value) return null;
  const digits = String(value).match(/\d+/);
  return digits?.[0] ?? null;
}

function normalizeStrictTitle(value: string): string {
  return normalizeText(value).toLowerCase().replace(/\s+/g, " ").trim();
}

export function preferredMangaDexTitle(item: MangaDexManga): string {
  const titles = item.attributes?.title;
  if (!titles) return item.id;
  return titles.en
    ?? titles["en-us"]
    ?? Object.values(titles)[0]
    ?? item.id;
}

export function mangaDexNormalizedTitles(item: MangaDexManga): string[] {
  const values: string[] = [];
  const title = item.attributes?.title ?? {};
  values.push(...Object.values(title));
  const altTitles = item.attributes?.altTitles ?? [];
  for (const alt of altTitles) values.push(...Object.values(alt));

  return Array.from(
    new Set(
      values
        .map((value) => normalizeStrictTitle(value))
        .filter((value) => value.length > 0),
      ),
  );
}

function mangaDexEnglishTitles(item: MangaDexManga): string[] {
  const values: string[] = [];
  const title = item.attributes?.title ?? {};
  for (const [lang, value] of Object.entries(title)) {
    if (lang.toLowerCase().startsWith("en")) values.push(value);
  }

  const altTitles = item.attributes?.altTitles ?? [];
  for (const alt of altTitles) {
    for (const [lang, value] of Object.entries(alt)) {
      if (lang.toLowerCase().startsWith("en")) values.push(value);
    }
  }

  return Array.from(
    new Set(
      values
        .map((value) => normalizeStrictTitle(value))
        .filter((value) => value.length > 0),
    ),
  );
}

export function chooseEnglishPreferredCollisionCandidate(
  candidates: CollisionCandidateScore[],
): CollisionCandidateScore | null {
  if (candidates.length === 0) return null;

  // Prefer a strong English-title match when available, but avoid edition variants.
  const strongEnglish = candidates
    .filter((row) => row.englishTitleSimilarity >= COLLISION_ENGLISH_HIGH_SIM && row.editionPenalty === 0)
    .sort((a, b) => b.score - a.score);
  if (strongEnglish.length > 0) return strongEnglish[0];

  const mediumEnglish = candidates
    .filter((row) => row.englishTitleSimilarity >= COLLISION_ENGLISH_MED_SIM && row.editionPenalty === 0)
    .sort((a, b) => b.score - a.score);
  if (mediumEnglish.length > 0) return mediumEnglish[0];

  return null;
}

function computeEditionPenalty(manga: MangaDexManga): number {
  const haystack = [
    preferredMangaDexTitle(manga),
    ...mangaDexNormalizedTitles(manga),
  ].join(" ").toLowerCase();
  const markers = [
    "webtoon version",
    "oneshot",
    "one shot",
    "promo",
    "pilot",
  ];
  return markers.some((marker) => haystack.includes(marker)) ? 0.08 : 0;
}

function computeLanguageMismatchPenalty(candidate: CandidateRow, manga: MangaDexManga): number {
  const localPrimary = normalizeStrictTitle(primaryTitle(candidate));
  const remotePrimary = normalizeStrictTitle(preferredMangaDexTitle(manga));
  if (!localPrimary || !remotePrimary) return 0;
  return jaroWinkler(localPrimary, remotePrimary) < 0.75 ? 0.05 : 0;
}

function computeBestEnglishTitleSimilarity(candidate: CandidateRow, manga: MangaDexManga): number {
  const localEnglish = normalizeStrictTitle(candidate.title_english ?? "");
  if (!localEnglish) return 0;

  const remoteEnglish = mangaDexEnglishTitles(manga);
  if (remoteEnglish.length === 0) return 0;

  let best = 0;
  for (const title of remoteEnglish) {
    const similarity = jaroWinkler(localEnglish, title);
    if (similarity > best) best = similarity;
  }
  return best;
}

function computeEnglishTitleBoost(similarity: number): number {
  if (similarity >= COLLISION_ENGLISH_HIGH_SIM) return 0.09;
  if (similarity >= COLLISION_ENGLISH_MED_SIM) return 0.05;
  return 0;
}

export function scoreFuzzyCandidates(candidate: CandidateRow, candidates: MangaDexManga[]): FuzzyCandidateScore[] {
  const candidateTitles = allCandidateTitles(candidate);
  const candidateTitleSet = new Set(
    candidateTitles.map((title) => normalizeStrictTitle(title)).filter((title) => title.length > 0),
  );
  const candidateTokenSet = tokensFromTitles(candidateTitles);

  return candidates.map((manga) => {
    const dexTitles = mangaDexNormalizedTitles(manga);
    const dexTitleSet = new Set(dexTitles);
    const dexTokenSet = tokensFromNormalizedTitles(dexTitles);
    const titleSimilarity = computeBestTitleSimilarity(candidateTitles, dexTitles);
    const tokenOverlap = jaccardSets(candidateTokenSet, dexTokenSet);
    const aliasExact = hasExactAlias(candidateTitleSet, dexTitleSet) ? 1 : 0;
    const hardConflict = evaluateHardConflict(candidate, manga);
    const score = (0.55 * titleSimilarity) + (0.30 * tokenOverlap) + (0.15 * aliasExact);
    return {
      manga,
      score,
      titleSimilarity,
      tokenOverlap,
      aliasExact,
      hardConflict,
    };
  });
}

function hasExactAlias(left: Set<string>, right: Set<string>): boolean {
  for (const key of left) {
    if (right.has(key)) return true;
  }
  return false;
}

export function evaluateHardConflict(candidate: CandidateRow, manga: MangaDexManga): boolean {
  const linkedAl = normalizeLinkedExternalId(manga.attributes?.links?.al);
  const linkedMal = normalizeLinkedExternalId(manga.attributes?.links?.mal);
  const localAl = candidate.anilist_id ? String(candidate.anilist_id) : null;
  const localMal = candidate.mal_id ? String(candidate.mal_id) : null;

  if (localAl && linkedAl && linkedAl !== localAl) return true;
  if (localMal && linkedMal && linkedMal !== localMal) return true;
  return false;
}

export function computeBestTitleSimilarity(candidateTitles: string[], dexNormalizedTitles: string[]): number {
  if (candidateTitles.length === 0 || dexNormalizedTitles.length === 0) return 0;
  let best = 0;
  for (const candidateTitle of candidateTitles) {
    const normalizedCandidate = normalizeStrictTitle(candidateTitle);
    if (!normalizedCandidate) continue;
    for (const dexTitle of dexNormalizedTitles) {
      const similarity = jaroWinkler(normalizedCandidate, dexTitle);
      if (similarity > best) best = similarity;
    }
  }
  return best;
}

function tokensFromTitles(titles: string[]): Set<string> {
  return tokensFromNormalizedTitles(titles.map((title) => normalizeStrictTitle(title)));
}

function tokensFromNormalizedTitles(titles: string[]): Set<string> {
  const tokens = new Set<string>();
  for (const title of titles) {
    const normalized = String(title ?? "").trim();
    if (!normalized) continue;
    for (const token of normalized.split(" ")) {
      if (token.length >= 2) tokens.add(token);
    }
  }
  return tokens;
}

function jaccardSets(left: Set<string>, right: Set<string>): number {
  if (left.size === 0 || right.size === 0) return 0;
  let intersection = 0;
  for (const value of left) {
    if (right.has(value)) intersection += 1;
  }
  const union = left.size + right.size - intersection;
  if (union <= 0) return 0;
  return intersection / union;
}

function jaroWinkler(a: string, b: string): number {
  if (a === b) return 1;
  if (!a || !b) return 0;
  const jaro = jaroSimilarity(a, b);
  const prefixLength = commonPrefixLength(a, b, 4);
  const scalingFactor = 0.1;
  return jaro + (prefixLength * scalingFactor * (1 - jaro));
}

function jaroSimilarity(a: string, b: string): number {
  const aLen = a.length;
  const bLen = b.length;
  if (aLen === 0 && bLen === 0) return 1;
  if (aLen === 0 || bLen === 0) return 0;

  const matchDistance = Math.max(0, Math.floor(Math.max(aLen, bLen) / 2) - 1);
  const aMatches = new Array<boolean>(aLen).fill(false);
  const bMatches = new Array<boolean>(bLen).fill(false);

  let matches = 0;
  for (let i = 0; i < aLen; i += 1) {
    const start = Math.max(0, i - matchDistance);
    const end = Math.min(i + matchDistance + 1, bLen);
    for (let j = start; j < end; j += 1) {
      if (bMatches[j]) continue;
      if (a[i] !== b[j]) continue;
      aMatches[i] = true;
      bMatches[j] = true;
      matches += 1;
      break;
    }
  }

  if (matches === 0) return 0;

  let transpositions = 0;
  let k = 0;
  for (let i = 0; i < aLen; i += 1) {
    if (!aMatches[i]) continue;
    while (!bMatches[k]) k += 1;
    if (a[i] !== b[k]) transpositions += 1;
    k += 1;
  }

  return (
    (matches / aLen) +
    (matches / bLen) +
    ((matches - (transpositions / 2)) / matches)
  ) / 3;
}

function commonPrefixLength(a: string, b: string, maxLength: number): number {
  const limit = Math.min(maxLength, a.length, b.length);
  let length = 0;
  while (length < limit && a[length] === b[length]) {
    length += 1;
  }
  return length;
}

/** Collision score once chapter coverage counts are already known. The weights are unchanged. */
export function applyCollisionCoverage(
  candidate: CandidateRow,
  base: FuzzyCandidateScore[],
  coverageValues: number[],
): CollisionCandidateScore[] {
  const maxCoverage = Math.max(1, ...coverageValues);
  return base.map((row, index) => {
    const coverage = coverageValues[index] ?? 0;
    const coverageScore = Math.min(1, coverage / maxCoverage);
    const editionPenalty = computeEditionPenalty(row.manga);
    const languagePenalty = computeLanguageMismatchPenalty(candidate, row.manga);
    const englishTitleSimilarity = computeBestEnglishTitleSimilarity(candidate, row.manga);
    const englishTitleBoost = computeEnglishTitleBoost(englishTitleSimilarity);
    const score = (
      (0.45 * row.titleSimilarity) +
      (0.18 * row.tokenOverlap) +
      (0.29 * coverageScore) +
      (0.08 * row.aliasExact) +
      englishTitleBoost
    ) - editionPenalty - languagePenalty;
    return {
      ...row,
      integerChapterCoverage: coverage,
      integerChapterCoverageScore: coverageScore,
      editionPenalty,
      languagePenalty,
      englishTitleSimilarity,
      englishTitleBoost,
      score,
    };
  });
}

/**
 * Strict and fuzzy title selection for rows already in hand.
 * No network and no database. External-id collisions stay with the run,
 * because those can consult alias memory and chapter coverage.
 */
export function selectTitleMatch(args: {
  candidate: CandidateRow;
  results: MangaDexManga[];
  queryTitles: string[];
  matcherMode: MatcherMode;
  minConfidence: number;
  minMargin: number;
  sample: unknown[];
  metrics: TitleMatchMetrics;
}): MappingResolution {
  const { candidate, results, queryTitles, matcherMode, metrics, sample } = args;
  const payload = { minConfidence: args.minConfidence, minMargin: args.minMargin };

  if (matcherMode === "strict") {
    const candidateTitleSet = new Set(
      queryTitles
        .map((title) => normalizeStrictTitle(title))
        .filter((title) => title.length > 0),
    );
    const strictMatches = results.filter((item) => {
      const dexTitles = mangaDexNormalizedTitles(item);
      return dexTitles.some((title) => candidateTitleSet.has(title));
    });

    if (strictMatches.length === 1) {
      return {
        mapped: true,
        method: "title_strict",
        confidence: 0.92,
        mangaDexId: strictMatches[0].id,
        providerUrl: `https://mangadex.org/title/${strictMatches[0].id}`,
        queryTitle: queryTitles[0],
        sample,
      };
    }
    if (strictMatches.length > 1) {
      metrics.skipped_ambiguous += 1;
      return { mapped: false, queryTitle: queryTitles[0], reason: "ambiguous_title_strict", sample };
    }

    metrics.skipped_low_confidence += 1;
    return { mapped: false, queryTitle: queryTitles[0], reason: "no_confident_match", sample };
  }

  metrics.fuzzy_attempted += 1;
  const scored = scoreFuzzyCandidates(candidate, results);
  const viable = scored.filter((row) => !row.hardConflict);

  if (viable.length === 0) {
    metrics.skipped_low_confidence += 1;
    return { mapped: false, queryTitle: queryTitles[0], reason: "hard_conflict", sample };
  }

  const sorted = viable.sort((a, b) => b.score - a.score);
  const top = sorted[0];
  const second = sorted[1];
  const margin = second ? top.score - second.score : 1;

  if (top.titleSimilarity < DEFAULT_TITLE_SIMILARITY_FLOOR) {
    metrics.skipped_low_confidence += 1;
    return { mapped: false, queryTitle: queryTitles[0], reason: "title_similarity_low", sample };
  }
  if (top.score < payload.minConfidence) {
    metrics.skipped_low_confidence += 1;
    return { mapped: false, queryTitle: queryTitles[0], reason: "fuzzy_score_low", sample };
  }
  if (margin < payload.minMargin) {
    metrics.skipped_ambiguous += 1;
    return { mapped: false, queryTitle: queryTitles[0], reason: "fuzzy_margin_low", sample };
  }

  metrics.fuzzy_auto_mapped += 1;
  return {
    mapped: true,
    method: "title_fuzzy",
    confidence: Math.min(0.98, Math.max(0.90, Number(top.score.toFixed(3)))),
    mangaDexId: top.manga.id,
    providerUrl: `https://mangadex.org/title/${top.manga.id}`,
    queryTitle: queryTitles[0],
    sample,
  };
}
