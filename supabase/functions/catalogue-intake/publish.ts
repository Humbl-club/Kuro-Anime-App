// publish (catalogue Task 15): the single writer of every field group whose mode is 'new'.
//
// For each such group it calls catalogue_publish_batch_v1 (supabase/prepared-migrations/
// 20261112100150_catalogue_publish_v1.sql), which in one transaction per batch of <= 500 titles
//   - snapshots the title's current columns and linked rows into catalogue_rollback_snapshots on the
//     first publish of the group (never overwritten while it exists),
//   - replaces main-row columns from catalogue_shadow_values (a null or absent shadow never blanks a
//     column; is_adult never clears) and replaces linked rows (credits, media_relations source='kuro').
// A group in 'anilist' or 'shadow' mode is never written here: AniList stays its writer.
// `data_sources` is copied once per title, with the first 'new' group in cutover order.
// Credits: new people/companies/characters are real inserts now that publish is the only writer, done
// by running the composer with allowCreate before the SQL batch, so the shadow credit lists name them.
// Which titles: handler run (runPublish) reads shadow rows changed since the group's last completed
// pass (computed_at watermark), paged below PostgREST's 1,000-row cap; a group first switched starts
// from the beginning.
import type { SupabaseLike } from "../_shared/catalogue/intake_persistence.ts";
import { FIELD_GROUP_COLUMNS, FIELD_GROUP_NAMES, type FieldGroup, type Mode, readCutoverModes } from "../_shared/catalogue/field_groups.ts";
import { compose, type ComposeDeps, type ComposeResult } from "./compose.ts";
import type { HandlerOutcome, RunContext } from "./context.ts";
import { chunk, clampInt, cursorKey, readCursor, WRITE_BATCH, writeCursor, type Medium } from "./store.ts";

export type PublishDeps = {
  supabase: SupabaseLike;
  /** Cutover modes; read from catalogue_cutover when absent (a failed read throws). */
  modes?: Record<FieldGroup, Mode>;
  /** Composer used for credits entity creation (tests inject a recorder). */
  compose?: (deps: ComposeDeps, medium: Medium, ids: number[]) => Promise<ComposeResult>;
  now?: () => number;
  /** Publish this group only (handler runs go one group at a time); modes still decide who owns data_sources. */
  onlyGroup?: FieldGroup;
};

export type GroupPublishResult = { titles: number; snapshotted: number; columnsUpdated: number; tablesReplaced: number };
export type PublishResult = { titles: number; groups: Partial<Record<FieldGroup, GroupPublishResult>>; skippedGroups: FieldGroup[] };

export async function publish(deps: PublishDeps, medium: Medium, mediaIds: number[]): Promise<PublishResult> {
  const ids = [...new Set(mediaIds)].sort((a, b) => a - b);
  const modes = deps.modes ?? (await readCutoverModes(deps.supabase));
  const result: PublishResult = { titles: ids.length, groups: {}, skippedGroups: [] };
  const firstNewGroup = FIELD_GROUP_NAMES.find((g) => modes[g] === "new");
  for (const group of FIELD_GROUP_NAMES) {
    if (deps.onlyGroup && group !== deps.onlyGroup) continue;
    if (modes[group] !== "new") {
      result.skippedGroups.push(group);
      continue;
    }
    const acc: GroupPublishResult = { titles: 0, snapshotted: 0, columnsUpdated: 0, tablesReplaced: 0 };
    for (const part of chunk(ids, WRITE_BATCH)) {
      if (group === "credits") await (deps.compose ?? compose)({ supabase: deps.supabase, now: deps.now, allowCreate: true }, medium, part);
      const { data, error } = await deps.supabase.rpc("catalogue_publish_batch_v1", {
        p_medium: medium,
        p_group: group,
        p_media_ids: part,
        p_columns: [...FIELD_GROUP_COLUMNS[medium][group]],
        p_with_data_sources: group === firstNewGroup,
      });
      if (error) throw new Error(`catalogue_publish_batch_v1(${group}) failed: ${error.message ?? error}`);
      const r = (data ?? {}) as Record<string, number>;
      acc.titles += Number(r.titles ?? 0);
      acc.snapshotted += Number(r.snapshotted ?? 0);
      acc.columnsUpdated += Number(r.columns_updated ?? 0);
      acc.tablesReplaced += Number(r.tables_replaced ?? 0);
    }
    result.groups[group] = acc;
  }
  return result;
}

// ---------------------------------------------------------------------------------------------
// list_only visibility (Task 15b): while the identity group is 'new', titles without an accepted link are
// hidden from browse and recommendations (they stay readable everywhere else). Applied in batches by
// catalogue_apply_visibility_v1 until it reports no change.

export const VISIBILITY_BATCH = 5000;
const VISIBILITY_MAX_CALLS = 20;

/** Applies (identity 'new') or lifts (otherwise) list_only for one medium. Returns the rows changed. Throws on a failed call. */
export async function applyVisibility(supabase: SupabaseLike, medium: Medium): Promise<number> {
  let changed = 0;
  for (let i = 0; i < VISIBILITY_MAX_CALLS; i++) {
    const { data, error } = await supabase.rpc("catalogue_apply_visibility_v1", { p_medium: medium, p_limit: VISIBILITY_BATCH });
    if (error) throw new Error(`catalogue_apply_visibility_v1(${medium}) failed: ${error.message ?? error}`);
    const n = Number(data ?? 0);
    changed += n;
    if (n === 0) break;
  }
  return changed;
}

// ---------------------------------------------------------------------------------------------
// Handler run. Cursor (import_track_state `catalogue-intake:publish:<medium>`):
//   { groups: { <group>: { since: iso | null, last_id: number } } }

export const PUBLISH_DEFAULT_LIMIT = 500;
type GroupCursor = { since: string | null; last_id: number };

/** Distinct media ids in id order with shadow rows computed after `since`, above `afterId`. Pages below 1,000 rows. */
export async function readShadowIds(supabase: SupabaseLike, medium: Medium, afterId: number, since: string | null, limit: number): Promise<number[]> {
  const ids: number[] = [];
  let last = afterId;
  while (ids.length < limit) {
    let q = supabase.from("catalogue_shadow_values").select("media_id").eq("medium", medium).gt("media_id", last);
    if (since) q = q.gt("computed_at", since);
    const { data, error } = await q.order("media_id", { ascending: true }).limit(1000);
    if (error) throw new Error(`catalogue_shadow_values read failed: ${error.message ?? error}`);
    const page = (data ?? []) as { media_id: number }[];
    for (const r of page) {
      if (ids[ids.length - 1] !== r.media_id) ids.push(r.media_id);
      if (ids.length >= limit) break;
    }
    if (page.length < 1000 || ids.length >= limit) break;
    last = page[page.length - 1].media_id;
  }
  return ids.slice(0, limit);
}

export async function runPublish(ctx: RunContext): Promise<HandlerOutcome> {
  const modes = await readCutoverModes(ctx.supabase);
  const key = cursorKey("publish", ctx.medium);
  const cursor = (await readCursor<{ groups?: Record<string, GroupCursor> }>(ctx.supabase, key)) ?? {};
  const state: Record<string, GroupCursor> = { ...(cursor.groups ?? {}) };
  const limit = clampInt(ctx.limit, PUBLISH_DEFAULT_LIMIT, 1, 5000);
  const results: Record<string, unknown> = { titles: 0, columnsUpdated: 0, tablesReplaced: 0, groups: {} as Record<string, unknown> };
  let stoppedEarly: string | undefined;
  const passStart = new Date(ctx.now()).toISOString();

  // A group that is no longer 'new' drops its watermark: a later switch starts from the beginning.
  for (const g of Object.keys(state)) if (modes[g as FieldGroup] !== "new") delete state[g];

  for (const group of FIELD_GROUP_NAMES) {
    if (modes[group] !== "new") continue;
    if (ctx.now() >= ctx.deadlineMs) {
      stoppedEarly = "budget";
      break;
    }
    const gs = state[group] ?? { since: null, last_id: 0 };
    const ids = await readShadowIds(ctx.supabase, ctx.medium, gs.last_id, gs.since, limit);
    if (ids.length > 0) {
      const r = await publish({ supabase: ctx.supabase, modes, now: ctx.now, onlyGroup: group }, ctx.medium, ids);
      const gr = r.groups[group];
      (results.groups as Record<string, unknown>)[group] = gr;
      results.titles = Number(results.titles) + ids.length;
      results.columnsUpdated = Number(results.columnsUpdated) + (gr?.columnsUpdated ?? 0);
      results.tablesReplaced = Number(results.tablesReplaced) + (gr?.tablesReplaced ?? 0);
    }
    state[group] = ids.length < limit ? { since: passStart, last_id: 0 } : { since: gs.since, last_id: ids[ids.length - 1] };
  }
  // Visibility follows the identity group; checked every run because a title can gain an accepted link without a shadow change.
  if (modes.identity === "new" && !stoppedEarly) results.visibilityChanged = await applyVisibility(ctx.supabase, ctx.medium);
  await writeCursor(ctx.supabase, key, ctx.medium, { groups: state }, results, stoppedEarly ? `stopped_early:${stoppedEarly}` : null);
  return { results, stoppedEarly };
}
