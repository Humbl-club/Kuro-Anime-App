# Manga Bookshelf — Round 2 parse report (manga scope)

Spec: `docs/superpowers/specs/2026-08-04-realm-repair-and-critique-plan.md` §5 Round 2 + §9.
Site: Manga Bookshelf (`manga-bookshelf` in `critic_sources`, tier C, `fetch_mode='agent'`,
blessed). Scope: **MANGA** entries only, from `scripts/data/critique_pilot_titles.DRAFT.json`
(31 manga titles). Model: Sonnet (parsing), per plan §8.

robots.txt verified live before fetching: `mangabookshelf.com/robots.txt` (permissive, only
`/wp-admin/` disallowed) and `suitablefortreatment.mangabookshelf.com/robots.txt` (disallows
query strings, feeds, comments, `wp-*` — none of which apply to dated post permalinks). No
crawl-delay declared; fetches paced at ≥3s apart via a polite custom User-Agent
(`KuroCritiqueResearchBot/1.0`, contact `contact@lazy.space`). Source HTML/text cached only in
the local scratchpad (never committed) for verbatim-quote validation; not persisted to the repo.

## Method

1. Located candidate reviews via web search restricted to `mangabookshelf.com` and its
   sub-blogs (`suitablefortreatment`, `mangacritic`, `soliloquyinblue`, `experimentsinmanga` —
   all part of the one blessed network entry), then confirmed exact post URLs via each
   sub-blog's WordPress category archive page (e.g. `/category/fairy-tail/`).
2. Fetched each candidate post with `curl`, stripped to the actual `entry-content` article body
   (excluding nav/sidebar/comment cruft), and manually identified the real byline per site
   (JSON-LD `author` field / visible "by NAME" line), since the network carries several named
   critics, not one.
3. Drafted axis claims (story/visuals/characters/pacing/legacy — **never `sound`**, manga is a
   print medium with no audio axis) + verdict 0–4 + confidence, using only axes the review
   actually argued. Compound flags: none applied — the six flags in the schema
   (`carried_by_animation`, `three_episode_rule`, `fumbled_the_ending`, `read_the_manga`,
   `sleeper`, `slow_burn_worth_it`) are anime/adaptation-comparison flags and none fit a manga
   reviewing itself.
4. **Every quote was verified as an exact Python-substring match against the fetched source
   text before submission** (script-enforced, not eyeballed) — see Quote fidelity below.
5. Cross-checked every `media_id` against `public.manga` (`format = 'MANGA'`,
   `title_english`/`title_romaji` match) via a read-only Management API query before writing —
   see Title resolution below.
6. Submitted via `public.upsert_critic_review_claims('manga-bookshelf', <url>, 'MANGA',
   <media_id>, <critic>, <date>, <claims jsonb>, <content_notes jsonb>)` over the Management
   API (keychain-sourced access token, `curl` — no urllib UA issue). Every call returned a
   `review_id`.

## Titles covered (14 of 31, cap 15)

| # | Title | media_id | Critic | Date | URL | Axes (verdict) |
|---|---|---|---|---|---|---|
| 1 | Monster | 29 | Michelle Smith | 2009-01-03 | soliloquyinblue…/monster-13-by-naoki-urasawa-a/ | characters(3), story(3) |
| 2 | 20th Century Boys | 30 | Katherine Dacey | 2010-01-09 | mangacritic…/20th-century-boys-vols-1-6/ | story(4), pacing(3) |
| 3 | Akira | 169 | Katherine Dacey | 2009-10-22 | mangacritic…/akira-vol-1/ | visuals(3), legacy(4), story(3) |
| 4 | Vinland Saga | 16 | Ash Brown | 2015-10-30 | experimentsinmanga…/vinland-saga-omnibus-6/ | story(4), characters(4) + content note |
| 5 | Vagabond | 14 | Ash Brown | 2011-05-13 | experimentsinmanga…/vagabond-omnibus-1/ | visuals(4), characters(3) + content note |
| 6 | One Piece | 7 | Sean Gaffney | 2015-04-14 | suitablefortreatment…/one-piece-vol-74/ | story(3), pacing(1) |
| 7 | Bleach | 22 | Michelle Smith | 2007-10-11 | soliloquyinblue…/bleach-8-by-tite-kubo-a/ | story(3), characters(3) |
| 8 | Naruto | 79 | Sean Gaffney | 2011-05-17 | suitablefortreatment…/naruto-volumes-1-3/ | pacing(1), characters(2) |
| 9 | Delicious in Dungeon | 151 | Katherine Dacey | 2017-05-30 | mangacritic…/delicious-in-dungeon-vol-1/ | story(3), characters(3) |
| 10 | Slam Dunk | 98 | Michelle Smith | 2008-08-04 | soliloquyinblue…/slam-dunk-1-by-takehiko-inoue-b/ | story(2), visuals(3) |
| 11 | Real | 162 | Katherine Dacey | 2009-05-03 | mangacritic…/real-vols-1-4/ | characters(4), visuals(4) |
| 12 | Fairy Tail | 130 | Sean Gaffney | 2013-09-24 | suitablefortreatment…/fairy-tail-vol-30/ | story(2), characters(1) |
| 13 | Dr. STONE | 84 | Sean Gaffney | 2018-09-23 | suitablefortreatment…/dr-stone-vol-1/ | visuals(3), characters(3), pacing(2) |
| 14 | Black Clover | 25 | Sean Gaffney | 2016-06-14 | suitablefortreatment…/black-clover-vol-1/ | story(2), characters(2) |

Totals: **14 reviews submitted, 30 axis claims, 2 content notes** (both `graphic_violence` /
`medium`, Vagabond and Vinland Saga, evidenced by the critics' own "very bloody, graphic, and
violent" / "brutal and shockingly gruesome" language). All 14 confirmed against
`public.critic_reviews` post-write (row count, axis count, note count match exactly what was
submitted — no silent partial writes).

Reviewers surfaced (the network is not single-byline): **Sean Gaffney** (A Case Suitable for
Treatment — 5 reviews), **Katherine Dacey** (The Manga Critic — 4 reviews), **Michelle Smith**
(Soliloquy in Blue — 3 reviews), **Ash Brown** (Experiments in Manga — 2 reviews: Vagabond,
Vinland Saga). Byline attribution was confirmed per post via JSON-LD `author` metadata or the
visible "by NAME" line, not assumed from the dossier's single verified name.

## Coverage of the 31 manga pilot titles

14/31 covered (45%). Remaining 17:

**No dedicated review found on the network** (checked via search + category-archive pages;
only release-list/roundup mentions or zero hits) — 14 titles: Jujutsu Kaisen (4), Berserk (5,
passing mentions only — no `/category/berserk/` page exists), Oyasumi Punpun (11, no category
page), Kingdom (97, zero hits), The Climber (116, no category page), A Returner's Magic Should
Be Special (163, roundup links to Fandom Post/Anime UK News/Honey's Anime instead), Second Life
Ranker (182), Tomb Raider King (254), FFF-Class Trashero (364), Mythic Item Obtained (375),
Log-in Murim (428), Helck (494), Demon Devourer (786), Ragna Crimson (833, roundup mentions of
an ANN review only).

**Not searched** — 1 title: Fairy Tail: 100 Years Quest (465). Search budget was spent once the
14-title near-cap was reached with strong candidates; not a negative finding, just unexplored.

**Coverage found but skipped on purpose** — 2 titles:
- **Frieren: Beyond Journey's End** (89): the only dedicated post on the network is
  `suitablefortreatment…/frieren-beyond-journeys-end-prelude/` (2026-03-31), which reviews the
  **~Prelude~ tie-in light novel**, not the ongoing manga. Skipped rather than force a claim
  about prose-fiction content onto the manga catalog row.
- **An Archdemon's Dilemma: How to Love Your Elf Bride** (533): the network has extensive
  coverage — 7+ dedicated posts by Sean Gaffney — but every one reviews the **light novel**
  edition ("Released in Japan as … by HJ Bunko", "Released in North America by J-Novel Club",
  illustrator COMTA). Confirmed via `public.manga` that Kuro's catalog id 533 is
  `format = 'MANGA'` — a separate work from the LN. Skipped per the plan's title-resolution
  rule ("unresolved → report, never guess") rather than attribute LN-specific claims/quotes to
  the manga entry.

## Quote fidelity: 100%

All 30 claim quotes + 2 content-note quotes were checked with a Python substring test
(`quote in fetched_source_text`) against the raw fetched article text before any submission —
script output: `ALL 14 REVIEWS / quotes verified verbatim substrings, within limits.` One real
gotcha hit during drafting: the Delicious in Dungeon source contains literal U+00A0
(non-breaking space) characters at a few word boundaries (e.g. between "is" and "surprisingly")
that are invisible in normal reading but broke a naive `grep -F` match — quotes were rerouted
around those spans rather than silently accepted with an invisible mismatch risk. All final
quotes are ≤29 words (well under the 40-word cap) and ≤300 chars (schema limit).

## Title resolution: 0 wrong-title upserts

All 14 submitted `media_id`s were cross-checked against `public.manga` (`format='MANGA'`,
title match) via a read-only query before and would have blocked on `MEDIA_NOT_FOUND` /
`INVALID_MEDIA_TYPE` otherwise (RPC-enforced). The 2 skips above are exactly the cases where
resolution was uncertain (format mismatch) — both logged rather than guessed.

## Failures / risks for the gate

- No axis-coverage gap: all 14 titles have ≥2 axes from this single review; cross-review
  consensus (≥2 reviews/title) is **not yet met for any of these 14** — this pilot pass is one
  review per title by design (cap 15, breadth-first). Consensus/spread checks in the plan's
  gate (§5 "Consensus sanity: inter-site verdict spread ≤1 step on 80% of shared titles")
  cannot be evaluated from Manga Bookshelf alone; needs the other blessed sites' passes over
  the same titles (dual-use with anime gold seeds is anime-side; manga-side overlap depends on
  whether other blessed manga-capable sites cover the same 14).
- `sound` axis: never used (correctly, per plan's note that manga has no audio) — this pilot's
  data cannot inform the "keep or drop sound" owner decision on its own; that reads on the
  anime-side passes.
- Byline attribution required manual JSON-LD inspection per sub-blog rather than trusting the
  single name in the site dossier — worth updating the dossier note that the network has (at
  least) 4 distinct named critics, not just Sean Gaffney.
