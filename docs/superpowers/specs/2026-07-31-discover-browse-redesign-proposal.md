# Design Proposal — Discover & Browse Split (2026-07-31, draft for owner review)

**The problem:** both pages currently sell the same thing — abundance. "Well-mannered streaming app, not a magazine" (design audit). Kuro's moat is curation with a point of view; a page that shows 200 posters says "we have data", not "we have taste".

**The split, one sentence each:**
- **Discover = the editorial desk.** Every section must answer "why is this here?" in one line. If a section can't say why, it doesn't ship. Maximum ~6 sections; each viewport asks at most one question.
- **Browse = the instrument.** The full catalog with a sharp lens — dense by design, but the chrome becomes modern (glass), and the lens becomes taste-aware without becoming a "For You" feed.

**Shared visual language (modern, grown-up, monochrome):**
- Glass belongs to *floating chrome over art*: hero cards, the pinned filter bar, countdown pills. Text sections stay on paper — glass everywhere is Apple circa 2023; glass as punctuation is Kuro.
- One grammar, already proven in the Deck: art + grain + dual gradient + glass panel + serif masthead + tracked eyebrow + italic serif reason lines.
- Bigger posters, fewer per row (Discover rail cards grow ~15–20%: fewer faces, more presence). Gutters 24/32 per `EditorialLayout`.
- Color-law cleanup on these two pages: score badges go monochrome (glass chip, white text), killing the yellow-orange drift visible on today's Discover cards.

---

## DISCOVER — what shows, top to bottom

1. **The One Thing** (replaces FEATURED hero). One title per day, full-bleed art, glass card with a 2–3 sentence *argument* — "why this, why now" — not a label and a year. Copy source: `editorial_boosts.label` → curated rail intros → `synopsis_enhanced` (in that priority order; all exist today). This is the magazine cover.
2. **Because you loved X** (replaces NEW TO YOU as the flagship rail). Personalized rail from the taste profile — *with the reason printed*: "Because you loved Frieren — quiet fantasy with weight." The explainability is already computed (top shared tags from the cosine profile); this is its first visible consumer. Falls back to editorial NEW TO YOU below confidence. Flag: `personalized_new_to_you_v1`.
3. **This Week, Yours** (new, slim). A glass pill strip, not a rail: episodes airing this week *from your own list*, with countdowns (component exists). The daily-habit surface, personal by construction. Hidden when empty.
4. **The Shelf** (rotating, one per day). One of the 50 curated rails gets the spotlight with its full editorial intro copy — "Rainy Sunday: eight films that feel like wool blankets." This is the curation differentiator surfaced as *voice*. Rotates daily via existing rotation infra.
5. **The Bridge** (anime↔manga, unique-to-Kuro). "You read it — now watch it" / "The manga continues past the anime" — driven by `media_relations` ADAPTATION edges + the ladder RPC + your list state. No competitor can build this rail; it monetizes later (READ ON links) without trying.
6. **Hidden Gem** (one card, weekly). High score, low popularity, editorial gamble — the anti-chart, proof the desk reads past the top-100.

- **Killed/demoted:** TRENDING (everyone else's game — moves to Browse as a sort), ESSENTIALS fold into The Shelf rotation, the "7 MORE SECTIONS" wall dies. We choose; we don't dump.

## BROWSE — what shows

Browse keeps its contract (everything, findable) and gets the instrument upgrade:

1. **Pinned glass filter bar** — a floating glass capsule (Deck's `.onImage` tone inverted for paper) that stays on scroll; active filters render as one readable sentence: "Sci-Fi · 2016–2020 · TV · score 75+".
2. **Entry state** — not raw popularity: curated entry shelves (genre hubs as editorial pages with a paragraph of voice each — the idea the dead `GenreHubView` was reaching for, done right).
3. **Two taste lenses (toggles, off by default, honest labels):**
   - **"Hide what I'll hate"** — excludes your avoided tags (the profile's avoidance map, already computed).
   - **"Surprise me" sort** — explore-UCB ordering from the deck's posteriors. Browse becomes a taste *instrument* with named, inspectable mechanics — never a black-box feed.
4. Cards adopt the shared grammar: larger, monochrome score chip, quick-add.

## What this does to the brand
Discover stops competing with Netflix's grid and starts doing the thing Netflix can't: a daily editorial desk with a byline. Browse stops pretending to be a destination and becomes the best lens in the category. Both speak the deck's glass-and-serif language, so the app finally reads as one product.

## Build notes (all existing infrastructure)
Editorial boost labels ✓ · taste profile + reason tags ✓ · airing/countdown data ✓ · curated rails + rotation ✓ · ladder/relations ✓ · avoided tags ✓ · UCB posteriors ✓. No new backend universes. Suggested phasing: P1 = One Thing + Because-You rail + glass/chrome pass + score badge cleanup; P2 = This Week strip + The Shelf; P3 = The Bridge + Hidden Gem + Browse lenses.
