// A conflicting upstream MAL alias must not stall the AniList-keyed catalogue page.
// Retry ONLY that unique constraint, preserving the existing owner of the MAL id.
// Other constraints, provider errors and failed retries still fail the page.
export async function writeWithMALConflict<T>(
  medium: "anime" | "manga",
  write: (omitMalId: boolean) => PromiseLike<{ data: T; error: unknown }>,
  metrics: { identityConflicts?: number; identityConflictSample?: unknown[] },
  identity?: { anilistId: number; malId: number },
): Promise<{ data: T; error: unknown }> {
  const first = await write(false);
  const error = first.error as { code?: string; message?: string } | null;
  if (error?.code !== "23505" || !error.message?.includes(`${medium}_mal_id_key`)) return first;
  metrics.identityConflicts = (metrics.identityConflicts ?? 0) + 1;
  if (identity) {
    metrics.identityConflictSample ??= [];
    if (metrics.identityConflictSample.length < 10) metrics.identityConflictSample.push({ medium, ...identity });
  }
  console.warn(`${medium}: conflicting MAL alias omitted; existing identity preserved`);
  return await write(true);
}
