# Wrong Every Time — Round 2 parse report (anime scope)

Spec: `docs/superpowers/specs/2026-08-04-realm-repair-and-critique-plan.md` §5 Round 2 + §9.
Site: Wrong Every Time (`wrong-every-time` in `critic_sources`, tier B, critic Nick Creamer,
`fetch_mode='agent'`, blessed 2026-08-05). Scope: **ANIME** entries only, from
`scripts/data/critique_pilot_titles.DRAFT.json` (86 anime titles). Model: Sonnet (parsing), per
plan §8.

`robots.txt` verified live before any fetch: `wrongeverytime.com/robots.txt` — permissive,
only `/wp-admin/` disallowed (with `admin-ajax.php` explicitly re-allowed), two sitemaps
declared, no crawl-delay. Fetches paced ≥3–4s apart via `curl` with a polite, identifying
User-Agent (`KuroCritiquePilot/1.0 (research; contact: contact@lazy.space)`). Discovery
(search-engine queries, WordPress category/tag archive listings) does not count as a direct
site fetch and was not rate-limited the same way. Source HTML/text was cached only in the
local scratchpad for verbatim-quote validation and has been deleted — nothing was committed,
nothing went in the DB beyond the ≤40-word quotes.

## Method

1. Built a candidate list from the site's `Reviews`/`Essays` categories (paginated), tag
   archives per pilot title, on-site search (`?s=`), and off-site `site:wrongeverytime.com`
   searches, cross-referenced against the 86 ANIME pilot titles.
2. **Critical discovery mid-pipeline**: most of the site's post-~2015 `"<Title> – Review"` posts
   are NOT full reviews — they are short (120–180 word) teaser posts that link out to the actual
   review hosted on Anime News Network (where Creamer worked as a paid critic) or, for the
   "Why It Works" column, Crunchyroll. Confirmed by fetching raw HTML and checking outbound
   `href`s in `entry-content` for `animenewsnetwork.com` / `crunchyroll.com`. These are **out of
   scope** — Wrong Every Time is the only blessed site for this pass; ANN/Crunchyroll were never
   scouted, tiered, or blessed (Round 0), so pulling their text would be exactly the
   "swarm before the gate" mistake the plan guards against. Every candidate below was verified
   to have its full argued prose hosted locally on `wrongeverytime.com` itself before parsing.
3. Local full-text posts cluster in two patterns: (a) early-blog reviews from before the ANN
   affiliation (2013–2015), and (b) episode write-ups / essays that substantively assess the
   whole work even when framed around one episode (a season finale wrap-up, or a single-episode
   close reading that argues a series-wide thematic/character point) — common on this site
   throughout its run.
4. Fetched each candidate with `curl`, stripped HTML down to `div.entry-content` text only
   (script excludes `<script>`/`<style>`, normalizes U+00A0 non-breaking spaces to regular
   spaces — the raw HTML uses `&nbsp;` inconsistently mid-sentence), confirmed ≥800 words and
   genuinely argued (not just a plot recap) before drafting claims.
5. Drafted axis claims (story/visuals/characters/pacing/sound/legacy, only axes the piece
   actually argues) + verdict 0–4 + confidence + compound flags where supported, and content
   notes only where the piece itself flags something (deadpan, evidence quote required).
6. **Every quote was verified as an exact Python substring match against the fetched source
   text before submission** (script-enforced — see Quote fidelity below).
7. Cross-checked every `media_id` against `public.anime` (title match) via a read-only
   Management API query — see Title resolution below.
8. Submitted via `public.upsert_critic_review_claims('wrong-every-time', <url>, 'ANIME',
   <media_id>, 'Nick Creamer', <date>, <claims jsonb>, <content_notes jsonb>)` over the
   Management API (keychain-sourced access token). Every call returned a `review_id`.

## Titles covered (8 of 86, cap 15)

| # | Title | media_id | Date | URL | Axes (verdict) | Flags | review_id |
|---|---|---|---|---|---|---|---|
| 1 | Attack on Titan | 2 | 2013-10-14 | `…/2013/10/14/attack-on-titan-final-review/` | visuals(3), pacing(1), characters(1), story(2) | — | 18 |
| 2 | Tokyo Ghoul | 9 | 2018-03-05 | `…/2018/03/05/a-violence-like-this-tokyo-ghoul/` | story(2), characters(3) | — | 19 |
| 3 | Toradora! | 96 | 2026-04-20 | `…/2026/04/20/toradora-episode-14/` | characters(4), story(4) | slow_burn_worth_it | 20 |
| 4 | WONDER EGG PRIORITY | 208 | 2024-08-12 | `…/2024/08/12/wonder-egg-priority-episode-12/` | visuals(4), characters(4), story(3) | fumbled_the_ending | 21 |
| 5 | K-ON! | 220 | 2015-10-19 | `…/2015/10/19/k-on-review/` | visuals(4), characters(2), sound(3) | — | 22 |
| 6 | BOCCHI THE ROCK! | 271 | 2023-10-07 | `…/2023/10/07/bocchi-the-rock-episode-12/` | characters(4), visuals(4), sound(4) | — | 23 |
| 7 | Wolf Children | 334 | 2015-11-24 | `…/2015/11/24/wolf-children-and-the-wilderness/` | story(4), characters(4), pacing(3) | — | 24 |
| 8 | Nisemonogatari | 356 | 2013-04-14 | `…/2013/04/14/nisemonogatari-and-the-nature-of-fanservice/` | story(4), visuals(4) | — | 25 |

Totals: **8 reviews submitted, 22 axis claims, 3 content notes.** All 8 confirmed post-write
against `public.critic_reviews` joined to `media_critic_claims`/`media_content_notes` — row
counts match exactly what was submitted (4/2/2/3/3/3/3/2 claims per title in submission order;
0/1/0/1/0/0/0/1 notes per title) — no silent partial writes.

Content notes (all deadpan, evidence-quoted, ≤40 words):
- Tokyo Ghoul (9): `graphic_violence` / high — the review dwells at length on torture imagery
  ("his scar-crossed wrists, his grinding teeth, the half-formed toes ever growing in, ever
  being torn away") as a structuring device for its whole argument.
- WONDER EGG PRIORITY (208): `self_harm` / high — the review discusses the show's central
  suicide/grief plot directly ("the pain of suicide, the agony of not knowing what we could
  have done differently").
- Nisemonogatari (356): `sexual_content` / medium — the review's whole thesis is about the
  show's use (and critique) of fanservice/sexuality as direction, quoting a nudity-heavy episode
  directly. Note: the review does not itself state any character's age, so this was logged as
  `sexual_content` rather than `sexualized_minors` — the stricter label would rely on outside
  franchise knowledge, not evidence the review itself flags, which the plan's rule forbids.

## Coverage of the 86 anime pilot titles: 8/86 (9.3%)

This is a genuinely low number and is the pilot's most important finding for Round 3
site-portfolio planning, not a search-effort shortfall — dozens of tag-archive checks, category
paginations, and targeted searches were run (see below) before concluding coverage is this
sparse. **Root cause**: Wrong Every Time's own back-catalog of full local reviews is small.
Most of Creamer's professional-era review output (~2015 onward) lives at Anime News Network,
correctly out of scope; most of the site's own extensive archive is per-episode write-ups of
currently-airing seasonal shows, and a large fraction of those never reach a finale (coverage is
visibly dropped mid-season on many titles — confirmed for Kaguya-sama S1 (dropped at ep 6/12),
Horimiya (dropped at ep 6), Call of the Night (dropped at ep 6/13), Mushoku Tensei (no episode
coverage at all found), Wotakoi (dropped after 2 mentions), NANA (dropped at ep 2)).

**Found but skipped — link-out teasers, not local coverage** (9 titles; confirmed by fetching
and checking outbound links, not assumed): Neon Genesis Evangelion (110, → ANN), Made in Abyss
(141, → ANN), Violet Evergarden (98, → ANN), Death Parade (112, → ANN), Your lie in April (23,
→ ANN), Hyouka (162, both parts → ANN), Fate/stay night: Unlimited Blade Works (229, both parts
→ ANN), Laid-Back Camp (416, → ANN), Kizumonogatari Part 1: Tekketsu (424, → ANN), Hunter x
Hunter (7, "Why It Works" essay → Crunchyroll), Miss Kobayashi's Dragon Maid (172, "Why It
Works" → Crunchyroll).

**Checked, no coverage found at all** (via tag archive + on-site/off-site search — not a
partial-effort skip): Spirited Away (111), Princess Mononoke (200), My Neighbor Totoro (221),
Howl's Moving Castle (161, zero site-search hits), Grave of the Fireflies (336, only a 150-word
aside in a reader comment, not the author's own coverage), Cowboy Bebop (117), Trigun (429),
Perfect Blue (286), Paprika (486, one passing mention in a year-end roundup only), Death Note
(4), Code Geass + R2 (109, 159 — only the "Akito the Exiled" spinoff has a review), Monster (181,
Urasawa's — the only "Monster" hit is a Kore-eda film essay), PSYCHO-PASS (158, only S2 has a
review), Dororo (153), Vinland Saga (102, anime — coverage exists only for the manga volumes,
different pilot entry), Free! (358), NANA (338), Mob Psycho 100 (22, finale write-up exists but
is only 400 words), ERASED (24, finale write-up exists but is only 499 words), Kakegurui (118),
and roughly 45 further titles (mostly the newer battle-shounen / isekai gold seeds — Demon
Slayer, JJK, AoT Final Season, Re:Zero, HAIKYU!! S1/S2, Black Clover, Tokyo Revengers, Slime,
Food Wars! ×3, Oshi No Ko, Hell's Paradise, SPY x FAMILY ×2, Dr. STONE: STONE WARS, Saiki K.,
Another, I Want to Eat Your Pancreas, given, Yuri!!! on ICE, High School DxD NEW, Ponyo, Takagi-
san, The Fruit of Grisaia, Blue Literature Series, Bungo Stray Dogs WAN!, Toilet-bound Hanako-
kun S2, Hyouge Mono, PUI PUI MOLCAR, Vending Machine + S2) where tag/search checks turned up
nothing beyond passing mentions in seasonal roundups.

## Quote fidelity: 100%

All 22 claim quotes + 3 content-note quotes were checked with a Python substring test
(`quote in fetched_source_text`) against the raw fetched article text before any submission —
script output: `TOTAL reviews=8 claims=22 notes=3 failures=0`. One real gotcha hit during
drafting: several posts (Attack on Titan, K-ON!) mix literal U+00A0 (non-breaking space) into
running prose — the extraction step normalizes this to a regular space so quotes read naturally,
and the validator runs against that same normalized text, so what's stored matches what a reader
of the DB row would see as an exact quote from the page. One quote (K-ON!, characters axis) was
trimmed by one trailing period that wasn't actually present at that point in the source
(mid-list line break, not a sentence end) — caught by the validator, fixed before submission,
not shipped mismatched. All final quotes are ≤27 words (well under the 40-word cap).

## Title resolution: 0 wrong-title upserts

All 8 submitted `media_id`s were cross-checked against `public.anime` (title match) via a
read-only query both before drafting (sourced from the pilot JSON's own `media_id` field) and
again immediately after submission, confirming exact `title_english`/`title_romaji` matches for
all 8 (Attack on Titan, Tokyo Ghoul, Toradora!, WONDER EGG PRIORITY, K-ON!, BOCCHI THE ROCK!,
Wolf Children, Nisemonogatari). No ambiguous or mismatched title was submitted; the ANN/
Crunchyroll link-outs and no-coverage titles above were logged and skipped rather than guessed.

## Failures / risks for the gate

- **Coverage is the real risk, not quality.** 8/86 (9.3%) is well under what a healthy tier-B
  site should probably contribute to a 15-title-per-site pilot slate; Wrong Every Time reads as
  correctly tiered (B, not A) but its *effective* local-text coverage is much smaller than its
  apparent archive size suggests, because so much of its nominal "review" output actually lives
  off-site at ANN. Round 0 dossier for this site should be amended to flag the ANN/Crunchyroll
  link-out pattern explicitly, so future passes don't burn fetch budget on the same discovery.
- Cross-review consensus (§5 gate: "inter-site verdict spread ≤1 step on 80% of shared titles")
  cannot be evaluated from this pass alone — one review per title, one site. Two of the 8 titles
  (Toradora!, Wolf Children) plausibly overlap with other blessed sites' anime coverage if/when
  those passes land; the rest (K-ON!, BOCCHI THE ROCK!, Attack on Titan, Tokyo Ghoul, WONDER EGG
  PRIORITY, Nisemonogatari) are exactly the kind of niche/classic/cult picks unlikely to be
  covered elsewhere in the pilot slate.
- `sound` axis: used twice (K-ON!, BOCCHI THE ROCK!), both at low-moderate confidence (0.6–0.7)
  since the site's prose treats music more as color/mood commentary than a distinct critical
  axis. Weak but real signal for the "keep or drop sound" owner decision — leans toward keeping
  it for music-centric titles specifically, dropping it as a default axis elsewhere.
- `fumbled_the_ending` (WONDER EGG PRIORITY) and `slow_burn_worth_it` (Toradora!) are both
  strongly textually supported (confidence 0.85 / 0.75) — good positive proof the compound-flag
  extraction works on real prose, not just the schema.
- Two content notes (self_harm, sexual_content) landed on titles that were **not** the plan's
  named anchor test cases (Made in Abyss, Noragami) — Made in Abyss itself was unreachable this
  pass (ANN link-out). Content-note recall against the plan's specific anchor titles is therefore
  **not yet tested** by this site/pass and should not be marked done at the gate on WET's data
  alone.

## Local cache

Raw HTML and extracted plain text for all 15 initially-fetched candidates (8 kept, 7 excluded as
ANN/Crunchyroll link-outs) were cached only under the session scratchpad directory, never
committed, never written to the DB beyond the ≤40-word quotes above, and have been deleted now
that verbatim validation and submission are complete.
