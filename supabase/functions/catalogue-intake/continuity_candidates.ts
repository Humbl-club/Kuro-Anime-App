import type { MuAnimeSpan } from "./map_mangaupdates.ts";

export type ContinuityMedium = "anime" | "manga";
export type ContinuitySectionKind = "main" | "side" | "adaptation";
export type ContinuityStatus = "pending" | "approved";

export type ResolvedLocalRelation = {
  relationType: "SEQUEL" | "PREQUEL" | "SIDE_STORY" | "SPIN_OFF" | "ADAPTATION" | "SOURCE" | string;
  sourceMediaType?: ContinuityMedium;
  sourceMediaId?: number;
  targetMediaType: ContinuityMedium;
  targetMediaId: number;
  year?: number | null;
  format?: string | null;
  note?: string | null;
};

export type SeriesCandidateRow = {
  root_media_type: ContinuityMedium;
  root_media_id: number;
  member_media_type: ContinuityMedium;
  member_media_id: number;
  section_kind: ContinuitySectionKind;
  ordinal: number;
  source_start_unit: number | null;
  source_end_unit: number | null;
  source_volume: number | null;
  raw_note: string | null;
  status: ContinuityStatus;
  auto_approvable: boolean;
};

export type ContinuityInput = {
  rootMediaType: ContinuityMedium;
  rootMediaId: number;
  relations: ResolvedLocalRelation[];
  adaptationSpan?: MuAnimeSpan | null;
};

const SIDE_FORMATS = new Set(["OVA", "ONA", "SPECIAL", "MUSIC"]);

function normalizeType(raw: string): string {
  return String(raw ?? "").trim().toUpperCase();
}

function keyOf(mediaType: ContinuityMedium, mediaId: number): string {
  return `${mediaType}:${mediaId}`;
}

function formatAdaptationNote(span: MuAnimeSpan | null | undefined): string | null {
  if (!span) return null;
  const parts = [span.rawStart, span.rawEnd].filter((p): p is string => Boolean(p && p.trim().length > 0));
  return parts.length > 0 ? parts.join(" -> ") : null;
}

/**
 * Builds deterministic, deduplicated `series_candidates` staging rows for a root title's
 * main sequel/prequel spine, side entries, and source/adaptation bridges.
 */
export function buildContinuityCandidates(input: ContinuityInput): SeriesCandidateRow[] {
  if (!Number.isInteger(input.rootMediaId) || input.rootMediaId < 1) {
    throw new Error("rootMediaId must be a positive integer");
  }

  const rootKey = keyOf(input.rootMediaType, input.rootMediaId);

  const mainForward = new Map<string, ResolvedLocalRelation[]>();
  const mainBackward = new Map<string, ResolvedLocalRelation[]>();
  const sideEntries: ResolvedLocalRelation[] = [];
  const adaptationEntries: ResolvedLocalRelation[] = [];

  for (const rel of input.relations) {
    if (!Number.isInteger(rel.targetMediaId) || rel.targetMediaId < 1) continue;
    const fromType = rel.sourceMediaType ?? input.rootMediaType;
    const fromId = rel.sourceMediaId ?? input.rootMediaId;
    const fromKey = keyOf(fromType, fromId);
    const kind = normalizeType(rel.relationType);

    if (kind === "SEQUEL") {
      if (rel.format && SIDE_FORMATS.has(normalizeType(rel.format))) {
        sideEntries.push(rel);
        continue;
      }
      const list = mainForward.get(fromKey) ?? [];
      list.push(rel);
      mainForward.set(fromKey, list);
    } else if (kind === "PREQUEL") {
      const list = mainBackward.get(fromKey) ?? [];
      list.push(rel);
      mainBackward.set(fromKey, list);
    } else if (kind === "SIDE_STORY" || kind === "SPIN_OFF") {
      sideEntries.push(rel);
    } else if (kind === "ADAPTATION" || kind === "SOURCE") {
      adaptationEntries.push(rel);
    }
  }

  // Detect any branching on either forward (SEQUEL) or backward (PREQUEL) main edges.
  let mainChainHasBranch = false;
  for (const list of mainForward.values()) {
    const distinct = new Set(list.map((r) => keyOf(r.targetMediaType, r.targetMediaId)));
    if (distinct.size > 1) mainChainHasBranch = true;
  }
  for (const list of mainBackward.values()) {
    const distinct = new Set(list.map((r) => keyOf(r.targetMediaType, r.targetMediaId)));
    if (distinct.size > 1) mainChainHasBranch = true;
  }

  // Walk backwards from root through PREQUEL edges (with cycle protection) to find start of spine.
  const backwardPrefix: { mediaType: ContinuityMedium; mediaId: number; rel: ResolvedLocalRelation }[] = [];
  const visitedBack = new Set<string>([rootKey]);
  let cursorKey = rootKey;
  while (true) {
    const prevs = (mainBackward.get(cursorKey) ?? [])
      .slice()
      .sort((a, b) => (a.year ?? 9999) - (b.year ?? 9999) || a.targetMediaId - b.targetMediaId);
    const nextPrev = prevs.find((p) => !visitedBack.has(keyOf(p.targetMediaType, p.targetMediaId)));
    if (!nextPrev) break;
    const pk = keyOf(nextPrev.targetMediaType, nextPrev.targetMediaId);
    visitedBack.add(pk);
    backwardPrefix.unshift({ mediaType: nextPrev.targetMediaType, mediaId: nextPrev.targetMediaId, rel: nextPrev });
    cursorKey = pk;
  }

  // Walk forwards from root through SEQUEL edges (BFS/linear deterministic order).
  const forwardSuffix: { mediaType: ContinuityMedium; mediaId: number; rel: ResolvedLocalRelation }[] = [];
  const visitedForward = new Set<string>(visitedBack);
  const queue: string[] = [rootKey];
  while (queue.length > 0) {
    const curr = queue.shift()!;
    const nexts = (mainForward.get(curr) ?? [])
      .slice()
      .sort((a, b) => (a.year ?? 9999) - (b.year ?? 9999) || a.targetMediaId - b.targetMediaId);
    for (const edge of nexts) {
      const ek = keyOf(edge.targetMediaType, edge.targetMediaId);
      if (visitedForward.has(ek)) continue;
      visitedForward.add(ek);
      forwardSuffix.push({ mediaType: edge.targetMediaType, mediaId: edge.targetMediaId, rel: edge });
      queue.push(ek);
    }
  }

  const rows: SeriesCandidateRow[] = [];
  const seenMember = new Set<string>();

  const pushUnique = (row: SeriesCandidateRow) => {
    const mk = keyOf(row.member_media_type, row.member_media_id);
    if (mk === rootKey || seenMember.has(mk)) return;
    seenMember.add(mk);
    rows.push(row);
  };

  let mainOrdinal = 1;
  for (const node of [...backwardPrefix, ...forwardSuffix]) {
    pushUnique({
      root_media_type: input.rootMediaType,
      root_media_id: input.rootMediaId,
      member_media_type: node.mediaType,
      member_media_id: node.mediaId,
      section_kind: "main",
      ordinal: mainOrdinal++,
      source_start_unit: null,
      source_end_unit: null,
      source_volume: null,
      raw_note: node.rel.note ?? null,
      status: "pending",
      auto_approvable: !mainChainHasBranch,
    });
  }

  const sortedSides = sideEntries
    .slice()
    .sort((a, b) => (a.year ?? 9999) - (b.year ?? 9999) || a.targetMediaId - b.targetMediaId);
  let sideOrdinal = 1;
  for (const rel of sortedSides) {
    pushUnique({
      root_media_type: input.rootMediaType,
      root_media_id: input.rootMediaId,
      member_media_type: rel.targetMediaType,
      member_media_id: rel.targetMediaId,
      section_kind: "side",
      ordinal: sideOrdinal++,
      source_start_unit: null,
      source_end_unit: null,
      source_volume: null,
      raw_note: rel.note ?? rel.format ?? null,
      status: "pending",
      auto_approvable: false,
    });
  }

  const distinctAdaptationKeys = new Set(
    adaptationEntries.map((r) => keyOf(r.targetMediaType, r.targetMediaId)),
  );
  const singleClearAdaptation = distinctAdaptationKeys.size === 1 &&
    input.adaptationSpan?.endChapter !== null &&
    input.adaptationSpan?.endChapter !== undefined;
  const spanNote = formatAdaptationNote(input.adaptationSpan);

  const sortedAdaptations = adaptationEntries
    .slice()
    .sort((a, b) => (a.year ?? 9999) - (b.year ?? 9999) || a.targetMediaId - b.targetMediaId);
  let adaptOrdinal = 1;
  for (const rel of sortedAdaptations) {
    pushUnique({
      root_media_type: input.rootMediaType,
      root_media_id: input.rootMediaId,
      member_media_type: rel.targetMediaType,
      member_media_id: rel.targetMediaId,
      section_kind: "adaptation",
      ordinal: adaptOrdinal++,
      source_start_unit: input.adaptationSpan?.startChapter ?? null,
      source_end_unit: input.adaptationSpan?.endChapter ?? null,
      source_volume: input.adaptationSpan?.endVolume ?? null,
      raw_note: rel.note ?? spanNote,
      status: "pending",
      auto_approvable: singleClearAdaptation,
    });
  }

  return rows;
}
