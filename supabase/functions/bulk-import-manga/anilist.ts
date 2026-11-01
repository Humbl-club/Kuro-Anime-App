// AniList provider transport for bulk-import-manga: the manga page query. Spacing, Retry-After,
// timeouts and GraphQL error detection live in ../_shared/anilist_client.ts (one limiter per
// isolate, shared with bulk-import-anime and release-intake). A GraphQL error or a response
// without data.Page throws; only a real empty page returns [].
import { type AniListClient, createAniListClient } from "../_shared/anilist_client.ts";
import type { PageQueryOptions } from "../bulk-import-anime/tracks.ts";

let defaultClient: AniListClient | null = null;
function client(): AniListClient {
  defaultClient ??= createAniListClient();
  return defaultClient;
}

/** The page query for one track. Variables are declared only when used (GraphQL rejects unused ones). */
export function buildMangaPageQuery(includeRelations: boolean, withStatusFilter: boolean): string {
  const relationsFragment = includeRelations ? `
          relations {
            edges {
              relationType(version: 2)
              node { id type }
            }
          }
          staff(sort: RELEVANCE, perPage: 10) { edges { role } nodes { id name { full native } image { large } description primaryOccupations } }
          tags { id name description category rank isGeneralSpoiler isMediaSpoiler isAdult }
          # Keep character ingestion intentionally compact: AniList ROLE sort puts mains first.
          characters(sort: ROLE, perPage: 10) { edges { role } nodes { id name { full native } image { large } description gender age } }
  ` : ``;
  const externalLinksFragment = `
          externalLinks { site url language color isDisabled }`;
  const statusDecl = withStatusFilter ? `, $statusIn: [MediaStatus]` : ``;
  const statusArg = withStatusFilter ? `, status_in: $statusIn` : ``;
  return `
    query ($page: Int, $perPage: Int, $sort: [MediaSort]${statusDecl}) {
      Page(page: $page, perPage: $perPage) {
        media(sort: $sort, type: MANGA${statusArg}) {
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
          chapters volumes
          averageScore meanScore popularity trending favourites
          genres
          siteUrl updatedAt
          ${externalLinksFragment}
          ${relationsFragment}
        }
      }
    }
  `;
}

export async function fetchAniListMangaData(
  page: number,
  perPage: number,
  includeRelations: boolean,
  retries: number,
  options: PageQueryOptions = { sort: "POPULARITY_DESC", statusIn: null },
  anilist: AniListClient = client(),
  // deno-lint-ignore no-explicit-any
): Promise<any[]> {
  const withStatus = Array.isArray(options.statusIn) && options.statusIn.length > 0;
  const variables: Record<string, unknown> = { page, perPage, sort: [options.sort] };
  if (withStatus) variables.statusIn = options.statusIn;
  const data = await anilist.query(buildMangaPageQuery(includeRelations, withStatus), variables, {
    require: ["Page"],
    deadlineMs: options.deadlineMs,
    retries,
  });
  const media = data.Page.media;
  if (!Array.isArray(media)) throw new Error("AniList response is missing data.Page.media");
  return media;
}
