// Import run. index.ts has already authenticated and rate-limited.
// Cached versus fresh is selectListSource. Pages come from the injected fetch.
// Lines and the item cap come from lines.ts.
import {
  type AniListEntry,
  type AniListMediaType,
  type AniListStatus,
  buildPreviewItems,
  dedupeAndJoinLines,
  lineForEntry,
  takePage,
} from "./lines.ts";
import { selectListSource } from "./list_policy.ts";
import { fetchAniListPage, type AniListFetch } from "./paging.ts";
import { libraryItem } from "./structured.ts";

export type RequestBody = {
  mode?: "preview" | "import";
  username: string;
  stream?: boolean;
  cursor?: string;
  types?: AniListMediaType[];
  statuses?: AniListStatus[];
  maxItems?: number;
  perPage?: number;
  text?: string;
  cachedText?: string;
  publicListOnly?: boolean;
  truncated?: boolean;
};

const STATUSES: readonly AniListStatus[] = [
  "CURRENT",
  "COMPLETED",
  "PLANNING",
  "DROPPED",
  "PAUSED",
  "REPEATING",
];

function json(res: unknown, init: ResponseInit = {}) {
  return new Response(JSON.stringify(res), {
    ...init,
    headers: { "Content-Type": "application/json", ...(init.headers ?? {}) },
  });
}

function asBody(raw: unknown): Partial<RequestBody> {
  if (!raw || typeof raw !== "object") return {};
  return raw as Partial<RequestBody>;
}

export async function runAnilistImport(
  rawInput: unknown,
  deps: { fetch: AniListFetch },
): Promise<Response> {
  try {
    const raw = asBody(rawInput);
    const source = selectListSource(raw.stream ? { ...raw, text: undefined, cachedText: undefined } : raw);
    const username = String(raw.username ?? "").trim();
    if (source.kind === "fresh") {
      if (!username) return json({ success: false, error: "Missing username" }, { status: 400 });
      if (username.length > 64) return json({ success: false, error: "Username too long" }, { status: 400 });
    }

    const types = (Array.isArray(raw.types) ? raw.types : ["ANIME", "MANGA"])
      .map((t) => String(t).toUpperCase())
      .filter((t) => t === "ANIME" || t === "MANGA") as AniListMediaType[];
    const uniqueTypes = Array.from(new Set(types));
    if (uniqueTypes.length === 0) return json({ success: false, error: "No types selected" }, { status: 400 });

    const statuses = (Array.isArray(raw.statuses) ? raw.statuses : ["CURRENT", "COMPLETED", "PLANNING"])
      .map((s) => String(s).toUpperCase())
      .filter((s) => STATUSES.includes(s as AniListStatus)) as AniListStatus[];
    const uniqueStatuses = Array.from(new Set(statuses));
    if (uniqueStatuses.length === 0) return json({ success: false, error: "No statuses selected" }, { status: 400 });

    // Unchanged caps: 200 items by default, clamped to 25..400; pages of 50, clamped to 10..50.
    const maxItems = Math.max(25, Math.min(400, Number(raw.maxItems ?? 200)));
    const perPage = Math.max(10, Math.min(50, Number(raw.perPage ?? 50)));
    const publicListOnly = raw.publicListOnly ?? true;

    if (source.kind === "cached") {
      return json({
        success: true,
        source: "anilist",
        mode: source.mode,
        username: username || null,
        itemCount: source.itemCount,
        truncated: source.truncated,
        text: source.text,
        publicListOnly,
        cachedTextUsed: true,
      });
    }

    const lines: string[] = [];
    const libraryItems: ReturnType<typeof libraryItem>[] = [];
    const sampledEntries: Array<{ type: AniListMediaType; entry: AniListEntry }> = [];
    const countsByType: Record<AniListMediaType, number> = { ANIME: 0, MANGA: 0 };
    const countsByStatus: Record<AniListStatus, number> = {
      CURRENT: 0,
      COMPLETED: 0,
      PLANNING: 0,
      DROPPED: 0,
      PAUSED: 0,
      REPEATING: 0,
    };
    let total = 0;
    let truncated = false;

    let nextCursor: string | null = null;
    let typeIndex = 0, pageOffset = 0, firstPage = 1;
    if (raw.stream && raw.cursor) {
      try {
        const cursor = JSON.parse(atob(raw.cursor));
        if (cursor.username !== username || JSON.stringify(cursor.types) !== JSON.stringify(uniqueTypes) || JSON.stringify(cursor.statuses) !== JSON.stringify(uniqueStatuses)
          || !Number.isInteger(cursor.typeIndex) || cursor.typeIndex < 0 || cursor.typeIndex >= uniqueTypes.length
          || !Number.isInteger(cursor.page) || cursor.page < 1 || cursor.page > 100000
          || !Number.isInteger(cursor.offset) || cursor.offset < 0 || cursor.offset >= perPage) throw new Error("cursor");
        typeIndex = cursor.typeIndex; firstPage = cursor.page; pageOffset = cursor.offset;
      } catch { return json({success:false,error:"Invalid provider cursor"},{status:400}); }
    }
    const cursorFor = (typeIndex: number, page: number, offset: number) => btoa(JSON.stringify({username,types:uniqueTypes,statuses:uniqueStatuses,typeIndex,page,offset}));
    for (; typeIndex < uniqueTypes.length; typeIndex++) {
      const t = uniqueTypes[typeIndex];
      let page = firstPage; firstPage = 1;
      while (true) {
        const { entries, hasNextPage } = await fetchAniListPage(
          deps.fetch,
          username,
          t,
          uniqueStatuses,
          page,
          perPage,
          raw.stream ? "MEDIA_ID" : "UPDATED_TIME_DESC",
        );
        const offset = pageOffset; pageOffset = 0;
        const taken = takePage(entries.slice(offset), total, maxItems, hasNextPage);
        for (const e of taken.entries) {
          lines.push(lineForEntry(t, e));
          libraryItems.push(libraryItem(t, e));
          countsByType[t] += 1;
          countsByStatus[e.status] += 1;
          if (sampledEntries.length < 8) sampledEntries.push({ type: t, entry: e });
          total += 1;
        }
        if (taken.truncated) truncated = true;
        if (raw.stream && total >= maxItems) {
          const consumed = offset + taken.entries.length;
          if (consumed < entries.length) nextCursor = cursorFor(typeIndex,page,consumed);
          else if (hasNextPage) nextCursor = cursorFor(typeIndex,page+1,0);
          else if (typeIndex+1 < uniqueTypes.length) nextCursor = cursorFor(typeIndex+1,1,0);
        }
        if (!taken.fetchNextPage) break;
        page += 1;
      }
      if (total >= maxItems) break;
    }

    const { text, itemCount } = dedupeAndJoinLines(lines);
    const sampleItems = buildPreviewItems(lines, sampledEntries);
    return json({
      success: true,
      source: "anilist",
      mode: source.mode,
      username,
      itemCount,
      truncated,
      text,
      publicListOnly,
      countsByType,
      countsByStatus,
      sampleItems,
      libraryItems,
      types: uniqueTypes, statuses: uniqueStatuses,
      ...(raw.stream ? { nextCursor, sourceExhausted: nextCursor === null } : {}),
    });
  } catch (e) {
    const msg = (e instanceof Error ? e.message : String(e)).slice(0, 400);
    return json({ success: false, error: msg }, { status: 500 });
  }
}
