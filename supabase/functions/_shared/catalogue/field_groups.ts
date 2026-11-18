// Field groups of the catalogue cutover (docs/superpowers/plans/2026-11-09-catalogue-sources.md Task 2).
//
// One definition of "which published columns and linked tables belong to which group", used by
// `publish` (catalogue-intake) and by every AniList-path writer. A group is written by exactly
// one side at a time: mode 'anilist' and 'shadow' keep AniList as the writer, 'new' hands the
// group to `publish`. The per-group mode lives in public.catalogue_cutover
// (supabase/prepared-migrations/20261112100000_catalogue_sources_v1.sql).

export type FieldGroup =
  | "identity"
  | "titles"
  | "facts"
  | "relations"
  | "credits"
  | "popularity"
  | "tags"
  | "adult"
  | "synopsis"
  | "episodes"
  | "links"
  | "images";

export type Mode = "anilist" | "shadow" | "new";
export type Medium = "anime" | "manga";

/** The 12 groups, in cutover-table order (spec section 5 sequence is a separate concern). */
export const FIELD_GROUP_NAMES: readonly FieldGroup[] = [
  "identity",
  "titles",
  "facts",
  "relations",
  "credits",
  "popularity",
  "tags",
  "adult",
  "synopsis",
  "episodes",
  "links",
  "images",
] as const;

const MODES: readonly Mode[] = ["anilist", "shadow", "new"];

export const CATALOGUE_USER_AGENT = "Kuro-Catalogue/1.0 (+https://kuro-legal.vercel.app/kontakt.html)";

const DATE_COLUMNS = [
  "start_date_year", "start_date_month", "start_date_day", "end_date_year", "end_date_month", "end_date_day",
] as const;

const COMMON = {
  identity: ["mal_id"],
  titles: ["title_english", "title_romaji", "title_native", "title_synonyms"],
  relations: [],
  credits: [],
  popularity: ["popularity", "trending", "average_score", "mean_score", "favourites"],
  tags: ["genres"],
  adult: ["is_adult", "age_rating"],
  synopsis: ["description"],
  links: ["site_url"],
  images: ["cover_image_large", "cover_image_medium", "cover_image_color", "banner_image"],
} as const;

/** Published main-row columns per group. Relations and credits own linked tables only. */
export const FIELD_GROUP_COLUMNS: Record<Medium, Record<FieldGroup, readonly string[]>> = {
  anime: {
    ...COMMON,
    facts: [
      "format", "status", ...DATE_COLUMNS, "episodes", "duration", "total_duration", "season", "season_year",
      "country_of_origin", "source",
    ],
    episodes: ["next_episode_number", "next_airing_at"],
  },
  manga: {
    ...COMMON,
    facts: ["format", "status", ...DATE_COLUMNS, "chapters", "volumes", "country_of_origin", "source"],
    episodes: ["next_chapter_number", "next_chapter_at"],
  },
};

/** Linked tables each group owns (a table belongs to one group per medium). */
export const FIELD_GROUP_TABLES: Record<Medium, Partial<Record<FieldGroup, readonly string[]>>> = {
  anime: {
    links: ["external_links"],
    episodes: ["episodes"],
    credits: ["anime_studios", "anime_characters", "anime_staff", "character_voice_actors"],
    tags: ["anime_tags"],
    relations: ["media_relations"],
  },
  manga: {
    links: ["external_links"],
    episodes: ["chapters", "volumes"],
    credits: ["manga_authors", "manga_characters", "manga_staff"],
    tags: ["manga_tags"],
    relations: ["media_relations"],
  },
};

/** Main-row columns of every group whose mode is 'new'. */
export function columnsOwnedByNew(medium: Medium, modes: Record<FieldGroup, Mode>): Set<string> {
  const owned = new Set<string>();
  for (const group of FIELD_GROUP_NAMES) {
    if (modes[group] === "new") for (const column of FIELD_GROUP_COLUMNS[medium][group]) owned.add(column);
  }
  return owned;
}

/**
 * True while AniList (importers, release-intake, mirror-images) remains the writer of the group:
 * every mode except 'new'. Every AniList-path writer checks this before touching a group's
 * columns or linked tables.
 */
export function groupIsAniListOwned(group: FieldGroup, modes: Record<FieldGroup, Mode>): boolean {
  return modes[group] !== "new";
}

// deno-lint-ignore no-explicit-any
type SupabaseLike = any;

/**
 * Reads public.catalogue_cutover. Fails closed: a read error, a missing group or an unknown mode
 * throws, so a caller never mistakes an unreadable switch for "AniList owns everything" and
 * skips nothing by accident.
 */
export async function readCutoverModes(supabase: SupabaseLike): Promise<Record<FieldGroup, Mode>> {
  const { data, error } = await supabase.from("catalogue_cutover").select("field_group, mode");
  if (error) {
    throw new Error(`catalogue_cutover unreadable: ${(error as { message?: string }).message ?? "error"}`);
  }
  if (!Array.isArray(data)) throw new Error("catalogue_cutover unreadable: no rows");
  const byGroup = new Map<string, unknown>();
  for (const row of data as { field_group?: unknown; mode?: unknown }[]) byGroup.set(String(row.field_group), row.mode);
  const modes = {} as Record<FieldGroup, Mode>;
  for (const group of FIELD_GROUP_NAMES) {
    const mode = byGroup.get(group);
    if (mode === undefined) throw new Error(`catalogue_cutover has no row for group ${group}`);
    if (!MODES.includes(mode as Mode)) throw new Error(`catalogue_cutover group ${group} has unknown mode ${String(mode)}`);
    modes[group] = mode as Mode;
  }
  return modes;
}
