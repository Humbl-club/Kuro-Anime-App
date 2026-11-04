// AniList provider transport for bulk-import-anime: the anime page query. Spacing, Retry-After,
// timeouts and GraphQL error detection live in ../_shared/anilist_client.ts (one limiter per
// isolate, shared with bulk-import-manga and release-intake). A GraphQL error or a response
// without data.Page throws; only a real empty page returns [].
import { type AniListClient, createAniListClient } from "../_shared/anilist_client.ts";
import type { PageQueryOptions } from "./tracks.ts";

let defaultClient: AniListClient | null = null;
function client(): AniListClient {
  defaultClient ??= createAniListClient();
  return defaultClient;
}

/** The page query for one track. Variables are declared only when used (GraphQL rejects unused ones). */
export function buildAnimePageQuery(
  includeRelations: boolean,
  includeEpisodes: boolean,
  withStatusFilter: boolean,
  includeVoiceActors = false,
): string {
  // Voice actors (owner item 4, 2026-11-03): opt-in only (payload includeVoiceActors, default off),
  // so the deployed query and its AniList complexity are unchanged until the lead enables it.
  // edges.node.id lets the mapping verify that edges[i] belongs to nodes[i].
  const voiceActorsFragment = includeRelations && includeVoiceActors
    ? ` node { id } voiceActors(language: JAPANESE, sort: [RELEVANCE, ID]) { id name { full native } image { large } }`
    : ``;
  const episodesFragment = includeEpisodes ? `streamingEpisodes { title thumbnail url site }` : ``;
  const externalLinksFragment = `
          externalLinks { site url language color isDisabled }`;
  const relationsFragment = includeRelations ? `
          relations {
            edges {
              relationType(version: 2)
              node { id type }
            }
          }
          studios { nodes { id name isAnimationStudio siteUrl favourites } }
          tags { id name description category rank isGeneralSpoiler isMediaSpoiler isAdult }
          # Keep character ingestion intentionally compact: AniList ROLE sort puts mains first.
          characters(sort: ROLE, perPage: 10) { edges { role${voiceActorsFragment} } nodes { id name { full native } image { large } description gender age } }
          staff(sort: RELEVANCE, perPage: 10) { edges { role } nodes { id name { full native } image { large } description primaryOccupations } }
  ` : ``;
  const statusDecl = withStatusFilter ? `, $statusIn: [MediaStatus]` : ``;
  const statusArg = withStatusFilter ? `, status_in: $statusIn` : ``;
  return `
    query ($page: Int, $perPage: Int, $sort: [MediaSort]${statusDecl}) {
      Page(page: $page, perPage: $perPage) {
        media(sort: $sort, type: ANIME${statusArg}) {
          id idMal
          title { romaji english native }
          synonyms
          coverImage { large medium color }
          bannerImage
          format status
          description(asHtml: false)
          source countryOfOrigin isAdult
          startDate { year month day }
          endDate { year month day }
          episodes duration
          season seasonYear
          nextAiringEpisode { episode airingAt }
          averageScore meanScore popularity trending favourites
          genres
          siteUrl updatedAt
          ${episodesFragment}
          ${externalLinksFragment}
          ${relationsFragment}
        }
      }
    }
  `;
}

export async function fetchAniListAnimeData(
  page: number,
  perPage: number,
  includeRelations: boolean,
  includeEpisodes: boolean,
  retries: number,
  options: PageQueryOptions = { sort: "POPULARITY_DESC", statusIn: null },
  anilist: AniListClient = client(),
  // deno-lint-ignore no-explicit-any
): Promise<any[]> {
  const withStatus = Array.isArray(options.statusIn) && options.statusIn.length > 0;
  const variables: Record<string, unknown> = { page, perPage, sort: [options.sort] };
  if (withStatus) variables.statusIn = options.statusIn;
  const query = buildAnimePageQuery(includeRelations, includeEpisodes, withStatus, options.includeVoiceActors === true);
  const data = await anilist.query(query, variables, {
    require: ["Page"],
    deadlineMs: options.deadlineMs,
    retries,
  });
  const media = data.Page.media;
  if (!Array.isArray(media)) throw new Error("AniList response is missing data.Page.media");
  return media;
}
