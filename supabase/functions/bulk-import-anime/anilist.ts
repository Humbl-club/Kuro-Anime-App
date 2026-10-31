// AniList provider transport for bulk-import-anime: the anime page query plus
// retry/backoff on 429, 5xx and thrown fetch errors. Manga keeps its own query.

const ANILIST_API = 'https://graphql.anilist.co';

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function fetchJsonWithRetry(query: string, variables: Record<string, unknown>, retries: number) {
  let attempt = 0;
  while (true) {
    try {
      const res = await fetch(ANILIST_API, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ query, variables })
      });
      if (res.ok) return await res.json();
      if ((res.status === 429 || res.status >= 500) && attempt < retries) {
        await sleep(500 * Math.pow(2, attempt));
        attempt++;
        continue;
      }
      throw new Error(`AniList error ${res.status}`);
    } catch (e) {
      if (attempt < retries) {
        await sleep(500 * Math.pow(2, attempt));
        attempt++;
        continue;
      }
      throw e;
    }
  }
}

export async function fetchAniListAnimeData(page: number, perPage: number, includeRelations: boolean, includeEpisodes: boolean, retries: number) {
  const episodesFragment = includeEpisodes ? `streamingEpisodes { title thumbnail url site }` : ``;
  const externalLinksFragment = `
          externalLinks { site url language color }`;
  const relationsFragment = includeRelations ? `
          relations {
            edges {
              relationType(version: 2)
              node { id type format title { romaji english native userPreferred } coverImage { large } }
            }
          }
          studios { nodes { id name isAnimationStudio siteUrl favourites } }
          tags { id name description category rank isGeneralSpoiler isMediaSpoiler isAdult }
          # Keep character ingestion intentionally compact: AniList ROLE sort puts mains first.
          characters(sort: ROLE, perPage: 10) { edges { role } nodes { id name { full native } image { large } description gender age } }
          staff(sort: RELEVANCE, perPage: 10) { edges { role } nodes { id name { full native } image { large } description primaryOccupations } }
  ` : ``;
  const query = `
    query ($page: Int, $perPage: Int) {
      Page(page: $page, perPage: $perPage) {
        media(sort: POPULARITY_DESC, type: ANIME) {
          id idMal
          title { romaji english native userPreferred }
          synonyms hashtag
          coverImage { extraLarge large medium color }
          bannerImage
          type format status
          description(asHtml: false)
          source countryOfOrigin isAdult
          startDate { year month day }
          endDate { year month day }
          episodes duration
          season seasonYear
          nextAiringEpisode { episode airingAt timeUntilAiring }
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
  const data = await fetchJsonWithRetry(query, { page, perPage }, retries);
  return data?.data?.Page?.media ?? [];
}
