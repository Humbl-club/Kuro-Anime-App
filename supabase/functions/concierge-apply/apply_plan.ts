// Pure validation, planning and outcome mapping for concierge-apply (no I/O, no remote imports).
//
// Policy lives here; the database transaction `apply_import_session` (prepared migration
// supabase/prepared-migrations/20261005130000_import_apply_undo_transactions.sql) owns atomicity,
// the compare-and-set on `expected`, the journal (before AND after image), idempotency and the
// session transition (P2-R2). This module decides WHAT each item writes:
//   - identity validation (F14): `mediaId` a positive integer within the int4 column, `mediaType`
//     ANIME|MANGA, `status` in that medium's vocabulary (case-insensitive, as before). Anything else
//     rejects the whole request (HTTP 400 INVALID_ITEM, nothing written). Quantities (progress,
//     rating, episode numbers) stay clamped; identities are never clamped.
//   - two write variants per item, because only the transaction knows under the row lock whether
//     the row exists: `insert_values` for a new row, `update_values` for an existing one. Only
//     provided fields are written; progress is never null (column NOT NULL DEFAULT 0, a new row gets
//     0 when unknown); rating obeys the DB CHECK 1..10 (clamped, below 1 = absent); verdict is never
//     written. `list_type` is always the status the client sent (or COMPLETED for an explicit finish).
//   - season/episode annotation (F15): "S{n}E{m}" is only a NEW anime row's notes; an existing row's
//     notes change only when the item carries explicit notes.
//   - `expected` (TOCTOU for `update` with expectedExisting): which stored fields must still match.
// The transaction's journal is the outcome's source; `applyResponseBody` maps it to the wire.

export type MediaType = "ANIME" | "MANGA";
export type ListStatus = "WATCHING" | "READING" | "PLANNING" | "COMPLETED" | "DROPPED" | "PAUSED";
export type ImportAction = "add" | "update" | "skip";

/** Items per request (unchanged). */
export const MAX_ITEMS = 100;
/** Largest id the integer list columns hold. */
export const MAX_MEDIA_ID = 2_147_483_647;

/** The list tables' CHECK vocabularies (baseline capture): anime has no READING. */
export const LIST_STATUSES: Record<MediaType, readonly ListStatus[]> = {
  ANIME: ["WATCHING", "PLANNING", "COMPLETED", "DROPPED", "PAUSED"],
  MANGA: ["WATCHING", "READING", "PLANNING", "COMPLETED", "DROPPED", "PAUSED"],
};

const IDEMPOTENCY_KEY = /^[A-Za-z0-9_-]{1,128}$/;

/**
 * Quantity clamp (progress, episode numbers, hit counts). Never use it for an identity.
 * An absent value and an explicit JSON null are both "not provided" (null), never 0.
 */
export function clampInt(v: unknown, min: number, max: number) {
  if (v == null) return null;
  const n = Math.floor(Number(v));
  if (!Number.isFinite(n)) return null;
  return Math.max(min, Math.min(max, n));
}

export type ValidatedItem = {
  mediaType: MediaType;
  mediaId: number;
  status: ListStatus;
  importAction: ImportAction;
};

/** A media identity as sent: a JSON number that is a positive integer the list columns hold, else null. */
export function validMediaId(v: unknown): number | null {
  return typeof v === "number" && Number.isSafeInteger(v) && v >= 1 && v <= MAX_MEDIA_ID ? v : null;
}

/** Identity validation of one item (F14). No coercion of identities: invalid input is rejected. */
export function validateApplyItem(
  // deno-lint-ignore no-explicit-any
  it: any,
): { ok: true; item: ValidatedItem } | { ok: false; error: string } {
  if (!it || typeof it !== "object" || Array.isArray(it)) return { ok: false, error: "Item must be an object" };
  const mediaType: MediaType | null = it.mediaType === "ANIME" || it.mediaType === "MANGA" ? it.mediaType : null;
  if (!mediaType) return { ok: false, error: "mediaType must be ANIME or MANGA" };
  const mediaId = validMediaId(it.mediaId);
  if (mediaId == null) return { ok: false, error: `mediaId must be an integer between 1 and ${MAX_MEDIA_ID}` };
  const status = typeof it.status === "string" ? it.status.toUpperCase() : "";
  if (!(LIST_STATUSES[mediaType] as readonly string[]).includes(status)) {
    return { ok: false, error: `status must be one of ${LIST_STATUSES[mediaType].join(", ")} for ${mediaType}` };
  }
  // Reconciliation action: 'add' (default for backwards compat), 'update', or 'skip' (unchanged).
  const importAction: ImportAction = it.action === "update" ? "update" : it.action === "skip" ? "skip" : "add";
  return { ok: true, item: { mediaType, mediaId, status: status as ListStatus, importAction } };
}

export type ApplyRequest = {
  // deno-lint-ignore no-explicit-any
  items: Array<{ raw: any; item: ValidatedItem }>;
  idempotencyKey: string | null;
};

/** Whole-request validation BEFORE anything is written: the first invalid item rejects the request. */
export function validateApplyRequest(
  // deno-lint-ignore no-explicit-any
  body: any,
): { ok: true; request: ApplyRequest } | { ok: false; body: Record<string, unknown> } {
  if (!Array.isArray(body?.items) || body.items.length > MAX_ITEMS) {
    return { ok: false, body: { error: `Too many items (max ${MAX_ITEMS})` } };
  }
  const key = body?.idempotencyKey;
  if (key != null && (typeof key !== "string" || !IDEMPOTENCY_KEY.test(key))) {
    return { ok: false, body: { error: "idempotencyKey must be 1-128 letters, digits, '-' or '_'", code: "INVALID_IDEMPOTENCY_KEY" } };
  }
  const items: ApplyRequest["items"] = [];
  for (let index = 0; index < body.items.length; index++) {
    const validated = validateApplyItem(body.items[index]);
    if (!validated.ok) return { ok: false, body: { error: validated.error, code: "INVALID_ITEM", index } };
    items.push({ raw: body.items[index], item: validated.item });
  }
  return { ok: true, request: { items, idempotencyKey: typeof key === "string" ? key : null } };
}

/** The status written: an explicit finish (anime: lastEpisode/completed, manga: completed) is COMPLETED. */
// deno-lint-ignore no-explicit-any
export function statusToWrite(item: ValidatedItem, it: any): ListStatus {
  const explicitComplete = item.mediaType === "ANIME"
    ? it?.lastEpisode === true || it?.completed === true
    : it?.completed === true;
  return explicitComplete ? "COMPLETED" : item.status;
}

/** Progress the item states itself (clamped quantity), or null; catalog fallbacks are the handler's reads. */
// deno-lint-ignore no-explicit-any
export function statedProgress(item: ValidatedItem, it: any): number | null {
  return item.mediaType === "ANIME"
    ? clampInt(it?.progressEpisodes, 0, 100_000) ?? clampInt(it?.progress, 0, 100_000)
    : clampInt(it?.progressChapters, 0, 500_000) ?? clampInt(it?.progress, 0, 500_000);
}

/** Season number for the S/E annotation: 1..100, otherwise none (0 or -1 is not season 1). */
function seasonNumber(v: unknown): number | null {
  const n = Math.floor(Number(v));
  return Number.isFinite(n) && n >= 1 && n <= 100 ? n : null;
}

/** "S{n}E{m}" for an anime item with a season and an episode >= 1, else null. */
// deno-lint-ignore no-explicit-any
export function seasonEpisodeNote(it: any): string | null {
  const season = seasonNumber(it?.seasonNumber);
  const episode = clampInt(it?.episodeInSeason, 0, 100_000);
  return season && episode ? `S${season}E${episode}` : null;
}

/** Rating as the DB accepts it (CHECK 1..10): clamp as before, then below 1 means "not provided". */
export function normalizeRating(v: unknown): number | null {
  const r = clampInt(v, 0, 10);
  return r != null && r >= 1 ? r : null;
}

export type ListWriteInput = {
  status: ListStatus;
  /** Resolved absolute progress (item value or catalog lookup); null when unknown. */
  progress: number | null;
  /** The item's raw `rating` as sent by the client (may be absent). */
  rating: unknown;
  /** Notes to write; null means "leave unchanged" (existing row) / "no notes" (new row). */
  notes: string | null;
};

/**
 * The list columns one variant writes. For an existing row (`rowExists`) an absent key means
 * "leave unchanged"; for a new row an absent key takes the column default, and progress is the
 * explicit default 0 when unknown (never null).
 */
export function buildListWriteValues(input: ListWriteInput, rowExists: boolean): Record<string, unknown> {
  const values: Record<string, unknown> = { list_type: input.status };
  if (input.progress != null) values.progress = input.progress;
  else if (!rowExists) values.progress = 0;
  const rating = normalizeRating(input.rating);
  if (rating != null) values.rating = rating;
  if (input.notes != null) values.notes = input.notes;
  return values;
}

/**
 * Compare-and-set fields for an `update` with expectedExisting (null = no check). Same rule as
 * before the transaction: the stored status must equal `expectedExisting.status` when given and the
 * stored progress must equal the medium's expected progress when given; any truthy
 * expectedExisting requires the row to exist.
 */
export function expectedCompareSet(mediaType: MediaType, exp: unknown): Record<string, unknown> | null {
  if (!exp) return null;
  const e = (typeof exp === "object" && !Array.isArray(exp) ? exp : {}) as Record<string, unknown>;
  const set: Record<string, unknown> = {};
  if (e.status) set.list_type = e.status;
  const progress = mediaType === "ANIME" ? e.progress_episodes : e.progress_chapters;
  if (progress != null) set.progress = progress;
  return set;
}

/** One planned item, exactly as `apply_import_session(p_items)` reads it. */
export type PlannedItem = {
  media_type: MediaType;
  media_id: number;
  import_action: ImportAction;
  expected: Record<string, unknown> | null;
  insert_values?: Record<string, unknown>;
  update_values?: Record<string, unknown>;
  journal: { raw: string; parsed: unknown; candidates: unknown[]; confidence: number };
};

/** Plans one validated item with its resolved status and progress (the handler did any catalog reads). */
export function planApplyItem(args: {
  item: ValidatedItem;
  // deno-lint-ignore no-explicit-any
  raw: any;
  status: ListStatus;
  progress: number | null;
}): PlannedItem {
  const { item, raw: it, status, progress } = args;
  const base = {
    media_type: item.mediaType,
    media_id: item.mediaId,
    import_action: item.importAction,
  };
  const journalBase = {
    raw: typeof it?.raw === "string" ? it.raw.slice(0, 500) : `${item.mediaType}:${item.mediaId}`,
    candidates: Array.isArray(it?.candidates) ? it.candidates.slice(0, 12) : [],
    confidence: typeof it?.confidence === "number" && Number.isFinite(it.confidence) ? it.confidence : 0,
  };
  if (item.importAction === "skip") {
    return { ...base, expected: null, journal: { ...journalBase, parsed: it?.parsed ?? {} } };
  }
  const caughtUp = it?.caughtUp === true;
  const explicitNotes = typeof it?.notes === "string" ? it.notes.slice(0, 2000) : null;
  let insertNotes = explicitNotes;
  let parsed: Record<string, unknown>;
  if (item.mediaType === "ANIME") {
    const seasonNote = seasonEpisodeNote(it);
    // F15: the structural annotation is only a NEW row's notes (and only without explicit notes).
    if (seasonNote && !explicitNotes) insertNotes = seasonNote;
    parsed = {
      status,
      progressEpisodes: progress ?? null,
      seasonNumber: seasonNumber(it?.seasonNumber),
      episodeInSeason: clampInt(it?.episodeInSeason, 0, 100_000),
      caughtUp: caughtUp || null,
      lastEpisode: it?.lastEpisode === true || it?.completed === true || null,
    };
  } else {
    parsed = { status, progressChapters: progress ?? null, caughtUp: caughtUp || null };
  }
  return {
    ...base,
    expected: item.importAction === "update" ? expectedCompareSet(item.mediaType, it?.expectedExisting) : null,
    insert_values: buildListWriteValues({ status, progress, rating: it?.rating, notes: insertNotes }, false),
    update_values: buildListWriteValues({ status, progress, rating: it?.rating, notes: explicitNotes }, true),
    journal: { ...journalBase, parsed },
  };
}

/** The transaction's outcome (`apply_import_session` return value), validated. */
export type ApplyOutcome = {
  sessionId: string;
  replayed: boolean;
  undoable: boolean;
  applied: Array<{ mediaType: MediaType; mediaId: number; status: ListStatus; action: ImportAction }>;
  skipped: Array<{ mediaType: MediaType; mediaId: number }>;
  conflicts: Array<{ mediaType: MediaType; mediaId: number; error: string }>;
  errors: Array<{ mediaType: MediaType; mediaId: number; error: string }>;
};

/** The RPC data as an outcome, or null when it is not the contract shape (handled as a failed call). */
export function parseApplyOutcome(data: unknown): ApplyOutcome | null {
  if (!data || typeof data !== "object" || Array.isArray(data)) return null;
  const d = data as Record<string, unknown>;
  const lists = [d.applied, d.skipped, d.conflicts, d.errors];
  if (typeof d.session_id !== "string" || !lists.every(Array.isArray)) return null;
  return {
    sessionId: d.session_id,
    replayed: d.replayed === true,
    undoable: d.undoable === true,
    applied: d.applied as ApplyOutcome["applied"],
    skipped: d.skipped as ApplyOutcome["skipped"],
    conflicts: d.conflicts as ApplyOutcome["conflicts"],
    errors: d.errors as ApplyOutcome["errors"],
  };
}

export type ApplyStatus = "applied" | "partial" | "none";

/**
 * Wire response for a committed (or replayed) Apply. `success` keeps its meaning (no conflict, no
 * error); `status` is applied (all accepted, something written) | partial (something written and
 * something conflicted/failed) | none (nothing written to the lists).
 */
export function applyResponseBody(outcome: ApplyOutcome) {
  const rejected = outcome.conflicts.length + outcome.errors.length;
  const status: ApplyStatus = outcome.applied.length === 0 ? "none" : rejected > 0 ? "partial" : "applied";
  return {
    success: rejected === 0,
    sessionId: outcome.sessionId,
    applied: outcome.applied,
    skipped: outcome.skipped,
    conflicts: outcome.conflicts,
    errors: outcome.errors,
    status,
    undoable: outcome.undoable,
    replayed: outcome.replayed,
  };
}

/** Response for an empty `items` array (nothing to do, nothing written). */
export function emptyApplyBody() {
  return {
    success: true,
    sessionId: null,
    applied: [],
    skipped: [],
    conflicts: [],
    errors: [],
    status: "none" as ApplyStatus,
    undoable: false,
    replayed: false,
  };
}

/** HTTP 500 body: the transaction did not commit (or its result is unknown); retrying with the same key is safe. */
export const APPLY_FAILED_BODY = { error: "Import could not be saved", status: "failed", retryable: true } as const;
