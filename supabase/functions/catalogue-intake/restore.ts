// restore (catalogue Task 15): rollback of one field group to its pre-switch state.
//
// Precondition: the group's mode is already back to 'anilist' (or 'shadow'); a group that is still
// 'new' is refused, so publish and restore never write the same group. It writes the snapshot taken at
// the first publish back through catalogue_restore_batch_v1 (main-row columns exactly, linked rows with
// their ids), in batches of <= 500 titles per medium, and records its duration in import_runs. It makes
// no AniList request: nothing here talks to a source, so values never blank while the importer is off.
import type { SupabaseLike } from "../_shared/catalogue/intake_persistence.ts";
import { finishImportRun, startImportRun } from "../_shared/catalogue/intake_persistence.ts";
import { type FieldGroup, FIELD_GROUP_NAMES, readCutoverModes } from "../_shared/catalogue/field_groups.ts";
import { WRITE_BATCH, type Medium } from "./store.ts";

export type RestoreDeps = { supabase: SupabaseLike; now?: () => number };
export type RestoreResult = { group: FieldGroup; restored: Record<Medium, number>; durationMs: number; batches: number };

const MEDIA: Medium[] = ["anime", "manga"];

export async function restore(deps: RestoreDeps, group: FieldGroup): Promise<RestoreResult> {
  if (!FIELD_GROUP_NAMES.includes(group)) throw new Error(`restore: unknown group ${String(group)}`);
  const now = deps.now ?? Date.now;
  const modes = await readCutoverModes(deps.supabase);
  if (modes[group] === "new") throw new Error(`restore: group ${group} is still 'new'; switch it back first`);
  const startedMs = now();
  const runId = await startImportRun(deps.supabase, "CATALOGUE", `catalogue_restore_${group}`, { group });
  const restored: Record<Medium, number> = { anime: 0, manga: 0 };
  let batches = 0;
  try {
    for (const medium of MEDIA) {
      for (;;) {
        const { data, error } = await deps.supabase.rpc("catalogue_restore_batch_v1", { p_medium: medium, p_group: group, p_limit: WRITE_BATCH });
        if (error) throw new Error(`catalogue_restore_batch_v1(${medium}, ${group}) failed: ${error.message ?? error}`);
        const r = (data ?? {}) as { restored?: number; remaining?: number };
        batches++;
        restored[medium] += Number(r.restored ?? 0);
        if (Number(r.remaining ?? 0) === 0 || Number(r.restored ?? 0) === 0) break;
      }
    }
  } catch (e) {
    await finishImportRun(deps.supabase, runId, "error", { group, restored }, e instanceof Error ? e.message : String(e), startedMs);
    throw e;
  }
  const durationMs = now() - startedMs;
  await finishImportRun(deps.supabase, runId, "success", { group, restored, batches, durationMs }, null, startedMs);
  return { group, restored, durationMs, batches };
}
