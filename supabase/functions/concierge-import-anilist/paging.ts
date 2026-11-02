// AniList list paging. Fetch is injected; this module does not call the network itself.
// The query still asks for POINT_10 scores, list status, and seasonYear.
import type { AniListEntry, AniListMediaType, AniListStatus } from "./lines.ts";

const ANILIST_URL = "https://graphql.anilist.co";

export type AniListFetch = typeof fetch;

export async function fetchAniListPage(
  fetchImpl: AniListFetch,
  username: string,
  type: AniListMediaType,
  statuses: AniListStatus[],
  page: number,
  perPage: number,
  sort: "MEDIA_ID" | "UPDATED_TIME_DESC" = "UPDATED_TIME_DESC",
): Promise<{ entries: AniListEntry[]; hasNextPage: boolean }> {
  const query = `
    query($username: String, $type: MediaType, $page: Int, $perPage: Int, $statuses: [MediaListStatus]) {
      User(name: $username) { mediaListOptions { scoreFormat rowOrder animeList { sectionOrder customLists splitCompletedSectionByFormat advancedScoring advancedScoringEnabled } mangaList { sectionOrder customLists splitCompletedSectionByFormat advancedScoring advancedScoringEnabled } } }
      Page(page: $page, perPage: $perPage) {
        pageInfo { hasNextPage }
        mediaList(userName: $username, type: $type, status_in: $statuses, sort: ${sort}) {
          status
          progress
          progressVolumes
          repeat
          notes
          private
          hiddenFromStatusLists
          customLists(asArray: false)
          startedAt { year month day }
          completedAt { year month day }
          score(format: POINT_10)
          scoreRaw: score(format: POINT_100)
          original3: score(format: POINT_3)
          original5: score(format: POINT_5)
          original10: score(format: POINT_10)
          originalDecimal: score(format: POINT_10_DECIMAL)
          updatedAt
          media {
            id
            seasonYear
            startDate { year }
            format
            title { english romaji native }
          }
        }
      }
    }
  `;

  const body = JSON.stringify({
    query,
    variables: { username, type, page, perPage, statuses },
  });

  const res = await fetchImpl(ANILIST_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json", "Accept": "application/json" },
    body,
  });

  if (!res.ok) {
    const snippet = await res.text().catch(() => "");
    throw new Error(`AniList error ${res.status}: ${snippet.slice(0, 280)}`);
  }

  const jsonRes = await res.json();
  if (jsonRes?.errors?.length) {
    const msg = String(jsonRes.errors?.[0]?.message ?? "Unknown AniList error");
    throw new Error(`AniList GraphQL: ${msg}`);
  }

  const pageObj = jsonRes?.data?.Page;
  const options = jsonRes?.data?.User?.mediaListOptions;
  const entryOptions = type === "ANIME" ? options?.animeList : options?.mangaList;
  const entries = ((pageObj?.mediaList ?? []) as AniListEntry[]).map((entry) => {
    const rawByFormat: Record<string, number | null | undefined> = {
      POINT_3: entry.original3, POINT_5: entry.original5, POINT_10: entry.original10,
      POINT_10_DECIMAL: entry.originalDecimal, POINT_100: entry.scoreRaw,
    };
    const format = String(options?.scoreFormat ?? "");
    return { ...entry, scoreRaw: format in rawByFormat ? rawByFormat[format] ?? null : entry.scoreRaw,
      scoreFormat: format in rawByFormat ? format : undefined,
      customListOrder: entryOptions?.customLists ?? undefined,
      sourceListOptions: options ? JSON.stringify({ scoreFormat: options.scoreFormat, rowOrder: options.rowOrder, ...entryOptions }) : undefined };
  });
  const hasNextPage = Boolean(pageObj?.pageInfo?.hasNextPage);
  return { entries, hasNextPage };
}
