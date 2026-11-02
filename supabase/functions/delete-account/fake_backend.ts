// Stateful in-memory stand-in for the Supabase boundaries used by delete-account
// tests (rows, storage objects, auth users, the barrier and club RPC outcomes,
// injected faults). It models EXTERNAL outcomes only; ordering / required-vs-fail-fast
// / retry policy is the production code in deletion.ts. The database behavior of the
// barrier and the club lifecycle themselves is proven by the SQL tests
// (supabase/tests/rls/51_*, 65_*, supabase/tests/concurrency/90_*, 91_*).
// Test support, not shipped by index.ts.
import {
  type DeletionDeps,
  type OpResult,
  REQUIRED_TEXT_USER_TABLES,
  type RequiredTextUserTable,
  type RpcOutcome,
  type StorageEntry,
} from "./deletion.ts";

export const USER = "user-aaaa";
export const OTHER = "user-bbbb";

export class FakeBackend implements DeletionDeps {
  calls: string[] = [];
  /** table -> stored user_id spelling -> row count */
  tables: Record<RequiredTextUserTable, Map<string, number>> = {
    anime_user_lists: new Map(),
    manga_user_lists: new Map(),
    anime_comments: new Map(),
    manga_comments: new Map(),
  };
  storage = new Set<string>();
  profiles = new Set<string>();
  authUsers = new Set<string>();
  /** users with a deletion barrier (begin_account_deletion succeeded) */
  barriers = new Set<string>();
  /** user -> club memberships still held */
  clubMemberships = new Map<string, number>();
  rpcMode: "ok" | "error" | "refused" = "ok";
  /** operation key -> error message; persists until cleared */
  faults = new Map<string, string>();
  /** operation keys that THROW instead of returning an error */
  throws = new Set<string>();
  /** when true, removeStorageObjects reports success but removes nothing */
  storageRemoveIsNoop = false;

  constructor() {
    for (const user of [USER, OTHER]) {
      for (const table of REQUIRED_TEXT_USER_TABLES) this.tables[table].set(user, 2);
      // a legacy upper-case spelling of the same id (F16) in one TEXT table
      this.tables.anime_user_lists.set(user.toUpperCase(), 1);
      this.profiles.add(user);
      this.authUsers.add(user);
      this.storage.add(`${user}/avatar.png`);
      this.storage.add(`${user}/sub/photo.png`);
      this.clubMemberships.set(user, 2);
    }
  }

  private gate(key: string): string | null {
    this.calls.push(key);
    if (this.throws.has(key)) throw new Error(`network down during ${key}`);
    return this.faults.get(key) ?? null;
  }

  beginAccountDeletion(userId: string): Promise<OpResult> {
    const fault = this.gate("beginAccountDeletion");
    if (fault) return Promise.resolve({ error: fault });
    this.barriers.add(userId);
    return Promise.resolve({ error: null });
  }

  deleteUserConciergeData(_userId: string): Promise<RpcOutcome> {
    const fault = this.gate("rpc");
    if (this.rpcMode === "refused") return Promise.resolve({ kind: "refused", reason: "forbidden" });
    if (this.rpcMode === "error" || fault) return Promise.resolve({ kind: "error", message: fault ?? "rpc exploded" });
    return Promise.resolve({ kind: "ok" });
  }

  deleteClubMemberships(userId: string): Promise<OpResult> {
    const fault = this.gate("deleteClubMemberships");
    if (fault) return Promise.resolve({ error: fault });
    // the real RPC refuses without the barrier (DELETION_NOT_STARTED)
    if (!this.barriers.has(userId)) return Promise.resolve({ error: "DELETION_NOT_STARTED" });
    this.clubMemberships.set(userId, 0);
    return Promise.resolve({ error: null });
  }

  deleteRowsByUserIds(table: RequiredTextUserTable, userIds: string[]): Promise<OpResult> {
    const fault = this.gate(`delete:${table}`);
    if (fault) return Promise.resolve({ error: fault });
    for (const id of userIds) this.tables[table].delete(id);
    return Promise.resolve({ error: null });
  }

  listStorageObjects(prefix: string, limit: number) {
    const fault = this.gate("listStorage");
    if (fault) return Promise.resolve({ entries: [] as StorageEntry[], error: fault });
    const seen = new Map<string, StorageEntry>();
    for (const path of [...this.storage].sort()) {
      if (!path.startsWith(`${prefix}/`)) continue;
      const rest = path.slice(prefix.length + 1);
      const slash = rest.indexOf("/");
      if (slash === -1) seen.set(rest, { name: rest, id: `obj-${path}` });
      else seen.set(rest.slice(0, slash), { name: rest.slice(0, slash), id: null });
    }
    return Promise.resolve({ entries: [...seen.values()].slice(0, limit), error: null });
  }

  removeStorageObjects(paths: string[]): Promise<OpResult> {
    const fault = this.gate("removeStorage");
    if (fault) return Promise.resolve({ error: fault });
    if (!this.storageRemoveIsNoop) for (const p of paths) this.storage.delete(p);
    return Promise.resolve({ error: null });
  }

  deleteProfile(userId: string): Promise<OpResult> {
    const fault = this.gate("deleteProfile");
    if (fault) return Promise.resolve({ error: fault });
    this.profiles.delete(userId);
    return Promise.resolve({ error: null });
  }

  deleteAuthUser(userId: string): Promise<OpResult> {
    const fault = this.gate("deleteAuthUser");
    if (fault) return Promise.resolve({ error: fault });
    this.authUsers.delete(userId);
    return Promise.resolve({ error: null });
  }

  /** TEXT rows left for the user in ANY spelling of the id. */
  rowsLeftFor(userId: string): number {
    const spellings = new Set([userId, userId.toLowerCase(), userId.toUpperCase()]);
    let n = 0;
    for (const t of REQUIRED_TEXT_USER_TABLES) for (const s of spellings) n += this.tables[t].get(s) ?? 0;
    return n;
  }
  storageFor(userId: string): string[] {
    return [...this.storage].filter((p) => p.startsWith(`${userId}/`));
  }
  authDeleteCalled(): boolean {
    return this.calls.includes("deleteAuthUser");
  }
  otherUserIntact(): boolean {
    return this.rowsLeftFor(OTHER) === 9 && this.storageFor(OTHER).length === 2 &&
      this.profiles.has(OTHER) && this.authUsers.has(OTHER) && !this.barriers.has(OTHER) &&
      this.clubMemberships.get(OTHER) === 2;
  }
}
