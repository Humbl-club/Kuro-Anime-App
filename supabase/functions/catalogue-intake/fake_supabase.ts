// TEST SUPPORT ONLY. Never imported by index.ts or handler.ts, so never part of a deployed bundle.
// In-memory stand-in for the supabase-js surface catalogue-intake uses: from(table) with
// select/insert/upsert/update/delete, eq/in/gt/lt/is/not filters, order/limit/maybeSingle/single,
// and rpc(acquire_import_lock / release_import_lock). Every write is recorded in `ops`.
// It models external outcomes only; policy under test stays in production code.
// Composite upsert conflict keys come from the `onConflict` option.
export type Row = Record<string, unknown>;
export type Op = { table: string; op: "insert" | "upsert" | "update" | "delete"; rows: Row[] };

export type FakeOptions = {
  tables?: Record<string, Row[]>;
  /** acquire_import_lock result: true (default), false (busy) or an error message. */
  lock?: boolean | { error: string };
  /** Tables whose insert/upsert returns this error. */
  writeErrors?: Record<string, { message: string; code?: string }>;
};

export function fakeSupabase(opts: FakeOptions = {}) {
  const tables: Record<string, Row[]> = {};
  for (const [k, v] of Object.entries(opts.tables ?? {})) tables[k] = v.map((r) => ({ ...r }));
  const ops: Op[] = [];
  const rpcs: { name: string; args: Row }[] = [];
  const reads: { table: string; filters: string[] }[] = [];
  let seq = 1;

  function from(table: string) {
    const filters: Array<(r: Row) => boolean> = [];
    const filterText: string[] = [];
    let order: { col: string; asc: boolean } | null = null;
    let limitN: number | null = null;
    let mode: "select" | "insert" | "upsert" | "update" | "delete" = "select";
    let body: Row[] = [];
    let patch: Row = {};
    let onConflict: string[] = [];
    let returning = false;
    let single: "single" | "maybe" | null = null;

    const exec = () => {
      const rows = (tables[table] ??= []);
      if (mode === "select") {
        reads.push({ table, filters: filterText });
        let out = rows.filter((r) => filters.every((f) => f(r)));
        if (order) {
          const { col, asc } = order;
          out = [...out].sort((a, b) => (Number(a[col]) - Number(b[col])) * (asc ? 1 : -1) || String(a[col]).localeCompare(String(b[col])) * (asc ? 1 : -1));
        }
        if (limitN !== null) out = out.slice(0, limitN);
        out = out.map((r) => ({ ...r }));
        return finish(out);
      }
      const err = opts.writeErrors?.[table];
      if ((mode === "insert" || mode === "upsert") && err) return { data: null, error: err };
      if (mode === "insert") {
        ops.push({ table, op: "insert", rows: body.map((r) => ({ ...r })) });
        const stored = body.map((r) => ({ id: seq++, ...r }));
        rows.push(...stored);
        return finish(stored.map((r) => ({ ...r })));
      }
      if (mode === "upsert") {
        ops.push({ table, op: "upsert", rows: body.map((r) => ({ ...r })) });
        for (const r of body) {
          const hit = onConflict.length ? rows.find((x) => onConflict.every((c) => String(x[c]) === String(r[c]))) : undefined;
          if (hit) Object.assign(hit, r);
          else rows.push({ ...r });
        }
        return finish(body.map((r) => ({ ...r })));
      }
      if (mode === "update") {
        const hit = rows.filter((r) => filters.every((f) => f(r)));
        ops.push({ table, op: "update", rows: [{ ...patch, __matched: hit.length }] });
        for (const r of hit) Object.assign(r, patch);
        return finish(hit.map((r) => ({ ...r })));
      }
      const keep = rows.filter((r) => !filters.every((f) => f(r)));
      ops.push({ table, op: "delete", rows: rows.filter((r) => !keep.includes(r)).map((r) => ({ ...r })) });
      tables[table] = keep;
      return { data: null, error: null };
    };

    const finish = (out: Row[]) => {
      if (mode !== "select" && !returning) return { data: null, error: null };
      if (single === "single") return out.length === 1 ? { data: out[0], error: null } : { data: null, error: { message: "single row expected", code: "PGRST116" } };
      if (single === "maybe") return { data: out[0] ?? null, error: null };
      return { data: out, error: null };
    };

    // deno-lint-ignore no-explicit-any
    const q: any = {
      select(_cols?: string) {
        if (mode !== "select") returning = true;
        return q;
      },
      insert(r: Row | Row[]) {
        mode = "insert";
        body = Array.isArray(r) ? r : [r];
        return q;
      },
      upsert(r: Row | Row[], o?: { onConflict?: string }) {
        mode = "upsert";
        body = Array.isArray(r) ? r : [r];
        onConflict = (o?.onConflict ?? "").split(",").map((s) => s.trim()).filter(Boolean);
        return q;
      },
      update(p: Row) {
        mode = "update";
        patch = p;
        return q;
      },
      delete() {
        mode = "delete";
        return q;
      },
      eq(c: string, v: unknown) {
        filters.push((r) => String(r[c]) === String(v));
        filterText.push(`${c}=${v}`);
        return q;
      },
      in(c: string, vs: unknown[]) {
        const set = new Set(vs.map(String));
        filters.push((r) => set.has(String(r[c])));
        filterText.push(`${c} in (${vs.length})`);
        return q;
      },
      gt(c: string, v: unknown) {
        filters.push((r) => Number(r[c]) > Number(v));
        filterText.push(`${c}>${v}`);
        return q;
      },
      lt(c: string, v: unknown) {
        filters.push((r) => Number(r[c]) < Number(v));
        filterText.push(`${c}<${v}`);
        return q;
      },
      gte(c: string, v: unknown) {
        filters.push((r) => String(r[c]) >= String(v));
        filterText.push(`${c}>=${v}`);
        return q;
      },
      not(c: string, op: string, v: unknown) {
        if (op === "is" && v === null) filters.push((r) => r[c] !== null && r[c] !== undefined);
        filterText.push(`${c} not ${op} ${v}`);
        return q;
      },
      is(c: string, v: unknown) {
        filters.push((r) => (v === null ? r[c] === null || r[c] === undefined : r[c] === v));
        return q;
      },
      order(col: string, o?: { ascending?: boolean }) {
        order = { col, asc: o?.ascending !== false };
        return q;
      },
      limit(n: number) {
        limitN = n;
        return q;
      },
      single() {
        single = "single";
        return q;
      },
      maybeSingle() {
        single = "maybe";
        return q;
      },
      // deno-lint-ignore no-explicit-any
      then(resolve: (v: any) => unknown, reject?: (e: unknown) => unknown) {
        try {
          return Promise.resolve(exec()).then(resolve, reject);
        } catch (e) {
          return Promise.reject(e).then(resolve, reject);
        }
      },
    };
    return q;
  }

  function rpc(name: string, args: Row) {
    rpcs.push({ name, args });
    if (name === "acquire_import_lock") {
      const l = opts.lock ?? true;
      if (typeof l === "object") return Promise.resolve({ data: null, error: { message: l.error } });
      return Promise.resolve({ data: l, error: null });
    }
    return Promise.resolve({ data: null, error: null });
  }

  return {
    client: { from, rpc },
    tables,
    ops,
    rpcs,
    reads,
    opsOn: (table: string, op?: Op["op"]) => ops.filter((o) => o.table === table && (!op || o.op === op)),
  };
}

/** A fetch fake that answers queued responses in order and records every request. */
export function queuedFetch(responses: Array<Response | ((url: string, init?: RequestInit) => Response)>) {
  const calls: { url: string; init?: RequestInit; body: string }[] = [];
  const fetch = (input: string | URL | Request, init?: RequestInit) => {
    const next = responses.shift();
    if (!next) return Promise.reject(new Error("unexpected extra request " + String(input)));
    const url = String(input);
    calls.push({ url, init, body: typeof init?.body === "string" ? init.body : "" });
    return Promise.resolve(typeof next === "function" ? next(url, init) : next);
  };
  return { calls, fetch: fetch as typeof globalThis.fetch };
}
