// TEST SUPPORT ONLY. Not imported by any index.ts, so never part of a deployed bundle.
//
// In-memory stand-in for the slice of supabase-js / PostgREST / PostgreSQL behaviour that the
// concierge-apply and concierge-undo handlers depend on. It models EXTERNAL outcomes only;
// the request policy under test stays in the handlers / *_plan.ts modules.
//
// Modelled semantics (PostgREST single-object writes as issued by supabase-js v2):
//   - insert: absent columns take their DEFAULT, an explicit null does NOT (null is stored);
//   - upsert(row, { onConflict }) with merge-duplicates: on conflict only the columns present
//     in the body are updated; otherwise it is an insert (defaults for absent columns);
//   - update(patch).eq(...): merges the patch into matching rows;
//   - NOT NULL and CHECK constraints reject the write with PostgreSQL codes 23502 / 23514;
//   - row-level security for owner tables: rows of other users are invisible and a write whose
//     owner column is not the JWT user fails with 42501;
//   - errors are returned as { data: null, error } (supabase-js does not throw).
// Every write is recorded in `ops` with the taste import context active at that moment
// (what the taste_capture trigger would read from taste_import_context) and with `via`:
// "table" for a direct PostgREST write by the handler, "rpc" for a write inside a modelled RPC.
//
// RPC boundary (2026-10-05, P2-R2): `apply_import_session` / `undo_import_session` are modelled
// from the CONTRACT of supabase/prepared-migrations/20261005130000_import_apply_undo_transactions.sql
// (atomic: every write of a call commits or none does; compare-and-set on `expected`; journal with
// before/after image; idempotency key per user; compare-and-revert Undo). The SQL is the authority
// and is tested against PostgreSQL in supabase/tests/rls/70_import_apply_undo_transactions.sql; this
// model only lets the handler tests run the real handlers end to end. A fault in `faults` that hits
// a write inside the model aborts the whole call (snapshot restored) and returns the error, like a
// rolled-back transaction; `rpcFaults` fails a call before it does anything.
// Modelled like the SQL: the identity rule (1..2147483647) in the outcome and the Undo journal guard,
// fixed item error text per SQLSTATE class, Undo in DESCENDING ordinal with results in request
// order, `no_after_image` / `invalid_journal_identity` / `unrestorable_before_value` warnings.
// Deliberately NOT modelled (PostgreSQL-only, tested in 70_...sql): row locks and the pre-lock
// pass, the taste_profile_recompute_queue lock and deadlocks (K3/K4), the unique-index wait of a
// concurrent duplicate key (K2), taste_signal_events rows (only the import context is recorded),
// catalog foreign keys, and the "most recent" tie-break of sessions created in one transaction.

export type Row = Record<string, unknown>;

export type TableSpec = {
  /** Column defaults applied on INSERT when the column is absent (functions are evaluated per row). */
  defaults?: Record<string, unknown | (() => unknown)>;
  notNull?: string[];
  /** Returns a violated constraint name, or null. */
  check?: (row: Row) => string | null;
  /** Auto-generated id column (string ids). */
  autoId?: string;
  /** RLS owner column compared with String(auth user id). */
  ownerColumn?: string;
};

export type WriteOp = {
  table: string;
  op: "insert" | "upsert" | "update" | "delete";
  body?: Row;
  filters: Array<[string, unknown]>;
  importContext: string | null;
  /** "table": direct PostgREST write by the handler; "rpc": a write inside a modelled RPC. */
  via: "table" | "rpc";
  error?: string;
};

type Result = { data: unknown; error: { message: string; code?: string } | null };

class SqlError extends Error {
  constructor(public code: string, message: string) {
    super(message);
  }
}

const TRACKED = ["list_type", "progress", "rating", "notes", "verdict"] as const;
const WRITABLE = ["list_type", "progress", "rating", "notes"] as const;

function isObject(v: unknown): v is Row {
  return Boolean(v) && typeof v === "object" && !Array.isArray(v);
}

/** jsonb equality for the scalar values the list rows hold. */
function sameValue(a: unknown, b: unknown): boolean {
  return JSON.stringify(a ?? null) === JSON.stringify(b ?? null);
}

function trackedImage(row: Row): Row {
  const out: Row = {};
  for (const k of TRACKED) out[k] = row[k] ?? null;
  return out;
}

/** The SQL identity rule: `^[1-9][0-9]{0,9}$` within int4, else null. */
function journalMediaId(v: unknown): number | null {
  const s = v == null ? "" : String(v);
  return /^[1-9][0-9]{0,9}$/.test(s) && Number(s) <= 2_147_483_647 ? Number(s) : null;
}

/** Fixed item error text per SQLSTATE (the SQL never returns schema or constraint names). */
function itemError(code: string): string {
  return code === "23503" ? "Unknown title" : "Value rejected";
}

function listTable(mediaType: unknown): { table: string; idColumn: string } {
  return mediaType === "ANIME"
    ? { table: "anime_user_lists", idColumn: "anime_id" }
    : { table: "manga_user_lists", idColumn: "manga_id" };
}

const LIST_TYPES_ANIME = new Set(["WATCHING", "PLANNING", "COMPLETED", "DROPPED", "PAUSED"]);
const LIST_TYPES_MANGA = new Set([...LIST_TYPES_ANIME, "READING"]);
const VERDICTS = new Set(["MASTERPIECE", "OKAY", "BAD"]);

function listCheck(listTypes: Set<string>) {
  return (row: Row): string | null => {
    if (!listTypes.has(String(row.list_type))) return "list_type_check";
    if (row.progress != null && Number(row.progress) < 0) return "progress_check";
    if (row.rating != null && (Number(row.rating) < 1 || Number(row.rating) > 10)) return "rating_check";
    if (row.verdict != null && !VERDICTS.has(String(row.verdict))) return "verdict_check";
    return null;
  };
}

/**
 * Schema slice used by the concierge tests, transcribed from the production-captured baseline
 * (supabase/migrations/20260807000000_baseline_capture_v1.sql: anime/manga_user_lists columns,
 * `progress integer NOT NULL DEFAULT 0`, `rating` CHECK 1..10, list_type CHECKs, UNIQUE
 * (user_id, anime_id|manga_id), owner-only RLS on user_id text).
 */
export function conciergeSchema(): Record<string, TableSpec> {
  let created = 0;
  const listSpec = (listTypes: Set<string>): TableSpec => ({
    defaults: { progress: 0, rating: null, notes: null, verdict: null },
    notNull: ["user_id", "list_type", "progress"],
    check: listCheck(listTypes),
    ownerColumn: "user_id",
  });
  return {
    anime_user_lists: listSpec(LIST_TYPES_ANIME),
    manga_user_lists: listSpec(LIST_TYPES_MANGA),
    import_sessions: {
      autoId: "id",
      defaults: { created_at: () => new Date(Date.UTC(2026, 9, 5, 0, 0, created++)).toISOString() },
      notNull: ["user_id", "status"],
      ownerColumn: "user_id",
    },
    import_session_items: { autoId: "id" },
    title_aliases: { ownerColumn: "user_id" },
    anime: {},
    manga: {},
    episodes: {},
  };
}

export class FakeSupabase {
  tables = new Map<string, Row[]>();
  ops: WriteOp[] = [];
  rpcCalls: Array<{ fn: string; args: unknown; importContext: string | null }> = [];
  /** taste_import_context.session_id for the JWT user (null = no context). */
  importContext: string | null = null;
  rateLimit: Row = { allowed: true };
  /** When set, `check_concierge_rate_limit` returns `{ data: null, error }` (limiter unavailable). */
  rateLimitError: { message: string } | null = null;
  /** `${table}:${op}` -> error message returned for that write (inside a modelled RPC: aborts the call). */
  faults = new Map<string, string>();
  /** RPC name -> error message returned before the call does anything. */
  rpcFaults = new Map<string, string>();
  private idSeq = 0;

  constructor(public specs: Record<string, TableSpec>, public authUserId: string | null) {}

  auth = {
    getUser: () =>
      Promise.resolve(
        this.authUserId
          ? { data: { user: { id: this.authUserId } }, error: null }
          : { data: { user: null }, error: { message: "invalid JWT" } },
      ),
  };

  seed(table: string, rows: Row[]) {
    const t = this.table(table);
    for (const r of rows) t.push({ ...r });
  }

  /** Raw table contents, ignoring RLS (test inspection only). */
  rows(table: string): Row[] {
    return this.table(table).map((r) => ({ ...r }));
  }

  writes(table?: string): WriteOp[] {
    return this.ops.filter((o) => !table || o.table === table);
  }

  from(table: string) {
    return new FakeQuery(this, table);
  }

  rpc(fn: string, args?: unknown): Promise<Result> {
    this.rpcCalls.push({ fn, args, importContext: this.importContext });
    const injected = this.rpcFaults.get(fn);
    if (injected) return Promise.resolve({ data: null, error: { message: injected, code: "XX000" } });
    if (fn === "check_concierge_rate_limit") {
      return Promise.resolve(this.rateLimitError ? { data: null, error: this.rateLimitError } : { data: this.rateLimit, error: null });
    }
    if (fn === "apply_import_session") return Promise.resolve(this.transaction(() => this.applyImportSession((args ?? {}) as Row)));
    if (fn === "undo_import_session") return Promise.resolve(this.transaction(() => this.undoImportSession((args ?? {}) as Row)));
    if (fn === "begin_taste_import_context") {
      this.importContext = String((args as Row)?.p_session_id ?? "");
    } else if (fn === "clear_taste_import_context") {
      this.importContext = null;
    }
    return Promise.resolve({ data: null, error: null });
  }

  /** Calls made to one RPC (test inspection). */
  calls(fn: string) {
    return this.rpcCalls.filter((c) => c.fn === fn);
  }

  // ---- modelled RPCs (contract of 20261005130000_import_apply_undo_transactions.sql) ----

  /** One transaction: every table change and recorded op of `body` is kept, or none is. */
  private transaction(body: () => unknown): Result {
    const snapshot = new Map([...this.tables].map(([name, rows]) => [name, rows.map((r) => ({ ...r }))]));
    const opsLength = this.ops.length;
    const context = this.importContext;
    try {
      return { data: body(), error: null };
    } catch (e) {
      for (const [name, rows] of this.tables) rows.splice(0, rows.length, ...(snapshot.get(name) ?? []));
      this.ops.length = opsLength;
      this.importContext = context;
      const err = e as { message?: string; code?: string };
      return { data: null, error: { message: err.message ?? String(e), code: err.code ?? "XX000" } };
    }
  }

  /** A write inside a modelled RPC: an injected fault aborts the whole call. */
  private rpcWrite(table: string, op: WriteOp["op"], body: Row | undefined, filters: Array<[string, unknown]>) {
    const fault = this.faults.get(`${table}:${op}`);
    if (fault) throw new SqlError("XX000", fault);
    this.ops.push({ table, op, body: body ? { ...body } : undefined, filters, importContext: this.importContext, via: "rpc" });
  }

  private rpcInsert(table: string, body: Row): Row {
    const row = this.insertRow(table, body);
    const bad = this.violation(table, row, true);
    if (bad) throw new SqlError(bad.code, bad.message);
    this.rpcWrite(table, "insert", body, []);
    this.table(table).push(row);
    return row;
  }

  private applyImportSession(args: Row): Row {
    const userId = args.p_user_id == null ? "" : String(args.p_user_id);
    const key = typeof args.p_idempotency_key === "string" ? args.p_idempotency_key : null;
    const items = args.p_items;
    if (!userId || !Array.isArray(items) || items.length === 0 || items.length > 100) {
      throw new SqlError("22023", "apply_import_session: p_user_id and 1..100 planned items are required");
    }
    if (key != null) {
      const existing = this.table("import_sessions").find((s) => s.user_id === userId && s.idempotency_key === key);
      if (existing) return this.applyOutcome(String(existing.id), true);
    }
    const sessionId = String(args.p_session_id ?? this.nextId("import_sessions"));
    this.rpcInsert("import_sessions", { id: sessionId, user_id: userId, status: "draft", source: "chat", idempotency_key: key });
    this.importContext = sessionId; // taste_import_context row, inside the transaction
    let applied = 0;
    items.forEach((raw, index) => {
      const item = isObject(raw) ? raw : {};
      const type = item.media_type;
      const mediaId = item.media_id;
      const action = item.import_action;
      if ((type !== "ANIME" && type !== "MANGA") || typeof mediaId !== "number" || !Number.isSafeInteger(mediaId) ||
        mediaId < 1 || mediaId > 2_147_483_647 || (action !== "add" && action !== "update" && action !== "skip")) {
        throw new SqlError("22023", `apply_import_session: item ${index + 1} is not a planned item`);
      }
      const { table, idColumn } = listTable(type);
      const expected = isObject(item.expected) ? item.expected : null;
      const journal = isObject(item.journal) ? item.journal : {};
      let cur: Row | null = null;
      let prev: Row | null = null;
      let after: Row | null = null;
      let outcome: "applied" | "skipped" | "conflict" | "error" | null = null;
      let error: string | null = null;
      if (action === "skip") {
        outcome = "skipped";
      } else {
        const rows = this.table(table);
        const at = rows.findIndex((r) => r.user_id === userId && r[idColumn] === mediaId);
        cur = at >= 0 ? trackedImage(rows[at]) : null;
        if (expected) {
          if (!cur) {
            outcome = "conflict";
            error = "Entry no longer exists (deleted since parse)";
          } else if (Object.entries(expected).some(([k, v]) => !sameValue(cur?.[k], v))) {
            outcome = "conflict";
            error = "State changed since parse — review and retry";
          }
        }
        if (!outcome) {
          if (!cur) {
            const values = isObject(item.insert_values) ? item.insert_values : {};
            const body: Row = { user_id: userId, [idColumn]: mediaId, list_type: values.list_type ?? null, progress: values.progress ?? 0 };
            if ("rating" in values) body.rating = values.rating;
            if ("notes" in values) body.notes = values.notes;
            const row = this.insertRow(table, body);
            const bad = this.violation(table, row, true);
            if (bad) {
              outcome = "error";
              error = itemError(bad.code);
            } else {
              this.rpcWrite(table, "insert", body, []);
              rows.push(row);
              after = trackedImage(row);
            }
          } else {
            const values = isObject(item.update_values) ? item.update_values : {};
            const patch: Row = {};
            for (const k of WRITABLE) if (k in values) patch[k] = values[k];
            const merged = { ...rows[at], ...patch };
            const bad = this.violation(table, merged, true);
            if (bad) {
              outcome = "error";
              error = itemError(bad.code);
            } else {
              this.rpcWrite(table, "update", patch, [["user_id", userId], [idColumn, mediaId]]);
              rows[at] = merged;
              after = {};
              for (const k of Object.keys(patch)) after[k] = merged[k] ?? null;
              prev = cur;
            }
          }
          if (!outcome) {
            outcome = "applied";
            applied += 1;
          }
        }
      }
      // Journal row: required (a fault here aborts the whole call).
      this.rpcInsert("import_session_items", {
        session_id: sessionId,
        raw: typeof journal.raw === "string" ? journal.raw.slice(0, 500) : `${type}:${mediaId}`,
        parsed: isObject(journal.parsed) ? journal.parsed : {},
        candidates: Array.isArray(journal.candidates) ? journal.candidates : [],
        chosen: { mediaType: type, mediaId },
        action: {
          ordinal: index + 1,
          outcome,
          table: action === "skip" ? null : table,
          before: cur,
          after: outcome === "applied" ? { user_id: userId, [idColumn]: mediaId, ...after } : null,
        },
        confidence: typeof journal.confidence === "number" ? journal.confidence : 0,
        state: outcome === "applied" ? "applied" : outcome === "skipped" ? "skipped" : "error",
        import_action: action,
        error,
        previous_values: outcome === "applied" ? prev : null,
        after_values: outcome === "applied" ? after : null,
        reverted_at: null,
      });
    });
    // Session transition: required.
    this.rpcWrite("import_sessions", "update", { status: applied > 0 ? "applied" : "failed" }, [["id", sessionId]]);
    const session = this.table("import_sessions").find((s) => s.id === sessionId);
    if (session) session.status = applied > 0 ? "applied" : "failed";
    this.importContext = null;
    return this.applyOutcome(sessionId, false);
  }

  private journal(sessionId: string): Row[] {
    const ord = (r: Row) => Number((r.action as Row | null)?.ordinal ?? 0);
    return this.table("import_session_items").filter((r) => r.session_id === sessionId).sort((a, b) => ord(a) - ord(b));
  }

  private applyOutcome(sessionId: string, replayed: boolean): Row {
    const items = this.journal(sessionId);
    const ident = (r: Row) => ({ mediaType: (r.chosen as Row).mediaType, mediaId: journalMediaId((r.chosen as Row).mediaId) });
    const isConflict = (r: Row) => (r.action as Row | null)?.outcome === "conflict";
    const session = this.table("import_sessions").find((s) => s.id === sessionId);
    return {
      session_id: sessionId,
      replayed,
      applied: items.filter((r) => r.state === "applied").map((r) => ({
        ...ident(r),
        status: (r.after_values as Row).list_type,
        action: r.import_action,
      })),
      skipped: items.filter((r) => r.state === "skipped").map(ident),
      conflicts: items.filter((r) => r.state === "error" && isConflict(r)).map((r) => ({ ...ident(r), error: r.error })),
      errors: items.filter((r) => r.state === "error" && !isConflict(r)).map((r) => ({ ...ident(r), error: r.error })),
      undoable: session?.status === "applied" && items.some((r) => r.state === "applied" && r.reverted_at == null),
    };
  }

  private undoImportSession(args: Row): Row {
    const userId = args.p_user_id == null ? "" : String(args.p_user_id);
    const sessionId = args.p_session_id == null ? "" : String(args.p_session_id);
    if (!userId || !sessionId) throw new SqlError("22023", "undo_import_session: p_user_id and p_session_id are required");
    const sessions = this.table("import_sessions");
    const session = sessions.find((s) => s.id === sessionId);
    if (!session || session.user_id !== userId) return { result: "not_found" };
    if (session.status === "cancelled") {
      return { result: "already_undone", session_id: sessionId, reverted: [], skipped: [], warnings: [] };
    }
    const items = this.journal(sessionId).filter((r) => r.state === "applied");
    if (session.status !== "applied" || items.length === 0) return { result: "not_found" };
    const latest = sessions
      .filter((s) => s.user_id === userId && s.status === "applied")
      .sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)) || String(b.id).localeCompare(String(a.id)))[0];
    if (latest?.id !== sessionId) return { result: "not_latest" };
    this.importContext = sessionId;
    const reverted: Row[] = [];
    const skipped: Row[] = [];
    const warnings: Row[] = [];
    // DESCENDING ordinal (a chain on one title unwinds last write first); results are prepended so
    // the response lists items in request order, as the SQL does.
    for (const item of items.filter((r) => r.reverted_at == null).reverse()) {
      const chosen = (item.chosen ?? {}) as Row;
      const mediaId = journalMediaId(chosen.mediaId);
      if ((chosen.mediaType !== "ANIME" && chosen.mediaType !== "MANGA") || mediaId == null) {
        warnings.unshift({ id: item.id, reason: "invalid_journal_identity" });
        continue;
      }
      const ident = { mediaType: chosen.mediaType, mediaId };
      const { table, idColumn } = listTable(chosen.mediaType);
      const actionData = isObject(item.action) ? item.action : {};
      const source = isObject(item.after_values) ? item.after_values : isObject(actionData.after) ? actionData.after : {};
      const after: Row = {};
      for (const k of TRACKED) if (k in source) after[k] = source[k];
      if (Object.keys(after).length === 0) {
        // no after image: cannot prove the row is unchanged, so never delete or restore it
        warnings.unshift({ ...ident, reason: "no_after_image" });
        continue;
      }
      const before = isObject(item.previous_values) ? item.previous_values : isObject(actionData.before) ? actionData.before : null;
      const rows = this.table(table);
      const at = rows.findIndex((r) => r.user_id === userId && r[idColumn] === mediaId);
      if (at < 0) {
        skipped.unshift({ ...ident, reason: "deleted_since_import" });
        continue;
      }
      const cur = trackedImage(rows[at]);
      const changed = Object.keys(after).filter((k) => !sameValue(cur[k], after[k])).sort();
      if (!before) {
        if (changed.length > 0) {
          skipped.unshift({ ...ident, reason: "edited_since_import", fields: changed });
          continue;
        }
        this.rpcWrite(table, "delete", undefined, [["user_id", userId], [idColumn, mediaId]]);
        rows.splice(at, 1);
        reverted.unshift({ ...ident, undoType: "deleted" });
      } else {
        const restorable = (k: string) => {
          const v = before[k];
          if (k === "list_type") return typeof v === "string";
          if (k === "progress") return typeof v === "number" && Number.isInteger(v) && v >= 0;
          if (k === "rating") return v == null || (typeof v === "number" && Number.isInteger(v) && v >= 1 && v <= 10);
          return v == null || typeof v === "string";
        };
        const equal = Object.keys(after).filter((k) => (WRITABLE as readonly string[]).includes(k) && sameValue(cur[k], after[k])).sort();
        const revert = equal.filter(restorable);
        const unrestorable = equal.filter((k) => !restorable(k));
        if (unrestorable.length > 0) warnings.unshift({ ...ident, reason: "unrestorable_before_value", fields: unrestorable });
        if (revert.length > 0) {
          const patch: Row = {};
          for (const k of revert) patch[k] = before[k] ?? null;
          this.rpcWrite(table, "update", patch, [["user_id", userId], [idColumn, mediaId]]);
          rows[at] = { ...rows[at], ...patch };
          reverted.unshift({ ...ident, undoType: "restored", fields: revert });
        }
        if (changed.length > 0) skipped.unshift({ ...ident, reason: "edited_since_import", fields: changed });
        if (revert.length === 0) continue;
      }
      this.rpcWrite("import_session_items", "update", { reverted_at: "now" }, [["id", item.id]]);
      item.reverted_at = new Date(Date.UTC(2026, 9, 5, 12)).toISOString();
    }
    this.rpcWrite("import_sessions", "update", { status: "cancelled" }, [["id", sessionId]]);
    session.status = "cancelled";
    this.importContext = null;
    return { result: "undone", session_id: sessionId, reverted, skipped, warnings };
  }

  /** @internal */
  table(name: string): Row[] {
    let t = this.tables.get(name);
    if (!t) {
      t = [];
      this.tables.set(name, t);
    }
    return t;
  }

  /** @internal */
  nextId(prefix: string): string {
    this.idSeq += 1;
    return `${prefix}-${this.idSeq}`;
  }

  /** @internal RLS visibility. */
  visible(table: string, row: Row): boolean {
    const owner = this.specs[table]?.ownerColumn;
    return !owner || String(row[owner]) === String(this.authUserId);
  }

  /** @internal Constraint + RLS WITH CHECK validation of a resulting row (`definer`: RLS does not apply). */
  violation(table: string, row: Row, definer = false): { message: string; code: string } | null {
    const spec = this.specs[table] ?? {};
    if (!definer && spec.ownerColumn && String(row[spec.ownerColumn]) !== String(this.authUserId)) {
      return { code: "42501", message: `new row violates row-level security policy for table "${table}"` };
    }
    for (const col of spec.notNull ?? []) {
      if (row[col] === null || row[col] === undefined) {
        return { code: "23502", message: `null value in column "${col}" of relation "${table}" violates not-null constraint` };
      }
    }
    const failed = spec.check?.(row);
    if (failed) return { code: "23514", message: `new row for relation "${table}" violates check constraint "${table}_${failed}"` };
    return null;
  }

  /** @internal Build an INSERT row: defaults only for ABSENT columns. */
  insertRow(table: string, body: Row): Row {
    const spec = this.specs[table] ?? {};
    const row: Row = {};
    for (const [k, v] of Object.entries(spec.defaults ?? {})) {
      if (!(k in body)) row[k] = typeof v === "function" ? (v as () => unknown)() : v;
    }
    Object.assign(row, body);
    if (spec.autoId && row[spec.autoId] == null) row[spec.autoId] = this.nextId(table);
    return row;
  }
}

type Filter = { col: string; kind: "eq" | "notnull"; val?: unknown };

class FakeQuery implements PromiseLike<Result> {
  private kind: "select" | "insert" | "upsert" | "update" | "delete" = "select";
  private columns = "*";
  private returning = false;
  private body: Row | null = null;
  private onConflict: string[] = [];
  private filters: Filter[] = [];
  private orderBy: { col: string; asc: boolean } | null = null;
  private limitN: number | null = null;
  private mode: "many" | "single" | "maybe" = "many";

  constructor(private db: FakeSupabase, private tableName: string) {}

  select(columns = "*") {
    this.columns = columns;
    if (this.kind !== "select") this.returning = true;
    return this;
  }
  insert(row: Row) {
    this.kind = "insert";
    this.body = row;
    return this;
  }
  upsert(row: Row, opts?: { onConflict?: string }) {
    this.kind = "upsert";
    this.body = row;
    this.onConflict = String(opts?.onConflict ?? "").split(",").map((s) => s.trim()).filter(Boolean);
    return this;
  }
  update(patch: Row) {
    this.kind = "update";
    this.body = patch;
    return this;
  }
  delete() {
    this.kind = "delete";
    return this;
  }
  eq(col: string, val: unknown) {
    this.filters.push({ col, kind: "eq", val });
    return this;
  }
  not(col: string, op: string, val: unknown) {
    if (op === "is" && val === null) this.filters.push({ col, kind: "notnull" });
    else throw new Error(`fake: unsupported not(${col}, ${op})`);
    return this;
  }
  order(col: string, opts?: { ascending?: boolean }) {
    this.orderBy = { col, asc: opts?.ascending !== false };
    return this;
  }
  limit(n: number) {
    this.limitN = n;
    return this;
  }
  maybeSingle() {
    this.mode = "maybe";
    return this;
  }
  single() {
    this.mode = "single";
    return this;
  }

  then<A = Result, B = never>(
    onFulfilled?: ((value: Result) => A | PromiseLike<A>) | null,
    onRejected?: ((reason: unknown) => B | PromiseLike<B>) | null,
  ): PromiseLike<A | B> {
    return Promise.resolve().then(() => this.execute()).then(onFulfilled, onRejected);
  }

  private matches(row: Row): boolean {
    if (!this.db.visible(this.tableName, row)) return false;
    return this.filters.every((f) =>
      f.kind === "eq" ? row[f.col] === f.val : row[f.col] !== null && row[f.col] !== undefined
    );
  }

  private project(row: Row): Row {
    if (this.columns.trim() === "*") return { ...row };
    const out: Row = {};
    for (const c of this.columns.split(",").map((s) => s.trim())) out[c] = row[c] ?? null;
    return out;
  }

  private shape(rows: Row[]): Result {
    const projected = rows.map((r) => this.project(r));
    if (this.mode === "many") return { data: projected, error: null };
    if (this.mode === "maybe") {
      if (projected.length > 1) return { data: null, error: { message: "multiple rows returned", code: "PGRST116" } };
      return { data: projected[0] ?? null, error: null };
    }
    if (projected.length !== 1) return { data: null, error: { message: "expected a single row", code: "PGRST116" } };
    return { data: projected[0], error: null };
  }

  private record(op: WriteOp["op"], error?: string) {
    this.db.ops.push({
      table: this.tableName,
      op,
      body: this.body ? { ...this.body } : undefined,
      filters: this.filters.map((f) => [f.col, f.kind === "eq" ? f.val : "NOT NULL"]),
      importContext: this.db.importContext,
      via: "table",
      ...(error ? { error } : {}),
    });
  }

  private fail(op: WriteOp["op"], error: { message: string; code: string }): Result {
    this.record(op, `${error.code} ${error.message}`);
    return { data: null, error };
  }

  private execute(): Result {
    const table = this.db.table(this.tableName);
    const fault = this.kind !== "select" ? this.db.faults.get(`${this.tableName}:${this.kind}`) : undefined;
    if (this.kind !== "select" && fault) return this.fail(this.kind, { code: "XX000", message: fault });

    switch (this.kind) {
      case "select": {
        let rows = table.filter((r) => this.matches(r));
        if (this.orderBy) {
          const { col, asc } = this.orderBy;
          rows = [...rows].sort((a, b) => (String(a[col]) < String(b[col]) ? -1 : String(a[col]) > String(b[col]) ? 1 : 0) * (asc ? 1 : -1));
        }
        if (this.limitN != null) rows = rows.slice(0, this.limitN);
        return this.shape(rows);
      }
      case "insert": {
        const row = this.db.insertRow(this.tableName, this.body ?? {});
        const bad = this.db.violation(this.tableName, row);
        if (bad) return this.fail("insert", bad);
        table.push(row);
        this.record("insert");
        return this.returning ? this.shape([row]) : { data: null, error: null };
      }
      case "upsert": {
        const body = this.body ?? {};
        const idx = this.onConflict.length
          ? table.findIndex((r) => this.onConflict.every((c) => r[c] === body[c]))
          : -1;
        if (idx >= 0) {
          const merged = { ...table[idx], ...body }; // merge-duplicates: only present columns change
          const bad = this.db.violation(this.tableName, merged);
          if (bad) return this.fail("upsert", bad);
          table[idx] = merged;
          this.record("upsert");
          return this.returning ? this.shape([merged]) : { data: null, error: null };
        }
        const row = this.db.insertRow(this.tableName, body);
        const bad = this.db.violation(this.tableName, row);
        if (bad) return this.fail("upsert", bad);
        table.push(row);
        this.record("upsert");
        return this.returning ? this.shape([row]) : { data: null, error: null };
      }
      case "update": {
        const updated: Row[] = [];
        for (let i = 0; i < table.length; i++) {
          if (!this.matches(table[i])) continue;
          const merged = { ...table[i], ...(this.body ?? {}) };
          const bad = this.db.violation(this.tableName, merged);
          if (bad) return this.fail("update", bad);
          table[i] = merged;
          updated.push(merged);
        }
        this.record("update");
        return this.returning ? this.shape(updated) : { data: null, error: null };
      }
      case "delete": {
        const keep = table.filter((r) => !this.matches(r));
        table.splice(0, table.length, ...keep);
        this.record("delete");
        return { data: null, error: null };
      }
    }
  }
}
