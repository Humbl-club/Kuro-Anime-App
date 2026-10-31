// AniList provider transport for bulk-import-manga: the manga page query plus
// the same retry/backoff as anime (429, 5xx, and thrown fetch errors). The query
// and the retry loop stay here; they are short and the page shape is manga-specific.

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

export async function fetchAniListMangaData(page: number, perPage: number, includeRelations: boolean, retries: number) {
  const relationsFragment = includeRelations ? `
          relations {
            edges {
              relationType(version: 2)
              node { id type format title { romaji english native userPreferred } coverImage { large } }
            }
          }
          staff(sort: RELEVANCE, perPage: 10) { edges { role } nodes { id name { full native } image { large } description primaryOccupations } }
          tags { id name description category rank isGeneralSpoiler isMediaSpoiler isAdult }
          # Keep character ingestion intentionally compact: AniList ROLE sort puts mains first.
          characters(sort: ROLE, perPage: 10) { edges { role } nodes { id name { full native } image { large } description gender age } }
  ` : ``;
  const externalLinksFragment = `
          externalLinks { site url language color }`;
  const query = `
    query ($page: Int, $perPage: Int) {
      Page(page: $page, perPage: $perPage) {
        media(sort: POPULARITY_DESC, type: MANGA) {
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
  const data = await fetchJsonWithRetry(query, { page, perPage }, retries);
  return data?.data?.Page?.media ?? [];
}
