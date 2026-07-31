# Creative Ideation Deck — 2026-07-31 (Kimi K3 Swarm)

Inputs: Phase 0 full-system check (`2026-07-31-phase0-full-system-check.md`). Every concept states: **user promise · why it fits Kuro · why it might fail · overnight feasibility (H/M/L) · beauty bar · backend dependency**. Red Team verdicts appended after the murder pass. Winners picked by criteria in §0, locked by ADRs.

## 0. Winner-selection criteria (defined before the fight)

1. **Shippable tonight** — code + migration + flag can land and build green by morning.
2. **Honest** — no fake intelligence, no engagement theater; the mechanism is explainable in one sentence.
3. **Kuro-native** — editorial, monochrome, quiet, physical; would look wrong inside a streaming app.
4. **Compounding** — uses or strengthens half-built systems (taste_signal_events, mirror pipeline, clubs), not a parallel universe.
5. **Reversible** — flag-gated where ranking or navigation changes; rollback is a config flip.
6. **Trust-neutral or better** — nothing that leaks, nags, or sells the user.

---

## A. Learning taste (cold start → living taste)

### A1 — "The Deck": a one-title ritual
Full-bleed single title, three deliberate gestures: **right = CALLS TO ME**, **left = NOT FOR ME**, **up = I KNOW THIS**. Long-press flips to synopsis. Sessions of 12; never repeats a title; ends with a serif summary ("Kuro is listening.").
- **Promise:** teach Kuro your taste in ninety seconds, honestly, one beautiful title at a time.
- **Fit:** turns taste collection into the most cinematic surface in the app; gestures map to signed signals that feed the *existing* `taste_signal_events` pipeline; mirrored-art-first dealing makes the image strategy product-visible.
- **Fail modes:** reads as Tinder-with-anime if the chrome is loud; gesture fatigue if dealt junk; "I KNOW THIS" without sentiment is ambiguous signal.
- **Feasibility: H.** One RPC for batches, one for recording, one view file, ContentView slot.
- **Beauty bar:** highest in the deck — grain hero recipe, serif masthead, physical spring.
- **Backend:** 2 new RPCs + event types (`deck_love/known/skip`) on existing table.

### A2 — "Contrast Rounds": pick one of twelve
Each round shows a curated 12-title grid with one editorial question ("A film for a rainy Sunday?"). Pick one; the rest count as weak rejects. Next round contrasts a different axis (cozy↔brutal, classic↔current).
- **Promise:** five taps and Kuro knows your contrast profile.
- **Fit:** comparative choice yields more information per tap; grids are cheap to render; very editorial (questions as copy).
- **Fail modes:** implicit rejection of 11 titles is noisy (user may love several); grid of remote images looks cheap before mirror coverage improves; feels like a BuzzFeed quiz if copy slips.
- **Feasibility: M.** Same RPCs as A1 but batch semantics per round; signal attribution murkier.
- **Beauty bar:** medium — grid layouts are commoditized.
- **Backend:** same as A1 + round curation logic.

### A3 — "The Interview": three questions, no catalog
Onboarding asks three editorial questions ("Do you want to feel good, or feel everything?") and maps answers to mood axes + seeded starter rails. No title judgments at all.
- **Promise:** Kuro understands you before you lift a finger.
- **Fit:** zero image dependency; copy-driven, which is Kuro's voice.
- **Fail modes:** mood answers are aspiration, not taste — low-fidelity signal; can't improve with use; "ML cosplay" risk if we pretend it's a profile.
- **Feasibility: H** (it's just onboarding copy + mapping table) but **low value density**.
- **Beauty bar:** high if copy is perfect.
- **Backend:** static mapping; optional signal seed.

### A4 — "The Canon Draft": pick your three
A wall of 24 canon titles (universally acclaimed, mirrored art guaranteed); new users draft exactly three favorites. Seeds profile with high-confidence anchors.
- **Promise:** three taps, real anchors, no quiz feel.
- **Fit:** canon = editorial identity made interactive; anchors are the highest-quality cold-start signal per tap.
- **Fail modes:** canon skews mainstream (shonen-heavy profile for everyone); users who know none of the 24 bounce; no negative signal.
- **Feasibility: H.** Static canon list + A1's record RPC.
- **Beauty bar:** high — a poster wall is a strong first screen.
- **Backend:** same as A1.

**Swarm lean:** A1 as the living mechanism (durable, replayable, feeds everything), with A4's draft folded into onboarding as the cold-start seed (Deck pre-dealt with canon-adjacent titles for empty profiles). A2's comparative insight noted for v2; A3 rejected as signal-poor.

---

## B. Taste representation

### B1 — Contract-native weighted vector (Sprint 02 as designed)
`recompute_user_taste_profile()`: aggregate `taste_signal_events` × `anime_tags.rank`/`manga_tags.rank` + genres, import discount ×0.25, confidence tiers (0.05→0.20), title cap 8%, franchise cap 15%. Stored in the existing `user_taste_profiles` table as inspectable jsonb.
- **Promise:** your taste, as weights a human can read.
- **Fit:** every input already in DB; contract numbers already frozen; queue already enqueued.
- **Fail modes:** tag noise (AniList tags are messy); drift if events lack retention/decay.
- **Feasibility: H.** One SQL function + drain cron.
- **Beauty bar:** n/a (backend), but enables a "Your leanings" sheet.
- **Backend:** this *is* the backend.

### B2 — "Taste Compass": 4–6 editorial axes
Collapse the vector onto named axes (Quiet↔Loud, Heart↔Spectacle, Classic↔Current, Comfort↔Challenge) for display and ranking tilt.
- **Promise:** see the shape of your taste at a glance.
- **Fit:** explainable, brandable, great empty-profile defaults.
- **Fail modes:** axis taxonomy is editorial guesswork; two mapping layers (tags→axes→ranking) doubles tuning debt; pretty-but-coarse.
- **Feasibility: M.** Needs taxonomy + mapping + UI.
- **Beauty bar:** high as a Profile graphic.
- **Backend:** derived from B1.

### B3 — "Neighborhoods": cluster membership
Cluster catalog by tag co-occurrence into named neighborhoods ("Melancholy Alley", "Grand Adventure Square"); user = distribution over neighborhoods.
- **Promise:** "You live between X and Y" — taste as a map.
- **Fail modes:** clustering + naming is a research project; unstable as catalog grows; naming 30 clusters well is weeks of editorial work.
- **Feasibility: L.**
- **Beauty bar:** highest concept ceiling in the deck.
- **Backend:** clustering infra that doesn't exist.

### B4 — Avoidance map as first-class citizen
Negative signals stored and *used*: skipped/dropped/verdict_bad tags become explicit penalties in ranking, separate from positive fit.
- **Promise:** Kuro never again pushes what you hate.
- **Fit:** honest, cheap, and the contract already weights negatives; NEW TO YOU currently only excludes, never avoids.
- **Fail modes:** sparse negatives → over-penalizing whole genres from one skip (needs per-tag floors).
- **Feasibility: H** on top of B1.
- **Backend:** same function.

**Swarm lean:** B1 + B4 ship tonight (they're one function). B2/B3 are presentation layers — noted as roadmap once the vector has data.

---

## C. Lists & surfaces IA

### C1 — Keep the 5-pager, sharpen page jobs
Deck = learn · Discover = editorial · Browse = lens · Collection = mine · Clubs = us. Each surface keeps its current mechanics; anime/manga stay per-surface toggles.
- **Fit:** zero navigation chaos; pager is ownable chrome (Design Director principle 7).
- **Fail modes:** none structural.
- **Feasibility: H.**

### C2 — Merge Discover + Browse into one "Catalog" page with mode switch
- **Fail modes:** violates "don't chaos-rearrange without strong reason"; Discover/Browse have different mental models (gift vs lens); burns the pager's best asset.
- **Feasibility: M. Rejected on principle.**

### C3 — App-level medium preference ("I'm primarily a manga reader")
One profile setting that tilts every surface's default type toggle.
- **Promise:** the app stops asking anime-or-manga fifty times a day.
- **Fit:** manga readers are second-class today; cheap to thread through.
- **Fail modes:** yet another setting; toggles already persist per surface.
- **Feasibility: M.** Roadmap, not tonight.

### C4 — Collection "Tonight" shelf
Top of Collection: "Continue tonight" — in-progress items ranked by pace + next-episode availability.
- **Promise:** your library answers "what now?" in one glance.
- **Fail modes:** needs availability data (parked) to be great; pace math on sparse progress is noisy.
- **Feasibility: M.** Strong roadmap candidate; depends on E/G infra.

**Swarm lean:** C1 now; C4 is the first post-overnight surface once taste + availability data thicken.

---

## D. Leftmost page destiny

### D1 — The Deck at index 0; Concierge archived, not gutted
Pager becomes `[Deck, Discover, Browse, Collection, Clubs]`, default still Discover. Concierge code preserved; entry points move to a Profile row + `kuro://concierge` deep link (both already half-exist). Header un-hides on page 0 (Deck wants search/profile access).
- **Promise:** the left edge becomes the app's soul — a place you visit to be known, not a chat box you must feed.
- **Fit:** chat is a tool; taste is an identity. Concierge usage is import-flavored anyway (already reachable from Profile). Solves A and D with one surface.
- **Fail modes:** existing concierge users lose muscle memory (mitigate: deep link + Profile row + one-time toast); Deck with poor candidates feels empty.
- **Feasibility: H.**
- **Beauty bar:** the highest-visibility design moment of the night.
- **Backend:** A1's RPCs.

### D2 — "Today": a morning page
Left edge becomes a daily journal: airing today from your list, club pulse, continue-where-you-left, one editorial pick.
- **Promise:** open Kuro every morning for sixty seconds.
- **Fail modes:** overlaps Discover's AIRING TODAY rail; empty for new users (worst possible cold start); dashboard-shaped, not editorial-shaped.
- **Feasibility: M.** Beautiful v2 candidate once clubs/taste thicken. **Deferred, not killed.**

### D3 — Keep Concierge left, demote chat to a sheet on Discover
- **Fail modes:** half-measure — keeps the weakest surface at the prime slot while adding a second entry point. **Rejected.**

### D4 — Clubs at the left edge
- **Fail modes:** social-first reframes the product away from curation; empty-club users get a dead front door. **Rejected.**

**Swarm lean:** D1 decisively; D2 written into the roadmap as the Deck's eventual sibling.

---

## E. Images / presence

### E1 — Convergence patch (ops truth)
Select remote-only rows (`cover NOT LIKE '%/storage/v1/%'`), keep popularity order, persist a cursor for the tail, and — critically — **stop the un-mirroring**: bulk imports must not overwrite already-mirrored columns. Nightly coverage metrics into a report.
- **Promise:** every week the app feels more ours.
- **Fit:** fixes the two root causes found in Phase 0; no product surface changes.
- **Feasibility: H.** Edge-function patch + import patch + cron SQL.

### E2 — Presence tiers
Mirror by visibility tier, not global popularity: tier 1 = current home rails + user lists + club rails + recently opened details; tier 2 = top-N popularity; tier 3 = tail by cursor.
- **Fit:** effort lands exactly where eyes are; makes "deck deals mirrored-first" trivially satisfiable.
- **Fail modes:** tier computation needs a membership query — an hour of SQL, not days.
- **Feasibility: H/M.**

### E3 — Designed absence
Unmirrored/failed art renders as a duotone monogram poster (title initials in serif, grain, title-color wash from `cover_image_color`) — absence becomes brand.
- **Promise:** even broken images look intentional.
- **Fit:** the placeholder system is currently per-call-site chaos; this unifies it.
- **Fail modes:** monogram posters everywhere could read as broken at scale; must remain the exception.
- **Feasibility: M.** One component + call-site sweep. **Deferred to polish pass; ship the unified placeholder only.**

### E4 — Mirror-on-view (event-driven)
Opening a detail page with remote art enqueues a priority mirror (fire-and-forget RPC into `image_mirror_state` queue).
- **Promise:** the app heals itself where you look.
- **Fit:** convergence driven by real attention; tiny payload.
- **Feasibility: H.** One RPC + one call site.

**Swarm lean:** E1 + E4 tonight (root causes + attention loop), E2's tier-1 query folded into E1's selection, E3 deferred.

---

## F. Clubs that feel alive

### F1 — The trust patch pack
Fix the reactions contract (align RPC allowlist with client keys), close the social-RPC privacy hole (respect sharing levels), add `kuro://join/<code>` deep link + share text URL + prefill, seed the five dark flags deliberately, fix the "You were removed" copy for non-members.
- **Promise:** invites that work, reactions that work, privacy that means it.
- **Fit:** repairs a live trust regression; makes built-but-dark features (realtime, pace, badges) actually run.
- **Feasibility: H.** SQL + small iOS patches.

### F2 — Duo mode
Make 2-person clubs first-class: full status visibility between the two (both consented by joining), explicit "Pair" framing in UI.
- **Promise:** the smallest club is the strongest one.
- **Fail modes:** changes the k-anonymity privacy math — needs consent copy and bundle changes; easy to get subtly wrong at 2am.
- **Feasibility: M.** **Roadmap; tonight we surface honest "3+ members unlocks activity" copy instead.**

### F3 — Club Night ritual
Weekly shared pick: club nominates via poll, watches by Sunday, pace-sync banner counts down.
- **Promise:** a reason to come back together every week.
- **Fail modes:** needs polls+pace live first (F1 unblocks); ritual features die without notifications (no push infra tonight).
- **Feasibility: M/L.** Roadmap, gated on F1.

### F4 — Full revamp to activity journal
- **Fail modes:** tonight is for making clubs trustworthy, not redesigning them. **Rejected for now.**

**Swarm lean:** F1 ships; F2/F3 written as the post-patch roadmap in the ADR.

---

## G. Monetization without ads

### G1 — Affiliate decoration on existing WATCH/READ links + click ledger
`outbound_link_events` table (RLS, JWT-derived user, link type/provider/media), one RPC, instrumentation on the buttons users already tap; affiliate tags applied at render to `external_links.url` per provider registry. Manga READ ON (BookWalker/Kobo/Kindle) is the highest-intent surface.
- **Promise:** the app earns when it genuinely helps you find where to watch/read.
- **Fit:** monetizes existing trust, not attention; zero new UI.
- **Fail modes:** legal/disclosure per affiliate program; decoration without measurement is blind (hence ledger first); revenue near-zero until volume.
- **Feasibility: H for scaffold** (ledger + RPC + instrumentation, tags OFF behind flag); **compliance notes required.**

### G2 — Kuro Patron (membership)
Voluntary support tier via StoreKit: supporter mark, concierge depth, early rails. No feature ransom.
- **Fail modes:** StoreKit + entitlement infra is not an overnight ship; perks must not touch editorial integrity.
- **Feasibility: L. Posture doc only.**

### G3 — "Kuro Selects": editorial commerce
Curated "Start here: Volume 1" guides with affiliate buy links — content, not feed.
- **Fit:** editorial commerce is the brand; uses curated_rails infrastructure.
- **Feasibility: M.** Mid-term, after G1's ledger proves click behavior.

### G4 — Club tiers (paywall larger clubs)
- **Fail modes:** taxing friendship destroys the clubs promise. **Killed on sight.**

### G5 — Curation API / B2B licensing
- **Feasibility: L.** Noted, not pursued.

**Swarm lean:** G1 scaffold tonight (ledger + instrumentation, flags OFF), posture ADR choosing G1→G3→G2 as the roadmap; G4 permanently banned.

---

## H. Design unity

### H1 — One Hero Grammar
Tokenize the club-hero recipe (full-bleed image + grain overlay + dual gradient + bottom-pinned serif masthead + tracked eyebrow) as *the* hero for all new surfaces, starting with the Deck. Discover hero title bumps from 20pt to the display serif scale.
- **Feasibility: H.** New surfaces + one Discover tweak.

### H2 — Warm paper migration
Promote Auth's warm ink `#161412` / warm paper to global semantic tokens.
- **Fail modes:** every screen rescreens against drift; regression surface too wide for one night.
- **Feasibility: M. Deferred with a token plan.**

### H3 — Motion grammar enforcement on touched surfaces
New UI uses only `KuroAnimation` tokens; hero parallax tokenized once; no new ad-hoc `.animation(.ease…)` in shipped code.
- **Feasibility: H** (discipline, not refactor).

### H4 — Placeholder religion
One placeholder spec (secondary background + shimmer + fade-in) for every `KuroCachedAsyncImage` call site touched tonight.
- **Feasibility: H** scoped to new/touched surfaces.

**Swarm lean:** H1 + H3 + H4 ship as the design law for new work; H2 deferred to a dedicated pass.

---

## Red Team murder pass — RESULTS (adversary agent, verified against HEAD)

**Killed tonight:**
- **A1-as-drag + D1-as-unflagged-surgery (original form):** the root pager uses `.simultaneousGesture(DragGesture)` (`ContentView.swift:252-321`); a viewport-sized draggable card *will* fight it, and the existing exclusion-rect machinery was built for 120pt rails. Three correlated unflagged changes (pager surgery + new gesture surface + concierge archive) on the front door = the most likely morning embarrassment.
- **A3 Interview** (aspiration ≠ taste), **C2 Catalog merge** (principle violation), **D3/D4** (half-measure / wrong product), **F4 revamp** (wrong night), **G4 club paywall** (killed on sight — taxes friendship), **B3 Neighborhoods** (research project), **E3 monograms** (deferred), **H2 warm paper** (deferred), Discover hero *size* bump (scope creep on the least-disciplined surface).

**Ship-with-conditions (adopted):**
- B1+B4: pure-SQL pg_cron drain (no HTTP/GUC pattern — it 401'd once already); seed personalization flag at 0%; **do not touch** the matview-backed discover RPCs; per-tag avoidance floors; `processed_at` + error capture.
- E1+E4: un-mirror guard as **DB trigger** (covers both importers + future writers), not TS checks; remote-only selection + cursor; coverage metric view in same migration (Phase 0 had no live measurement); E4 only with worker reading priority rows.
- F1: contract fix + privacy fix + join deep link unflagged (repairs); `clubs_reactions_v1`/`clubs_list_enriched_v1` → 100% after contract fix; realtime/pace/notifications seeded at 0% (remotely flippable without migration); privacy fix ports bundle semantics, no new rules; join link stashes through auth.
- G1: ledger + RPC + instrumentation only, retention **in the same migration**, affiliate flag OFF, no registry; first cut if the night runs long.
- H: token-swap (not size bump) for Discover hero at same 20pt.

**Missing-and-added:** a morning report (status views + metrics script) — "shipped" vs "known-shipped"; deck signal retraction path (mis-tap must not pollute taste forever).

## FINAL WINNERS (swarm lead decision, after the fight)

1. **A1′ The Deck — tap-to-decide, at pager index 0.** Red Team's kill targeted *drag gestures + unflagged surgery*, not the surface. The Kuro-native answer that survives: **no card drags in v1** — three deliberate tap actions (PASS / I KNOW THIS / CALLS TO ME) with cinematic spring exits and direction-colored-by-meaning (monochrome, obviously). Considered judgment, not reflex-flicking: more editorial *and* zero pager conflict. Flag `taste_deck_v1` (100%, one-UPDATE rollback). Concierge archived: Profile row + existing `kuro://concierge` deep link; code + backend untouched. Onboarding final card CTA jumps to the Deck. Candidate pool: unseen, quality-floored, ancillary-excluded, **mirrored-first but remote-allowed** (coverage is 10–20%; mirrored-only starves the deck). Retraction via `retract` action.
2. **B1+B4 taste vector + avoidance** per Red Team conditions, **plus one new isolated consumer**: `fetch_personalized_new_to_you` RPC (new code, no matview edits) consumed by Discover's NEW TO YOU rail only when `personalized_new_to_you_v1` (0%) is on and confidence > 0.
3. **E1+E4 image convergence** per conditions (DB trigger, remote-only + cursor, coverage view, mirror-on-view with real worker read).
4. **F1 clubs trust pack** per conditions (reactions contract, privacy port, `kuro://join/<code>`, flag seeding as above, copy fixes).
5. **G1 click ledger scaffold** (retention included, affiliate OFF, first cut if time runs out — it didn't).
6. **H1+H3+H4 design law** for all new/touched surfaces + Discover hero token-swap at same size.
7. **Morning report** status views + metrics extension (Red Team's missing piece).
