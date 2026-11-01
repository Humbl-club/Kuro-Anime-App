# Prototype spec (measured)

Status: reference for the prototype-fidelity pass (plan `docs/superpowers/plans/2026-11-01-prototype-fidelity.md`, Task 1). Measured on 2026-11-01 from the approved prototype in `tools/design-directions/`. All values are from the browser's computed styles on the rendered page, so they already include the prototype's cascade of overrides (`instrument.css?v=54`, `manga-directions.css?v=2`, `manga-philosophies.css?v=6`, `instrument.js?v=61`).

Later tasks cite this file and the captures in `docs/prototype-fidelity/reference/`. When this file and the spec (`docs/superpowers/specs/2026-11-01-prototype-fidelity-design.md`) disagree on a visual value, this file records what the prototype does. Section 8 lists every such disagreement so the lanes do not have to find them.

## 1. How the captures were made

- **Server:** `python3 -m http.server 8803 --bind 127.0.0.1 --directory tools/design-directions`.
- **URL:** `instrument.html?switch=poster&embed=1&scenario=<state>&medium=<anime|manga>`. Detail: add `&detail=anime-2` or `&detail=manga-0`. Taste: click the header's "‹ Taste" (`[data-home-page]`).
- **Why `embed=1`:** without it, `.phone` is a fixed 404 px screen inside a 414 px desktop "device" frame. Its width is not 390. With `embed=1` the studio panel and frame are hidden and `.phone` fills the viewport (`height:100dvh`). The viewport width is then the phone width.
- **Widths:** the Playwright viewport is resized to 390, 320 and 430. No CSS width override is used. A real 320 viewport is needed, because the prototype's small-phone rules are `@media(max-width:360px)` and only fire at a real narrow width. The measured `.phone` width equalled the viewport at every width.
- **Full-height Home shots:**
  - `html`, `body` and `.phone` are set to `height:auto/overflow:visible`, and `.phone` is expanded to its `scrollHeight`.
  - The viewport grows to match, with `scrollTop = 0`, so the sticky header has no "scrolled" shadow.
  - Lazy images are forced eager. Fonts and all images load first, then the page waits 1.2 s for the entrance animations to finish.
  - The `.phone` element is captured at CSS scale (1 px = 1 pt).
- **Detail shots:**
  - `#detail` is a fixed `<dialog>`. At 390 it is 356 × 776 with a 1 px border and 17 px side insets.
  - It is captured at `scrollTop` steps of `clientHeight − 32` (742). The actual `scrollTop` is read back after each step, because the last step clamps.
  - The tiles are stitched with PIL. Each later tile drops its top 17 px so the 1 px border and 9 px corner never land mid-image.
  - The sticky close button is hidden on every tile after the first.
  - `ref-detail-*-top-390.png` is the full 390 × 844 viewport with the sheet open (as first seen).
- **Prototype-only content:** the captures show the prototype's sample data: titles, clubs, notes, "in this preview" wording and the sample footnote. Section 7 marks which strings are product copy and which are sample data that must never ship.

### Reference index (`docs/prototype-fidelity/reference/`)

| File | State |
|---|---|
| `ref-home-{busy,full,undated,quiet,new}-anime-{390,320,430}.png` | Anime Home, five accounts, three widths (15 files) |
| `ref-home-{busy,full,undated,quiet,new}-manga-{390,320,430}.png` | Manga Home, five accounts, three widths (15 files) |
| `ref-taste-{busy,new}-{anime,manga}-390.png` | Taste page (in progress account and new account) |
| `ref-detail-anime-390.png` | Anime detail (`anime-2`, Jujutsu Kaisen S2), full stitched sheet, 356 wide |
| `ref-detail-manga-390.png` | Manga detail (`manga-0`, Chainsaw Man), full stitched sheet, 356 wide |
| `ref-detail-{anime,manga}-top-390.png` | First viewport of each detail, sheet over the dimmed Home |

Scenario meanings: `busy` = in progress (2 new episodes / 4 new chapters, 7-day calendar); `full` = full calendar (6 weeks, 48 releases); `undated` = only announced, undated releases; `quiet` = caught up; `new` = new account.

## 2. Global tokens (from `:root` and the poster/manga overrides)

| Token | Value | Native token (Task 2) | Notes |
|---|---|---|---|
| `--ink` | `#252625` | `kuroInk` | Primary text |
| `--muted` | `#696c6b` | `kuroMuted` | Secondary text (header page name) |
| `--line` | `#272b2920` | `kuroLine` | Hairlines |
| `--paper` | `#f5f5f4` | `kuroPaper` | Anime detail sheet background |
| Home canvas (poster) | `#fffef8` | `kuroCanvasHome` | `.phone` background on anime Home and Taste; header bar `#fffef8eb` + `backdrop-filter: blur(18px)` |
| Manga Home canvas | `#f5f5f3` (computed) | — | Poster manga Home; manga detail sheet `#f6f5ef` with `#fffdf4` border |
| Base `.phone` (non-poster) | `#f3f4f4` | — | Overridden in poster; do not use |
| `--key-face` light | `linear-gradient(#f1f4f2, #d5ded8)` | `kuroKeyLightTop/Bottom` | Scene-card key on art; `--key-ink #29352c` |
| `--key-face` dark | `linear-gradient(#444a47, #2c322f)` | `kuroKeyDarkTop/Bottom` | Declared for dark keys in the CSS. On the measured poster screens, the manga leaf inherits it but paints a solid face (next row), and Also watching uses the material (row after). Use it where no artwork material exists (e.g. Folio keys, Task 9). |
| Manga leaf key (`--mp-key`) | solid `#2b342e`, 1 px `#2b342e` border, key ink `#f8faf7`; face 38 × 38, radius 6; shadow `inset 0 1px #ffffff1f, 0 1px 2px #28372a14` | `.dark` | Manga Home "Ch. N" key |
| `--key-face` on art | `linear-gradient(var(--art-base), var(--art-deep))`, key ink `#fff` | `.material(ArtworkMaterial)` | **Also watching keys use each title's own material** (e.g. Jujutsu Kaisen `#493134→#2c2123`), not a fixed dark gradient. The detail "Up next" key uses the same material. |
| `--art-base/deep/wash/edge/ink` | per artwork (`art-hue-v1`) | `ArtworkMaterial` | e.g. Demon Slayer `#28484b/#1c2d2e/#e9ece7/#bfc8c5/#fff`; Jujutsu Kaisen `#493134/#2c2123/#eceae5/#c8c2bf/#fff`; Chainsaw Man `#493431/#2c2321/#eceae5/#c8c2be/#fff` |
| `--ease` | `cubic-bezier(.2,.8,.25,1)` | `KuroMotion` curve | Also `--form-ease` |
| `--motion-contact` | `120ms` | `KuroMotion.contact` | Press feedback |
| `--motion-settle` | `220ms` | `KuroMotion.settle` | |
| `--motion-medium` | `320ms` | `KuroMotion.medium` | Canvas colour change on medium switch |
| Rail tokens | `--rail-face #f4f4ee / #e8ebea / #111a1c30`, `--rail-key linear-gradient(160deg,#f8faf9,#cddad6) / #343e30 / #303937`, `--rail-ink #d3dede / #69736f / #66705e`, `--rail-line #ffffff16 / #d6d9cf / #cfd4d2`, `--rail-selected #fff / #f9fbf5 / #263530` | — | Season-rail studies (`seasons=compare`). The selected poster Home does not render them; the detail season tiles use the values in §4 (D4 Seasons) instead. |

**Type families.**
- `-apple-system` (SF Pro) is used for all UI, titles and most section headings.
- `Georgia` (serif) is used only for these (§8 compares this with the spec's list):
  - the club name "Sunday Club" and the club quote on Home
  - "Between us."
  - the manga detail title and hook
  - "Your bookmark"
  - manga chapter row numbers (italic)
  - "Seen the anime?"
- The bundled "Kuro Editorial" (Bodoni Moda) `@font-face` exists in the CSS but no rendered element of the poster direction uses it.

Weights such as 450, 530, 550 and 850 are variable-font weights in the browser. The nearest SF weights are: 450 ≈ regular+, 530/550 ≈ medium–semibold, 600 = semibold, 800 = heavy, 850 ≈ heavy/black.

## 3. Keyframes and motion (exact)

### 3.1 The three keyframes (`instrument.css`, line 21)

```css
@keyframes count{from{opacity:.3;transform:translateY(3px)}to{opacity:1;transform:translateY(0)}}
@keyframes confirm{0%{opacity:0;transform:scale(.8)}20%,65%{opacity:1;transform:scale(1)}100%{opacity:0}}
@keyframes restore{0%,65%{opacity:0}100%{opacity:1}}
```

Where they run:

| Keyframe | Rule | Duration · easing · fill | Trigger |
|---|---|---|---|
| `confirm` | `.step[data-feedback=saved]:not(:disabled) .success-cap{animation:confirm .65s var(--ease) both}` | 650 ms · `cubic-bezier(.2,.8,.25,1)` · both | +1 key saved: the ✓ cap (`M4 10l4 4 8-8`) pops in at 0.8→1 scale, holds, fades |
| `restore` | `.step[data-feedback=saved]:not(:disabled) .key-cap{animation:restore .65s ease both}` | 650 ms · **plain `ease`** (not `--ease`) · both | Same moment: the + glyph is hidden while ✓ shows, then returns over the last 35 % |
| `count` | `.bump{animation:count .25s var(--ease)}` | 250 ms · `--ease` | Defined in CSS, but no current JS adds `.bump`. The live count roll is the JS motion below. |

Notes:
- A key that reaches its maximum becomes `:disabled` ("Caught up."), so neither `confirm` nor `restore` runs on it. Only the toast confirms.
- Under `prefers-reduced-motion: reduce`, all CSS animations and transitions are off, `.success-cap` is hidden, and the key cap keeps opacity 1.

### 3.2 JS (Web Animations) motions in `instrument.js`

All of these are skipped when `prefers-reduced-motion: reduce` matches (`animate()` returns early). Running motions are cancelled on a medium switch.

| Motion | Keyframes | Duration · easing |
|---|---|---|
| Key press settle (on save) | `.key-cap, .save-mark`: `scale(.96)` → `scale(1)` | 160 ms · `cubic-bezier(.2,.7,.3,1)` |
| Count roll, anime and detail (`[data-count]`) | `opacity .55, translateY(2px)` → `opacity 1, translateY(0)` | 220 ms · `cubic-bezier(.2,.75,.25,1)` |
| Count roll, manga Home (page turn) | `opacity .45, perspective(180px) rotateX(-48deg) translateY(2px)`, origin 50% 100% → `rotateX(0) translateY(0)` | 280 ms · `cubic-bezier(.2,.75,.25,1)` |
| Scrub trace (`[data-trace]`) | `width: old/max %` → `new/max %` | 280 ms · `cubic-bezier(.22,.8,.24,1)` |
| Section entrance, anime (once per section and medium, IntersectionObserver root `.phone`, threshold .12) | artwork images `opacity .8, translateY(9px)` → `1, 0` | 380 ms · `cubic-bezier(.2,.75,.25,1)` |
| Section entrance, manga | artwork images `opacity .85, clip-path inset(0 0 7% 0)` → `1, inset(0)` | 260 ms · `cubic-bezier(.2,.75,.25,1)` |
| Titles after medium switch | `.scene-title, .carry-card h2, …` `opacity .65` → `1` | 240 ms · `ease-out` |
| Club spoiler reveal | content `opacity .6` → `1` | 180 ms · `ease-out` |

### 3.3 Contact (press) states (`[data-contact=pressed]`, set on pointerdown, cleared after 9 px of movement or on pointerup)

| Element | Pressed style | Transition |
|---|---|---|
| `.step::before` (raised key face) | `transform: scale(.95); filter: brightness(.86); box-shadow: inset 0 2px 3px #151d2430` | `transform var(--motion-contact) var(--ease), filter var(--motion-contact), box-shadow var(--motion-contact)` |
| `.cover img`, `.story-open img` | `scale(.987); brightness(.92)` (story `.94`) | — |
| `.title-open` | `opacity: .6` | — |
| `.save` (Plan key) | `box-shadow: inset 0 2px 4px #17251b20; background: #e7ebe7` (pressed + saved `#202922`) | — |
| `.story-open` | background `#f4f6f4` | — |
| `.spoiler` | background `#dae2d0` | — |
| `.unit-complete` (detail Up next key) | `translateY(1px) scale(.96); box-shadow: inset 0 2px 3px #14261b25` | — |

The resting raised key (`.step::before`) is drawn inset 4 px inside the 44 × 44 target. Measured on the scene card:
- face 34 × 34, radius 7
- `border: 1px solid #20282326`
- `box-shadow: inset 0 1px #ffffff35, 0 1px 2px #14231912` (base rule: `inset 0 1px #ffffff24, 0 1px 1px #1e272316`)
- face colour `var(--key-face)`

### 3.4 Toast (after +1, Plan or Undo)

- Box:
  - `position: fixed`; left 13, right 13, bottom 12
  - background `#282f2bf5`, white text 12 px w400
  - radius 18, padding `5 5 5 14`
  - `box-shadow: 0 8px 30px #18241c30`
- Content: message, then "Undo" and a dismiss "×" button.
- Messages: "Progress saved." / "Caught up." / "Added to your list." / "Removed from your list." / "Undone." / failure: "Not saved. Your progress is unchanged." / "Not saved. Your list is unchanged."
- Inside the detail sheet, the toast goes into the sheet's sticky `.dialog-result` instead.

## 4. Component anatomy (measured, 390 unless stated)

How to read the tables:
- Every value is a computed style, in CSS px (= iOS pt).
- **Type** is `family size/line-height weight, tracking`.
- **Padding** and **margin** follow CSS order: top/right/bottom/left, or top/horizontal.
- **Box** is the rendered size at 390.
- Inherited container styles (SF 14/19.6 w400 ink) appear on wrapper rows. Ignore them unless the element sets text.
- `vars` shows the custom properties in force where they first apply or change, for example the artwork material on a scene card.
- `::before`/`::after` give pseudo-element geometry, where the prototype draws keys, rules and gradients.
- The selector in each Notes cell is the source element in the prototype.


### Home, anime, busy, 390 (`ref-home-busy-anime-390.png`)

#### Page

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| phone canvas | 390×844 | SF 14/19.6 w400 | `#252625` (ink) | `#fffef8` (home canvas) | — | — | — | — | — |  (`.phone`) |

#### Header

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| bar | 390×71 | SF 14/19.6 w400 | `#252625` (ink) | `#fffef8eb` | — | — | — | 15/22/12 | — |  (`.app-header`) |
| KURO wordmark | 64×25.2 | SF 18/25.2 w800, tr 3 | `#252625` (ink) | — | — | — | — | — | — | text “KURO” (`.app-header .wordmark`) |
| page location | 30.8×15.4 | SF 11/15.4 w400 | `#696c6b` (muted) | — | — | — | — | — | — | text “Home” (`.app-header .page-location`) |
| ‹ Taste link | 64×44 | SF 12/16.8 w400, align center | `#252625` (ink) | — | 10 | — | — | 1/6 | — | text “‹ Taste” (`.app-header .page-switch`) |

#### Medium switch

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| opening block | 350×171.2 | SF 14/19.6 w400 | `#252625` (ink) | — | — | — | — | — | m 7/20/18; gap 12 |  (`.home-opening`) |
| control grid | 350×57 | SF 14/19.6 w400 | `#252625` (ink) | — | — | B:1px #20302744 | — | — | gap 12 | grid 169px 169px (`.family-control`) |
| selected button | 169×56 | SF 14/19.6 w400, align center | `#263328` | — | — | — | — | 4/0/10 | — |  (`.family-control button[aria-pressed=true]`) |
| selected type box | 107.1×36 | SF 14/19.6 w400, align center | `#263328` | — | — | — | — | — | — |  (`.family-control button[aria-pressed=true] .family-type`) |
| selected word | 107.1×36 | SF 36/36 w850, tr -1.9, uppercase, align center | `#00000000` | `#253a2a`; linear-gradient(#15221c15, #15221c38), url("assets/anime1.jpg"); clip:text, text | — | — | — | — | — | text “Anime” (`.family-control button[aria-pressed=true] .mode-name`) |
| unselected word | 127.3×36 | SF 36/36 w850, tr -1.9, uppercase, align center | `#6e786f` | — | — | — | — | — | — | text “Manga” (`.family-control button[aria-pressed=false] .mode-name`) |
| selected ink underline | 28×2 | SF 14/19.6 w400, align center | `#263328` | `#203027` | — | — | — | — | — |  (`.family-control button[aria-pressed=true] .family-mark`) |
| unselected mark | 15.4×2 | SF 14/19.6 w400, align center | `#66716a` | `#203027` | — | — | — | — | — | opacity 0 (`.family-control button[aria-pressed=false] .family-mark`) |

#### Coming-up glance

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| card | 350×72 | SF 14/19.6 w400 | `#303932` | `#fffefa` | 8 | T:1px #29312918 R:1px #29312918 B:1px #29312918 L:1px #29312918 | #29312905 0px 1px 2px 0px | 10/12 | gap 12 |  (`.upcoming-glance`) |
| title | 167.8×19.6 | SF 14/19.6 w550, tr -0.3 | `#303932` | — | — | — | — | — | — | text “Coming up” (`.upcoming-copy b`) |
| caption | 167.8×14 | SF 10/14 w400 | `#687064` | — | — | — | — | — | — | whiteSpace nowrap; text “Today · 3 releases” (`.upcoming-copy small`) |
| art strip | 69×38 | SF 14/19.6 w400 | `#303932` | — | — | — | — | 0/2/0/0 | — |  (`.upcoming-art`) |
| art thumb | 27×38 | SF 14/19.6 w400 | `#303932` | — | 2 | T:1px #fffefa R:1px #fffefa B:1px #fffefa L:1px #fffefa | #26352b14 0px 1px 2px 0px | — | — | objectFit cover (`.upcoming-art img`) |
| count | 39×21 | SF 21/21 w450, tr -0.6, align right | `#303932` | — | — | — | — | — | — | text “6” (`.upcoming-total b`) |
| count label | 39×11.2 | SF 8/11.2 w400, align right | `#687064` | — | — | — | — | — | — | whiteSpace nowrap; text “this week” (`.upcoming-total small`) |
| arrow | 12.2×22.4 | SF 16/22.4 w400 | `#687064` | — | — | — | — | — | — | text “↓” (`.upcoming-arrow`) |

#### Opening line

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| row | 350×18.2 | SF 14/19.6 w400 | `#252625` (ink) | — | — | — | — | — | gap 12 |  (`.opening-copy`) |
| kicker | 87.1×12.6 | SF 9/12.6 w400, tr 1.05 | `#666c68` | — | — | — | — | — | — | text “NOW WATCHING” (`.opening-eyebrow`) |
| headline | 99.5×18.2 | SF 14/18.2 w550, tr -0.3 | `#252625` (ink) | — | — | — | — | — | — | whiteSpace nowrap; text “2 new episodes” (`.opening-copy h1`) |
| quiet line (quiet scenario) | — | not rendered in this state | | | | | | | | `.quiet` |

#### Scene card

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| stage | 350×693.4 | SF 14/19.6 w400 | `#252625` (ink) | — | — | — | — | — | m 0/20 |  (`.activity-stage`) |
| stack | 350×435.4 | SF 14/19.6 w400 | `#252625` (ink) | — | — | — | — | — | gap 18 | grid 350px (`.scene-stack`) |
| card | 350×206.7 | SF 14/19.6 w400 | `#252625` (ink) | linear-gradient(135deg, #28484b, #1c2d2e) | 5 | — | #19221b0a 0px 1px 2px 0px | — | — | vars --art-base=#28484b, --art-deep=#1c2d2e, --art-wash=#e9ece7, --art-edge=#bfc8c5, --art-ink=#ffffff, --scene-tone=#28484b (`.scene-card`) |
| artwork window | 350×107.7 | SF 14/19.6 w400 | `#252625` (ink) | — | — | — | — | — | — |  (`.scene-card .study-image`) |
| artwork button | 350×107.7 | SF 14/19.6 w400, align center | `#252625` (ink) | `#28484b` | 5 5 0 0 | — | — | — | — | ::after "" 348×106.688 r5 5 0 0 border 1px #ffffff25 shadow #000000 (black) 0px -10px 20px -15px inset (`.scene-card .scene-window`) |
| artwork image | 350×107.7 | SF 14/19.6 w400, align center | `#252625` (ink) | — | — | — | — | — | — | objectFit cover (`.scene-card .scene-window img`) |
| season tab button | 60.5×44 | SF 14/19.6 w400, align center | `#26372c` | — | — | — | — | — | — |  (`.scene-card .study-art-marker`) |
| season tab face | 60.5×31 | SF 14/19.6 w400, align center | `#26372c` | `#f3f4f4` | 8 8 0 0 | — | #ffffff65 0px -1px 0px 0px | 7/8 | gap 5 |  (`.scene-card .study-art-marker > span`) |
| season tab word | 31.6×9.8 | SF 7/9.8 w400, tr 0.3, uppercase, align center | `#26372c` | — | — | — | — | — | — | text “Season” (`.scene-card .study-art-marker small`) |
| season tab number | 7.9×17 | SF 17/17 w550, align center | `#26372c` | — | — | — | — | — | — | text “1” (`.scene-card .study-art-marker b`) |
| material foot (caption) | 350×58 | SF 14/19.6 w400 | `#fafafa` | — | — | T:1px #ffffff18 | #0000000c 0px 1px 0px 0px inset | 0/10/0/14 | gap 8 |  (`.scene-card .scene-caption`) |
| title | 206×44 | SF 17/23.8 w550, tr -0.35 | `#fafafa` | — | — | — | — | — | — |  (`.scene-card .scene-title h2`) |
| title button | 206×44 | SF 17/21.25 w550, tr -0.35 | `#fafafa` | — | — | — | — | 4/0 | — | text “Demon Slayer” (`.scene-card .title-open`) |
| progress control | 112×48 | SF 14/19.6 w400 | `#ffffff` (white) | — | — | L:1px #ffffff24 | — | 0/0/0/12 | gap 2 |  (`.scene-card .progress-control`) |
| scrub track | 52×1 | SF 14/19.6 w400 | `#ffffff` (white) | `#ffffff1c` | — | — | — | — | — |  (`.scene-card .progress-track`) |
| scrub trace | 41.6×1 | SF 14/19.6 w400 | `#ffffff` (white) | `#e9eeee` | — | — | — | — | — |  (`.scene-card .progress-trace`) |
| unit "Ep." | 28.5×11 | SF 9/11 w400 | `#dce3df` | — | — | — | — | — | — | whiteSpace nowrap; text “Ep.” (`.scene-card .progress-unit`) |
| count | 11.8×20.9 | SF 19/20.9 w500 | `#ffffff` (white) | — | — | — | — | — | — | whiteSpace nowrap; text “4” (`.scene-card .progress-value b`) |
| total "/ 5" | 16.7×13 | SF 11/12.1 w400 | `#dce3df` | — | — | — | — | — | — | opacity 0.8; whiteSpace nowrap; text “/ 5” (`.scene-card .progress-total`) |
| light key (button) | 44×44 | SF 14/19.6 w400, align center | `#29352c` | — | 12 | — | — | — | — | grid 44px; vars --key-face=linear-gradient(#f1f4f2,#d5ded8), --key-ink=#29352c; ::before "" 34×34 linear-gradient(#f1f4f2, #d5ded8) r7 border 1px #20282326 shadow #ffffff35 0px 1px 0px 0px inset, #14231912 0px 1px 2px 0px (`.scene-card .step`) |
| key glyph | 16×16 | SF 14/19.6 w400, align center | `#29352c` | — | — | — | — | — | — | grid 16px (`.scene-card .key-cap`) |
| key glyph svg | 16×16 | SF 14/19.6 w400, align center | `#29352c` | — | — | — | — | — | — |  (`.scene-card .key-cap svg`) |
| success cap | 44×44 | SF 14/19.6 w400, align center | `#29352c` | — | — | — | — | — | — | grid 44px; opacity 0 (`.scene-card .success-cap`) |
| footer row | 350×41 | SF 14/19.6 w400 | `#252625` (ink) | — | — | T:1px #ffffff0d | — | 0/12/0/14 | gap 8 |  (`.scene-card .scene-context`) |
| availability fact | 107.2×40 | SF 10/13 w400 | `#dce2df` | — | — | — | — | — | — | text “New episode available” (`.scene-card .availability`) |
| club link | 95.3×44 | SF 10/12 w400 | `#dce2df` | — | — | — | — | — | gap 5 | vars --art-base=#465471, --art-deep=#2b3341, --art-wash=#ecedea, --art-edge=#c8cbd0, --scene-tone=#465471 (`.scene-card .club-link`) |
| club initial | 17×17 | SF 8/9.6 w400 | `#dce2df` | `#ffffff14` | 50% | T:1px #ffffff44 R:1px #ffffff44 B:1px #ffffff44 L:1px #ffffff44 | — | — | — | grid 15px; text “M” (`.scene-card .club-initial`) |
| stage caption | 0×0 | SF 14/19.6 w400 | `#252625` (ink) | — | — | — | — | — | — | display none (`.stage-caption`) |

#### Also watching

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| heading row | 350×21 | SF 14/19.6 w400 | `#252625` (ink) | — | — | — | — | — | m 25/0/12 |  (`.rotation-heading`) |
| heading | 96.8×21 | SF 15/21 w550, tr -0.2 | `#252625` (ink) | — | — | — | — | — | — | text “Also watching” (`.rotation-heading h2`) |
| count | 33.4×14 | SF 10/14 w400 | `#696c6b` (muted) | — | — | — | — | — | — | text “4 titles” (`.rotation-heading > span`) |
| grid | 350×200 | SF 14/19.6 w400 | `#252625` (ink) | — | — | — | — | — | gap 16 | grid 167px 167px (`.carry-grid`) |
| tile | 167×92 | SF 14/19.6 w400 | `#252625` (ink) | — | — | — | — | — | gap normal 9 | grid 44px 114px; vars --art-base=#493134, --art-deep=#2c2123, --art-wash=#eceae5, --art-edge=#c8c2bf, --art-ink=#ffffff, --scene-tone=#493134 (`.carry-card`) |
| poster button | 44×66 | SF 14/19.6 w400, align center | `#252625` (ink) | `#e9e9e6` | 4 | — | #22222255 0px 3px 7px -4px | — | — | ::after "" 42×64 r4 border 1px #0000000b (`.carry-card .cover`) |
| poster image | 44×66 | SF 14/19.6 w400, align center | `#252625` (ink) | — | — | — | — | — | — | objectFit contain (`.carry-card .cover img`) |
| S2 stamp | 23.6×17 | SF 14/19.6 w400, align center | `#26372c` | `#f3f4f4` | 5 0 0 | — | — | 3/5 | gap 2 |  (`.carry-card .study-art-stamp`) |
| stamp S | 4.7×7 | SF 7/7 w400, align center | `#26372c` | — | — | — | — | — | — | text “S” (`.carry-card .study-art-stamp small`) |
| stamp number | 6.9×11 | SF 11/11 w550, align center | `#26372c` | — | — | — | — | — | — | text “2” (`.carry-card .study-art-stamp b`) |
| title | 114×48 | SF 12/15.6 w500 | `#252625` (ink) | — | — | — | — | — | — |  (`.carry-card h2`) |
| title button | 114×44 | SF 12/15 w500 | `#252625` (ink) | — | — | — | — | — | — | lines 3; text “Jujutsu Kaisen” (`.carry-card .title-open`) |
| progress row | 114×44 | SF 14/19.6 w400 | `#252625` (ink) | — | — | — | — | — | gap 2 |  (`.carry-card .progress-control`) |
| scrub track | 67×1 | SF 14/19.6 w400 | `#252625` (ink) | `#d7d9d7` | — | — | — | — | — |  (`.carry-card .progress-track`) |
| scrub trace | 44.7×1 | SF 14/19.6 w400 | `#252625` (ink) | `#626962` | — | — | — | — | — |  (`.carry-card .progress-trace`) |
| unit "Ep." | 15.3×14 | SF 10/14 w400 | `#5b635c` | — | — | — | — | — | — | whiteSpace nowrap; text “Ep.” (`.carry-card .progress-unit`) |
| count | 8.9×19.6 | SF 14/19.6 w500 | `#252625` (ink) | — | — | — | — | — | — | whiteSpace nowrap; text “6” (`.carry-card .progress-value b`) |
| dark key (button) | 44×44 | SF 14/19.6 w400, align center | `#ffffff` (white) | — | 12 | — | — | — | — | grid 44px; vars --key-face=linear-gradient(#493134,#2c2123), --key-ink=#fff; ::before "" 34×34 linear-gradient(#493134, #2c2123) r7 border 1px #20282326 shadow #ffffff35 0px 1px 0px 0px inset, #14231912 0px 1px 2px 0px (`.carry-card .step`) |
| key glyph | 16×16 | SF 14/19.6 w400, align center | `#ffffff` (white) | — | — | — | — | — | — | grid 16px (`.carry-card .key-cap`) |

#### Calendar

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| paper feed | 390×1028.8 | SF 14/19.6 w400 | `#252625` (ink) | — | — | — | — | 0/22/20 | — |  (`.paper-feed`) |
| section | 346×583.4 | SF 14/19.6 w400 | `#252625` (ink) | — | — | — | — | — | — |  (`.coming-up`) |
| heading row | 346×26.4 | SF 14/19.6 w400 | `#252625` (ink) | — | — | — | — | — | m 32/0/17; gap 9 |  (`.coming-up .section-head`) |
| heading "Coming up." | 113.8×26.4 | SF 24/26.4 w550, tr -0.85 | `#252625` (ink) | — | — | — | — | — | — | text “Coming up.” (`.coming-up .section-head h2`) |
| summary | 89.8×14 | SF 10/14 w400 | `#656c66` | — | — | — | — | — | — | text “6 releases · 7 days” (`.coming-up .section-head small`) |
| card | 346×540 | SF 14/19.6 w400 | `#252625` (ink) | `#fafcf9` | 18 | T:1px #d8ddd9 R:1px #d8ddd9 B:1px #d8ddd9 L:1px #d8ddd9 | #1d291c20 0px 2px 6px -4px | — | — |  (`.release-calendar`) |
| day group (open) | 344×307 | SF 14/19.6 w400 | `#252625` (ink) | — | — | — | — | — | — |  (`.release-day`) |
| day toggle | 344×76 | SF 14/19.6 w400 | `#252625` (ink) | `#ffffff` (white) | — | — | — | 12 | gap 11 |  (`.release-day .day-toggle`) |
| date chip | 40×44 | SF 14/19.6 w400 | `#252625` (ink) | `#ffffff` (white) | 10 | T:1px #d4dbd4 R:1px #d4dbd4 B:1px #d4dbd4 L:1px #d4dbd4 | #ffffff (white) 0px 1px 0px 0px inset | — | — |  (`.date-stamp`) |
| date chip day | 10.7×19 | SF 19/19 w550, tr -0.6 | `#252625` (ink) | — | — | — | — | — | — | text “2” (`.date-stamp b`) |
| date chip month | 20.6×10.8 | SF 9/10.8 w400, tr 0.4, uppercase | `#667267` | — | — | — | — | — | m 3/0/0 | text “Oct” (`.date-stamp small`) |
| day label | 172×16.8 | SF 12/16.8 w550 | `#252625` (ink) | — | — | — | — | — | — | text “Today” (`.day-copy strong`) |
| release count | 172×14 | SF 10/14 w400 | `#68736a` | — | — | — | — | — | m 4/0/0 | text “3 releases” (`.day-copy small`) |
| day art thumb | 23×34 | SF 14/19.6 w400 | `#252625` (ink) | — | 3 | T:2px #fafcf9 R:2px #fafcf9 B:2px #fafcf9 L:2px #fafcf9 | #243a2120 -2px 0px 2px 0px | — | m 0/0/0/-6 | objectFit contain (`.day-art img`) |
| disclosure | 18×24 | SF 21/29.4 w300 | `#727d73` | — | — | — | — | — | — | grid 18px; text “⌄” (`.disclosure-mark`) |
| events list | 344×231 | SF 14/19.6 w400 | `#252625` (ink) | `#ffffff` (white) | — | — | — | 0/12/9 | — |  (`.day-events`) |
| release row | 320×74 | SF 14/19.6 w400 | `#252625` (ink) | — | — | T:1px #e3e7e1 | — | 10/0 | gap 10 |  (`.release-row`) |
| row poster | 32×48 | SF 14/19.6 w400 | `#252625` (ink) | — | 3 | — | — | — | — | objectFit contain (`.release-row img`) |
| row title | 216.8×15.6 | SF 12/15.6 w500 | `#252625` (ink) | — | — | — | — | — | — | display flow-root; lines 2; text “Demon Slayer” (`.release-copy strong`) |
| row unit | 216.8×14 | SF 10/14 w400 | `#68736a` | — | — | — | — | — | m 4/0/0 | text “S1 · Episode 6” (`.release-copy small`) |
| row time | 27.2×13.5 | SF 10/13.5 w400, align right | `#58665b` | — | — | — | — | — | — | text “16:00” (`.release-when`) |
| row arrow | 14×26.6 | SF 19/26.6 w400 | `#798679` | — | — | — | — | — | — | grid 14px; text “›” (`.release-row .row-arrow`) |
| closed day group | 344×77 | SF 14/19.6 w400 | `#252625` (ink) | — | — | T:1px #dde2dd | — | — | — |  (`.release-day:nth-child(2)`) |

#### Dates to come

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| group | 344×77 | SF 14/19.6 w400 | `#252625` (ink) | `#f0f3ed` | — | T:1px #d7ded5 | — | — | — |  (`.pending-day`) |
| toggle | 344×76 | SF 14/19.6 w400 | `#252625` (ink) | — | — | — | — | 12 | gap 11 |  (`.pending-day .day-toggle`) |
| pending stamp | 40×44 | SF 18/25.2 w400 | `#737e70` | — | 10 | T:1px #d4dbd4 R:1px #d4dbd4 B:1px #d4dbd4 L:1px #d4dbd4 | — | — | — | text “…” (`.pending-stamp`) |
| label | 172×16.8 | SF 12/16.8 w550 | `#252625` (ink) | — | — | — | — | — | — | text “Dates to come” (`.pending-day .day-copy strong`) |
| count | 172×14 | SF 10/14 w400 | `#68736a` | — | — | — | — | — | m 4/0/0 | text “3 announcements” (`.pending-day .day-copy small`) |

#### Club room

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| room | 356×393.4 | SF 14/19.6 w400 | `#f0f4ef` | `#252b28`; radial-gradient(at 0px 0px, #444a46 0px, #00000000 65%), none; clip:border-box, border-box | 24 | T:1px #535a554c R:1px #535a554c B:1px #535a554c L:1px #535a554c | #ffffff21 0px 1px 0px 0px inset, #10171066 0px 10px 20px -14px | 20/16/12 | m 32/-5/0 |  (`.club-room`) |
| masthead | 322×36 | SF 14/19.6 w400 | `#f0f4ef` | — | — | — | — | — | m 0/0/19; gap 10 |  (`.club-masthead`) |
| seal | 42.7×42.7 | SF 9/12.6 w400, tr 1 | `#f0f4ef` | — | 50% | T:1px #899c8c R:1px #899c8c B:1px #899c8c L:1px #899c8c | — | 7/5 | — | grid 28px (`.club-seal`) |
| kicker | 116.7×9.8 | SF 7/9.8 w400, tr 1.4 | `#c0cbbb` | — | — | — | — | — | m 0/0/4 | text “YOUR PRIVATE CLUB” (`.club-kicker`) |
| club name | 116.7×22 | Georgia (serif) 22/22 w400, tr -0.6 | `#f0f4ef` | — | — | — | — | — | — | whiteSpace nowrap; text “Sunday Club” (`.club-masthead h2`) |
| member avatar | 22×22 | SF 7/9.8 w400 | `#33412e` | `#d0d8cb` | 50% | T:2px #2f3730 R:2px #2f3730 B:2px #2f3730 L:2px #2f3730 | — | — | m 0/0/0/-6 | grid 18px; text “M” (`.member-stack span`) |
| note card | 322×208.2 | SF 14/19.6 w400 | `#2e342c` | `#f5f6ef` | 14 | T:1px #ffffff88 R:1px #ffffff88 B:1px #ffffff88 L:1px #ffffff88 | #00000022 0px 3px 7px 0px | 15 | — |  (`.club-note`) |
| entry | 290×116.2 | SF 14/19.6 w400 | `#2e342c` | — | — | — | — | — | gap 13 |  (`.club-entry`) |
| title art | 60×90 | SF 14/19.6 w400, align center | `#2e342c` | — | 3 | — | #252b2625 0px 3px 6px 0px | — | — | objectFit contain (`.club-title-art img`) |
| person name | 25.9×15.4 | SF 11/15.4 w550 | `#2e342c` | — | — | — | — | — | — | text “Mina” (`.person-line b`) |
| time ago | 33×14 | SF 10/14 w400 | `#656e65` | — | — | — | — | — | m 0/0/0/152.094 | text “2h ago” (`.person-line small`) |
| quote | 217×46.8 | Georgia (serif) 18/23.4 w400, tr -0.3 | `#2e342c` | — | — | — | — | — | m 10/0/0 | text ““Just one more. Famous last words.”” (`.club-copy p`) |
| title link | 105.5×44 | SF 10/14 w400 | `#66705d` | — | — | — | — | 8/0/0 | — | text “Finished Death Note” (`.club-title`) |
| spoiler disclosure | 290×46 | SF 10/14 w400 | `#59664e` | `#e9ede2` | 8 | T:1px #ccd4c3 R:1px #ccd4c3 B:1px #ccd4c3 L:1px #ccd4c3 | — | 7/10 | m 14/0/0; gap 10 |  (`.club-note .spoiler`) |
| spoiler key | 24×24 | SF 20/28 w400 | `#59664e` | — | — | — | — | — | — | grid 24px; text “⌄” (`.spoiler-key`) |
| activity row | 322×70 | SF 14/19.6 w400 | `#f1f5ed` | — | 8 | — | — | 13/2 | m 4/0/0; gap 10 |  (`.club-secondary`) |
| activity art | 30×44 | SF 14/19.6 w400 | `#f1f5ed` | — | 3 | — | — | — | — | objectFit contain (`.club-secondary img`) |
| activity line 1 | 254×15.4 | SF 11/15.4 w500 | `#f1f5ed` | — | — | — | — | — | — | text “Jules started” (`.club-secondary b`) |
| activity line 2 | 254×14 | SF 10/14 w400 | `#c1cdb7` | — | — | — | — | — | m 3/0/0 | text “Attack on Titan” (`.club-secondary > span > span`) |
| footer | 322×22.2 | SF 8/11.2 w400 | `#b4c2a9` | — | — | T:1px #c5d2b81c | — | 10/2/0 | gap 10 |  (`.club-room-footer`) |
| footer text | 112.1×11.2 | SF 8/11.2 w400 | `#b4c2a9` | — | — | — | — | — | — | text “Shared stories. Your people.” (`.club-room-footer span`) |

#### Footer

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| footer | 390×62 | SF 10/14 w400 | `#696c6b` (muted) | — | — | — | — | 20/22/28 | — | text “Your pace. Your place.” (`.app-end`) |
| KURO | 38×14 | SF 10/14 w700, tr 2 | `#696c6b` (muted) | — | — | — | — | — | — | text “KURO” (`.app-end span`) |

### Home, anime, quiet (caught up), 390 (`ref-home-quiet-anime-390.png`)

#### Opening line

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| row | 350×18.2 | SF 14/19.6 w400 | `#252625` (ink) | — | — | — | — | — | gap 12 |  (`.opening-copy`) |
| kicker | 87.1×12.6 | SF 9/12.6 w400, tr 1.05 | `#666c68` | — | — | — | — | — | — | text “NOW WATCHING” (`.opening-eyebrow`) |
| headline | 98.3×18.2 | SF 14/18.2 w550, tr -0.3 | `#252625` (ink) | — | — | — | — | — | — | whiteSpace nowrap; text “Keep watching.” (`.opening-copy h1`) |
| quiet line (quiet scenario) | 350×37.4 | SF 11/15.4 w400 | `#696c6b` (muted) | `#ffffff80` | 8 | T:1px #dce1dc R:1px #dce1dc B:1px #dce1dc L:1px #dce1dc | — | 10/12 | m 0/20/20 | text “Nothing new today. Stay at your own pace.” (`.quiet`) |

### Home, anime, undated only, 390 (`ref-home-undated-anime-390.png`)

#### Coming-up glance

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| card | 350×72 | SF 14/19.6 w400 | `#303932` | `#fffefa` | 8 | T:1px #29312918 R:1px #29312918 B:1px #29312918 L:1px #29312918 | #29312905 0px 1px 2px 0px | 10/12 | gap 12 |  (`.upcoming-glance`) |
| title | 167.8×19.6 | SF 14/19.6 w550, tr -0.3 | `#303932` | — | — | — | — | — | — | text “Coming up” (`.upcoming-copy b`) |
| caption | 167.8×14 | SF 10/14 w400 | `#687064` | — | — | — | — | — | — | whiteSpace nowrap; text “Dates still to come” (`.upcoming-copy small`) |
| art strip | 69×38 | SF 14/19.6 w400 | `#303932` | — | — | — | — | 0/2/0/0 | — |  (`.upcoming-art`) |
| art thumb | 27×38 | SF 14/19.6 w400 | `#303932` | — | 2 | T:1px #fffefa R:1px #fffefa B:1px #fffefa L:1px #fffefa | #26352b14 0px 1px 2px 0px | — | — | objectFit cover (`.upcoming-art img`) |
| count | 39×21 | SF 21/21 w450, tr -0.6, align right | `#303932` | — | — | — | — | — | — | text “3” (`.upcoming-total b`) |
| count label | 39×11.2 | SF 8/11.2 w400, align right | `#687064` | — | — | — | — | — | — | whiteSpace nowrap; text “pending” (`.upcoming-total small`) |
| arrow | 12.2×22.4 | SF 16/22.4 w400 | `#687064` | — | — | — | — | — | — | text “↓” (`.upcoming-arrow`) |

#### Calendar

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| paper feed | 390×628.5 | SF 14/19.6 w400 | `#252625` (ink) | — | — | — | — | 0/22/20 | — |  (`.paper-feed`) |
| section | 346×183.2 | SF 14/19.6 w400 | `#252625` (ink) | — | — | — | — | — | — |  (`.coming-up`) |
| heading row | 346×26.4 | SF 14/19.6 w400 | `#252625` (ink) | — | — | — | — | — | m 32/0/17; gap 9 |  (`.coming-up .section-head`) |
| heading "Coming up." | 113.8×26.4 | SF 24/26.4 w550, tr -0.85 | `#252625` (ink) | — | — | — | — | — | — | text “Coming up.” (`.coming-up .section-head h2`) |
| summary | 65.9×14 | SF 10/14 w400 | `#656c66` | — | — | — | — | — | — | text “From your list” (`.coming-up .section-head small`) |
| card | 346×139.8 | SF 14/19.6 w400 | `#252625` (ink) | `#fafcf9` | 18 | T:1px #d8ddd9 R:1px #d8ddd9 B:1px #d8ddd9 L:1px #d8ddd9 | #1d291c20 0px 2px 6px -4px | — | — |  (`.release-calendar`) |
| day group (open) | 344×77 | SF 14/19.6 w400 | `#252625` (ink) | `#f0f3ed` | — | T:1px #d7ded5 | — | — | — |  (`.release-day`) |
| day toggle | 344×76 | SF 14/19.6 w400 | `#252625` (ink) | — | — | — | — | 12 | gap 11 |  (`.release-day .day-toggle`) |
| date chip | 40×44 | SF 18/25.2 w400 | `#737e70` | — | 10 | T:1px #d4dbd4 R:1px #d4dbd4 B:1px #d4dbd4 L:1px #d4dbd4 | — | — | — | text “…” (`.date-stamp`) |
| date chip day | — | not rendered in this state | | | | | | | | `.date-stamp b` |
| date chip month | — | not rendered in this state | | | | | | | | `.date-stamp small` |
| day label | 172×16.8 | SF 12/16.8 w550 | `#252625` (ink) | — | — | — | — | — | — | text “Dates to come” (`.day-copy strong`) |
| release count | 172×14 | SF 10/14 w400 | `#68736a` | — | — | — | — | — | m 4/0/0 | text “3 announcements” (`.day-copy small`) |
| day art thumb | 23×34 | SF 14/19.6 w400 | `#252625` (ink) | — | 3 | T:2px #f0f3ed R:2px #f0f3ed B:2px #f0f3ed L:2px #f0f3ed | #243a2120 -2px 0px 2px 0px | — | m 0/0/0/-6 | objectFit contain (`.day-art img`) |
| disclosure | 18×24 | SF 21/29.4 w300 | `#727d73` | — | — | — | — | — | — | grid 18px; text “⌄” (`.disclosure-mark`) |
| events list | 0×0 | SF 14/19.6 w400 | `#252625` (ink) | `#ffffff` (white) | — | — | — | 0/12/9 | — | display none (`.day-events`) |
| release row | 0×0 | SF 14/19.6 w400 | `#252625` (ink) | — | — | T:1px #e3e7e1 | — | 10/0 | gap 10 |  (`.release-row`) |
| row poster | 0×0 | SF 14/19.6 w400 | `#252625` (ink) | — | 3 | — | — | — | — | objectFit contain (`.release-row img`) |
| row title | 0×0 | SF 12/15.6 w500 | `#252625` (ink) | — | — | — | — | — | — | display flow-root; lines 2; text “Death Note” (`.release-copy strong`) |
| row unit | 0×0 | SF 10/14 w400 | `#68736a` | — | — | — | — | — | m 4/0/0 | text “New season” (`.release-copy small`) |
| row time | 0×0 | SF 10/13.5 w400, align right | `#58665b` | — | — | — | — | — | — | text “Date TBA” (`.release-when`) |
| row arrow | 0×0 | SF 19/26.6 w400 | `#798679` | — | — | — | — | — | — | text “›” (`.release-row .row-arrow`) |
| closed day group | — | not rendered in this state | | | | | | | | `.release-day:nth-child(2)` |

#### Dates to come

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| group | 344×77 | SF 14/19.6 w400 | `#252625` (ink) | `#f0f3ed` | — | T:1px #d7ded5 | — | — | — |  (`.pending-day`) |
| toggle | 344×76 | SF 14/19.6 w400 | `#252625` (ink) | — | — | — | — | 12 | gap 11 |  (`.pending-day .day-toggle`) |
| pending stamp | 40×44 | SF 18/25.2 w400 | `#737e70` | — | 10 | T:1px #d4dbd4 R:1px #d4dbd4 B:1px #d4dbd4 L:1px #d4dbd4 | — | — | — | text “…” (`.pending-stamp`) |
| label | 172×16.8 | SF 12/16.8 w550 | `#252625` (ink) | — | — | — | — | — | — | text “Dates to come” (`.pending-day .day-copy strong`) |
| count | 172×14 | SF 10/14 w400 | `#68736a` | — | — | — | — | — | m 4/0/0 | text “3 announcements” (`.pending-day .day-copy small`) |

### Home, manga, busy, 390 (`ref-home-busy-manga-390.png`)

#### Page

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| phone canvas (manga) | 390×844 | SF 14/19.6 w400 | `#272c28` | `#f5f5f3` | — | — | — | — | — |  (`.phone`) |

#### Opening line

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| headline (manga) | 98.7×18.2 | SF 14/18.2 w550, tr -0.3 | `#272c28` | — | — | — | — | — | — | whiteSpace nowrap; text “4 new chapters” (`.opening-copy h1`) |

#### Medium switch

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| selected word (manga) | 127.3×36 | SF 36/36 w850, tr -1.9, uppercase, align center | `#00000000` | `#253a2a`; linear-gradient(#15221c15, #15221c38), url("assets/manga0.jpg"); clip:text, text | — | — | — | — | — | text “Manga” (`.family-control button[aria-pressed=true] .mode-name`) |
| unselected word (anime) | 107.1×36 | SF 36/36 w850, tr -1.9, uppercase, align center | `#6e786f` | — | — | — | — | — | — | text “Anime” (`.family-control button[aria-pressed=false] .mode-name`) |

#### Manga leaf

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| stage | 346×506 | SF 14/19.6 w400 | `#272c28` | — | — | — | — | — | m 0/22 |  (`.activity-stage`) |
| grid | 346×506 | SF 14/19.6 w400 | `#272c28` | — | — | — | — | — | gap 26 14 | grid 106px 106px 106px; vars --mp-key=#2b342e (`.library-covers`) |
| leaf | 106×240 | SF 14/19.6 w400, align center | `#272c28` | — | — | — | — | — | — |  (`.library-object`) |
| story button | 106×190 | SF 14/19.6 w400, align center | `#272c28` | — | 4 | — | — | — | gap 8 | grid 106px (`.library-story`) |
| cover frame | 106×138 | SF 14/19.6 w400, align center | `#272c28` | — | — | — | — | — | — |  (`.library-art`) |
| cover image | 106×138 | SF 14/19.6 w400, align center | `#272c28` | — | 4 | — | #242c2514 0px 2px 3px 0px | — | — | objectFit cover (`.library-art img`) |
| title | 106×44 | SF 11/12.65 w500, tr -0.2, align center | `#272c28` | — | — | — | — | 3/0 | — | text “Chainsaw Man” (`.library-title`) |
| action row | 106×50 | SF 14/19.6 w400, align center | `#272c28` | — | — | T:1px #d8ddd2 | — | 5/0/0 | — |  (`.library-reading-actions`) |
| progress control | 106×44 | SF 14/19.6 w400, align center | `#2b342e` | — | — | — | — | — | gap 3 |  (`.library-reading-actions .progress-control`) |
| unit "Ch." | 14.9×12.6 | SF 9/12.6 w400, align center | `#59665a` | — | — | — | — | — | — | whiteSpace nowrap; text “Ch.” (`.library-reading-actions .progress-unit`) |
| count | 28.5×24 | SF 24/24 w500, tr -0.8, align center | `#27322b` | — | — | — | — | — | — | whiteSpace nowrap; text “24” (`.library-reading-actions .progress-value b`) |
| dark key | 44×44 | SF 14/19.6 w400, align center | `#f8faf7` | — | 6 | — | — | — | — | grid 44px; vars --key-face=linear-gradient(#444a47,#2c322f), --key-ink=#f8faf7; ::before "" 38×38 #2b342e r6 border 1px #2b342e shadow #ffffff1f 0px 1px 0px 0px inset, #28372a14 0px 1px 2px 0px (`.library-reading-actions .step`) |
| key glyph | 16×16 | SF 14/19.6 w400, align center | `#f8faf7` | — | — | — | — | — | — | grid 16px (`.library-reading-actions .key-cap`) |

#### Calendar

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| row time (manga) | 62×27 | SF 10/13.5 w400, align right | `#58665b` | — | — | — | — | — | — | text “Chapter release” (`.release-when`) |
| card (manga) | 346×538 | SF 14/19.6 w400 | `#272c28` | `#fafbf7` | 14 14 5 5 | — | #ffffff (white) 0px 1px 0px 0px inset, #2d302709 0px 5px 16px 0px | — | — |  (`.release-calendar`) |

#### Club room

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| room (manga) | 356×393.4 | SF 14/19.6 w400 | `#f0f4ef` | `#252b28`; radial-gradient(at 0px 0px, #444a46 0px, #00000000 65%), none; clip:border-box, border-box | 13 | T:1px #535a554c R:1px #535a554c B:1px #535a554c L:1px #535a554c | #ffffff21 0px 1px 0px 0px inset, #10171066 0px 10px 20px -14px | 20/16/12 | m 32/-5/0 |  (`.club-room`) |

### Home, new account, anime, 390 (`ref-home-new-anime-390.png`)

#### New-account Home

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| section | 390×356.8 | SF 14/19.6 w400, align center | `#252625` (ink) | — | — | — | — | 50/25/70 | — |  (`.empty-home`) |
| + mark | 340×58.8 | SF 42/58.8 w200, align center | `#858b84` | — | — | — | — | — | m 0/0/26 | text “＋” (`.empty-home > span`) |
| headline | 340×33.6 | SF 24/33.6 w700, tr -0.8, align center | `#252625` (ink) | — | — | — | — | — | — | text “Your stories belong here.” (`.empty-home h2`) |
| line | 196.5×36.4 | SF 13/18.2 w400, align center | `#646b65` | — | — | — | — | — | m 14/71.75/24/71.7344 | text “Import your list to bring your place with you.” (`.empty-home p`) |
| Explore Taste button | 144.9×44 | SF 14/19.6 w400, align center | `#252625` (ink) | — | 12 | T:1px #bfc4bd R:1px #bfc4bd B:1px #bfc4bd L:1px #bfc4bd | — | 0/20 | — | text “Explore Taste” (`.empty-home button`) |
| opening kicker | 102.8×12.6 | SF 9/12.6 w400, tr 1.05 | `#666c68` | — | — | — | — | — | — | text “YOUR COLLECTION” (`.opening-eyebrow`) |
| opening headline | 72.5×18.2 | SF 14/18.2 w550, tr -0.3 | `#252625` (ink) | — | — | — | — | — | — | whiteSpace nowrap; text “Begin here.” (`.opening-copy h1`) |
| footer | 390×62 | SF 10/14 w400 | `#696c6b` (muted) | — | — | — | — | 20/22/28 | — | text “Your pace. Your place.” (`.app-end`) |

### Taste, anime, busy, 390 (`ref-taste-busy-anime-390.png`)

#### Taste

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| section | 390×574.7 | SF 14/19.6 w400 | `#252625` (ink) | — | — | — | — | 0/22/24 | — |  (`.suggestions`) |
| heading | 151.7×26.4 | SF 24/26.4 w550, tr -0.85 | `#252625` (ink) | — | — | — | — | — | — | text “Your next story.” (`.suggestions .section-head h2`) |
| list | 346×507.3 | SF 14/19.6 w400 | `#252625` (ink) | — | — | — | — | — | gap 16 | grid 346px (`.story-list`) |
| landscape card | 346×295.3 | SF 14/19.6 w400 | `#252625` (ink) | `#ffffff` (white) | 19 | — | #14222540 0px 4px 14px -11px | — | — |  (`.story-card.story-landscape`) |
| landscape open | 346×295.3 | SF 14/19.6 w400 | `#252625` (ink) | — | 19 | — | — | — | — | grid 103px minmax(0px, 1fr) (`.story-landscape .story-open`) |
| landscape art | 346×123.6 | SF 14/19.6 w400 | `#252625` (ink) | `#365477` | 19 19 0 0 | — | — | — | — |  (`.story-landscape .story-art`) |
| landscape image | 346×123.6 | SF 14/19.6 w400 | `#252625` (ink) | — | — | — | — | — | — | objectFit cover (`.story-landscape .story-art img`) |
| copy block | 346×171.8 | SF 14/19.6 w400 | `#252625` (ink) | — | — | — | — | 17/17/67 | — |  (`.story-landscape .story-copy`) |
| kind kicker | 312×11.2 | SF 8/11.2 w400, tr 0.5 | `#626b63` | — | — | — | — | — | — | text “FILM · ROMANCE” (`.story-landscape .story-kind`) |
| title (landscape) | 312×28.6 | SF 26/28.6 w550, tr -0.6 | `#252625` (ink) | — | — | — | — | — | m 6/0/0 | text “Your Name.” (`.story-landscape .story-title`) |
| premise | 219.2×36 | SF 12/18 w400 | `#575c59` | — | — | — | — | — | m 6/0/0 | text “Two strangers wake up in each other’s lives.” (`.story-landscape .story-premise`) |
| save row | 312×44 | SF 14/19.6 w400 | `#252625` (ink) | — | — | — | — | — | — |  (`.story-landscape .story-save`) |
| Plan key | 312×44 | SF 11/15.4 w500, align center | `#36433a` | `#f4f6f5` | 10 | T:1px #e0e5e1 R:1px #e0e5e1 B:1px #e0e5e1 L:1px #e0e5e1 | #ffffff (white) 0px 1px 0px 0px inset | 0/12 | gap 5 |  (`.story-landscape .save`) |
| Plan label | 72.3×15.4 | SF 11/15.4 w500, align center | `#36433a` | — | — | — | — | — | — | text “Plan to watch” (`.story-landscape .save > span`) |
| Plan bookmark | 26×28 | SF 11/15.4 w500, align center | `#36433a` | — | — | — | — | — | — | grid 26px (`.story-landscape .save-mark`) |
| portrait card | 346×196 | SF 14/19.6 w400 | `#252625` (ink) | `#ffffff` (white) | 19 | — | #14222540 0px 4px 14px -11px | — | — |  (`.story-card:not(.story-landscape)`) |
| portrait art | 103×180 | SF 14/19.6 w400 | `#252625` (ink) | `#f0f0ed` | 12 | — | — | — | — |  (`.story-card:not(.story-landscape) .story-art`) |
| title (portrait) | 202×23.1 | SF 21/23.1 w550, tr -0.6 | `#252625` (ink) | — | — | — | — | — | m 8/0/0 | text “A Silent Voice” (`.story-card:not(.story-landscape) .story-title`) |
| opening kicker | 93×12.6 | SF 9/12.6 w400, tr 1.05 | `#666c68` | — | — | — | — | — | — | text “FOR YOUR TASTE” (`.opening-eyebrow`) |
| opening headline | 94.6×18.2 | SF 14/18.2 w550, tr -0.3 | `#252625` (ink) | — | — | — | — | — | — | whiteSpace nowrap; text “Another world.” (`.opening-copy h1`) |

### Taste, manga, new account, 390 (`ref-taste-new-manga-390.png`)

#### Taste (new, manga)

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| list | 346×397.2 | SF 14/19.6 w400 | `#272c28` | — | — | — | — | — | gap 17 | grid 164.5px 164.5px (`.story-list`) |
| card | 164.5×397.2 | SF 14/19.6 w400 | `#272c28` | — | — | — | — | — | — |  (`.story-card`) |
| art | 164.5×246.8 | SF 14/19.6 w400 | `#272c28` | `#ffffff` (white) | 2 | T:1px #d9dbd3 R:1px #d9dbd3 B:1px #d9dbd3 L:1px #d9dbd3 | #fafbf6 2px 2px 0px -1px, #e1e3da 2px 2px 0px 0px | 9 | — |  (`.story-card .story-art`) |
| kind | 164.5×12.6 | SF 9/12.6 w400, tr 0.2 | `#626b63` | — | — | — | — | — | — | text “MANGA · HISTORICAL” (`.story-card .story-kind`) |
| title | 164.5×22 | SF 20/22 w550, tr -0.5 | `#272c28` | — | — | — | — | — | m 7/0/0 | text “Vinland Saga” (`.story-card .story-title`) |
| premise | 164.5×31.9 | SF 11/15.95 w400 | `#575c59` | — | — | — | — | — | m 8/0/0 | text “A young Viking dreams of a land beyond war.” (`.story-card .story-premise`) |
| Plan key | 164.5×44 | SF 10/14 w500, align center | `#36433a` | `#fffffc` | 10 | T:1px #bec5b8 R:1px #bec5b8 B:1px #bec5b8 L:1px #bec5b8 | #ffffff (white) 0px 1px 0px 0px inset | 0/12 | gap 5 |  (`.story-card .save`) |
| heading | 155×26.4 | SF 24/26.4 w500, tr -0.65 | `#272c28` | — | — | — | — | — | — | text “A first favourite.” (`.suggestions .section-head h2`) |

### Detail, anime (`detail=anime-2`), 390 (`ref-detail-anime-390.png`)

#### Detail sheet

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| sheet | 356×776.5 | SF 14/19.6 w400 | `#252625` (ink) | `#f5f5f4` (paper) | 24 | T:1px #ffffff (white) R:1px #ffffff (white) B:1px #ffffff (white) L:1px #ffffff (white) | #1c1c1c40 0px 25px 80px 0px | — | m 55.5312/17/12 | vars --art-base=#493134, --art-deep=#2c2123, --art-wash=#eceae5, --art-edge=#c8c2bf, --art-ink=#ffffff, --detail-tint=#526e60, --scene-tone=#493134 (`#detail`) |
| close | 44×44 | SF 22/30.8 w400, align center | `#ffffff` (white) | `#493134` | 50% | T:1px #ffffff45 R:1px #ffffff45 B:1px #ffffff45 L:1px #ffffff45 | — | 1/6 | m 12/12/-56/0 | text “×” (`#detail .close`) |
| sample footnote (prototype only) | 306×25.2 | SF 9/12.6 w400 | `#757c72` | — | — | — | — | — | m 18/0/0 | text “Design preview · sample progress, groupings & club activity. Editorial descripto” (`#detail .sample`) |

#### D1 Hero

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| intro band | 354×222.7 | SF 14/19.6 w400 | `#ffffff` (white) | linear-gradient(135deg, #493134, #2c2123) | — | — | — | — | gap 16 | vars --art-base=#493134, --art-deep=#2c2123, --art-wash=#eceae5, --art-edge=#c8c2bf, --art-ink=#ffffff, --detail-tint=#526e60, --scene-tone=#493134 (`#detail .detail-intro`) |
| light layer | 0×0 | SF 14/19.6 w400 | `#ffffff` (white) | — | — | — | — | — | — | display none; opacity 0.06; filter blur(38px) saturate(0.6) (`#detail .detail-light`) |
| artwork | 354×150.6 | SF 14/19.6 w400 | `#ffffff` (white) | — | — | — | — | — | — | ::after "" 354×150.625 linear-gradient(#00000000 50%, #2c2123) (`#detail .detail-object`) |
| artwork image | 354×150.6 | SF 14/19.6 w400 | `#ffffff` (white) | — | — | — | — | — | — | objectFit cover (`#detail .detail-object img`) |
| heading block | 354×72 | SF 14/19.6 w400 | `#ffffff` (white) | `#2c2123` | — | — | — | 4/24/19 | gap 6 12 | grid 235.906px 58.0938px (`#detail .detail-heading`) |
| kind kicker | 306×12.8 | SF 8/12.8 w400, tr 1.7, uppercase | `#c6ceca` | — | — | — | — | — | — | text “Anime” (`#detail .detail-kicker`) |
| title | 235.9×30.2 | SF 27/30.24 w600, tr -1.1 | `#ffffff` (white) | — | — | — | — | — | — | text “Jujutsu Kaisen” (`#detail .detail-heading h2`) |
| status mark | 58.1×14 | SF 10/14 w400 | `#dae4df` | — | — | — | — | — | gap 6 | ::before "" 5×5 r50% border 1px #dae4df; text “Watching” (`#detail .detail-collection`) |

#### D2 Story

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| body | 354×2434.3 | SF 14/19.6 w400 | `#252625` (ink) | radial-gradient(115% 200px at 0px 0px, #526e600b, #00000000) | — | — | — | 23/24/24 | — | vars --art-base=#493134, --art-deep=#2c2123, --art-wash=#eceae5, --art-edge=#c8c2bf, --art-ink=#ffffff, --detail-tint=#526e60, --scene-tone=#493134 (`#detail .detail-body`) |
| section | 306×122.3 | SF 14/19.6 w400 | `#252625` (ink) | — | — | — | — | — | m 0/0/4 |  (`#detail .detail-hook`) |
| eyebrow | 306×11.2 | SF 8/11.2 w600, tr 1.4, uppercase | `#68776f` | — | — | — | — | — | m 0/0/10 | text “Season 2” (`#detail .detail-hook .detail-eyebrow`) |
| hook headline | 306×54.1 | SF 22/27.06 w530, tr -0.65 | `#252625` (ink) | — | — | — | — | — | m 0/0/3 | text “Old friendships. A city on the edge.” (`#detail .detail-hook h3`) |
| About this season + | 306×44 | SF 10/14 w400 | `#59685f` | — | — | — | — | — | — | text “About this season” (`#detail .full-synopsis summary`) |
| summary + | 10.3×23.8 | SF 17/23.8 w400 | `#59685f` | — | — | — | — | — | — | text “+” (`#detail .full-synopsis summary span`) |
| synopsis | 306×85.8 | SF 13/21.45 w400 | `#58635b` | — | — | — | — | — | m 13/0 | text “Two connected chapters shift the perspective: the bonds of an earlier generation” (`#detail .full-synopsis p`) |
| expectation | 306×17 | SF 10/17 w400, tr 0.05 | `#56635b` | — | — | — | — | — | m 12/0/18 | text “Past and present · Fractured bonds · Rising tension” (`#detail .expectation`) |

#### D3 Club presence

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| row | 306×44 | SF 11/15.4 w400 | `#526459` | — | — | — | — | — | m 0/0/15; gap 10 | vars --art-base=#493134, --art-deep=#2c2123, --art-wash=#eceae5, --art-edge=#c8c2bf, --art-ink=#ffffff, --detail-tint=#526e60, --scene-tone=#493134 (`#detail .circle-jump`) |
| avatar | 25×25 | SF 9/12.6 w400 | `#3c5041` | `#d3ded3` | 50% | T:2px #f4f5f0 R:2px #f4f5f0 B:2px #f4f5f0 L:2px #f4f5f0 | — | — | m 0/0/0/-4 | grid 21px; text “M” (`#detail .circle-jump .tiny-people i`) |
| label | 115.8×15.4 | SF 11/15.4 w400 | `#526459` | — | — | — | — | — | — | text “3 people in your clubs” (`#detail .circle-jump > span:nth-child(2)`) |

#### D4 Seasons

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| workspace | 322×559.6 | SF 14/19.6 w400 | `#252625` (ink) | — | — | — | — | 0/8/8 | m 0/-8 | vars --art-base=#493134, --art-deep=#2c2123, --art-wash=#eceae5, --art-edge=#c8c2bf, --art-ink=#ffffff, --detail-tint=#526e60, --scene-tone=#493134 (`#detail .season-workspace`) |
| heading | 65.8×25.2 | SF 18/25.2 w550, tr -0.7 | `#252625` (ink) | — | — | — | — | — | — | text “Seasons” (`#detail .series-overview-heading h3`) |
| count | 48.6×14 | SF 10/14 w400 | `#727873` | — | — | — | — | — | — | text “2 seasons” (`#detail .series-overview-heading small`) |
| tiles row | 306×89 | SF 14/19.6 w400 | `#252625` (ink) | — | — | — | — | 2/1/0 | gap 8 |  (`#detail .section-panels`) |
| tile | 148×87 | SF 14/19.6 w400, align center | `#7b847e` | linear-gradient(150deg, #ffffff (white), #eef1ee) | 11 | T:1px #d9dedb R:1px #d9dedb B:1px #d9dedb L:1px #d9dedb | #ffffff (white) 0px 1px 0px 0px inset, #20292305 0px 2px 2px 0px | 11/12/9 | — | opacity 0.72; ::before "" 146×85 repeating-linear-gradient(90deg, #00000000 0px, #00000000 5px, #232c2405 5px, #232c2405 6px); ::after "" auto×2 linear-gradient(90deg, #7b847e 6px, #00000000 6px, #00000000 calc(100% - 6px), #7b847e calc(100% - 6px)) (`#detail .section-panel:not(.is-resume)`) |
| tile (current) | 148×87 | SF 14/19.6 w400, align center | `#ffffff` (white) | linear-gradient(135deg, #493134, #2c2123) | 11 | T:1px #493134 R:1px #493134 B:1px #493134 L:1px #493134 | #718478 0px 0px 0px 1px inset, #273b3010 0px 3px 7px 0px | 11/12/9 | — | ::before "" 146×85 repeating-linear-gradient(90deg, #00000000 0px, #00000000 5px, #ffffff06 5px, #ffffff06 6px); ::after "" 7×18 #493134 (`#detail .section-panel.is-resume`) |
| tile number | 18.3×39.6 | SF 33/39.6 w350, tr -2, align center | `#7b847e` | — | — | — | — | — | — | text “1” (`#detail .section-panel .panel-index`) |
| tile number (current) | 18.3×39.6 | SF 33/39.6 w350, tr -2, align center | `#ffffff` (white) | — | — | — | — | — | — | text “2” (`#detail .section-panel.is-resume .panel-index`) |
| tile foot | 122×13 | SF 8/13 w400, tr 0.1, align center | `#ffffff` (white) | — | — | — | — | — | — | text “Current” (`#detail .section-panel.is-resume .panel-foot`) |
| selection thread | 306×18 | SF 14/19.6 w400 | `#252625` (ink) | — | — | B:1px #becbc0 | — | — | — | ::before "" 6×6 #493134 r50% shadow #f1f3ef 0px 0px 0px 3px; ::after "" 1×18 #718a78 (`#detail .selection-thread`) |

#### D5 Progress

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| content | 306×409.4 | SF 14/19.6 w400 | `#252625` (ink) | linear-gradient(#eceae5, #00000000 250px) | — | — | — | 15/0/1 | — | vars --art-base=#493134, --art-deep=#2c2123, --art-wash=#eceae5, --art-edge=#c8c2bf, --art-ink=#ffffff, --detail-tint=#526e60, --scene-tone=#493134 (`#detail .season-content`) |
| row | 306×47 | SF 14/19.6 w400 | `#252625` (ink) | — | — | B:1px #344a3914 | — | 0/0/12 | gap 10 |  (`#detail .detail-progress`) |
| label | 114.5×14 | SF 10/14 w500 | `#5a695f` | — | — | — | — | — | — | text “Season 2 progress” (`#detail .progress-context > span`) |
| caption | 114.5×13.5 | SF 9/13.5 w400 | `#6b776d` | — | — | — | — | — | m 4/0/0 | text “9 episodes in this preview” (`#detail .progress-context small`) |
| unit | 15.3×14 | SF 10/14 w400 | `#696c6b` (muted) | — | — | — | — | — | — | whiteSpace nowrap; text “Ep.” (`#detail .detail-progress .progress-unit`) |
| count | 13×29.4 | SF 21/29.4 w500 | `#252625` (ink) | — | — | — | — | — | — | whiteSpace nowrap; text “6” (`#detail .detail-progress .progress-value b`) |
| total | 16.7×13 | SF 11/15.4 w400 | `#696c6b` (muted) | — | — | — | — | — | — | opacity 0.8; whiteSpace nowrap; text “/ 9” (`#detail .detail-progress .progress-total`) |
| scrub track | 0×1 | SF 14/19.6 w400 | `#252625` (ink) | `#d7d9d7` | — | — | — | — | — |  (`#detail .detail-progress .progress-track`) |

#### D6 Episodes

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| season eyebrow | 306×11.2 | SF 8/11.2 w600, tr 1.2, uppercase | `#68776f` | — | — | — | — | — | — | vars --art-base=#493134, --art-deep=#2c2123, --art-wash=#eceae5, --art-edge=#c8c2bf, --art-ink=#ffffff, --detail-tint=#526e60, --scene-tone=#493134; text “Season 2” (`#detail .edition-heading .detail-eyebrow`) |
| season title | 306×23.4 | SF 18/23.4 w550, tr -0.55 | `#252625` (ink) | — | — | — | — | — | m 6/0 | text “Hidden Inventory / Shibuya Incident” (`#detail .edition-heading h3`) |
| heading | 68.5×23.8 | SF 17/23.8 w550, tr -0.4 | `#252625` (ink) | — | — | — | — | — | — | text “Episodes” (`#detail .selected-edition .detail-section-head h4`) |
| heading note | 34.5×12.6 | SF 9/12.6 w400 | `#738076` | — | — | — | — | — | — | text “Preview” (`#detail .selected-edition .detail-section-head small`) |
| Up next row | 324×74 | SF 14/19.6 w400 | `#252625` (ink) | `#eceae5` | 12 | T:1px #c8c2bf R:1px #c8c2bf B:1px #c8c2bf L:1px #c8c2bf | #ffffff (white) 0px 1px 0px 0px inset, #344d3805 0px 3px 8px 0px | 7/9 | m 6/-9; gap normal 8 | grid 252px 44px (`#detail .unit-item.is-next`) |
| Up next summary | 252×58 | SF 14/19.6 w400 | `#252625` (ink) | — | — | — | — | — | gap 12 |  (`#detail .unit-item.is-next summary`) |
| Up next thumb | 32×44 | SF 14/19.6 w400 | `#252625` (ink) | — | — | — | — | — | — | objectFit cover (`#detail .unit-item.is-next summary img`) |
| Up next kicker | 56.8×9.8 | SF 7/9.8 w650, tr 1.4 | `#526d56` | — | — | — | — | — | m 0/0/4 | text “UP NEXT” (`#detail .unit-item.is-next summary small`) |
| Up next title | 56.8×16.8 | SF 12/16.8 w550 | `#252625` (ink) | — | — | — | — | — | — | text “Episode 7” (`#detail .unit-item.is-next summary b`) |
| Up next key | 44×44 | SF 14/19.6 w400, align center | `#ffffff` (white) | linear-gradient(#493134, #2c2123) | 12 | T:1px #493134 R:1px #493134 B:1px #493134 L:1px #493134 | #ffffff36 0px 1px 0px 0px inset, #23392a16 0px 2px 2px 0px | — | m 7/0/0 |  (`#detail .unit-complete`) |
| Up next key glyph | 42×18 | SF 14/19.6 w400, align center | `#ffffff` (white) | — | — | — | — | — | — |  (`#detail .unit-complete .key-cap`) |
| finished row | 306×57 | SF 14/19.6 w400 | `#252625` (ink) | — | — | — | — | — | gap 12 |  (`#detail .unit-item.is-finished summary`) |
| row number | 26×25.2 | SF 18/25.2 w350, tr -1 | `#79847b` | — | — | — | — | — | — | text “06” (`#detail .unit-item.is-finished summary > span:first-child`) |
| row title | 57.7×16.8 | SF 12/16.8 w550 | `#79847b` | — | — | — | — | — | — | text “Episode 6” (`#detail .unit-item.is-finished summary b`) |
| row state | 57.7×12.6 | SF 9/12.6 w400 | `#6c766e` | — | — | — | — | — | m 3/0/0 | text “Completed” (`#detail .unit-item.is-finished summary small`) |
| later row | 306×57 | SF 14/19.6 w400 | `#252625` (ink) | — | — | — | — | — | gap 12 |  (`#detail .unit-item:not(.is-next):not(.is-finished) summary`) |
| More episodes | 306×44 | SF 11/15.4 w400, align center | `#495e50` | — | — | — | — | — | — | text “More episodes” (`#detail .detail-text-button`) |

#### D7 Original story

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| card | 306×219.6 | SF 14/19.6 w400 | `#252625` (ink) | — | — | T:1px #364b3620 B:1px #364b3620 | — | 19/8/19/0 | m 27/0; gap 18 | vars --art-base=#493134, --art-deep=#2c2123, --art-wash=#eceae5, --art-edge=#c8c2bf, --art-ink=#ffffff, --detail-tint=#526e60, --scene-tone=#493134 (`#detail .source-bridge`) |
| 原作 book | 57.2×77.2 | SF 14/19.6 w400 | `#516149` | linear-gradient(100deg, #d6dbce 0px, #d6dbce 5px, #fafaf0 5px) | — | T:1px #b6c1ac R:1px #b6c1ac B:1px #b6c1ac L:1px #b6c1ac | #f6f5e9 3px 1px 0px 0px, #c7cebd 4px 1px 0px 0px, #edeedf 6px 2px 0px 0px | 14/0/0 | — |  (`#detail .bridge-book`) |
| 原作 glyph | 20.7×30.8 | SF 13/18.2 w400, tr 2 | `#516149` | — | — | — | — | — | — | text “原作” (`#detail .bridge-book span`) |
| eyebrow | 128.5×9.8 | SF 7/9.8 w600, tr 1.4, uppercase | `#68776f` | — | — | — | — | — | — | text “The original story” (`#detail .source-bridge .detail-eyebrow`) |
| title | 128.5×23.8 | SF 17/23.8 w550, tr -0.4 | `#252625` (ink) | — | — | — | — | — | m 6/0/2 | text “Jujutsu Kaisen” (`#detail .source-bridge h4`) |
| author | 128.5×14 | SF 10/14 w400 | `#6c786a` | — | — | — | — | — | — | text “Gege Akutami” (`#detail .source-bridge p`) |
| Explore the manga | 128.5×44 | SF 11/15.4 w400 | `#252625` (ink) | — | — | — | — | — | gap 16 | text “Explore the manga” (`#detail .source-bridge .source-detail-link`) |
| mapping note | 128.5×12 | SF 8/12 w400 | `#7a8576` | — | — | — | — | — | — | text “Season 2 → manga” (`#detail .source-bridge small`) |
| coverage disclosure | 298×48 | SF 11/15.4 w400 | `#252625` (ink) | — | — | — | — | — | gap 10 | text “Where this season meets the manga” (`#detail .coverage-disclosure summary`) |

#### D8 Sound

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| panel | 306×405.3 | SF 14/19.6 w400 | `#f0f5f1` | linear-gradient(145deg, #493134, #2c2123) | 16 | T:1px #493134 R:1px #493134 B:1px #493134 L:1px #493134 | #ffffff24 0px 1px 0px 0px inset, #14291c0b 0px 6px 15px 0px | 19/16/12 | m 25/0/0 | vars --art-base=#493134, --art-deep=#2c2123, --art-wash=#eceae5, --art-edge=#c8c2bf, --art-ink=#ffffff, --detail-tint=#526e60, --scene-tone=#493134 (`#detail .sound-panel`) |
| heading | 116.1×23.8 | SF 17/23.8 w550, tr -0.4 | `#f0f5f1` | — | — | — | — | — | — | text “The sound of it.” (`#detail .sound-panel h3`) |
| signature bar | 2×9 | SF 26/36.4 w400, italic | `#abbdb0` | `#a4baa9` | 2 | — | — | — | — |  (`#detail .sound-signature i`) |
| song row | 272×78 | SF 14/19.6 w400 | `#f0f5f1` | — | — | B:1px #ffffff14 | — | 12/0 | gap 12 |  (`#detail .song-row`) |
| OP/ED glyph | 43×43 | SF 23/32.2 w400 | `#493134` | `#eceae5` | 5 | T:1px #e5ecd84c R:1px #e5ecd84c B:1px #e5ecd84c L:1px #e5ecd84c | #f1f5e870 2px 0px 0px 0px inset, #071b1320 0px 3px 5px 0px | — | — |  (`#detail .song-glyph`) |
| glyph text | 15.6×26.8 | SF 12/16.8 w550, tr -0.8 | `#493134` | — | — | T:1px #546b5235 B:1px #546b5235 | — | 4/0 | — | text “OP” (`#detail .song-glyph span`) |
| row kicker | 175×11.2 | SF 8/11.2 w400, tr 0.2 | `#b0c3b5` | — | — | — | — | — | — | text “Opening · Hidden Inventory” (`#detail .song-row small`) |
| song title | 175×16.3 | SF 13/16.25 w550 | `#f0f5f1` | — | — | — | — | — | m 4/0 | text “Where Our Blue Is” (`#detail .song-row b`) |
| artist | 175×14 | SF 10/14 w400 | `#b4c6ba` | — | — | — | — | — | — | text “Tatsuya Kitani” (`#detail .song-row > span:nth-child(2) > span`) |
| Listen ↗ | 30×30 | SF 13/18.2 w400 | `#c1d4c6` | — | 50% | T:1px #ffffff18 R:1px #ffffff18 B:1px #ffffff18 L:1px #ffffff18 | — | — | — | text “↗” (`#detail .song-arrow`) |
| music note | 272×13.5 | SF 9/13.5 w400 | `#a9beb0` | — | — | — | — | — | m 13/0/0 | text “Find on Spotify · track links not yet matched” (`#detail .music-note`) |

#### D9 Characters

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| heading | 117.7×23.8 | SF 17/23.8 w550, tr -0.4 | `#252625` (ink) | — | — | — | — | — | — | vars --art-base=#493134, --art-deep=#2c2123, --art-wash=#eceae5, --art-edge=#c8c2bf, --art-ink=#ffffff, --detail-tint=#526e60, --scene-tone=#493134; text “The characters.” (`#detail .detail-cast h3`) |
| Tap to meet | 52×12.6 | SF 9/12.6 w400 | `#738076` | — | — | — | — | — | — | text “Tap to meet” (`#detail .detail-cast small`) |
| rail | 306×139.8 | SF 14/19.6 w400 | `#252625` (ink) | — | — | — | — | 5/1/7 | gap 12 |  (`#detail .portrait-rail`) |
| card | 67×127.8 | SF 14/19.6 w400 | `#252625` (ink) | — | — | — | — | — | — |  (`#detail .character-card`) |
| portrait | 67×83.8 | SF 14/19.6 w400 | `#252625` (ink) | `#e3e8e2` | 8 | — | #00000011 0px 0px 0px 1px inset | — | — |  (`#detail .character-image`) |
| name | 67×44 | SF 10/15 w400 | `#252625` (ink) | — | — | — | — | 9/0/0 | — | text “Yuji Itadori” (`#detail .character-card > span:last-child`) |

#### D10 Credits

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| heading | 306×23.8 | SF 17/23.8 w550, tr -0.4 | `#252625` (ink) | — | — | — | — | — | m 0/0/13 | vars --art-base=#493134, --art-deep=#2c2123, --art-wash=#eceae5, --art-edge=#c8c2bf, --art-ink=#ffffff, --detail-tint=#526e60, --scene-tone=#493134; text “Behind the frames.” (`#detail .detail-credits h3`) |
| row | 306×40.4 | SF 11/15.4 w400 | `#252625` (ink) | — | — | B:1px #26382e14 | — | 12/0 | gap 15 |  (`#detail .detail-credits div`) |
| role | 69×15.4 | SF 11/15.4 w400 | `#69766c` | — | — | — | — | — | — | text “Original work” (`#detail .detail-credits span`) |
| name | 75.9×15.4 | SF 11/15.4 w550, align right | `#252625` (ink) | — | — | — | — | — | — | text “Gege Akutami” (`#detail .detail-credits b`) |

#### D11 Between us

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| card | 318×498.9 | SF 14/19.6 w400 | `#252625` (ink) | radial-gradient(at 100% 0px, #dce6d59c, #00000000 60%), linear-gradient(125deg, #e8eee6, #eff2e9); clip:border-box, border-box | 22 22 8 8 | T:1px #c4d0c5 R:1px #c4d0c5 B:1px #c4d0c5 L:1px #c4d0c5 | #ffffff (white) 0px 1px 0px 0px inset, #2b463b06 0px 5px 12px 0px | 23/20/13 | m 28/-6/18 | vars --art-base=#493134, --art-deep=#2c2123, --art-wash=#eceae5, --art-edge=#c8c2bf, --art-ink=#ffffff, --detail-tint=#526e60, --scene-tone=#493134 (`#detail .detail-club-room`) |
| art heading | 316×154.5 | SF 14/19.6 w400 | `#252625` (ink) | linear-gradient(120deg, #dbe3d5, #eaf0e4) | 20 20 0 0 | — | — | — | m -23/-20/0; gap 19 |  (`#detail .circle-art-heading`) |
| cover | 105×154.5 | SF 14/19.6 w400 | `#252625` (ink) | — | — | — | — | — | — |  (`#detail .circle-cover`) |
| eyebrow | 138.4×9.8 | SF 7/9.8 w600, tr 1.2, uppercase | `#68776f` | — | — | — | — | — | — | text “Your clubs · private” (`#detail .circle-art-copy .detail-eyebrow`) |
| heading | 138.4×30.8 | Georgia (serif) 28/30.8 w400, tr -0.9 | `#252625` (ink) | — | — | — | — | — | m 12/0/16 | text “Between us.” (`#detail .circle-art-copy h3`) |
| avatar | 22×22 | SF 8/11.2 w400 | `#3c5041` | `#d3ded3` | 50% | T:2px #e5ecdf R:2px #e5ecdf B:2px #e5ecdf L:2px #e5ecdf | — | — | m 0/0/0/-4 | grid 18px; text “M” (`#detail .circle-art-copy .tiny-people i`) |
| names | 138.4×12.6 | SF 9/12.6 w400 | `#61725d` | — | — | — | — | — | m 6/0/0 | text “Mina, Jules, Noah” (`#detail .circle-names`) |
| Who's watching | 276×47 | SF 10/14 w400 | `#252625` (ink) | — | — | B:1px #647c6426 | — | — | — | text “Who's watching” (`#detail .circle-members summary`) |
| note | 276×93 | SF 14/19.6 w400 | `#252625` (ink) | — | — | B:1px #6f867120 | — | 13/0/14 | — |  (`#detail .circle-note`) |
| note name | 26.2×15.4 | SF 11/15.4 w600 | `#252625` (ink) | — | — | — | — | — | — | text “Mina” (`#detail .note-byline b`) |
| note club | 49.8×11.2 | SF 8/11.2 w400 | `#6b7b6d` | — | — | — | — | — | — | text “Sunday Club” (`#detail .note-byline span`) |
| note text | 276×41.6 | SF 13/20.8 w400 | `#405646` | — | — | — | — | — | m 8/0/0 | whiteSpace pre-wrap; text “Came for the animation. Stayed for the characters.” (`#detail .circle-note p`) |
| spoiler | 276×44 | SF 10/14 w400 | `#526c56` | — | — | — | — | — | gap 8 |  (`#detail .comment-spoiler summary`) |
| Reveal | 28.9×13.6 | SF 9/12.6 w400 | `#526c56` | — | — | B:1px #647c6340 | — | — | — | text “Reveal” (`#detail .reveal-label`) |
| Leave a thought | 276×62 | SF 12/16.8 w500 | `#252625` (ink) | `#f6f8f1` | 12 | T:1px #cbd7c5 R:1px #cbd7c5 B:1px #cbd7c5 L:1px #cbd7c5 | #ffffff (white) 0px 1px 0px 0px inset | 10/12 | m 11/0/0; gap 12 |  (`#detail .circle-compose summary`) |
| + symbol | 28×28 | SF 20/28 w300 | `#4e6849` | — | 50% | T:1px #adc0a9 R:1px #adc0a9 B:1px #adc0a9 L:1px #adc0a9 | — | — | — | grid 26px; text “＋” (`#detail .compose-symbol`) |
| Leave a thought label | 100.5×34.4 | SF 12/16.8 w500 | `#252625` (ink) | — | — | — | — | — | — | text “Leave a thought” (`#detail .circle-compose summary > span:nth-child(2)`) |
| Shared with your clubs | 100.5×12.6 | SF 9/12.6 w400 | `#697e64` | — | — | — | — | — | m 5/0/0 | text “Shared with your clubs” (`#detail .circle-compose summary small`) |

### Detail, manga (`detail=manga-0`), 390 (`ref-detail-manga-390.png`)

#### Detail sheet (manga)

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| sheet | 356×776.5 | SF 14/19.6 w400 | `#252625` (ink) | `#f6f5ef` | 9 | T:1px #fffdf4 R:1px #fffdf4 B:1px #fffdf4 L:1px #fffdf4 | #1c1c1c40 0px 25px 80px 0px | — | m 55.5312/17/12 | vars --art-base=#493431, --art-deep=#2c2321, --art-wash=#eceae5, --art-edge=#c8c2be, --art-ink=#ffffff, --detail-tint=#526e60, --scene-tone=#493431 (`#detail`) |
| close | 44×44 | SF 22/30.8 w400, align center | `#394631` | `#edeedfef` | 50% | T:1px #ffffff45 R:1px #ffffff45 B:1px #ffffff45 L:1px #ffffff45 | — | 1/6 | m 12/12/-56/0 | text “×” (`#detail .close`) |

#### D1 Hero (manga)

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| intro band | 354×213.6 | SF 14/19.6 w400 | `#252625` (ink) | repeating-linear-gradient(0deg, #00000000, #00000000 6px, #24292003 6px, #24292003 7px), linear-gradient(110deg, #eceae5, #faf9f2); clip:border-box, border-box | — | B:1px #d2d4c6 | — | 28/24/24 | gap 23 | vars --art-base=#493431, --art-deep=#2c2321, --art-wash=#eceae5, --art-edge=#c8c2be, --art-ink=#ffffff, --detail-tint=#526e60, --scene-tone=#493431 (`#detail .detail-intro`) |
| cover | 107.1×160.6 | SF 14/19.6 w400 | `#252625` (ink) | — | — | — | — | — | — | ::after "" 93.0938×6 repeating-linear-gradient(#c7c6bc 0px, #c7c6bc 1px, #faf9f2 1px, #faf9f2 2px) (`#detail .detail-object`) |
| cover image | 107.1×160.6 | SF 14/19.6 w400 | `#252625` (ink) | — | 2 5 5 2 | T:1px #ffffff45 R:1px #ffffff45 B:1px #ffffff45 L:1px #ffffff45 | #00000022 3px 0px 0px 0px inset, #f8f7ef 4px 2px 0px 0px, #bbb9ae 5px 2px 0px 0px, #f4f2e9 8px 4px 0px 0px, #c6c2b6 9px 4px 0px 0px, #25281d18 0px 16px 24px 0px | — | — | objectFit contain (`#detail .detail-object img`) |
| kind kicker | 39.1×10 | SF 8/12.8 w400, tr 1.7, uppercase | `#62695b` | — | — | — | — | — | — | text “Manga” (`#detail .detail-kicker`) |
| title | 175.9×63.8 | Georgia (serif) 29/31.9 w400, tr -1 | `#252625` (ink) | — | — | — | — | — | m 9/0/15 | text “Chainsaw Man” (`#detail .detail-heading h2`) |
| status mark | 52×14 | SF 10/14 w400 | `#626b5a` | — | — | — | — | — | gap 6 | ::before "" 5×5 r50% border 1px #626b5a; text “Reading” (`#detail .detail-collection`) |

#### D2 Story (manga)

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| eyebrow | 306×11.2 | SF 8/11.2 w600, tr 1.4, uppercase | `#68776f` | — | — | — | — | — | m 0/0/10 | vars --art-base=#493431, --art-deep=#2c2321, --art-wash=#eceae5, --art-edge=#c8c2be, --art-ink=#ffffff, --detail-tint=#526e60, --scene-tone=#493431; text “Series overview” (`#detail .detail-hook .detail-eyebrow`) |
| hook headline | 306×62.5 | Georgia (serif) 25/31.25 w400, tr -0.6 | `#252625` (ink) | — | — | — | — | — | m 0/0/9 | text “Small dreams. Monstrous consequences.” (`#detail .detail-hook h3`) |
| premise | 306×39.6 | SF 12/19.8 w400 | `#555f59` | — | — | — | — | — | m 0/0/6 | text “A broke young devil hunter gets a second chance at life—with a chainsaw for a he” (`#detail .detail-hook > p`) |
| About this story + | 306×44 | SF 10/14 w400 | `#59685f` | — | — | — | — | — | — | text “About this story” (`#detail .full-synopsis summary`) |

#### D5 Bookmark (manga)

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| folio card | 306×77.9 | SF 14/19.6 w400 | `#252625` (ink) | linear-gradient(110deg, #eceae5, #faf9f2) | 3 | T:1px #c8c2be B:1px #c8c2be L:2px #493431 | #ffffff80 0px 2px 0px 0px | 16/13 | m 0/0/16; gap 10 | vars --art-base=#493431, --art-deep=#2c2321, --art-wash=#eceae5, --art-edge=#c8c2be, --art-ink=#ffffff, --detail-tint=#526e60, --scene-tone=#493431 (`#detail .detail-progress`) |
| Your bookmark | 145×26.4 | Georgia (serif) 22/26.4 w400, tr -0.5 | `#5a695f` | — | — | — | — | — | — | text “Your bookmark” (`#detail .progress-context > span`) |
| caption | 145×13.5 | SF 9/13.5 w400 | `#6b776d` | — | — | — | — | — | m 4/0/0 | text “25 chapters in this preview” (`#detail .progress-context small`) |
| unit Ch. | 16.4×14 | SF 10/14 w400 | `#696c6b` (muted) | — | — | — | — | — | — | whiteSpace nowrap; text “Ch.” (`#detail .detail-progress .progress-unit`) |
| count | 25.9×29.4 | SF 21/29.4 w500 | `#252625` (ink) | — | — | — | — | — | — | whiteSpace nowrap; text “24” (`#detail .detail-progress .progress-value b`) |
| total | 23.7×13 | SF 11/15.4 w400 | `#696c6b` (muted) | — | — | — | — | — | — | opacity 0.8; whiteSpace nowrap; text “/ 25” (`#detail .detail-progress .progress-total`) |

#### D6 Chapters (manga)

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| heading | 69×23.8 | SF 17/23.8 w550, tr -0.4 | `#252625` (ink) | — | — | — | — | — | — | vars --art-base=#493431, --art-deep=#2c2321, --art-wash=#eceae5, --art-edge=#c8c2be, --art-ink=#ffffff, --detail-tint=#526e60, --scene-tone=#493431; text “Chapters” (`#detail .selected-edition .detail-section-head h4`) |
| Up next row | 324×74 | SF 14/19.6 w400 | `#252625` (ink) | `#eceae5` | 4 13 13 4 | T:1px #c8c2be R:1px #c8c2be B:1px #c8c2be L:1px #c8c2be | #292a2008 0px 2px 5px 0px | 7/9 | m 6/-9; gap normal 8 | grid 252px 44px (`#detail .unit-item.is-next`) |
| row number | 26×25.2 | Georgia (serif) 18/25.2 w350, tr -1, italic | `#79847b` | — | — | — | — | — | — | text “24” (`#detail .unit-item.is-finished summary > span:first-child`) |

#### D7 Seen the anime?

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| card | 306×256.3 | SF 14/19.6 w400 | `#252625` (ink) | linear-gradient(120deg, #eceae5, #f8f8f0) | 4 18 4 4 | T:1px #c8c2be R:1px #c8c2be B:1px #c8c2be L:1px #c8c2be | #e0e4d966 3px 3px 0px 0px | 21/18/15 | m 27/0/30 | vars --art-base=#493431, --art-deep=#2c2321, --art-wash=#eceae5, --art-edge=#c8c2be, --art-ink=#ffffff, --detail-tint=#526e60, --scene-tone=#493431 (`#detail .adaptation-guide`) |
| eyebrow | 268×11.2 | SF 8/11.2 w600, tr 1.4, uppercase | `#68776f` | — | — | — | — | — | — | text “From screen to page” (`#detail .adaptation-heading .detail-eyebrow`) |
| heading | 268×31 | Georgia (serif) 27/31.05 w400, tr -0.7 | `#252625` (ink) | — | — | — | — | — | m 8/0/18 | text “Seen the anime?” (`#detail .adaptation-heading h3`) |
| 映 symbol | 62×76 | serif 25/35 w400 | `#493431` | `#f7f8f0` | — | T:1px #c8c2be R:1px #c8c2be B:1px #c8c2be L:1px #c8c2be | — | — | — | grid 60px; text “映” (`#detail .adaptation-symbol`) |
| title | 105.7×19.5 | SF 15/19.5 w550 | `#252625` (ink) | — | — | — | — | — | — | text “Chainsaw Man” (`#detail .adaptation-title b`) |
| caption | 105.7×12.6 | SF 9/12.6 w400 | `#687668` | — | — | — | — | — | m 5/0/0 | text “Anime adaptation” (`#detail .adaptation-title small`) |
| site link | 105.7×44 | SF 11/15.4 w400 | `#252625` (ink) | — | — | — | — | — | gap 16 | text “Official anime site ↗” (`#detail .adaptation-title .source-detail-link`) |
| I've watched the anime | 268×52 | SF 12/16.8 w500 | `#252625` (ink) | — | — | — | — | — | — | text “I've watched the anime” (`#detail .watched-guide summary`) |

#### D10 Credits (manga)

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| heading | 306×23.8 | SF 17/23.8 w550, tr -0.4 | `#252625` (ink) | — | — | — | — | — | m 0/0/13 | vars --art-base=#493431, --art-deep=#2c2321, --art-wash=#eceae5, --art-edge=#c8c2be, --art-ink=#ffffff, --detail-tint=#526e60, --scene-tone=#493431; text “Behind the pages.” (`#detail .detail-credits h3`) |
| Read with the publisher | 306×66 | SF 12/16.8 w400 | `#252625` (ink) | — | — | T:1px #bfc7b7 B:1px #bfc7b7 | — | — | gap 15 |  (`#detail .publisher-link`) |
| publisher label | 139.2×34.8 | SF 12/16.8 w400 | `#252625` (ink) | — | — | — | — | — | — | text “Read with the publisher” (`#detail .publisher-link > span:first-child`) |
| publisher caption | 139.2×14 | SF 10/14 w400 | `#6f7769` | — | — | — | — | — | m 4/0/0 | text “Chapters & availability at VIZ” (`#detail .publisher-link small`) |

#### D11 Between us (manga)

| Part | Box | Type (family size/line-height weight, tracking) | Colour | Fill | Radius | Border | Shadow | Padding | Margin · gap | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| art heading | 316×154.5 | SF 14/19.6 w400 | `#252625` (ink) | linear-gradient(120deg, #dcdfcb, #efefdf) | 3 17 0 0 | — | — | — | m -23/-20/0; gap 19 | vars --art-base=#493431, --art-deep=#2c2321, --art-wash=#eceae5, --art-edge=#c8c2be, --art-ink=#ffffff, --detail-tint=#526e60, --scene-tone=#493431 (`#detail .circle-art-heading`) |
| card | 318×498.9 | SF 14/19.6 w400 | `#252625` (ink) | linear-gradient(120deg, #e7e9db, #f3f2e7) | 5 19 5 5 | T:1px #c4d0c5 R:1px #c4d0c5 B:1px #c4d0c5 L:1px #c4d0c5 | #d8dfce 2px 3px 0px 0px | 23/20/13 | m 28/-6/18 |  (`#detail .detail-club-room`) |

## 5. Width changes (320 and 430)

The manga Home is fluid in width and fixed in height. At 430 the three leaves widen, but the cover frames stay 138 pt tall, so the page height is unchanged (390: 1894 pt, 430: 1894 pt). Anime scene artwork height scales with width (89 pt at 320, 108 pt at 390), so anime pages grow.

### Width changes: 390 → 320 (Home, anime, busy)

Only properties that change are listed. They come from the prototype's `@media(max-width:360px)` rules.

| Component · part | Property | 390 | 320 |
|---|---|---|---|
| Medium switch · opening block | margin | 7 20 18 | 7 16 18 |
| Medium switch · control grid | grid | 169 169 | 138 138 |
| Medium switch · selected type box | height | 36 | 30 |
| Medium switch · selected word | size | 36 | 30 |
| Medium switch · selected word | track | -1.9 | -1.55 |
| Medium switch · selected word | lh | 36 | 30 |
| Medium switch · selected word | height | 36 | 30 |
| Medium switch · unselected word | size | 36 | 30 |
| Medium switch · unselected word | track | -1.9 | -1.55 |
| Medium switch · unselected word | lh | 36 | 30 |
| Medium switch · unselected word | height | 36 | 30 |
| Coming-up glance · card | pad | 10 12 | 10 |
| Coming-up glance · card | gap | 12 | 8 |
| Coming-up glance · caption | size | 10 | 9 |
| Coming-up glance · caption | lh | 14 | 12.6 |
| Coming-up glance · art strip | height | 38 | 34 |
| Coming-up glance · art thumb | height | 38 | 34 |
| Opening line · kicker | size | 9 | 8 |
| Opening line · kicker | lh | 12.6 | 11.2 |
| Opening line · headline | size | 14 | 13 |
| Opening line · headline | lh | 18.2 | 16.9 |
| Scene card · stage | margin | 0 20 | 0 15 |
| Scene card · stage | height | 693.4 | 654.4 |
| Scene card · stack | grid | 350 | 290 |
| Scene card · stack | height | 435.4 | 398.4 |
| Scene card · card | height | 206.7 | 188.2 |
| Scene card · artwork window | height | 107.7 | 89.2 |
| Scene card · artwork button | height | 107.7 | 89.2 |
| Scene card · artwork image | height | 107.7 | 89.2 |
| Scene card · material foot (caption) | pad | 0 10 0 14 | 0 10 0 11 |
| Scene card · material foot (caption) | gap | 8 | 7 |
| Scene card · progress control | pad | 0 0 0 12 | 0 0 0 8 |
| Scene card · count | size | 19 | 17 |
| Scene card · count | lh | 20.9 | 18.7 |
| Scene card · count | height | 20.9 | 18.7 |
| Scene card · footer row | pad | 0 12 0 14 | 0 10 0 11 |
| Scene card · availability fact | size | 10 | 9 |
| Scene card · availability fact | lh | 13 | 11.7 |
| Scene card · club link | size | 10 | 9 |
| Scene card · club link | lh | 12 | 10.8 |
| Also watching · grid | gap | 16 | 14 12 |
| Also watching · grid | grid | 167 167 | 139 139 |
| Also watching · grid | height | 200 | 198 |
| Also watching · tile | gap | normal 9 | normal 7 |
| Also watching · tile | grid | 44 114 | 44 88 |
| Also watching · title | size | 12 | 11 |
| Also watching · title | lh | 15.6 | 14.3 |
| Also watching · title button | size | 12 | 11 |
| Also watching · title button | lh | 15 | 13.75 |
| Also watching · unit "Ep." | size | 10 | 9 |
| Also watching · unit "Ep." | lh | 14 | 12.6 |
| Also watching · count | size | 14 | 13 |
| Also watching · count | lh | 19.6 | 18.2 |
| Calendar · paper feed | pad | 0 22 20 | 0 18 20 |
| Calendar · paper feed | height | 1028.8 | 1012.8 |
| Calendar · section | height | 583.4 | 581.2 |
| Calendar · heading row | height | 26.4 | 24.2 |
| Calendar · heading "Coming up." | size | 24 | 22 |
| Calendar · heading "Coming up." | lh | 26.4 | 24.2 |
| Calendar · heading "Coming up." | height | 26.4 | 24.2 |
| Calendar · summary | size | 10 | 9 |
| Calendar · summary | lh | 14 | 12.6 |
| Club room · room | pad | 20 16 12 | 20 12 12 |
| Club room · room | height | 393.4 | 379.6 |
| Club room · masthead | gap | 10 | 8 |
| Club room · masthead | height | 36 | 32.8 |
| Club room · seal | height | 42.7 | 35.6 |
| Club room · club name | size | 22 | 19 |
| Club room · club name | lh | 22 | 19 |
| Club room · club name | height | 22 | 19 |
| Club room · member avatar | grid | 18 | 16 |
| Club room · member avatar | height | 22 | 20 |
| Club room · note card | pad | 15 | 13 |
| Club room · note card | height | 208.2 | 197.6 |
| Club room · entry | gap | 13 | 11 |
| Club room · entry | height | 116.2 | 109.6 |
| Club room · title art | height | 90 | 72 |
| Club room · person name | size | 11 | 10 |
| Club room · person name | lh | 15.4 | 14 |
| Club room · time ago | size | 10 | 9 |
| Club room · time ago | lh | 14 | 12.6 |
| Club room · time ago | margin | 0 0 0 152.094 | 0 0 0 121.156 |
| Club room · quote | size | 18 | 16 |
| Club room · quote | lh | 23.4 | 20.8 |
| Club room · quote | height | 46.8 | 41.6 |

### Width changes: 390 → 320 (Home, manga, busy)

| Component · part | Property | 390 | 320 |
|---|---|---|---|
| Opening line · headline (manga) | size | 14 | 13 |
| Opening line · headline (manga) | lh | 18.2 | 16.9 |
| Medium switch · selected word (manga) | size | 36 | 30 |
| Medium switch · selected word (manga) | track | -1.9 | -1.55 |
| Medium switch · selected word (manga) | lh | 36 | 30 |
| Medium switch · selected word (manga) | height | 36 | 30 |
| Medium switch · unselected word (anime) | size | 36 | 30 |
| Medium switch · unselected word (anime) | track | -1.9 | -1.55 |
| Medium switch · unselected word (anime) | lh | 36 | 30 |
| Medium switch · unselected word (anime) | height | 36 | 30 |
| Manga leaf · stage | margin | 0 22 | 0 17 |
| Manga leaf · stage | height | 506 | 462 |
| Manga leaf · grid | gap | 26 14 | 24 11 |
| Manga leaf · grid | grid | 106 106 106 | 88 88 88 |
| Manga leaf · grid | height | 506 | 462 |
| Manga leaf · leaf | height | 240 | 219 |
| Manga leaf · story button | gap | 8 | 6 |
| Manga leaf · story button | grid | 106 | 88 |
| Manga leaf · story button | height | 190 | 169 |
| Manga leaf · cover frame | height | 138 | 119 |
| Manga leaf · cover image | height | 138 | 119 |
| Manga leaf · title | size | 11 | 10 |
| Manga leaf · title | lh | 12.65 | 11.5 |
| Club room · room (manga) | pad | 20 16 12 | 20 12 12 |
| Club room · room (manga) | height | 393.4 | 379.6 |

### Width changes: 390 → 430 (Home, anime, busy)

Only properties that change are listed. Most components are fluid, so heights grow with width.

| Component · part | Property | 390 | 430 |
|---|---|---|---|
| Medium switch · control grid | grid | 169 169 | 189 189 |
| Scene card · stage | height | 693.4 | 718 |
| Scene card · stack | grid | 350 | 390 |
| Scene card · stack | height | 435.4 | 460 |
| Scene card · card | height | 206.7 | 219 |
| Scene card · artwork window | height | 107.7 | 120 |
| Scene card · artwork button | height | 107.7 | 120 |
| Scene card · artwork image | height | 107.7 | 120 |
| Also watching · grid | grid | 167 167 | 187 187 |
| Also watching · tile | grid | 44 114 | 44 134 |
| Club room · time ago | margin | 0 0 0 152.094 | 0 0 0 192.094 |


## 6. Interaction behaviour carried by the prototype

| Interaction | Behaviour (prototype) |
|---|---|
| Scene card / cover tap | Opens the detail sheet. The artwork button, the title button (`.title-open`) and the +1 key (`.step`) are separate targets; every target is ≥ 44 × 44. |
| +1 key | Increments progress. The key settles 160 ms, the count rolls, the trace widens 280 ms, then `confirm`/`restore` (§3.1) and a toast with Undo. A capped key becomes disabled and the toast reads "Caught up.". |
| Undo (toast) | Restores the previous count and saved state; toast "Undone.". |
| Season tab ("SEASON 2") | Separate 44 pt target on the artwork; opens the detail at the season overview. Inspecting a season never changes progress. |
| Coming-up glance | Scrolls the phone (smooth; instant under Reduce Motion) to the calendar, header height + 12 pt above it, and focuses the calendar. |
| Calendar day | Toggles open and closed (`aria-expanded`). The first day starts open. `Next N dates` button appears past four groups (full calendar). |
| Club spoiler | Toggles "Mina’s thought on the ending" ↔ "Hide spoiler" and reveals the note (180 ms fade). |
| Medium switch | Tap a word, or drag horizontally > 30 pt across the control. Vertical drags > 12 pt cancel. Switching scrolls to top, cancels running motions and replays the entrances once per medium. |
| Page swipe Home ↔ Taste | Horizontal swipe > 85 pt (and > 2× vertical) on non-interactive surface; the header link toggles too ("‹ Taste" / "Home ›"). |
| Detail sheet | Opens as a dialog over the dimmed Home: 17 pt side insets, top margin 55.5, bottom 12. Radius 24 (anime) / 9 (manga). Sticky round close button (44 × 44) at top 12. |

## 7. Copy (EN as in the prototype, DE draft)

German drafts follow the existing Kuro tone (du-form, short, no exclamation marks). They were checked against the strings already in `KuroLocale.text(` calls: "Demnächst", "Start", "Geschmack", "Rückgängig", "Erneut versuchen", "Vormerken" and "Auf dem neuesten Stand" are reused as they are. Other existing translations win over these drafts if a lane finds a conflict. The lanes may refine wording; the EN strings are the prototype's exact text. `N`, `{title}` and `{date}` are placeholders.

### 7.1 Product copy (ships)

| Where | EN (prototype) | DE (draft) |
|---|---|---|
| Header | KURO | KURO |
| Header page name | Home · Taste | Start · Geschmack |
| Header neighbour link | ‹ Taste · Home › | ‹ Geschmack · Start › |
| Medium switch | ANIME · MANGA | ANIME · MANGA |
| Glance title | Coming up | Demnächst |
| Glance caption | Today · N releases · Dates still to come | Heute · N Veröffentlichungen · Termine folgen noch |
| Glance count label | this week · 6 weeks · pending | diese Woche · 6 Wochen · offen |
| Opening kicker | NOW WATCHING · NOW READING · YOUR COLLECTION · FOR YOUR TASTE | DU SCHAUST GERADE · DU LIEST GERADE · DEINE SAMMLUNG · FÜR DEINEN GESCHMACK |
| Opening headline | N new episode(s) · N new chapter(s) · Keep watching. · Keep reading. · Begin here. | N neue Folge(n) · N neue(s) Kapitel · Weiterschauen. · Weiterlesen. · Fang hier an. |
| Opening headline (Taste) | Another world. · Another chapter. | Eine andere Welt. · Ein anderes Kapitel. |
| Quiet line (caught up) | Nothing new today. Stay at your own pace. | Heute nichts Neues. Bleib in deinem Tempo. |
| Season tab | SEASON N · stamp "S N" | STAFFEL N · Stempel "S N" |
| Progress unit | Ep. N / M · Ch. N | Folge N / M · Kap. N |
| Scene footer fact | New episode available | Neue Folge verfügbar |
| Scene footer club | {name} + {name} › | {Name} + {Name} › |
| Also watching | Also watching · N titles | Schaust du auch · N Titel |
| Calendar heading | Coming up. · N releases · 7 days / 6 weeks · From your list | Demnächst. · N Veröffentlichungen · 7 Tage / 6 Wochen · Aus deiner Liste |
| Calendar day | Today · Tomorrow · Fri 9 Oct · N release(s) · chip "2 OCT" | Heute · Morgen · Fr. 9. Okt. · N Veröffentlichung(en) · Chip "2 OKT" |
| Calendar row (anime) | S2 · Episode 9 · 16:00 · Time TBA | S2 · Folge 9 · 16:00 · Uhrzeit offen |
| Calendar row (manga) | Chapter 26 · Volume 11 · Chapter release · English edition | Kapitel 26 · Band 11 · Neues Kapitel · Englische Ausgabe |
| Dates to come | Dates to come · N announcements · Date TBA · No confirmed dates yet. | Termine folgen · N Ankündigungen · Datum offen · Noch keine bestätigten Termine. |
| Club room | YOUR PRIVATE CLUB · Finished {title} › · Hide spoiler · {name} started · Shared stories. Your people. · N updates | DEIN PRIVATER CLUB · Hat {Titel} beendet › · Spoiler ausblenden · {Name} hat angefangen · Geteilte Geschichten. Deine Leute. · N Neuigkeiten |
| Club room spoiler | {name}’s thought on the ending | {Name}s Gedanke zum Ende |
| Footer | Your pace. Your place. · KURO | Dein Tempo. Dein Ort. · KURO |
| New-account Home | ＋ · Your stories belong here. · Import your list to bring your place with you. · Explore Taste ← | ＋ · Hier gehören deine Geschichten hin. · Importiere deine Liste und nimm deinen Stand mit. · Geschmack entdecken ← |
| Taste headings | Your next story. · Turn to something new. · A first favourite. | Deine nächste Geschichte. · Zeit für etwas Neues. · Ein erster Favorit. |
| Taste card | FILM · ROMANCE (kind kicker) · Plan to watch · Plan to read · Planned | FILM · ROMANCE · Vormerken · Vormerken · Vorgemerkt (the app already uses "Vormerken" for "Plan to watch") |
| Toasts | Progress saved. · Caught up. · Added to your list. · Removed from your list. · Undone. · Undo | Fortschritt gespeichert. · Auf dem neuesten Stand. · Zu deiner Liste hinzugefügt. · Von deiner Liste entfernt. · Rückgängig gemacht. · Rückgängig |
| Toast failure | Not saved. Your progress is unchanged. · Not saved. Your list is unchanged. | Nicht gespeichert. Dein Fortschritt ist unverändert. · Nicht gespeichert. Deine Liste ist unverändert. |
| Detail hero | Anime · Manga (kicker) · Watching · Reading · Not in your list | Anime · Manga · Schaust du · Liest du · Nicht in deiner Liste |
| Detail story | Season N (eyebrow) · Series overview · About this season + · About this story + | Staffel N · Serienüberblick · Über diese Staffel + · Über diese Geschichte + |
| Detail club presence | N people in your clubs ↓ | N Personen aus deinen Clubs ↓ |
| Detail seasons | Seasons · N seasons · Current | Staffeln · N Staffeln · Aktuell |
| Detail progress | Season N progress · Ep. N / M · Your bookmark · Ch. N / M · Caught up · Ongoing · total unknown | Fortschritt Staffel N · Folge N / M · Dein Lesezeichen · Kap. N / M · Auf dem neuesten Stand · Laufend · Gesamtzahl unbekannt |
| Detail units | Episodes · Chapters · UP NEXT · Episode N · Chapter N · Completed · Tap for details · More episodes ↓ · More chapters ↓ · Fewer episodes ↑ | Folgen · Kapitel · ALS NÄCHSTES · Folge N · Kapitel N · Gesehen / Gelesen · Für Details tippen · Mehr Folgen ↓ · Mehr Kapitel ↓ · Weniger Folgen ↑ |
| Detail original story (anime) | The original story · 原作 · Explore the manga → · Season N → manga · Where this season meets the manga + · Starts at · Ends at · Read next | Die Vorlage · 原作 · Zum Manga → · Staffel N → Manga · Wo diese Staffel im Manga steht + · Beginnt bei · Endet bei · Weiterlesen ab |
| Detail Seen the anime? (manga) | From screen to page · Seen the anime? · 映 · Anime adaptation · Official anime site ↗ · I've watched the anime + · Which season did you finish? · Choose a season · Choose a finished season to find your place on the page. · This guide never marks manga chapters as read. | Vom Bildschirm aufs Papier · Den Anime gesehen? · 映 · Anime-Adaption · Offizielle Anime-Seite ↗ · Ich habe den Anime gesehen + · Welche Staffel hast du beendet? · Staffel wählen · Wähle eine beendete Staffel, um deine Stelle im Manga zu finden. · Diese Hilfe markiert keine Kapitel als gelesen. |
| Detail sound | The sound of it. · Opening · Ending · OP · ED · Listen ↗ | So klingt es. · Opening · Ending · OP · ED · Anhören ↗ |
| Detail characters | The characters. · Tap to meet | Die Figuren. · Zum Kennenlernen tippen |
| Detail credits | Behind the frames. · Behind the pages. · Original work · Director · Animation · Story & art · English publisher · Read with the publisher ↗ | Hinter den Bildern. · Hinter den Seiten. · Vorlage · Regie · Animation · Story & Zeichnungen · Englischer Verlag · Beim Verlag lesen ↗ |
| Detail Between us | Your clubs · private · Between us. · Who's watching ⌄ · Who's reading ⌄ · N people · Spoiler · Season N · Reveal · Leave a thought · Shared with your clubs · Your comment · Contains spoilers · Spoiler scope: … · Edit your thought · Write a comment of 1–500 characters. · Could not save. Your draft is still here—try again. | Deine Clubs · privat · Unter uns. · Wer schaut mit ⌄ · Wer liest mit ⌄ · N Personen · Spoiler · Staffel N · Anzeigen · Gedanken teilen · Mit deinen Clubs geteilt · Dein Kommentar · Enthält Spoiler · Spoiler-Bereich: … · Gedanken bearbeiten · Schreib einen Kommentar mit 1–500 Zeichen. · Nicht gespeichert. Dein Entwurf ist noch da – versuch es noch einmal. |
| Accessibility | Go to Taste · Go to Home · Close details · Dismiss notification · Upcoming from your list · Currently watching · Currently reading | Zu Geschmack · Zum Start · Details schließen · Hinweis schließen · Demnächst aus deiner Liste · Du schaust gerade · Du liest gerade |

### 7.2 Sample data (prototype only: never ship, never hard-code)

These strings appear in the captures but are fixtures. The native app shows real data in their place, or hides the element (no fabricated data):
- **People and clubs:** "Sunday Club", "Frame by Frame", "Ink Room", "Mina", "Jules", "Noah", "Ari", "Mina + Jules", "2h ago", the quote "“Just one more. Famous last words.”", "Sample spoiler: that quiet final scene changes the opening.", the member notes and spoiler notes in "Between us.", and the roster statuses ("Watching Season 2", "Reading Ch. 24", …).
- **Editorial hooks and synopses** (`instrument-detail-data.js`): "Old friendships. A city on the edge.", "Small dreams. Monstrous consequences.", the expectation lines ("Past and present · Fractured bonds · Rising tension"), the Taste premises ("Two strangers wake up in each other’s lives.", …) and kind kickers. Hooks come from `detail_copy` only when it has rows (spec §4); premises come from real catalogue data.
- **Calendar and counts:** every date, time, count, "Hidden Inventory / Shibuya Incident", song titles and artists, the character names, and the credits (Gege Akutami, MAPPA, VIZ Media …).
- **Preview wording:**
  - "9 episodes in this preview"
  - "Preview" (section note)
  - "Episode synopsis unavailable in this preview."
  - "Unverified"
  - "Chapter match unverified"
  - "Find on Spotify · track links not yet matched"
  - "Chapters & availability at VIZ"
  - "Local preview only · nothing is posted."
  - "Save preview comment"
  - "Saved in this preview only."
  - "Design preview · sample progress, groupings & club activity."
  - "Editorial descriptors are illustrative. No live tracking."
  - "No verified anime link in this preview."
  - The real app states the real total, or omits the line. The rulebook also forbids internal words such as "verified".
- **Prototype studio controls** (outside the phone): "Preview account", "Fail next change", "Reset preview ↺".

## 8. Differences the lanes must know (prototype vs spec/plan)

The prototype wins on visuals (spec §2). The items below are where the written spec or plan says something the prototype does not do, or where the prototype carries something the spec does not mention. Each lane decides with this list in hand; Task 10's fidelity review checks against the captures.

1. **Serif headings.** The spec (§3) lists "Coming up." and "The sound of it." as serif. In the prototype both are **SF sans** ("Coming up." 24/26.4 w550 tr −0.85; "The sound of it." 17/23.8 w550 tr −0.4). The serif (Georgia) is used only for the elements listed in §2. `kuroEditorial` should cover exactly those: the club name, club quote, "Between us.", manga detail title and hook, "Your bookmark", manga row numbers (italic) and "Seen the anime?".
2. **Caught-up opening line.** In the prototype the right-aligned headline reads "Keep watching." / "Keep reading.". "Nothing new today. Stay at your own pace." is a separate quiet line (`.quiet`) at the top of the feed. Plan Task 4's `HomeOpeningLine.headline` folds it into the headline. Either keep the plan's API and render the quiet line separately, or record the change.
3. **New-account Home has no Import button in the prototype.** It shows ＋, "Your stories belong here.", "Import your list to bring your place with you." and only "Explore Taste ←". The opening reads "YOUR COLLECTION" / "Begin here.", and the coming-up glance is hidden. Spec §5.3 adds "Import" and "A first favourite." (an owner-approved addition).
4. **Also watching keys use each title's artwork material**, not one fixed dark key. The manga leaf key is a solid `#2b342e`. The `#444a47→#2c322f` gradient is not drawn on the measured poster screens (§2).
5. **Detail sheet paper.**
   - The anime sheet background is `--paper #f5f5f4` with a white 1 px border, radius 24.
   - The manga sheet is `#f6f5ef`, border `#fffdf4`, radius 9.
   - The artwork `wash` is applied to the progress card and the Up next row, the `edge` to their borders, and the `base→deep` gradient to the hero band and the Up next key.
   - Spec §3 says "The detail sheet paper uses `wash`". The measured prototype keeps the paper neutral and uses `wash` on the cards. The lanes follow the prototype unless the owner rules otherwise.
6. **Detail sheet geometry.**
   - The prototype sheet is a floating dialog: 17 pt side insets, 55.5 pt top margin, shadow `0 25px 80px #1c1c1c40`.
   - The native detail is a full sheet (spec §5.2: "behave like today's sheet"), so the inset and dimmed Home behind it are expected differences, not defects.
7. **`count` keyframe.** It is defined but not used by the prototype JS. The live count roll is the 220 ms / 280 ms WAAPI motion in §3.2. Port `.kuroCountRoll` from §3.2, using the `count` keyframe only as its static shape.
8. **Easings.** `restore` uses plain `ease`. Entrances and count rolls use `cubic-bezier(.2,.75,.25,1)`, and the trace uses `cubic-bezier(.22,.8,.24,1)`. Only contact and `confirm` use `--ease` (`.2,.8,.25,1`). The plan's single global ease is a simplification.
9. **Medium-switch fill.** The selected word is SF 36/36 w850, tracking −1.9 (at 390), uppercase. Its fill is the current lead title's artwork (`background-clip: text`) under `linear-gradient(#15221c15, #15221c38)`, with fallback colour `#253a2a`, plus a 28 × 2 underline `#203027`. The unselected word is solid `#6e786f`. The spec's "roughly −3.8 tracking" is the studio heading, not the switch.
10. **Taste in a new account** keeps the same story cards as the busy account. Only the heading changes to "A first favourite.", and the opening stays "FOR YOUR TASTE / Another world.". The anime Taste uses one landscape card, then a portrait card. Manga Taste uses a two-column portrait grid.
11. **Detail "Seasons" tiles** in the prototype are numbered tiles ("1", "2" with "Current"), not artwork, for this fixture. The spec allows artwork tiles where artwork exists.
12. **Header controls.** The prototype header has only KURO, the page name and "‹ Taste". It has no Search or Profile glyph and no page dots. The native header keeps Search, Profile and smaller dots (spec §3a), so these are expected differences.
13. **Prototype-only density content** (the "Where this season meets the manga" coverage table with "Unverified" values, and "Find on Spotify · track links not yet matched") must stay hidden until real data exists (spec §5.2 empty rules).

## 9. Re-running the measurement

The capture and measurement scripts were run through the Playwright MCP against the local server. The method is in §1. To re-measure a single value:
1. Open the same URL with `embed=1` at the target width.
2. Read `getComputedStyle` on the selector given in the table's Notes column.
