// TEST SUPPORT ONLY. Never imported by an index.ts or handler.ts, so never part of a deployed bundle.
//
// A small stand-in for the read-mostly supabase-js surface the concierge-parse and concierge-recommend
// handlers use: `auth.getUser()`, `rpc(name, args)` and `from(table)` with
// select/eq/in/not(is null)/order/limit/maybeSingle/upsert. It models EXTERNAL outcomes only (rows,
// RPC replies, errors, an unauthenticated caller); every policy under test stays in production code.
// Every executed call is recorded in `calls`, so tests can assert that work did NOT happen.
// Write semantics are deliberately minimal (upsert merges on its onConflict columns); the list-write
// fake with constraints and RLS is _shared/test_fake_supabase.ts (concierge-apply / undo).

export type Row = Record<string, unknown>;
export type RpcResult = { data: unknown; error: unknown };
export type RpcReply = RpcResult | ((args: Record<string, unknown>) => RpcResult | Promise<RpcResult>);

export type Call =
  | { kind: "rpc"; name: string; args: Record<string, unknown> }
  | { kind: "select"; table: string; filters: Array<[string, string, unknown]> }
  | { kind: "upsert"; table: string; body: Row };

export type FakeOptions = {
  /** The verified caller; null means `auth.getUser()` returns an auth error. */
  user?: { id: string } | null;
  tables?: Record<string, Row[]>;
  /** A table whose reads return `{ data: null, error: { message } }`. */
  tableErrors?: Record<string, string>;
  /** RPC replies by name. Unlisted RPCs return `{ data: null, error: null }`. */
  rpc?: Record<string, RpcReply>;
};

export type QueryFake = {
  // deno-lint-ignore no-explicit-any
  client: any;
  calls: Call[];
  tables: Record<string, Row[]>;
  rpcCalls(name: string): Array<Record<string, unknown>>;
  reads(table: string): number;
};

const same = (a: unknown, b: unknown) => a === b || (a != null && b != null && String(a) === String(b));

export function queryFake(opts: FakeOptions = {}): QueryFake {
  const tables: Record<string, Row[]> = {};
  for (const [name, rows] of Object.entries(opts.tables ?? {})) tables[name] = rows.map((r) => ({ ...r }));
  const calls: Call[] = [];

  function from(table: string) {
    const filters: Array<[string, string, unknown]> = [];
    let orderBy: { col: string; ascending: boolean } | null = null;
    let limitN: number | null = null;

    const run = (): RpcResult => {
      calls.push({ kind: "select", table, filters: [...filters] });
      const err = opts.tableErrors?.[table];
      if (err) return { data: null, error: { message: err } };
      let rows = (tables[table] ?? []).filter((r) =>
        filters.every(([op, col, v]) => {
          if (op === "eq") return same(r[col], v);
          if (op === "in") return (v as unknown[]).some((x) => same(r[col], x));
          if (op === "not-is-null") return r[col] != null;
          return true;
        })
      );
      if (orderBy) {
        const { col, ascending } = orderBy;
        rows = [...rows].sort((a, b) => (Number(a[col] ?? 0) - Number(b[col] ?? 0)) * (ascending ? 1 : -1));
      }
      if (limitN != null) rows = rows.slice(0, limitN);
      return { data: rows.map((r) => ({ ...r })), error: null };
    };

    const builder = {
      select(_cols?: string) {
        return builder;
      },
      eq(col: string, v: unknown) {
        filters.push(["eq", col, v]);
        return builder;
      },
      in(col: string, vs: unknown[]) {
        filters.push(["in", col, vs]);
        return builder;
      },
      not(col: string, op: string, v: unknown) {
        if (op === "is" && v === null) filters.push(["not-is-null", col, null]);
        return builder;
      },
      order(col: string, o: { ascending?: boolean } = {}) {
        orderBy = { col, ascending: o.ascending !== false };
        return builder;
      },
      limit(n: number) {
        limitN = n;
        return builder;
      },
      maybeSingle(): Promise<RpcResult> {
        const r = run();
        if (r.error) return Promise.resolve(r);
        const rows = r.data as Row[];
        if (rows.length > 1) return Promise.resolve({ data: null, error: { message: "multiple rows", code: "PGRST116" } });
        return Promise.resolve({ data: rows[0] ?? null, error: null });
      },
      upsert(body: Row, o: { onConflict?: string } = {}): Promise<RpcResult> {
        calls.push({ kind: "upsert", table, body: { ...body } });
        const keys = (o.onConflict ?? "").split(",").map((k) => k.trim()).filter(Boolean);
        const rows = (tables[table] ??= []);
        const hit = keys.length ? rows.find((r) => keys.every((k) => same(r[k], body[k]))) : undefined;
        if (hit) Object.assign(hit, body);
        else rows.push({ ...body });
        return Promise.resolve({ data: null, error: null });
      },
      then<T>(resolve: (r: RpcResult) => T, reject?: (e: unknown) => T) {
        return Promise.resolve(run()).then(resolve, reject);
      },
    };
    return builder;
  }

  const client = {
    auth: {
      getUser: () =>
        Promise.resolve(
          opts.user ? { data: { user: opts.user }, error: null } : { data: { user: null }, error: { message: "invalid JWT" } },
        ),
    },
    rpc(name: string, args: Record<string, unknown> = {}): Promise<RpcResult> {
      calls.push({ kind: "rpc", name, args });
      const reply = opts.rpc?.[name];
      if (reply === undefined) return Promise.resolve({ data: null, error: null });
      return Promise.resolve(typeof reply === "function" ? reply(args) : reply);
    },
    from,
  };

  return {
    client,
    calls,
    tables,
    rpcCalls: (name) => calls.flatMap((c) => (c.kind === "rpc" && c.name === name ? [c.args] : [])),
    reads: (table) => calls.filter((c) => c.kind === "select" && c.table === table).length,
  };
}
