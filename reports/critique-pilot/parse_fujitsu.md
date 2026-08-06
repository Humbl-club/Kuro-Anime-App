# Critique ingestion pilot — 藤津亮太のアニメの門V (fujitsu-anime-mon)

Source: `animeanime.jp`, slug `fujitsu-anime-mon`, tier B (blessed 2026-08-05 per
`20260805130000_critique_ingestion_schema.sql`). Scope: ANIME pilot titles only,
per `scripts/data/critique_pilot_titles.DRAFT.json` (86 anime entries).

## Method

1. Verified `https://animeanime.jp/robots.txt` live:
   ```
   User-agent: ClaudeBot
   Crawl-delay: 5
   ```
   Confirmed explicit ClaudeBot permission. All fetches honored the 5s delay
   (explicit `sleep 5` between requests; archive-listing fetches and full-article
   fetches to the same host were spaced accordingly).
2. Archive is small and fully paginated (132 essays, 7 listing pages at
   `https://animeanime.jp/category/column/animonv/latest/?page=N`). Rather than
   guessing search queries, **the entire archive index (all 132 essay titles) was
   read page-by-page** and every title cross-checked against the 86 pilot anime
   titles (JP title knowledge, not string matching — column titles rarely quote
   the anime title verbatim). This is more reliable than site search for a
   132-entry archive and stays well under the "first 10" pilot cap.
3. For every title-plausible essay, fetched the full article body directly
   (`curl -A ClaudeBot`, article text extracted from the `<article class="arti-body">`
   container) so quotes could be verified as **exact substrings** of the source
   text before submission (Python `in` check on the extracted plain text).
4. Resolved titles against the pilot JSON's media_id — not the general catalog.
   Several essays cover a *different season/format* of a pilot title (confirmed
   via `select id, title_english, format, season_year from anime where title_romaji
   ilike ...`); these were logged as skips, not guessed.
5. Submitted via Management API SQL, `upsert_critic_review_claims(...)`, one call
   per (review URL, media_id). Verified by reading back
   `critic_reviews ⋈ media_critic_claims ⋈ anime` after each submission.

## Essays parsed and submitted (3 essays → 3 claims)

### 1. Kizumonogatari Part 1: Tekketsu (media_id 424, catalog: MOVIE, 2016)

- Essay: 藤津亮太のアニメの門V 第7回「魅了する『傷物語』『昭和元禄落語心中』の演出」
- URL: https://animeanime.jp/article/2016/02/05/26843.html
- Published: 2016-02-05 (article is single-page for the 傷物語 half; the
  昭和元禄落語心中 half lives on a second page, `_2.html`, not fetched — out of
  pilot scope)
- Axis: **visuals** (directing/演出 — this essay is a formal analysis of staging,
  not story/character/pacing/sound/legacy)
- Verdict: **3** ("clean" — measured, analytical praise; Fujitsu frames it as a
  successfully executed directorial conceit, not superlative/greatest-ever language)
- Quote (verbatim, 77 chars, confirmed exact substring of fetched source):
  > 室内から室外へと移動することによって生まれた「誕生」のイメージが、太陽に照らさたことで「死」のイメージへと反転する。この落差、この反転が本作の中心にある。
- Confidence: 0.75
- Flags: none. Content notes: none (essay doesn't flag content).
- Review row id returned: **2**

### 2. Perfect Blue (media_id 286, catalog: MOVIE, 1998)

- Essay: 藤津亮太のアニメの門V 第62回「今敏作品における『虚構と現実』の関係性とは？ 『千年女優』ほか劇場作から探る」
- URL: https://animeanime.jp/article/2020/09/04/56083.html
- Published: 2020-09-04
- Axis: **story** (thematic execution — how the "3 Mimas" climax staging embodies
  the film's identity theme)
- Verdict: **3** ("cooking" — strong, specific technical praise of how the device
  ties to the film's core "who am I" theme; not framed as the pinnacle of the
  medium)
- Quote (verbatim, 74 chars, confirmed exact substring):
  > この3人が並び立つ構図こそ、アニメならではの「虚構と現実」の混淆を表現しており、しかも「私は誰？」という本作を貫くテーマとも深く結びついているのだ。
- Confidence: 0.8
- Flags: none. Content notes: none (this essay is a formalist analysis of Kon's
  visual grammar across his filmography; it does not discuss Perfect Blue's
  disturbing content — no evidence quote to attach a note to, so none created).
- Review row id returned: **5**

### 3. PUI PUI MOLCAR (media_id 4409, catalog: TV_SHORT, 2021)

- Essay: 藤津亮太のアニメの門V 第67回「アニメにおける『世界観』とは？ 話題作『モルカー』『プペル』から考える」
- URL: https://animeanime.jp/article/2021/02/05/59317.html
- Published: 2021-02-05
- Axis: **story** (worldbuilding — how "Molcar" being a common noun rather than a
  proper noun gives the short-form show unexpected narrative logic/scope)
- Verdict: **3** ("cooking" — explicit, positive assessment that tone and logic
  "gently unified," credited despite the format's short runtime)
- Quote (verbatim, 43 chars, confirmed exact substring):
  > 「トーン」の魅力と「ロジック」のおもしろさが、やんわりと合一することができたのだろう。
- Confidence: 0.7
- Flags: none. Content notes: none.
- Review row id returned: **8**

## Skips (logged, not guessed)

| Essay | What it covers | Why skipped |
|---|---|---|
| 第62回 (same URL as Perfect Blue, above) | Paprika (media_id 486, in pilot list) — a genuine, substantive ~4-sentence passage comparing Paprika's dream/reality "blending depth" to Millennium Actress | **Schema gap, not a title-resolution failure.** `critic_reviews.url` is UNIQUE and the RPC's `on conflict (url) do update` clause does not update `media_id` — a second call for the same URL with a different `media_id` returns the *same* review row and would silently overwrite that row's claims with the second title's claims while leaving `media_id` pointed at the first title. One review URL can currently only be attributed to one media_id. Perfect Blue was chosen (longer, more developed passage, directly tied to the film's theme); Paprika's coverage is real but not represented in the DB. **Flag for the Phase 3 gate**: either widen the unique key to `(source_slug, url, media_id)` or accept that multi-title essays only donate claims to their dominant subject. |
| 第63回「劇場版 ヴァイオレット・エヴァーガーデン」 (2020-10-02, `/article/2020/10/02/56657.html`) | The 2020 theatrical movie, at length (thesis: "time" as theme, letters as asynchronous media) | Resolves to catalog media_id **345** ("Violet Evergarden: the Movie"), a different AniList entry from the pilot list's media_id **98** (TV series, 2018). Pilot JSON only blesses id 98. Skipped as out-of-scope, not guessed onto 98. |
| 第60回 (2020-07-03, `/article/2020/07/03/54774.html`), finale-construction survey covering 4 shows | かぐや様は告らせたい？～天才たちの恋愛頭脳戦～ (Kaguya-sama **Season 2**) discussed for ~5 sentences on how its finale balances "1-episode-complete" and epic structure | Resolves to catalog media_id **127** ("Kaguya-sama: Love is War?", 2020), not the pilot list's media_id **94** (Season 1, 2019). Skipped as out-of-scope. (Also borderline on substantiveness — one of 4 shows surveyed in ~5 sentences each — so would have been a lower-confidence claim even if in-scope.) |
| 第84回「劇場版からかい上手の高木さん」 (2022-07-11, `/article/2022/07/11/70731.html`) | The 2022 theatrical movie, at length (visuals/lighting analysis of the 虫送り sequence, structure) | Resolves to catalog media_id **12952** ("Teasing Master Takagi-san: The Movie"), not the pilot list's media_id **410** (Season 1 TV, 2018). Skipped as out-of-scope. |

No other pilot anime title (of the 86) appeared as an essay subject anywhere in
the full 132-essay archive. Fujitsu's column skews heavily toward Ghibli/Kon/
Shinkai/Hosoda-adjacent auteur work, industry-trend/business pieces (アニメ産業
レポート, streaming vs. TV), and smaller-scale seasonal titles — not the
mainstream battle-shounen/isekai titles that dominate the gold-seed list
(Attack on Titan, Demon Slayer, JJK, One Piece, HxH, Death Note, etc. — none
appear as column subjects).

## Totals

- Essays scanned (full archive): **132/132** (100% of the column's run)
- Title-matched essays found: **6** (well under the pilot cap of 10 — the
  archive's total size was the limiting factor, not the cap)
- Essays submitted: **3**
- Claims submitted: **3** (1 axis each — only the axis each essay actually
  addressed; no forced six-axis coverage)
- Titles covered: **3** of 86 pilot anime (Kizumonogatari Part 1, Perfect Blue,
  PUI PUI MOLCAR) — **4** if Paprika's un-submitted coverage is counted
- Quote fidelity: **3/3 (100%)** — every submitted quote verified as an exact
  Python substring of the curl-fetched article body before submission
- Skips logged: **4** (1 schema-constrained multi-title loss [Paprika], 3
  season/format title-resolution mismatches [Violet Evergarden movie,
  Kaguya-sama S2, Takagi-san movie])
- Failures: **0** hallucinated quotes, **0** wrong-title upserts, **0** RPC
  errors. All 3 submissions returned distinct review ids (2, 5, 8) and were
  independently re-verified by reading back the joined rows.

## Process note

Local HTML fetch cache lives at
`/private/tmp/claude-501/-Users-max-Kuro-Anime-App/76133ac5-f444-45ff-8f70-4429ca45160b/scratchpad/fujitsu/`
(session scratchpad, not committed). Per plan §9 this should be deleted once
the overall pilot QA closes — not deleted here since Fable 5's 30-sample QA
re-read step (plan §5 Round 2, pipeline stage 6) may need to check these
specific sources against the submitted quotes.
