// Offline import run. Fetch is injected. Nothing calls graphql.anilist.co.
import { assertEquals } from "jsr:@std/assert@1";
import type { AniListEntry } from "./lines.ts";
import { runAnilistImport } from "./run.ts";

function entry(id: number, title: string, year = 2020): AniListEntry {
  return {
    status: "COMPLETED",
    progress: 12,
    score: 8,
    updatedAt: 1_700_000_000,
    media: {
      id,
      seasonYear: year,
      startDate: { year: year - 1 },
      format: "TV",
      title: { english: title, romaji: null, native: null },
    },
  };
}

function pageResponse(entries: AniListEntry[], hasNextPage: boolean): Response {
  return new Response(JSON.stringify({
    data: {
      Page: {
        pageInfo: { hasNextPage },
        mediaList: entries,
      },
    },
  }), { status: 200, headers: { "Content-Type": "application/json" } });
}

Deno.test("cached import returns truncated true in the declared shape and does not fetch", async () => {
  let fetched = 0;
  const fetchImpl: typeof fetch = () => {
    fetched += 1;
    return Promise.reject(new Error("live AniList must not be called"));
  };
  const res = await runAnilistImport({
    mode: "import",
    username: "kuro",
    types: ["ANIME"],
    statuses: ["COMPLETED"],
    text: "Naruto (2002) (completed)\n\nNaruto (2002) (completed)\nBleach (2004) (watching)",
    truncated: true,
    publicListOnly: false,
  }, { fetch: fetchImpl });

  assertEquals(res.status, 200);
  assertEquals(fetched, 0);
  const body = await res.json();
  assertEquals(body, {
    success: true,
    source: "anilist",
    mode: "import",
    username: "kuro",
    itemCount: 2,
    truncated: true,
    text: "Naruto (2002) (completed)\nBleach (2004) (watching)",
    publicListOnly: false,
    cachedTextUsed: true,
  });
});

Deno.test("fresh import pages under the cap and truncates at the cap", async () => {
  const calls: Array<{ url: string; body: string }> = [];
  const pages = [
    pageResponse([entry(1, "Page One"), entry(2, "Page Two")], true),
    pageResponse([entry(3, "Page Three", 1998)], false),
  ];
  const fetchImpl: typeof fetch = (input, init) => {
    calls.push({ url: String(input), body: String(init?.body ?? "") });
    const next = pages.shift();
    if (!next) return Promise.reject(new Error("unexpected extra page"));
    return Promise.resolve(next);
  };

  const under = await runAnilistImport({
    mode: "import",
    username: "kuro",
    types: ["ANIME"],
    statuses: ["COMPLETED"],
    maxItems: 25,
  }, { fetch: fetchImpl });
  assertEquals(under.status, 200);
  const underBody = await under.json();
  assertEquals(calls.length, 2);
  assertEquals(calls[0].url, "https://graphql.anilist.co");
  assertEquals(calls[1].url, "https://graphql.anilist.co");
  const firstQuery = JSON.parse(calls[0].body);
  assertEquals(firstQuery.variables, {
    username: "kuro",
    type: "ANIME",
    page: 1,
    perPage: 50,
    statuses: ["COMPLETED"],
  });
  assertEquals(String(firstQuery.query).includes("score(format: POINT_10)"), true);
  assertEquals(String(firstQuery.query).includes("seasonYear"), true);
  assertEquals(JSON.parse(calls[1].body).variables.page, 2);
  assertEquals(underBody.success, true);
  assertEquals(underBody.source, "anilist");
  assertEquals(underBody.mode, "import");
  assertEquals(underBody.username, "kuro");
  assertEquals(underBody.truncated, false);
  assertEquals(underBody.itemCount, 3);
  assertEquals(underBody.publicListOnly, true);
  assertEquals(underBody.cachedTextUsed, undefined);
  assertEquals(
    underBody.text,
    "Page One (2020) (completed)\nPage Two (2020) (completed)\nPage Three (1998) (completed)",
  );
  assertEquals(underBody.countsByType, { ANIME: 3, MANGA: 0 });
  assertEquals(underBody.countsByStatus.COMPLETED, 3);
  assertEquals(underBody.sampleItems.length, 3);
  assertEquals(underBody.sampleItems[0].score, 8);
  assertEquals(underBody.sampleItems[0].year, 2020);
  assertEquals(underBody.sampleItems[2].year, 1998);

  calls.length = 0;
  const overflow = Array.from({ length: 26 }, (_, index) => entry(index + 1, `Title ${index + 1}`));
  const capFetch: typeof fetch = (input, init) => {
    calls.push({ url: String(input), body: String(init?.body ?? "") });
    return Promise.resolve(pageResponse(overflow, true));
  };
  const capped = await runAnilistImport({
    mode: "preview",
    username: "kuro",
    types: ["ANIME"],
    statuses: ["COMPLETED"],
    maxItems: 25,
    publicListOnly: true,
  }, { fetch: capFetch });
  const cappedBody = await capped.json();
  assertEquals(calls.length, 1);
  assertEquals(cappedBody.success, true);
  assertEquals(cappedBody.mode, "preview");
  assertEquals(cappedBody.truncated, true);
  assertEquals(cappedBody.itemCount, 25);
  assertEquals(cappedBody.publicListOnly, true);
  assertEquals(String(cappedBody.text).includes("Title 25"), true);
  assertEquals(String(cappedBody.text).includes("Title 26"), false);
  assertEquals(cappedBody.countsByType.ANIME, 25);
  assertEquals(cappedBody.sampleItems.length, 8);
});

Deno.test("a provider failure does not invent lines", async () => {
  let calls = 0;
  const fetchImpl: typeof fetch = (input) => {
    calls += 1;
    assertEquals(String(input), "https://graphql.anilist.co");
    if (calls === 1) return Promise.resolve(pageResponse([entry(7, "Only Real Title")], true));
    return Promise.resolve(new Response("down", { status: 503 }));
  };
  const res = await runAnilistImport({
    mode: "import",
    username: "kuro",
    types: ["ANIME"],
    statuses: ["COMPLETED"],
  }, { fetch: fetchImpl });

  assertEquals(calls, 2);
  assertEquals(res.status, 500);
  const body = await res.json();
  assertEquals(body.success, false);
  assertEquals(body.error, "AniList error 503: down");
  assertEquals(body.text, undefined);
  assertEquals(body.itemCount, undefined);
  assertEquals(body.sampleItems, undefined);
  assertEquals(JSON.stringify(body).includes("Only Real Title"), false);
});

Deno.test("publicListOnly is returned unchanged", async () => {
  const onePage: typeof fetch = () => Promise.resolve(pageResponse([entry(1, "Solo")], false));
  const cachedFalse = await runAnilistImport({
    mode: "import",
    text: "Naruto (2002) (completed)",
    truncated: true,
    publicListOnly: false,
    types: ["ANIME"],
    statuses: ["CURRENT"],
  }, { fetch: onePage });
  assertEquals((await cachedFalse.json()).publicListOnly, false);

  const cachedDefault = await runAnilistImport({
    mode: "import",
    cachedText: "Naruto (2002) (completed)",
    types: ["ANIME"],
    statuses: ["CURRENT"],
  }, { fetch: onePage });
  const cachedDefaultBody = await cachedDefault.json();
  assertEquals(cachedDefaultBody.publicListOnly, true);
  assertEquals(cachedDefaultBody.truncated, false);

  const freshFalse = await runAnilistImport({
    username: "kuro",
    types: ["ANIME"],
    statuses: ["COMPLETED"],
    publicListOnly: false,
  }, { fetch: onePage });
  assertEquals((await freshFalse.json()).publicListOnly, false);

  const freshDefault = await runAnilistImport({
    username: "kuro",
    types: ["ANIME"],
    statuses: ["COMPLETED"],
  }, { fetch: onePage });
  assertEquals((await freshDefault.json()).publicListOnly, true);
});

Deno.test("stream imports all 5000 anime and manga rows without repeating or skipping provider ids", async () => {
  const received: string[] = [], cursors = new Set<string>();
  let cursor: string | undefined, calls = 0;
  const fetchImpl: typeof fetch = (_input, init) => {
    calls++;
    const {variables} = JSON.parse(String(init?.body));
    const count = variables.type === "ANIME" ? 3500 : 1500;
    const start = (variables.page-1)*variables.perPage;
    const entries = Array.from({length:Math.max(0,Math.min(variables.perPage,count-start))},(_,i)=>entry(start+i+1,`Title ${start+i+1}`));
    return Promise.resolve(pageResponse(entries,start+variables.perPage<count));
  };
  for (let request=0;request<30;request++) {
    const response = await runAnilistImport({username:"kuro",mode:"import",stream:true,types:["ANIME","MANGA"],statuses:["COMPLETED"],maxItems:200,perPage:50,cursor},{fetch:fetchImpl});
    assertEquals(response.status,200);
    const body = await response.json();
    assertEquals(body.libraryItems.length <= 200,true);
    received.push(...body.libraryItems.map((i:{medium:string;external_id:string})=>`${i.medium}:${i.external_id}`));
    if (body.sourceExhausted) { assertEquals(body.nextCursor,null); break; }
    assertEquals(typeof body.nextCursor,"string");
    assertEquals(cursors.has(body.nextCursor),false);
    cursors.add(body.nextCursor); cursor=body.nextCursor;
  }
  assertEquals(received.length,5000);
  assertEquals(new Set(received).size,5000);
  assertEquals(calls,100);
});

Deno.test("stream cursor is bound to provider selection and failure never returns partial success",async()=>{
  const fetchImpl:typeof fetch=()=>Promise.resolve(pageResponse(Array.from({length:50},(_,i)=>entry(i+1,`Title ${i}`)),true));
  const response=await runAnilistImport({username:"kuro",stream:true,types:["ANIME"],statuses:["COMPLETED"],maxItems:25},{fetch:fetchImpl});
  const first=await response.json();
  const changed=await runAnilistImport({username:"other",stream:true,types:["ANIME"],statuses:["COMPLETED"],cursor:first.nextCursor},{fetch:fetchImpl});
  assertEquals(changed.status,400);
  let calls=0;
  const broken:typeof fetch=()=>++calls===1 ? Promise.resolve(pageResponse(Array.from({length:50},(_,i)=>entry(i+1,`Title ${i}`)),true)) : Promise.reject(new Error("offline"));
  const failure=await runAnilistImport({username:"kuro",stream:true,types:["ANIME"],statuses:["COMPLETED"],maxItems:200},{fetch:broken});
  assertEquals(failure.status,500);
  const body=await failure.json(); assertEquals(body.success,false); assertEquals(body.libraryItems,undefined);
});

Deno.test("original score scale and ordered custom shelves survive the structured stream", async () => {
  const row = { ...entry(77, "Fidelity"), score: 10, scoreRaw: 100, original3: 3,
    customLists: { Later: true, Favorites: true, Hidden: false }, private: true, notes: "Owner only" };
  const response = await runAnilistImport({ mode: "stream", username: "kuro", types: ["ANIME"], statuses: ["COMPLETED"] }, {
    fetch: () => Promise.resolve(new Response(JSON.stringify({ data: {
      User: { mediaListOptions: { scoreFormat: "POINT_3", rowOrder: "TITLE", animeList: {
        customLists: ["Favorites", "Later"], sectionOrder: ["Favorites", "Completed", "Later"], advancedScoringEnabled: false,
      } } }, Page: { pageInfo: { hasNextPage: false }, mediaList: [row] },
    } }), { status: 200 })),
  });
  const body = await response.json();
  assertEquals(body.libraryItems[0].score_raw, "3");
  assertEquals(body.libraryItems[0].score_scale, "POINT_3");
  assertEquals(body.libraryItems[0].normalized_rating, 10);
  assertEquals(body.libraryItems[0].custom_lists, ["Favorites", "Later"]);
  assertEquals(body.libraryItems[0].notes, "Owner only");
  assertEquals(JSON.parse(body.libraryItems[0].source_list_options).sectionOrder, ["Favorites", "Completed", "Later"]);
});
