// Test support for the concierge-recommend router tests (NOT imported by index.ts or handler.ts, never deployed).
//
// `routePrompt` wires a prompt into the REAL production chain (router.ts `routePrimaryMode`)
// with exactly the inputs handler.ts computes for it: inferSeedQuery, inferMediaType(text, scope),
// inferRequiredGenres, extractConstraints (excluded genres come from the TEXT, never from the
// request body), anchorModes(modeById). Only the `search_titles` RPC is faked.
//
// The fake models one external outcome: the catalog contains a handful of real titles and
// `search_titles` returns a confident (>= 0.45) row only for those. Any other bare prompt gets
// no confident row. In production the outcome for non-title bare prompts depends on live
// trigram similarity; `searchCalls` lets the tests report which cases are contingent on it.
import {
  anchorModes,
  type ConciergeMode,
  defaultModes,
  extractConstraints,
  inferMediaType,
  inferRequiredGenres,
  inferSeedQuery,
  type MediaType,
  parseModesFromConfig,
  type PrimaryRoute,
  routePrimaryMode,
  type SearchTitlesPort,
} from "./router.ts";
import modesFixture from "./router_modes.fixture.json" with { type: "json" };

/** Real titles the fake catalog knows (the targets of expandKnownAbbrevSeed). */
export const FAKE_CATALOG_TITLES = [
  "Attack on Titan",
  "Hunter x Hunter",
  "Fullmetal Alchemist: Brotherhood",
  "Neon Genesis Evangelion",
  "Legend of the Galactic Heroes",
  "One Piece",
];

const normTitle = (s: string) => s.toLowerCase().replace(/\b(19|20)\d{2}\b/g, "").replace(/\s+/g, " ").trim();

/** Modes as get_concierge_config returns them after the migration chain (23 modes). */
export const MIGRATION_CHAIN_MODES: ConciergeMode[] = parseModesFromConfig(modesFixture);
/** The code fallback used when the config has no valid modes (17 modes). */
export const FALLBACK_MODES: ConciergeMode[] = defaultModes();

export type RoutedPrompt = PrimaryRoute & {
  /** `${mediaType}:${query}` for every search_titles call the chain made. */
  searchCalls: string[];
  excludedGenres: string[];
};

export function catalogSearch(calls: string[], titles = FAKE_CATALOG_TITLES, score = 0.95): SearchTitlesPort {
  return (query: string, mt: MediaType) => {
    calls.push(`${mt}:${query}`);
    const hit = titles.find((t) => normTitle(t) === normTitle(query));
    return Promise.resolve({
      data: hit ? [{ media_id: 1000 + titles.indexOf(hit), title_raw: hit, score }] : [],
      error: null,
    });
  };
}

export async function routePrompt(
  prompt: string,
  modes: ConciergeMode[] = MIGRATION_CHAIN_MODES,
  opts: { scope?: string; search?: (calls: string[]) => SearchTitlesPort } = {},
): Promise<RoutedPrompt> {
  const text = String(prompt ?? "");
  const modeById = new Map<string, ConciergeMode>(modes.map((m) => [m.id, m]));
  const { classicsMode, premiumMode } = anchorModes(modeById);
  const constraints = extractConstraints(text);
  const searchCalls: string[] = [];
  const search = opts.search ? opts.search(searchCalls) : catalogSearch(searchCalls);
  const route = await routePrimaryMode(
    {
      text,
      seedQuery: inferSeedQuery(text),
      mediaType: inferMediaType(text, opts.scope ?? "both"),
      modeById,
      classicsId: classicsMode?.id ?? "classics_expanded",
      premiumId: premiumMode?.id,
      requiredGenres: inferRequiredGenres(text),
      userExcludedGenres: constraints.excluded_genres,
      constraints,
    },
    search,
  );
  return { ...route, searchCalls, excludedGenres: constraints.excluded_genres };
}
