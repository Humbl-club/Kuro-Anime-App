// TEST SUPPORT ONLY. Never imported by index.ts or handler.ts.
// A small in-memory model of the Task 15 SQL contract (catalogue_publish_batch_v1 /
// catalogue_restore_batch_v1 in 20261112100150_catalogue_publish_v1.sql) so publish.ts, restore.ts and the
// handler run end to end offline. The SQL is the authority and is tested against PostgreSQL in
// supabase/tests/rls/124_catalogue_publish_lists.sql; this model covers main-row columns, anime_staff and
// media_relations only, and records each call.
import type { Row } from "./fake_supabase.ts";

type Result = { data: unknown; error: { message: string } | null };
const ok = (data: unknown): Result => ({ data, error: null });
const fail = (message: string): Result => ({ data: null, error: { message } });

export const SNAPSHOT_TABLE = "catalogue_rollback_snapshots";

export function publishModel(log: { name: string; args: Row }[] = []) {
  return {
    catalogue_publish_batch_v1(args: Row, tables: Record<string, Row[]>): Result {
      log.push({ name: "catalogue_publish_batch_v1", args });
      const medium = String(args.p_medium);
      const group = String(args.p_group);
      const mode = (tables.catalogue_cutover ?? []).find((r) => r.field_group === group)?.mode;
      if (mode !== "new") return fail(`group ${group} is ${mode}, not new`);
      const cols = [...((args.p_columns as string[]) ?? []), ...(args.p_with_data_sources ? ["data_sources"] : [])];
      const rows = (tables[medium] ??= []);
      const snaps = (tables[SNAPSHOT_TABLE] ??= []);
      const shadow = (tables.catalogue_shadow_values ??= []);
      let snapshotted = 0;
      let updated = 0;
      for (const id of args.p_media_ids as number[]) {
        const row = rows.find((r) => r.id === id);
        if (!row) continue;
        let snap = snaps.find((s) => s.field_group === group && s.medium === medium && s.media_id === id);
        if (!snap) {
          snap = { field_group: group, medium, media_id: id, payload: { columns: Object.fromEntries(cols.map((c) => [c, row[c] ?? null])), tables: {} } };
          snaps.push(snap);
          snapshotted++;
        }
        const payload = snap.payload as { columns: Row; tables: Record<string, Row[]> };
        for (const c of cols) {
          const sv = shadow.find((s) => s.medium === medium && s.media_id === id && s.field === c);
          if (!sv || sv.value === null || sv.value === undefined) continue; // never blank
          if (c === "is_adult" && row.is_adult === true && sv.value !== true) continue;
          if (JSON.stringify(row[c]) !== JSON.stringify(sv.value)) {
            row[c] = sv.value;
            updated++;
          }
        }
        if (group === "credits") {
          const sv = shadow.find((s) => s.medium === medium && s.media_id === id && s.field === "credits:staff");
          if (sv && Array.isArray(sv.value)) {
            const staff = (tables.anime_staff ??= []);
            if (!("anime_staff" in payload.tables)) payload.tables.anime_staff = staff.filter((r) => r.anime_id === id).map((r) => ({ ...r }));
            tables.anime_staff = staff.filter((r) => r.anime_id !== id);
            let n = 900_000 + tables.anime_staff.length;
            for (const c of sv.value as { kuro_id: number; role: string | null }[]) tables.anime_staff.push({ id: n++, anime_id: id, staff_id: c.kuro_id, role: c.role });
          }
        }
        if (group === "relations") {
          const sv = shadow.find((s) => s.medium === medium && s.media_id === id && s.field === "relations");
          if (sv && Array.isArray(sv.value)) {
            const rel = (tables.media_relations ??= []);
            if (!("media_relations" in payload.tables)) payload.tables.media_relations = rel.filter((r) => r.from_media_id === id && r.source === "kuro").map((r) => ({ ...r }));
            tables.media_relations = rel.filter((r) => !(r.from_media_id === id && r.source === "kuro"));
            for (const c of sv.value as { type: string; kind: string; target_id: number; status?: string }[]) {
              if ((c.status ?? "accepted") === "accepted") tables.media_relations.push({ from_media_id: id, relation_type: c.type, to_media_id: c.target_id, source: "kuro" });
            }
          }
        }
      }
      return ok({ titles: (args.p_media_ids as number[]).length, snapshotted, columns_updated: updated, tables_replaced: 0 });
    },

    catalogue_restore_batch_v1(args: Row, tables: Record<string, Row[]>): Result {
      log.push({ name: "catalogue_restore_batch_v1", args });
      const medium = String(args.p_medium);
      const group = String(args.p_group);
      const mode = (tables.catalogue_cutover ?? []).find((r) => r.field_group === group)?.mode;
      if (mode === "new") return fail(`group ${group} is still new`);
      const snaps = (tables[SNAPSHOT_TABLE] ??= []);
      const mine = snaps.filter((s) => s.field_group === group && s.medium === medium).sort((a, b) => Number(a.media_id) - Number(b.media_id)).slice(0, Number(args.p_limit ?? 500));
      for (const s of mine) {
        const payload = s.payload as { columns: Row; tables: Record<string, Row[]> };
        const row = (tables[medium] ?? []).find((r) => r.id === s.media_id);
        if (row) for (const [k, v] of Object.entries(payload.columns)) row[k] = v;
        for (const [t, rows] of Object.entries(payload.tables)) {
          const mine2 = (tables[t] ??= []);
          const isRel = t === "media_relations";
          tables[t] = mine2.filter((r) => !(isRel ? r.from_media_id === s.media_id && r.source === "kuro" : r.anime_id === s.media_id));
          tables[t].push(...rows.map((r) => ({ ...r })));
        }
        tables[SNAPSHOT_TABLE] = (tables[SNAPSHOT_TABLE] ?? []).filter((x) => x !== s);
      }
      return ok({ restored: mine.length, remaining: (tables[SNAPSHOT_TABLE] ?? []).filter((s) => s.field_group === group && s.medium === medium).length });
    },
  };
}
