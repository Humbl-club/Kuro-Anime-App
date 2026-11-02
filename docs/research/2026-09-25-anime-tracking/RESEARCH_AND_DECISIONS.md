# Free to use. Worth returning to.

## Anime and manga tracking: comparative research, product decisions and monetization

Prepared for Max · 25 September 2026 · Revised research edition 02

**Recommendation:** Keep Kuro free for tracking and discovery. Win repeat use through dependable personal history, easy updates, better manga semantics and relevant discovery. Earn, if the evidence supports it, by helping users obtain something they already want: the correct next volume, an official sample, or an optional useful event. Retailers and publishers pay; basic use never becomes the obstacle that makes money.

**Status:** Proposed decisions, not implementation approval. This edition replaces the initial report, including its paid-convenience suggestion. The companion visual brief is two pages: product priorities and how to fund them. No app, backend, flag, partner account or deployment was changed.

## 1. What this research establishes

This is a comparative qualitative study of personal anime/manga tracking and discovery, covering evidence dated **1 January 2025–25 September 2026**, plus current official capability, commercial and policy references. It concerns watched/read history, progress, future titles, recommendations and related social behavior. Readers and streaming integrations appear only where they reveal relevant tracking needs. Their playback and content-access features are not Kuro requirements.

**The revised register contains 110 selected source records across 37 distinct hosting domains.** That measures breadth of material, not independent people, market share, complaint frequency, or proof of demand. Six sub-agents researched separate lanes: MAL; other platforms/forums; manga; native clients; affiliate programmes; and sponsorship/constraints. The lead researcher reconciled overlaps, reviewed their findings, checked high-impact claims and built the decisions. A further cross-check corrected a Bookshop terms date and verified a Kitsune review year through Apple's dated feed.

### Coverage and the remaining access gaps

| Research lane | Material actually inspected | Important boundary |
|---|---|---|
| MyAnimeList | Multiple r/MyAnimeList and r/animeapp threads with replies; Android and iOS store listings/reviews; corporate and commercial pages | MAL's own forum navigation was blocked by browser safety policy. This report does not claim those forum discussions were read. |
| AniList | Seven directly inspected forum threads in the first pass, including replies/dates; selected records retained here; current terms and ecosystem references | Existing filters, fixed bugs and planned work are distinguished. No signed-in task benchmark. |
| MyAniList and other clients | Apple public review feeds, dated release notes, Google Play and GitHub issues with maintainer replies | MyAniList is an independent AniList client. MALClient, AL-chan and MALSync have their own failure modes. |
| Anime-Planet | Ten recent forum threads read directly, including all visible replies; official support policy | Reports often reveal discoverability or mobile parity problems, not globally absent features. |
| MangaBaka / manga readers | Nine recent tracker-owned forum posts and visible statuses; Reddit reader/collector threads; Mihon documentation and changelogs | MangaBaka comments did not load; dates are approximate from relative labels. Done is not a verified shipped fix. |
| Kitsu / LiveChart / AniDB | Kitsu public issues and component status; LiveChart official release/notification documentation; AniDB documentation and a Shoko issue | Current documentation/status is distinct from 2025–2026 customer sentiment; AniDB evidence is narrower. |
| Other communities | Direct NeoGAF, Something Awful and MangaHelpers discussions; indexed complete ResetEra discussion | Different sites give independent contexts, but do not eliminate self-selection. |
| Monetization | Merchant/network programmes, publisher collaborations, platform terms and regulatory guidance | Public programme terms do not prove Kuro approval, native-app eligibility, signed partners, conversion or profit. |

Direct MangaUpdates access was safety-blocked. Its strengths and weaknesses here are attributed to users and integration documentation, not a firsthand inspection of its forum. Anime News Network forum searches did not yield usable recent tracker-specific material. Blocked or low-detail pages were not counted as successfully read evidence. We did not create accounts, contact anyone, install competitors, test private libraries, or measure live market shares.

**Naming matters:** MyAnimeList = MAL, a database/community platform with official apps. AniList is a separate platform. MyAniList is a third-party iOS client for AniList. A comment saying “the AniList app” may mean a client or mobile website; attribution is retained wherever known. [P08, C02, M14]

**How evidence was coded:** One thread and its replies form one source record. Multiple selected reviews in one feed are aggregated. Store variants and duplicated agent finds were reconciled. We recorded date, access method, platform/client, reported job, workaround, staff/developer response, and whether the issue was fixed, disputed, unknown or merely proposed. Promotional launch posts, old featured reviews and undated statements were not counted as recent user complaints. Apple feed dates are review-update timestamps; edits can change them. Official undated pages were checked now but are not assigned invented 2026 publication dates.

**Confidence:** High means a repeated need across contexts or unusually clear primary confirmation. Medium means coherent but limited qualitative evidence. Low means an isolated request or commercial/product hypothesis. None means a measured prevalence. Priorities combine risk to history, recurrence in ordinary use, dependencies and Kuro relevance; they are analyst judgments, not a Reddit vote tally.

### What changed from the first report

The first version leaned too heavily on AniList's accessible forums. This version adds substantial platform-specific MAL, Anime-Planet, MangaBaka, client and independent-forum evidence. It changes the recommendations in four ways: retain information density as a choice; separate library views from tracking status; distinguish manga position from actual consumption; and allow deeper recommendation exploration beyond a short default. Its paid-convenience proposal is withdrawn. The new business constraint is **zero fees to use Kuro**, with useful optional commerce and partner-funded benefits assessed separately.

## 2. The market is several overlapping jobs

The main competition is not a single app category. A person may keep a trusted MAL archive, use a native client for quick updates, consult LiveChart for schedules, and ask a community what to try. Kuro must replace enough effort to earn a place without requiring users to abandon valuable history or communities.

| Layer | Examples | Asset users keep | Implication for Kuro |
|---|---|---|---|
| History and community platforms | MAL, AniList, Anime-Planet, Kitsu | Accumulated lists, reviews, relationships, metadata | Switching cost is personal history and habit, not just account creation. |
| Native and automation clients | MyAniList, ManGo, Kitsune, AL-chan, MALClient, MALSync | Fast updates, widgets, device fit, optional synchronization | Attractive cards and +1 controls are competitive basics. Reliability and recovery matter. |
| Manga specialist discovery | MangaUpdates, MangaBaka | Niche coverage, alternate titles, creators, publication/licensing context | Anime-style progress alone does not serve manga well. |
| Release specialists | LiveChart and seasonal tools | Relevant schedule distinctions, reminders, legal destinations | A Japanese airing countdown is weaker than a personal, language-aware release view. |
| Precision/library tooling | AniDB and Shoko | Exact episodes/files, local-library integration | Serve precise identities without exposing every underlying technical detail to casual users. |
| Personal substitutes | Notes, spreadsheets, book trackers, general TV trackers | Control, flexible categories, no unwanted feed | Fast defaults must coexist with optional notes and organization. |

There is evidence of scale, but no defensible tracker-market revenue or share estimate in this study. A **May 2025 joint corporate release reports MAL had 19.5 million registered users**; that is self-reported historical registrations, not current monthly active users or paying demand. A 2025 Dentsu study covers 8,600 consumers across ten countries and discusses anime-related spending; Germany is not in that sample. Neither source estimates Kuro's reachable audience. Broad anime merchandise/streaming expenditure is not tracker revenue. [T01, T02]

### Who to serve first

| Segment | Recurring job | What matters most | Proposed role |
|---|---|---|---|
| Busy / returning fan | Where was I, and what fits tonight? | Immediate Continue, trustworthy history, a useful shortlist | Primary entry experience |
| Seasonal viewer | Which of my shows has something new? | Current-season view without changing status; relevant notifications | Primary retention loop |
| Manga-first reader | Which chapter, volume or translation am I on? | Independent units, unknown totals, publication distinctions | Co-primary, tested separately |
| Established archivist | Keep years of records intact | Import reconciliation, export, dates, exact adaptations | Essential migration audience |
| Explorer / enthusiast | Help me find something specific or obscure | Rich filters, selected seeds, deeper results, creator metadata | Optional depth, not mandatory complexity |
| Private group | Help us choose and stay spoiler-safe | Polls, reasons, shared pace, understandable privacy | Preserve Kuro clubs |
| Physical collector | Which exact edition is next, and did I preorder it? | Language, ISBN/edition, release source, duplicate avoidance | Narrow commerce pilot; defer full inventory |

These are research-derived segments, not quantified shares. The strongest starting hypothesis is a returning or busy fan with existing history who wants continuity and relevant discovery. Manga readers should not be treated as a smaller copy of anime viewers. Interviews must include people who abandoned tracking, not only power users posting on forums.

## 3. What each major competitor teaches us

### MyAnimeList: strong accumulated value, uneven access to it

MAL users value its connected information, reviews, interest stacks, friends and familiar lists. A recent client discussion explicitly asks for that information without requiring a public forum experience. [C14] A July 2025 iOS review specifically praises compact, easy list updating; a NeoGAF exchange prefers the website after app trouble. These are reasons not to assume that replacing the platform with a beautiful empty shell is enough. [M07, M11, F16]

The concrete friction is more useful than “old design.” In an August 2026 UI thread, a user discovers sorting after years while others defend the dense desktop layout. In July, another moved genuinely in-progress older shows to Dropped to isolate current-season watching. A returning fan with 500+ watched titles wants recognition-based batch capture rather than typing every title. Official Android reviews independently request better aliases, personal organization and season grouping and describe a loading failure. [M01, M04, M05, C01]

**Decision:** Improve collection control, findability and native continuity while retaining compact rows and access to rich title context. Distinguish website, official app and third-party client. Do not say MAL lacks all seasonal filters or cannot track manhwa based on one reviewer. No incidence or current global outage was established. [M08, M09]

### AniList: powerful controls and ecosystem, but semantics and recovery still matter

AniList's forum shows that users can miss existing exclusion controls and medium filters. A developer explains why imports cannot reconstruct absent historical dates. A duplicate-entry cause was fixed in August 2026, while existing damage still required careful cleanup. The running bug thread and roadmap provide more specific context than a general “unreliable” label. [S08–S13, S26]

**Decision:** Make power visible, imports inspectable and repairs easy. Do not interpret missing source history as newly deleted data, or a roadmap item as shipped. Its API terms create a separate commercial/data dependency that must be resolved for Kuro; the report does not determine Kuro's agreement status. [B11]

### MyAniList: native convenience can be undermined by monetization interruption

MyAniList is not MAL. Apple's public review feed includes a September 2026 complaint about repeated upgrade prompts and perceived loss of value from an old lifetime purchase. June sorting criticism has an explicit later correction saying sorting was fixed and free again. Other reviews praise organization and season-level precision; some dislike notification behavior or tag overload. [C02]

The changelog documents active work on synchronization, saved filters, notifications and accessibility. Those developer statements are not hands-on proof, but they prevent a misleading claim that every reported issue remains unresolved. [C03]

**Decision:** Never interrupt opening a collection or updating progress to seek revenue. Remember sort/filter preferences. Let users dismiss a campaign persistently. Group franchises without throwing away season-level detail that some users explicitly like. This evidence supports respecting attention; it does not prove nobody in the market pays for apps.

### Anime-Planet: a feature can exist and still fail the user's task

Ten directly read threads show several distinct failures: desktop average-score sorting is not equally discoverable on mobile; a completed-airing filter already exists under Other; mobile width/zoom breaks a user's flow; and a requested manga submission form competes with limited developer/moderation capacity. The response is not automatically “add more features.” [F01, F02, F04, F08]

Its progress discussion exposes a deeper model issue: starting manga after an anime adaptation should not claim that every preceding chapter was read. Partial rereads and rewatches need a session concept. A missing-entry complaint was investigated without confirming deletion; another export-date concern was explained by fields never historically recorded. [F03, F05, F09]

**Decision:** Separate position from consumption, personal status from publication status, and save confirmation from visual feedback. Offer a simple correction form only with a workable review queue. The privacy discussion supports a clear friends-only middle ground, while its public support policy offers a useful clean-profile advertising precedent. [F07, F23]

### MangaBaka and MangaUpdates: depth is an asset; simplification must be selective

MangaBaka's recent forum contains requests both to declutter home and to restore explicit progress totals. One user wants more recommendation results, another wants results based on a selected list rather than the entire history. Creator identity and follow alerts also matter. Import and volume-filter issues marked Done remain instructive but are not asserted to be current bugs. Comments were unavailable and September dates are approximate. [G01–G09]

Readers praise MangaUpdates for detailed tags, aliases, creator links and licensing context, but the sample also shows catalogue disagreements and people using it only for lookup without discovering personal-list sharing. Direct MangaUpdates forum access was blocked, so these are attributed community observations. [G14, G16, G21]

**Decision:** Keep a fast default and an intentional deeper path. Support chapter and volume input, creator identity and explicit coverage boundaries. A reader's missing webtoon is not proof of a universally small database; do a real coverage benchmark before claiming completeness. MangaBaka's own upstream-data documentation also shows aggregation does not remove provenance, freshness or rights dependencies. [G10, G23, G24]

### Kitsu: don't confuse component problems with a dead service

Kitsu's public issues include filtered pagination and a More info control that reportedly reveals nothing. Its official status page separates an operational website/API from unavailable app-store components and records resolved incidents. These are concrete continuity and empty-state lessons; a status component is not a verdict on every installed client. [F11–F15]

**Decision:** Preserve readable history when one capability fails, distinguish no results from failed loading, and isolate optional sections from core tracking. The sample is narrower than for MAL/AniList/Anime-Planet; no general satisfaction ranking is warranted.

### LiveChart: release awareness already has a serious benchmark

LiveChart documents per-title schedules, earliest/sub/dub distinctions, local-time countdowns, opt-in reminders and schedule-change information. It also distinguishes release notifications from partner giveaways. Its FAQ explains the limits of guest marks stored in a browser. These are current documented capabilities, not proof that Kuro's target users are dissatisfied with them. [F19–F21]

**Decision:** Build a personal catch-up view only if its data is useful for the user's country and language. Keep announcement, airing and actual availability distinct. Explain local-only guest saving. Do not claim an integration exists merely because a website has the needed information.

### Native clients, AniDB and automation: maintenance is part of the product

ManGo's recent notes cover cache, login, widget and dual-service repairs. AL-chan reports show rate-limit friction, an auxiliary notification parsing failure with a reported repair, and a useful cached fallback. MALClient users report schedule/detail failures while still valuing the client. A MALSync matching issue received a partial change; a different automatic-progress complaint was withdrawn after extension-conflict testing. [C04, C07–C13]

AniDB's model distinguishes seen episodes and files. A Shoko issue shows a novice surprised by a huge synchronization queue, not an AniDB-wide failure. [F24, F25]

**Decision:** Optional automation needs an identity preview, queue visibility, conflict policy and undo. Broad integrations increase maintenance obligations. A generic green sync icon is insufficient, and a closed issue is not proof that the user's installed version is fixed.

## 4. Priorities, contradictions and design consequences

| Priority | Consequential problem | Supporting contexts | Product response |
|---|---|---|---|
| P0 | History or changes become untrustworthy | AniList import/repair; A-P saves/dates; MangaBaka import; client sync | Reconciliation, confirmed saves, export, repair, no fabricated history |
| P0 | A daily update requires unnecessary navigation | MAL seasonal workaround; MyAniList interruption; home clutter | Continue, visible +1 and set-progress, retained views, no monetization in the task |
| P0 | Manga data collapses different meanings | A-P start offsets; volume-only filtering; chapter/volume and translation distinctions | Bookmark vs consumption, chapters vs volumes, original vs available translation |
| P0 | Search/filter power cannot be found or used consistently | MAL sort/aliases; A-P desktop/mobile; AniList exclusion; Kitsu pagination | Explicit include/exclude, clear labels, robust own-list search, device parity |
| P1 | Franchise structure creates administrative work | MAL grouping requests; native precision praise; automation mapping | One visual journey with exact seasons/parts underneath |
| P1 | Discovery lacks the right context or useful depth | MAL information demand; MangaBaka list seeds/more results; ResetEra resolution | Small default, useful reasons, selected seeds, deeper exploration |
| P1 | Release information is irrelevant or ambiguous | Manga collectors; client reminders; LiveChart benchmark | Followed titles/creators, chosen schedule, language/region, opt-in alerts |
| P1 | Revenue interrupts utility or biases choices | MyAniList review/correction; commerce and sponsorship mechanisms | Free core, user-requested commerce, separated and labelled sponsorship |
| P2 | Social is either intrusive or too limited | Opposing MAL requests; A-P privacy; MangaHelpers club behavior | Optional private clubs, spoiler boundaries, simple outward sharing |

P0 means first to evaluate and address if Kuro fails the task; it does not mean every proposed feature should be built immediately. Revenue-enabling data rights are a separate prerequisite, not a reason to halt unrelated local usability improvements.

**The contradictions change the design.** Some users want fewer sections; others want denser information. Some want hidden scores; others prominent scores. Some want a short recommendation shortlist; others more results. Some value individual seasons; others think in franchises. Those are not noise to average away. Use sensible defaults with a few meaningful controls, not an infinitely customizable interface. [M01, M06, C05, G01–G04]

**What not to conclude:** These sources do not prove that one tracker is best, that all users dislike social features, that AI recommendations outperform editorial/community picks, that automation should always be on, or that a paid feature is never commercially viable. Kuro's free-to-user strategy is the user's constraint and the proposal here; its profitability still needs proof.

## 5. Product decision register

All decisions are recommendations for validation. P0/P1/P2 indicate sequencing; confidence refers to the need, not guaranteed impact. Existing Kuro implementation must be inspected before any change.

### D01 — Choose continuity as the central promise

**P0 · High confidence in the job; audience positioning remains a hypothesis.** Build the first experience around remembering progress, choosing the next worthwhile title and noticing relevant releases. The seasonal-status workaround, history-reconstruction request and notes-app workflows show a need for continuity that spans account creation, daily use and returning after a gap. [M04, M05, M07]

**Design decision:** Present Continue, Discover and Upcoming as clear task concepts. They need not become three new tabs. Preserve valuable review/title context and an obvious path back to a personal collection.

**Tradeoff:** This avoids building a public entertainment feed, but may appeal less to people primarily seeking public identity and debate. Keep clubs and outward sharing optional rather than removing social value.

**Validation:** Recruit returning, seasonal, manga-first and experienced tracker users. Ask them to locate their place, choose a suitable next title and explain an upcoming release. Measure success and return use; do not infer product-market fit from preference for a mockup.

### D02 — Separate collection views from actual watch/read status

**P0 · High confidence in the failure case; medium in its reach.** A user changed Watching entries to Dropped simply to isolate current-season viewing. That distorts the meaning of a record to compensate for a missing or undiscoverable view. [M04]

**Design decision:** Offer Continue, This season, Caught up and Recently updated as views derived from data. Personal status remains Planning/Watching/Reading/Completed/Paused/Dropped as appropriate. A “Ready to binge” view combines personal planning state and finished publication state; label these separately. Remember the last chosen sort and provide visible reset. [F04]

**Tradeoff:** More views can become navigation clutter. Start with the smallest set that solves observed tasks, with compact rows alongside editorial cards. Do not add a dashboard editor by default.

**Validation:** Mix ongoing seasonal titles with older shows and manga. Users must find next actions without falsely completing, dropping or hiding real progress. Compare against current Kuro navigation before replacing it.

### D03 — Make progress fast, explicit and recoverable

**P0 · High confidence.** Keep visible +1 and set-progress actions, with optional reviewed batch updates. Never require a rating, review, ad view or purchase to record consumption. Quick updates already exist in the market; the differentiator is confidence that they affected the right title once. [C04, M07]

**Design decision:** Confirm the exact episode/chapter/volume and provide immediate undo. Batch completion lists the affected entries. Automation is opt-in, with a visible match and a correction path; preserve specific mappings instead of rerunning uncertain guesses silently. [C12, C13]

**Tradeoff:** An undo window and a pending state add visual detail, but prevent the costlier burden of reconstructing history. Haptics or animation alone are not confirmation from the server.

**Validation:** Test rapid taps, app backgrounding, network failure, duplicate retries, mistaken season matches and rollback. Verify both stored state and visible state. A spinner disappearing is not proof of durable saving.

### D04 — Keep history usable when a dependency fails

**P0 · High confidence.** AL-chan's cached list remained useful during one fetch failure; other client reports show optional metadata, notifications or schedule failures interrupting the experience. Rate limits also appear during rapid seasonal additions. [C07–C11]

**Design decision:** Distinguish saved, pending, failed and stale. Keep previously fetched personal history readable. If offline editing is supported, define conflict behavior and show queued changes; never promise offline writes merely because a banner/cache exists. Isolate optional social/recommendation errors from core list access.

**Tradeoff:** Reliable offline mutation is meaningful engineering work. A clear read-only fallback is safer than silently losing queued edits while advertising full offline support. Reconnect/retry must avoid overwriting newer remote state.

**Validation:** Simulate loss of connectivity and individual provider capabilities, then reopen. A user should know what is saved, what needs action and what can still be done. Confirm retry correctness and account separation, not only pleasant error wording.

### D05 — Treat migration as reconciliation, and make departure easy

**P0 · High confidence.** Multiple forums describe intermediary formats, missing coverage and lost meaning in imported dates. A-P's null-date example and AniList's recent-order explanation show why unknown history must remain unknown. [F09, F10, F17, S08, G08]

**Design decision:** Before applying an import, show source count, matches, duplicates, unresolved works, unsupported fields and proposed updates. Preserve source identifiers and date precision. Retain unmatched private records or a downloadable unresolved file rather than silently dropping them. Export a human-readable format and a documented machine format for the user's own Kuro history.

**Tradeoff:** Reconciliation takes longer than a success toast. Offer a short summary with detailed review only where needed; do not force users to inspect every exact match.

**Validation:** Round-trip representative libraries with absent/partial dates, notes, rewatches, manga volumes, aliases and missing titles. Target zero silent loss. Provider contracts and connector direction are independent prerequisites; a successful import is not continuous two-way sync. Reader-integration documentation and recent repairs corroborate that distinction. [G11, G18, G19]

### D06 — Group franchises without merging away precision

**P1 · High confidence in the tension; medium in the chosen UI.** MAL users request whole-series grouping while MyAniList reviewers value individual seasons. Both needs are legitimate. [M02, C01, C02]

**Design decision:** Use a franchise overview showing entry point, completed parts and the next relevant part. Expand to exact seasons, split cours, films, specials and alternate adaptations. Keep separate scores and progress; label “series” versus “entries” in statistics. Never infer a universal watch order or copy a rating across adaptations without a choice.

**Tradeoff:** Relation data can be incomplete or ambiguous. Present sourced relationships and uncertainty. Do not let a simple umbrella card hide an unresolved match that an automated integration will later write to incorrectly. [C12]

**Validation:** Use complex examples, including split seasons, remakes and manga adaptations. Users should find where to continue and understand exactly which entry receives an update. Preserve imported IDs through grouping and export.

### D07 — Separate manga position, units and actual consumption

**P0 · High confidence.** Starting at chapter 1000 after watching an adaptation does not mean reading 999 earlier chapters. Volume-only progress must not look unread because chapters remain zero. Weekly chapter reading, physical editions and partial rereads are distinct workflows. [F03, G09, G17]

**Design decision:** Store bookmark position separately from optional reading sessions. Support independent chapter and volume values, unknown totals and partial dates. Let advanced users specify a starting offset or reread range; keep ordinary +1 simple. Ownership and preorder status are separate from reading. Original publication completion, translated availability and personal caught-up state are different facts. [G13]

**Tradeoff:** Accurate consumption statistics require more data than a single counter. Do not invent precise hours or chapters read from an absolute bookmark. Avoid fixed chapter-to-volume conversion; use edition-specific mapping only when verified.

**Validation:** Test ongoing unknown-total works, chapter-first readers, volume-only readers, omnibus editions, adaptation handoff and partial rereads. Filters, completion logic, imports and exports must all preserve the distinction.

### D08 — Make releases personal, qualified and controllable

**P1 · High confidence in distinctions; medium in priority.** Release specialists already support precise schedules. Readers also want upcoming volumes and new creator work; client reviews warn that stale reminders become noise. [F06, F19, F20, G05, G12, C02]

**Design decision:** Show Today, This week and Later for followed titles/franchises and deliberately followed creators. Label announcement, Japanese broadcast, selected-language release and physical-edition publication separately. Include source/freshness where meaningful, delays and unknown dates. Stop appropriate reminders when a title is removed or dropped; allow the user to override intentionally.

**Tradeoff:** Reliable localized data and identity resolution cost money and maintenance. An honest partial view is preferable to false certainty. No sponsor notifications are bundled with utility reminders.

**Validation:** Measure useful alerts versus dismissals and mistaken destinations. Test late schedule changes, time zones, dropped titles and different languages. A push delivered on time is not useful if the episode or edition is unavailable to that user.

### D09 — Make availability useful even when it earns nothing

**P1 · Data-dependent.** “Aired” does not mean legally available in the user's language, region or current subscriptions. Documentation already distinguishes these facts; verified availability is a data problem before a visual one. [P06, F19]

**Design decision:** Preserve official destinations, show qualified availability only when country, language, service and freshness support it, and prioritize access the user already has. Keep free/legal/library and non-affiliate alternatives where verified. A monetized merchant link is not evidence that a title can be watched there.

**Tradeoff:** More precise promises narrow coverage. Keep “unknown” explicit and allow a clean official-source link without pretending to know entitlement. Do not build a scraping-dependent availability business as an incidental monetization experiment.

**Validation:** Check a small set in real target countries/languages against official destinations. Track dead links, wrong territories and unexpected extra charges. Kuro's provider-availability work remains staged according to local documentation; this study did not change or live-verify it.

### D10 — Make filters, aliases and sorting visible across devices

**P0 · High confidence.** MAL and Anime-Planet discussions expose hidden sort, confusing personal/community ratings and mobile parity; AniList users miss existing exclusions. Kitsu's filter-pagination report adds a reliability dimension. [M01, F02, F04, S11–S13, F11]

**Design decision:** Provide alias-aware title search with a preferred display language and a useful secondary title. Distinguish own-list search from catalogue search; my score from community score; personal status from publication status. Use explicit include/exclude/reset controls and retain selections. Essential sort/filter capability should survive grid/list, small screens and accessibility text sizes.

**Tradeoff:** Showing all specialist tags upfront overwhelms people. Start with common choices, make active criteria visible, and reveal deeper taxonomy intentionally. Never conflate demographic labels with story themes or protagonist attributes. [G07]

**Validation:** Test forgotten English titles, punctuation, excluded themes, completed-airing planned titles, mixed media and paginated filtered results. Observe finding and correcting criteria without explaining hidden gestures first.

### D11 — Offer a useful shortlist and an escape from it

**P1 · Medium confidence.** People need contextual choosing, but some want deeper exploration. MangaBaka users request recommendations from a particular list and more than a limited result set; a ResetEra user ultimately finds an existing app satisfactory. [G03, G04, F18]

**Design decision:** Default to a few varied, well-explained choices based on stated mood, time, format, exclusions and taste. Offer “more like these,” a chosen-list seed and See more. A reason must reflect actual selection signals, not invented AI confidence. Keep editorial and community context available. Sponsored content never secretly alters these rankings.

**Tradeoff:** More controls can recreate administration. Ask only what helps the current decision; remember optional preferences and allow skipping. A whole-library taste profile should not override a deliberate different mood today.

**Validation:** Measure whether a user finds and later tries a suitable title, not just card clicks. Compare with current Kuro editorial/Taste Deck behavior. Include obscure-title seekers and people who actively reject similar-to-everything-they-already-know results.

### D12 — Keep personal evaluation separate from public score

**P1 · Medium confidence.** Kitsune reviews from January 2025 and January 2026 ask for opposite score presentations. MAL notes-app comparisons show different scoring and journal preferences. [C05, M07]

**Design decision:** Always distinguish the user's rating from aggregate rating. Allow aggregate scores to be hidden without changing discovery access; retain a clear view for those who use them. Notes and short personal verdicts are optional. Do not force a score to mark progress or mix a recommendation explanation with an apparently scientific fit percentage.

**Tradeoff:** Excessive rating scales complicate interoperability. Preserve imported precision even if the default input is simple, and disclose any required conversion when syncing. Do not silently round historical values to fit a cosmetic control.

**Validation:** Ask users to explain whose score they see, record unrated completion and recover imported ratings. Test both score-led and score-averse users. The goal is comprehension and control, not a universal rating philosophy.

### D13 — Support import, recognition and browsing at first use

**P1 · Medium confidence in tasks; onboarding outcome unproven.** File import serves established trackers; returning fans without a file need recognition-based reconstruction. A request to mark hundreds of remembered shows by genre exposes that distinct need. [M05]

**Design decision:** Offer Import, Mark what I know and Browse first. Use genre/era/title recognition with explicit exact-entry selection, reviewed batch completion and undo. Preserve unknown historical dates. Taste training remains optional and resumable; it should not block first value.

**Tradeoff:** A broad completion grid can introduce accidental matches and overwhelm new fans. Keep it a chosen path, use a final preview and avoid automatically selecting every season of a franchise.

**Validation:** Compare first useful action and later return for users with files, remembered history and no history. Check accidental bulk changes and task abandonment. Existing Kuro Taste Deck should be evaluated rather than discarded on the basis of forum inference.

### D14 — Preserve private clubs and optional sharing

**P2 · Medium confidence.** A-P users ask for a middle ground between public and private. MangaHelpers' actual reading club uses nominations, reasons, polls and shared spoiler boundaries. Other users want rich reviews without a public feed. [F07, G20, C14]

**Design decision:** Keep understandable club sharing levels and show what others can see. Make a shared reading boundary visible. Use nomination reasons and spoiler-aware discussion; a simple outward share can serve some users without another public social network. Ordinary tracking never requires joining or posting.

**Tradeoff:** Sharing and moderation have real costs. Sponsor access must not be added to private clubs. Granular privacy that nobody understands is not safer than a small set of explicit levels.

**Validation:** Ask members to predict which name/status/progress/comment is shared and with whom. Test withdrawing sharing, leaving a club and spoiler protection beyond the agreed point. User comprehension must match server behavior before a privacy promise is made.

### D15 — Keep the entire useful core free and uninterrupted

**P0 · Explicit business constraint, supported by attention-friction evidence.** Kuro will not charge for tracking, ordinary discovery, search/filter/sort, history, import/export or useful reminders. The first report's paid-convenience idea is superseded. MyAniList complaints about recurring prompts—and the correction when sorting became free again—show the practical harm of monetizing through routine friction. [C02]

**Design decision:** No upgrade modal, artificial daily tracking limit, reward-ad requirement, paid export or pay-to-sort mechanism. Optional purchases happen with an outside merchant because the user wants that product. Partner-funded content must deliver a distinct benefit and be visibly commercial.

**Tradeoff:** This removes a revenue option; it does not remove costs. Affiliate and sponsor income must earn their place through contribution margin and demonstrated usefulness. If the economics fail, reduce scope/cost or choose a different business, rather than quietly weakening the free-core promise.

**Validation:** Test the unmonetized core against each pilot; core task success, latency, trust and return use are guardrails, not variables to sacrifice for more clicks.

### D16 — Resolve data permissions independently of monetization format

**P0 prerequisite · High confidence in published constraints; Kuro agreements unknown.** AniList's competing-tracker restrictions are separate from its commercial revenue threshold. MAL's agreement also has commercial, review, storage and advertising conditions. A switch of data supplier is not automatically a solution. [B11, B12]

**Design decision:** Record permitted use for catalogue text/images, user imports, storage, synchronization, redistribution, commercial display and partner reporting. Obtain scope appropriate to the actual app before revenue-dependent rollout. Retail affiliate approval cannot authorize catalogue usage. Aggregators retain upstream dependencies. [G24]

**Tradeoff:** Contractual clarity may limit or delay a revenue path. Continue unrelated usability work, but do not fund a business forecast on assumed permission or on remaining below a nominal threshold.

**Validation:** A written permission matrix with responsible owner, source/version, covered app/domain, geography and renewal/change requirements. This is a future implementation gate; this research makes no finding that Kuro has or lacks a private agreement.

### D17 — Preserve editorial identity with functional density and accessible actions

**P0 for controls/legibility; P1 for layout changes · High confidence in differing needs.** Familiar density is actively defended on MAL; MangaBaka's simplified display prompts a request to restore totals; mobile layout trouble on A-P is concrete. [M01, M06, G01, F08]

**Design decision:** Keep Kuro's monochrome editorial direction for discovery. Give collection rows legible progress, persistent sort and obvious actions. Support meaningful text enlargement, screen-reader labels and narrow widths. Important controls must not rely only on long press, color or tiny decorative labels. Display optional detail progressively without stripping it out. Some readers actively enjoy organizing personal notes and categories. [G15]

**Tradeoff:** More visible controls reduce poster-led minimalism. Judge this by fewer errors and faster everyday use, not visual novelty. Do not add arbitrary themes or infinite layout choices to satisfy every isolated request.

**Validation:** Real update/search tasks on small screens and large text, plus a compact-versus-card comparison. Check empty states, loading, image-viewer return and discoverability before aesthetic polishing.

### D18 — Make catalogue coverage and corrections honest

**P1 · Medium-high confidence.** Readers find differing coverage across trackers; an A-P correction request reveals that submission ease and moderation capacity must be designed together. Vendor catalogue counts do not measure overlap with a user's library. [G10, G21, F01]

**Design decision:** Define supported media/origins and measure a representative library benchmark. Provide private unresolved placeholders during import when needed. Offer a prefilled report-error/missing-title path with source URL, field and proposed correction, duplicate checks and visible status. Keep metadata provenance; do not replace nuanced publisher descriptions with untraceable generated copy. [G06]

**Tradeoff:** A submission form without review capacity creates false promises and catalogue pollution. Limit supported corrections, triage queues and communicate delay. Private placeholders should not instantly become public canon.

**Validation:** Separate title coverage from successful matching. Test obscure manga, one-shots, aliases, manhwa/manhua and deliberately included/excluded Western webtoons. Track correction turnaround, false merges and reopened errors, not submission volume alone.

## 6. Monetization that pays for a useful next step

The strategic constraint is **free access to the product**. Users may choose to buy a book, ticket or outside service, but Kuro does not charge them to remember, discover or keep up. A good commercial feature should still be useful if its commission were zero. That is the simplest test for distinguishing assistance from disguised advertising.

### Recommended order

| Model | Who pays / what they receive | Benefit to users | Recommendation |
|---|---|---|---|
| Exact-volume referrals | Retailer pays for an eligible referred purchase | Correct edition/language, local availability, fewer duplicate purchases | First small pilot, after data and app permissions |
| Licensed samples / sponsored discovery | Publisher funds a defined, labelled useful asset or campaign | Try an official work before buying; find a relevant translated edition | Second pilot with an actual partner and bounded cost |
| Optional club/event resources | Publisher, distributor or event organizer funds a kit/activity | Legal sample, reading guide, creator Q&A or relevant event | Later and opt-in; no private-club ad inventory |
| Publisher/retailer discovery tools | Business pays for a scoped tool on its own property | Better navigation through that partner's catalogue | Separate B2B hypothesis; secure paid demand before building |
| Voluntary publisher research | Publisher commissions disclosed feedback on selected samples | A chance to influence future legal translations/releases | Defer; distinct opt-in, no pooled history sale |
| Generic display/behavioral ads | Advertiser pays for impressions/targeting | Usually little direct benefit | Not the recommended base model; exclude intrusive/behavioral forms |

The strongest initial combination is **a narrow book-referral utility plus, later, a genuinely useful sponsored sample**. It is not yet a proven sustainable business. The first is easier to test but can produce little revenue at small scale. The second may fund more work per agreement but introduces sales, rights, production and servicing costs. B2B tooling may earn earlier money from a business customer, but it is separate product/services work and can distract from Kuro.

### Actual market precedents, with limits

MAL's 2026 Publisher & Bookseller Picks explicitly identifies sponsor selections; its MAL×Japan area hosts industry-linked discovery and participation. This establishes a commercial discovery surface, not neutral recommendation quality or disclosed fees. [B01, B02]

MAL's Manga Sampler Pilot offers authorized opening chapters and asks about future translation demand. Its July–September 2026 giveaway had already closed by this research date. The experimental service discloses unreviewed machine translation, availability limits and free-for-now status. It proves a mechanism, not publisher payment or profitability; Kuro should not copy its translation or broad data permissions by default. [B03]

NTT DOCOMO's March 2025 MANGA MIRAI announcement describes previews and purchases integrated into MAL. KADOKAWA's 2025 writing contest with MAL/Honeyfeed and its February 2026 result demonstrate a real creator opportunity. These collaborations show publishers will work through fandom platforms, but do not establish willingness to pay a small Kuro audience or prices for club sponsorship. [B04–B06]

LiveChart and Anime-Planet describe restrained advertising supporting operations. Anime-Planet says profiles are ad-free and rejects intrusive formats. Their statements are useful design precedents, not audited proof that ads alone fund a commercial team. MAL's advertised skins/banner/mobile inventory is a different approach and not a recommendation for Kuro. [B07, F23, B09]

### Merchant feasibility: current public terms, not Kuro approvals

Germany is the initial worked example because of the user's operating context; the intended launch geography was not otherwise specified. Programme geography, audience and native-app permission must be verified before implementation. Rates below were checked on 25 September 2026 and can change.

| Route | Verified public commercial detail | Territory / permission limit | Assessment |
|---|---|---|---|
| Thalia / Awin | Books 11%; non-price-bound books with a coupon 8%; 30-day attribution; daily product feed | German programme; accepted commission base and Kuro native-app placement still need confirmation. “App-Tracking” does not prove publisher-app approval. | Best DE first investigation; exact-volume utility. [A01, A02] |
| Amazon DE | Books currently 4.5%; ordinary session generally 24 hours, with conditional cart extension | Mobile app must be approved and meet original-content/free-access rules. No Amazon WebViews; permitted linking/price tools and relevant policy apply. | Additional neutral option, not a commission-driven default. [A03, A04] |
| Amazon US | Physical books 4.5%; some qualified Prime Video actions have published bounties | US programme only; eligible action/customer and storefront-specific digital-link rules matter | Do not transplant US bounties into Germany or budget unapproved streaming income. [A05] |
| Bookshop.org US | Standard media affiliate 10%, 48-hour last-touch window; enhanced offer carries audience/exclusivity conditions | US affiliate terms; US and UK sites have domestic fulfillment, not a German shipping route. UK programme terms require separate confirmation. Native app eligibility unknown. | Good potential indie option for a relevant market; reject exclusivity that removes neutral shop choice. [A06–A08] |
| Rakuten Kobo | Public page says up to 5% for ebooks/audio/devices and 14-day attribution | Exact accepted rate, German route and native-app placement unconfirmed; “up to” is not a promise | Secondary legal ebook route after approval and iOS review. [A09] |
| CDJapan | 5–7% by prior sales tier; 30 days; paid/shipped orders qualify | Site definition does not establish native-app permission; shipping, cancellations and payout timing matter | Niche Japanese-edition/artbook/merch route when explicitly sought. [A10, A11] |
| EVENTIM DE | 20% of net presale fee, not ticket price; page estimates that fee at 8–10% of net ticket | Programme has event exclusions; header says one-day attribution while text says session, requiring clarification; application/placement approval needed | Optional relevant-event experiment, not a dependable core forecast. [A12] |
| Crunchyroll streaming/store | No authoritative current public rate and acceptance terms were verified | Streaming/store, country, app traffic and contract remain unresolved | Accurate non-affiliate links remain valuable. Model zero revenue until accepted terms. |

No programme was joined and nobody was contacted. A legal official link is not automatically an affiliate link. Programme acceptance is not permission to use a third party's catalogue, images or user data commercially.

## 7. Monetization decision register

These ten decisions make the free-core commitment operational. Commercial attractiveness is a hypothesis until Kuro has valid permissions, useful task outcomes and accepted revenue.

### N01 — Pilot “Find the next volume,” not a general storefront

**First commercial test · Medium confidence in utility; revenue unproven.** Collector discussions describe difficulty finding upcoming editions and duplicate preorders. Chapter-first readers also need reliable edition mapping. Pair that need with a user-requested retailer choice, rather than showing random merchandise after a progress tap. [G12, G17]

**Flow:** The user opens Get this volume → chooses language/edition → sees verified local options and total-cost context → chooses a merchant → returns to the same Kuro state. Keep a clean official/non-affiliate option. Do not equate an outbound click with a purchase, ownership or reading progress.

**Payer/value:** An approved retailer pays for a qualifying attributed sale. The user benefits from finding the right item faster, not from an unverified claim that Kuro has the cheapest price or a discount.

**Tradeoff and test:** ISBN/edition mapping, stock, shipping and link maintenance cost money. Start with a limited manually verified set in one country. Stop on persistent wrong-edition or wrong-language recommendations. Expand only if usefulness and contribution justify maintenance.

### N02 — Keep retailer and recommendation rankings independent of payment

**Permanent design rule.** Rank purchase options by exact item match, language/region, availability, reliable total cost and chosen preferences. Do not use commission as a relevance signal. Keep non-paying merchants and already-owned subscription access visible when useful. [A01–A12]

**Commercial content:** A paid placement, if offered, is a visually separate labelled module. A sponsor cannot purchase a hidden lift in “because you liked…” recommendations, suppress criticism or exclude competing stores. Reject an enhanced affiliate arrangement when its exclusivity would undermine neutral choice; Bookshop's enhanced terms illustrate why this needs contract-level checking. [A07]

**Tradeoff:** Kuro may earn less per click than an aggressive affiliate site. The strategy depends on repeated trusted use, not maximizing the payout of a single session.

**Validation:** Audit results with affiliate flags/rates removed: organic order should be unchanged. Ask users who paid for a sponsored item and why a shop is ranked first. A disclosure that exists but is misunderstood is insufficient.

### N03 — Sell a licensed sample benefit, not an undisclosed recommendation

**Second pilot · Primary precedent, unproven Kuro demand.** A publisher funds a clearly labelled sample or useful discovery feature. MAL's sponsor picks, sampler and MANGA MIRAI integration establish relevant mechanisms; they do not disclose a transferable campaign rate. [B01, B03, B04]

**Product:** Start with a publisher-hosted, properly licensed sample link showing language, available chapters, territory and any expiry. It should help someone assess a work without buying. A separate sponsored card may introduce it in Discover, with hide/dismiss controls. Avoid an embedded reader initially unless the extra rights and maintenance are justified. No sponsor inside Continue, import/export, private notes or progress controls.

**Commercial structure:** Negotiate a bounded pilot fee for agreed placement/production, or a capped measurable engagement arrangement. Do not guarantee sales or positive reviews. Catalogue/image rights and translation quality need explicit treatment.

**Validation:** Measure useful sampling, voluntary saves after sampling, helpfulness, hides, load impact and contribution after labour. Clicks caused by confusing placement count against the experiment. A free sample available only in the wrong country is not a benefit.

### N04 — Keep sponsorship optional, sparse and understandable

**Permanent UX rule.** A user can ignore or hide a campaign and retain the full tracker. Sponsor identity and the commercial relationship appear beside the content; the relevant local advertising label must be clear. Commercial disclosure is not buried in terms. [B14]

**Design starting point:** Test no more than one commercial module in a discovery session, with persistent campaign hiding and no repeated opening modal. That frequency is a proposed ceiling for a pilot, not an industry-validated optimum. Prefer contextual selection from the page's subject over profiling a person's history. Ordinary organic discovery remains usable when no sponsor is available.

**Tradeoff:** Lower exposure may constrain what sponsors will pay. If a campaign requires repeated nagging, accidental clicks or a blocked task to meet its target, reject the deal rather than alter the free-core promise.

**Validation:** Include an unexposed comparison group. Watch comprehension, task completion, latency, hides/reports and 7/28-day return alongside earned revenue. Do not interpret increased dwell time as success if users are struggling to exit.

### N05 — Let partners fund an optional club benefit, never access to a club

**Later · Medium evidence of collaboration, low evidence of Kuro demand.** A publisher could fund a reading guide, authorized sample, creator discussion or relevant event. Actual industry contests demonstrate collaboration, while MangaHelpers shows what small reading groups do; neither proves a sponsor market for Kuro clubs. [B05, B06, G20]

**Product:** Offer a separate public event/resource page. A club organizer may choose a kit; members can decline. Sponsor identity, rights, age/territory limits and recording rules are explicit. Existing clubs keep ordinary polls, planning and discussion without participating. Sponsors receive no members' names, notes, private progress or membership lists.

**Tradeoff:** Events introduce coordination and moderation costs. Start with a simple static resource and publisher-hosted sample before a live event. No reward for positive ratings, public sharing or unwanted marketing consent.

**Validation:** Measure voluntary uptake, useful participation, repeat club use, moderator hours and net contribution. Cancel a pilot that trades privacy or participant attention for sponsor deliverables users did not choose.

### N06 — Treat B2B discovery tools as a separate business hypothesis

**Defer until paid demand · Low confidence.** A publisher or bookstore might pay for a small recommendation questionnaire or curated widget using its own licensed catalogue. Existing MAL-linked marketing services show adjacent B2B activity, not proof that a neutral tracker can profitably sell reusable widgets. [B10]

**Product:** Clearly say “From this publisher's catalogue.” Use session preferences or the partner's own content, not access to Kuro histories. Keep the consumer app free regardless of the business relationship. Define integration, support and update responsibilities before building.

**Tradeoff:** Custom work may earn cash but consume the team in one-off services. A sponsor wanting a unique microsite is not recurring software demand. Do not build a multi-tenant platform in anticipation of buyers.

**Validation:** Obtain an actual paid pilot before substantial engineering, then measure discovery usefulness, support hours, contribution and willingness to renew. Scope and customer commitments would require a later authorized initiative; no outreach occurred in this research.

### N07 — Avoid selling histories under an “insights” label

**Permanent boundary; optional research is separate.** No sale of personal lists, inferred tastes, private notes, club activity or event-level user identifiers. Removing names does not automatically make a dataset anonymous; small cohorts and combinations can still identify people. [B18]

**Permissible proposal:** Report broad campaign delivery totals with appropriate small-count suppression. A future publisher-feedback study would be a distinct opt-in task explaining the recipient, purpose, retention and reuse, with no effect on tracker access. The MAL sampler demonstrates a feedback mechanism, not permission to copy its data terms. [B03]

**Tradeoff:** This excludes targeting/longitudinal-data opportunities and may reduce advertiser interest. It protects the intended product relationship. Underlying measurement still needs a lawful basis even when the final output is aggregated. [B17]

**Validation:** Audit exactly what leaves Kuro and the merchant subtags; no private history or stable user identifier should be transmitted for affiliate reporting. Test opt-out and deletion against actual data flows before making privacy claims.

### N08 — Keep utility reminders independent of commercial messages

**Permanent design rule.** A chosen title's release alert is a service the user requested. A partner giveaway or marketing message is a different purpose. LiveChart's separate categories provide a useful precedent; native reviews show how irrelevant reminders damage trust. [F20, C02, C14]

**Design decision:** A user can subscribe to a specific edition's availability without agreeing to broad promotions. Keep sponsor messages out of push/email in the initial model. Apple also restricts display advertising in notifications and widgets. [B13]

**Tradeoff:** A commercial partner may prefer push reach; that is not part of the initial inventory. Opting into a release reminder should never be treated as consent to behavioral advertising or a sponsor contact list.

**Validation:** Check removed/dropped titles, quiet hours, timezone changes and consent withdrawal. Track usefulness and unwanted-alert reports. An update to merchant inventory must not produce repeated promotional alerts or imply a release date is certain when it is not.

### N09 — Review each channel's rights, geography and payment rules separately

**Prerequisite · High confidence in constraints; implementation-specific assessment still required.** A public website, a German iOS app and a US iOS app are not interchangeable distribution channels. Physical books consumed outside the app follow different Apple payment rules from digital content/service purchase links. A tracker does not automatically qualify for a reader-app entitlement. [B13]

**Decision:** Obtain merchant approval for the exact placement/app; verify attribution without intrusive tracking; confirm content/API commercial scope; and review the chosen storefront flow. German/EU disclosure, storage/access and personal-data requirements apply according to the actual implementation. Avoid behavioral ad targeting by design rather than treating every cookie or every DSA obligation as identical. [B11, B12, B14–B17]

**Tradeoff:** This is bounded implementation diligence, not a giant compliance feature project. Start with a simple approved physical-book route and clean links. Contextual placement reduces complexity but does not automatically eliminate privacy obligations.

**Validation:** A signed/accepted permission record and tested compliant route for each pilot. Public “App-Tracking” wording or a competitor's example is not evidence of Kuro authorization.

### N10 — Require useful outcomes and positive contribution before scaling

**Permanent commercial gate · Revenue hypothesis.** Do not judge monetization by raw clicks, registrations or a nominal commission percentage. Approved attributable revenue must cover the incremental data, editorial, engineering, sales, servicing and support cost of the feature. Sponsor fees are not recurring revenue until renewal is demonstrated.

**Decision:** Keep a comparison group without the commercial treatment. Report correct-item success, sample usefulness, core tracking success, return use and complaints alongside approved revenue. Revenue generated by wrong-edition confusion, hidden paid rank or accidental taps fails the pilot regardless of gross results.

**Tradeoff:** At a small audience, the economically honest result may be “not enough yet.” Reduce scope or pursue separately justified partner services; do not add friction to make users click. Cost of running the free core remains a business obligation.

**Validation:** Review settled commissions and real labour over a defined pilot period. Set quantitative noninferiority margins after establishing a baseline and adequate sample size. The illustrative calculations below are sensitivity analysis, not a promise of profitability.

## 8. Economics: what would have to be true

There is no measured Kuro audience, conversion, accepted merchant rate or publisher budget in this research. Every scenario is illustrative. The point is to expose the scale and cost questions before investing, not to manufacture a business forecast.

### Affiliate revenue formula

Approved monthly commission = monthly active users × share with a relevant shopping need × share of those users clicking × orders per click × commissionable basket × commission rate × approval after refunds × attribution survival.

“One click opportunity per relevant user” is the simplified assumption; repeat purchases are not added. Attribution survival represents such things as lost/cross-device attribution, another last-click affiliate or ineligible transactions. Its relationship with conversion is not necessarily independent. Use the merchant's accepted commissionable base, not an unexplained retail checkout total.

| Illustrative month | Audience and funnel assumptions | Basket / commission / settlement assumptions | Result before costs |
|---|---|---|---|
| Small DE pilot | 10,000 MAU; 40% relevant need; 20% of those click; 4% order | €20 commissionable basket; 11% rate; 90% approved; 80% attribution survival | **€50.69/month** |
| Larger manga audience | 50,000 MAU; 50% relevant; 25% click; 6% order | €25 basket; 11%; 92% approved; 85% attribution | **€806.44/month** |
| Strong-intent example | 100,000 MAU; 50% relevant; 25% click; 8% order | €30 basket; 11%; 95% approved; 90% attribution | **€2,821.50/month** |

The 11% is a currently published Thalia book rate, conditional on applicable accepted terms. **Every other input is an assumption**, and accepted basket basis is still unresolved. These rows change both audience and behavior; they are not a measured growth curve. Under the first row's unchanged assumptions, about 197,286 MAU would be needed for €1,000 monthly commission. Actual results could be substantially lower or higher. [A01, A02]

The lesson is not that affiliates cannot work. It is that a high headline percentage applied to occasional small purchases may generate little per active user. It can offset costs or become meaningful with a concentrated purchasing audience, but it does not justify a sprawling marketplace. Infrastructure, licensed data, labour, taxes, support and network costs are not deducted above.

**Ticket example:** At an assumed €50 net ticket and a 9% net presale fee, EVENTIM's 20%-of-fee rule yields €0.90, not €10. One hundred approved attributed sales would yield €90 under those assumptions. Actual event fees and eligibility control. [A12]

### Sponsorship contribution, without invented market prices

No verified source disclosed what Kuro could charge for a sample campaign. Negotiate only after measuring relevant reach and showing a useful asset. Price must cover creative/rights costs, delivery/measurement, sales and servicing hours, and a reasonable contribution toward the free product.

**Pure arithmetic example, not a market quote:** If a pilot were priced at €1,000 and took eight total hours at an assumed fully loaded €50/hour plus €150 for permitted assets/hosting/other variable costs, contribution would be €450 before general overhead and tax. At sixteen hours it falls to €50. If no sponsor buys it, revenue is zero. This is why contract scope and servicing effort matter as much as a sponsor logo.

Do not assume one campaign per month, continuing renewals or an advertiser's budget. Publisher revenue is concentrated and sales-led. A free sample linked without a sponsor may still help retention, but it is not monetization until a commercial relationship actually exists.

### Costs to record before a decision

For each pilot record catalogue/image rights, mapping/edition maintenance, feed/link checking, privacy/measurement implementation, accessibility, content production, account management, support, refunds/reconciliation, and ordinary infrastructure. Separate one-time setup from recurring costs. Report **incremental contribution** and overall product sustainability separately; a positive campaign does not mean Kuro as a whole is profitable.

## 9. Application to Kuro and a bounded sequence

This mapping uses local source and canonical documents read during this initiative and the immediately preceding pass. It is not a signed-in simulator test, remote database check, production audit or authorization to change live flags.

| Existing local capability | What the evidence changes | First evaluation |
|---|---|---|
| Collection card/list +1 controls already exist | Native speed is table stakes; findability, confirmation and recovery are the questions | Update current titles, rapid taps, undo, background/reconnect and seasonal views |
| Concierge AniList import preview/confirmation | Do not duplicate a flow; assess preservation and explanation | Missing dates/coverage, duplicates, unresolved fields, export and connector direction |
| AddToListSheet progress logic uses a known maximum for visibility | Unknown-total manga is a specific source-review candidate | Validate actual ongoing manga journey before declaring a shipped defect |
| Taste Deck and editorial discovery | Keep identity; test optional onboarding, contextual seeds and more-results path | Time to first value and a title actually tried later |
| Adaptation/relationship tools and title detail | Grouping needs exact underlying identity | Complex franchises, inherited progress, false matches and continuation clarity |
| Search/Browse filters | Existing power may be hard to reach | Own-list versus catalogue search, include/exclude, alias and device parity |
| Private clubs, polls and privacy levels | Preserve the useful social niche | Member understanding, shared boundary, spoiler safety; no sponsor access |
| Staged provider availability | Accurate region/language remains a data prerequisite | Keep staged status until source, cost and permission strategy is resolved |
| AniList-sourced catalogue | Monetization requires actual rights scope | Owner review of agreement and allowed storage/commercial distribution |

The source locations reviewed include `Kuro/Views/EditorialCollectionComponents.swift`, `Kuro/Views/AddToListSheet.swift`, `Kuro/Views/ConciergeView+AniListImport.swift`, `Kuro/Services/SupabaseService.swift`, `Kuro/ContentView.swift`, and the three canonical state/plan documents. A source pattern is a candidate to test, not a claim about every live user's behavior. No application source was changed by this research.

### Phase 1 — Validate the trust and daily-use foundation

Evaluate D02–D05, D07, D10 and D17 against the existing app. Prioritize failures that lose/misrepresent history, block unknown-total progress or require inaccurate status changes. Establish basic task and return-use baselines. Add no commercial interruptions. Run the data-permission review in parallel as a separate owner responsibility.

### Phase 2 — Prove better choosing and keeping up

Test franchise grouping, useful contextual discovery with optional depth, first-use recognition, release relevance and catalogue correction intake. Preserve existing Taste Deck/editorial/clubs value. Avoid broad social expansion, general inventory and universal two-way sync before the core behavior and maintenance capacity are proven.

### Phase 3 — One approved commerce pilot

Choose one country and a limited set of verified physical editions. Confirm exact merchant/app/data permissions. Offer neutral next-volume help only when requested; include clean non-affiliate choices. Measure correct-item task success and approved commission with a no-commerce comparison group. Do not extend the pilot simply because a merchant feed contains millions of products.

### Phase 4 — One useful publisher-funded experiment

Only after measurable reach and a partner agreement, test a licensed sample or small resource kit with bounded production cost. Keep organic recommendations and personal surfaces independent. Pursue business widgets or research services only if a specific paying customer validates a repeatable need; neither is authorized implementation in this report.

## 10. Validation plan: fill the gaps forums cannot answer

Desk research identifies candidate problems and design constraints. It cannot establish Kuro's conversion, incidence of competitor bugs, target segment size, catalogue overlap, willingness to use commerce, or a partner's willingness to pay.

### Recruit for differences, not only enthusiastic power users

Start with a proposed 16–20 moderated participants across returning/casual, seasonal, manga-first and established-library users, with overlap allowed. Include at least a few people who abandoned tracking and users with accessibility needs. Choose launch-country/language coverage deliberately. This is a practical discovery sample, not a statistically representative survey. Ask for real workflows and voluntary example titles; do not require private notes or account credentials.

| Task | What to observe | What would change the decision |
|---|---|---|
| Resume and update a current title | Time, mistaken entry, confirmed saved state, ability to undo | Existing flow already succeeds; improve specific friction rather than rebuild navigation |
| Isolate this season without changing status | Understanding of collection view vs record state | Users still move shows to Dropped or cannot locate older in-progress titles |
| Restore a remembered history / import a file | Wrong matches, unknown dates, missing titles, effort to resolve | Loss of fields or silent omissions block migration rollout |
| Log volume-only or unknown-total manga | Unit comprehension, preserved values, correct filters | Anime-shaped assumptions still hide or mislabel progress |
| Start manga after an anime / partial reread | Bookmark versus actual consumption | Inflated statistics or confusing advanced controls require model/UX revision |
| Find a title by another name; exclude a theme | Alias matching, visible criteria, pagination and reset | Hidden controls or failed loads masquerade as absent catalogue coverage |
| Choose tonight from a selected mood/list | Explanation usefulness, need for deeper results, later trial | More clicks without a worthwhile title does not validate discovery |
| Follow a relevant release | Correct region/language/date, notification relevance | Wrong or duplicate alerts outweigh convenience |
| Choose the next physical volume | Correct ISBN/edition, total cost, neutral choice, return state | Wrong-edition risk or confusing disclosure stops commerce |
| Use a sponsored sample | Who paid, usefulness, ability to ignore, impact on core task | Users mistake it for an independent recommendation or core use worsens |
| Share inside a club | Prediction of what is shared and spoiler boundary | Misunderstood privacy blocks social or partner expansion |

### Small catalogue benchmark

With permitted source access and voluntary real-library examples, construct a proposed 100-title test set covering mainstream anime, split seasons, alternate adaptations, ongoing and obscure manga, one-shots, manhwa/manhua, alias-heavy works, volumes/omnibus editions and intentionally scoped Western webtoons. This benchmark was **not run** in this research. Report correct coverage, successful identity match and freshness separately; record why misses occur. A huge vendor count cannot substitute for this exercise.

### Pilot measurement and stopping rules

For product changes: task success/error rate, time to durable update, successful reconciliation, false matches, recovery effort, and 7/28-day return. For discovery: a useful chosen title and later consumption, not endless swipes. For commerce: correct product found, broken/wrong links, user trust, settled attributable commission and incremental cost. For sponsors: useful asset engagement, explicit recognition of sponsorship, hides/complaints and contribution after servicing.

Do not invent significance from a small pilot. Set noninferiority margins and a sample plan after measuring baseline behavior. Stop immediately for silent history corruption, undisclosed paid ranking, unauthorized private-data disclosure or affiliate-induced wrong-progress changes. Investigate sustained increases in wrong-edition complaints, core-task failure or notification fatigue before expansion.

### Open decisions for an implementation initiative

Confirm initial launch countries/languages, primary segment, available catalogue/image permissions, willingness to operate a corrections queue, edition-data sources and budget. Measure actual product costs and reach. Then validate merchant placement and a specific sponsor proposition. These are decision inputs; this report does not contact partners, enroll programmes, approve spending or start implementation.

## 11. Evidence register

All sources were accessed during this research on 25 September 2026 or retained from the directly preceding pass the same day. Source IDs are clickable in the PDF; titles link to the original page. Dates below identify publication, review update, explicit issue update or approximate displayed age. **Undated official references and older live agreements are not fresh user testimony.** No public post is a confirmed population statistic. Hosting domains count platforms such as Reddit once; many subreddits are not presented as different websites.

### MyAnimeList communities and official app references

**M01 — Is there any chance of UI rework?**

[Original source](https://www.reddit.com/r/MyAnimeList/comments/1vt45n2/is_there_any_chance_of_ui_rework/) · **Date:** 2026-08-20 (indexed exact post date) · **Type/access:** Community discussion: r/MyAnimeList; Direct public thread and replies via web.open, accessed 2026-09-25

A user describes hidden seasonal sorting and overloaded mobile menus, but replies explicitly defend dense old-style desktop design and report no navigation difficulty. Another wants date displayed as a list column. Functional findability and compact presentation should be tested separately from aesthetic modernization. **Boundary:** Self-selected preferences, not a consensus or hands-on feature audit. No maintainer resolution observed.

**M02 — What would your perfect anime app actually look like?**

[Original source](https://www.reddit.com/r/MyAnimeList/comments/1te7tuo/what_would_your_perfect_anime_app_actually_look/) · **Date:** 2026-05-15 to 2026-05-20 (indexed discussion dates) · **Type/access:** Community discussion: r/MyAnimeList; Direct public thread and replies via web.open, accessed 2026-09-25

Participants report MAL app redirects for cast/information and ask for a whole-series view instead of managing many season entries. Social preferences conflict: some want community, others less social, and one says AniList already satisfies their needs. Supports franchise grouping and optional social without flattening exact histories. **Boundary:** Prompted wishlist thread; possible builder bias. Streaming-player wishlists excluded. An AniList-app claim is ambiguous between website/PWA/community clients.

**M04 — Recommendations for a FOSS anime tracking app?**

[Original source](https://www.reddit.com/r/animeapp/comments/1usi8z2/recommendations_for_a_foss_anime_tracking_app/) · **Date:** 2026-07-10 (indexed exact post date) · **Type/access:** Community discussion: r/animeapp; Direct public thread and replies via web.open, accessed 2026-09-25

A user requests current-season filtering and fast progress updates. To isolate this season they moved genuinely in-progress older titles to Dropped. This is a concrete workaround that distorts personal history, supporting seasonal collection views separate from canonical status. **Boundary:** Does not establish that every MAL interface lacks the filter. Replies recommend clients but no successful resolution is confirmed.

**M05 — Anime website or app for a watchlist**

[Original source](https://www.reddit.com/r/animeapp/comments/1uz5c8e/general_anime_website_or_app_for_a_watchlist/) · **Date:** 2026-07-17 (indexed exact post date) · **Type/access:** Community discussion: r/animeapp; Direct public thread and replies via web.open, accessed 2026-09-25

A returning fan reporting over 500 watched anime wants genre-based visual selection and one-click completed status rather than typing every name or seeing only popular titles. Follow-up questions concern account connection and sync. Supports optional bulk history reconstruction beyond file import. **Boundary:** Single detailed workflow, not prevalence evidence. Suggested clients were not verified to solve the batch task.

**M06 — It's 2025, and MAL still looks like it came out of the '80s**

[Original source](https://www.reddit.com/r/Animemes/comments/1ip9qor/its_2025_and_mal_still_looks_like_it_came_out_of/) · **Date:** 2025-02-14 to 2025-02-15 (indexed exact discussion dates) · **Type/access:** Community discussion: r/Animemes; Direct public thread and replies via web.open, accessed 2026-09-25

Replies under a design meme show strongly divergent preferences. Multiple users defend predictable sections, information density and performance; others prefer AniList or find MAL frustrating. This reinforces preserving a compact mode and testing actual task completion instead of assuming newer-looking design is better. **Boundary:** Humor community, selection bias and vote counts cannot establish market shares. Unverified API accusations excluded.

**M07 — Started Watching Anime a Year Ago**

[Original source](https://www.reddit.com/r/MyAnimeList/comments/1mehirb/started_watching_anime_a_year_ago/) · **Date:** Post 2025-07-31; relevant replies 2025-08-01 (indexed exact dates) · **Type/access:** Community discussion: r/MyAnimeList; Direct public thread and replies via web.open, accessed 2026-09-25

Notes-app users want half-point scores, whole-series ratings, chronological memories and detailed next/later categories. A large-list user values MAL's linked saved state, friends, authors and reviews and enjoys quick progress increments. Different list sizes and motivations change what counts as simplicity. **Boundary:** Five statuses satisfy another participant. Randomizer is clarified as third-party. Do not convert perceived rating pressure into a claim that rating is technically mandatory.

**M08 — What is wrong with mal app**

[Original source](https://www.reddit.com/r/MyAnimeList/comments/1o0d5rm/what_is_wrong_with_mal_app/) · **Date:** 2025-10-07 (indexed exact post date) · **Type/access:** Community discussion: r/MyAnimeList; Direct public thread and replies via web.open, accessed 2026-09-25

A Huawei user reports recurring connection errors; replies distinguish an SSL-type issue from a separate HTTP 500 report and discuss comparing browser access. Another person reports no problem. This supports accurate error states and preservation of useful cached history during failures. **Boundary:** No maintainer-confirmed root cause or global scope. Historic incident and no verified resolution; not evidence of a current outage.

**M09 — myanimelist tracking search not working?**

[Original source](https://www.reddit.com/r/mangapiracy/comments/1wbqy3o/myanimelist_tracking_search_not_working/) · **Date:** 2026-09-09 to 2026-09-10 (indexed dates and relative ages) · **Type/access:** Community discussion: r/mangapiracy; Direct public thread and replies via web.open, accessed 2026-09-25

OP explicitly identifies Mihon stable: MAL search fails while updates to an already-linked series work; MangaUpdates search works and reauthentication did not help. Search, identity mapping and progress writes need independently visible health and recoverable errors. **Boundary:** Third-party integration, not official MAL app. Root cause unresolved and no reading or piracy workflow recommendation is made.

**M11 — MyAnimeList Official — Romanian App Store**

[Original source](https://apps.apple.com/ro/app/myanimelist-official/id1469330778) · **Date:** Review 2025-07-13 · **Type/access:** Official store customer review; Direct store page read via web.open, accessed 2026-09-25

A recent reviewer values the official iOS app's compactness and easy list updating without needing the website. This is useful positive counterevidence: a utility-only segment already gets meaningful value from MAL, so new features should not obstruct that simple use. **Boundary:** One storefront review, not prevalence. Nearby 2021 manga-search complaint is out of period and excluded; do not compare regional overall star ratings as equivalent samples.

**M14 — MyAnimeList Official — US App Store baseline**

[Original source](https://apps.apple.com/us/app/myanimelist-official/id1469330778) · **Date:** Accessed 2026-09-25; displayed latest version dated 2024-03-08 · **Type/access:** Current official product listing; not recent sentiment evidence; Direct store listing via web.open

Official iOS listing advertises anime/manga progress, seasons, reviews, recommendations, friends and groups. Displayed privacy label includes tracking/advertising identifiers. Latest displayed iOS version is March 2024, while Android listing has a May 2026 update; platform maintenance claims need qualification. **Boundary:** Developer disclosure is not a privacy audit. Prominent 2021/2024 reviews excluded from recent sentiment. Do not infer MAL is abandoned across platforms.

### Anime-Planet, Kitsu, LiveChart, AniDB and independent forums

**F01 — Manga corrections are hard to submit; moderation capacity is limiting**

[Original source](https://www.anime-planet.com/forum/threads/make-it-easier-to-report-errors-and-add-manga.361849/) · **Date:** 24 September 2026 (HTML time attributes; UI Yesterday on Sep25). Two posts, user + database moderator. · **Type/access:** community forum; full thread directly via Codex in-app browser DOM, including moderator response.

user requests a report-error action and structured missing-manga form rather than copying a pinned forum template. Moderator added a cleaner template, says form has not been prioritized because volunteer developer time and poor-source submissions reduce expected value. medium-high for specific friction; hypothesis for Kuro: prefill title/ID, require source URL and changed value, retain status. Human review remains essential. No claim every A-P user has difficulty. **Boundary:** a small format improvement was delivered; no structured form promised. Moderator's claimed proportion of poor requests is anecdotal, not a measured research statistic.

**F02 — Site-rating sort exists on desktop but is hidden/absent on mobile**

[Original source](https://www.anime-planet.com/forum/threads/option-to-sort-my-anime-by-site-rating-currently-we-only-sort-by-personal-rating.361040/) · **Date:** 3–6 July 2026. Six posts. · **Type/access:** community forum; full direct browser thread.

user says Rating is misleading/useless on Want to Watch because it means personal rating. Reply points to AVG sorting in desktop table view. Another cannot find mobile version; third reports only exposing it by desktop-site plus landscape workaround. OP wants it in grid too. **Boundary:** not evidence feature entirely missing. Desktop capability is counterevidence; mobile inconsistency is reported, not independently interaction-tested.

**F03 — Start at manga chapter X; partial rereads and rewatches**

[Original source](https://www.anime-planet.com/forum/threads/add-a-started-on-chapter-xx-option-for-manga.360006/) · **Date:** 21 November 2025; replies 1 June and 5 July 2026. Three posts. · **Type/access:** community forum; full direct browser thread and machine dates.

OP loves time-spent stats but switched from One Piece anime to manga, reading one chapter after ~1000 caused past chapters to be counted. Reply wants reread tracking for only ~20 chapters/an arc. Another proposes reading/viewing instances and skipped-episode support, noting backend effort. **Boundary:** user request; no staff implementation commitment.

**F04 — Binge-ready filter request is partly an existing hidden feature**

[Original source](https://www.anime-planet.com/forum/threads/feature-request-recently-finished-aired-anime-filter.360722/) · **Date:** 14 May and 13 June 2026. Two posts. · **Type/access:** community forum; full direct browser thread.

OP wants completed-airing shows from Want to Watch; moderator explains Other already has Completed/Ongoing/Unreleased, combined with airing-date filters. Moderator says finished recently needs a defined time window. **Boundary:** high for confusion/counterevidence. Distinguish My status from Release status, surface Ready to binge as an optional shortcut built from precise filters. Do not report absent completed filter.

**F05 — Apparent lost list entries: developer suspects failed saves**

[Original source](https://www.anime-planet.com/forum/threads/items-getting-randomly-removed-from-my-list.360681/) · **Date:** 3–23 May 2026. Five posts. · **Type/access:** community forum; full direct browser thread.

user reports formerly watched/stalled entries now unwatched. Developer initially suggests merged duplicates, asks examples. After user supplies titles and re-adds them, developer checks feed and challenge tables and finds no prior mark; guesses timed-out save after tab switching/navigation might hide normal error alert. **Boundary:** **not confirmed deletion, not proved timeout root cause**, no deployed fix in thread.

**F06 — Per-title countdown and consolidated new-episode summary**

[Original source](https://www.anime-planet.com/forum/threads/feature-request-anime-episode-release-timer-with-notifications.360717/) · **Date:** 13 May 2026. One post, no reply. · **Type/access:** community forum; full direct browser thread.

requests exact next episode timer, alerts, and number of new episodes across tracked series since last check. **Boundary:** medium-low isolated request. Personal Upcoming with since-last-visit catch-up can reduce scanning. Benchmark LiveChart; do not invent region-specific availability from global airing.

**F07 — More privacy than everyone/only me**

[Original source](https://www.anime-planet.com/forum/threads/privacy-filter-filter-out-what-level-of-details-public-can-see-and-what-your-followers-or-people-youre-following-can-see.360619/) · **Date:** 18–21 April 2026. User + developer. · **Type/access:** community forum; full direct browser thread.

user wants friends/followers-specific fields; developer says following/followers privacy is something to investigate, per-status/list privacy not soon. **Boundary:** medium-high. Kuro club sharing fits need. Offer small number of understandable levels, not user's proposed sixty combinations. “Planned investigation” is not shipped.

**F08 — Mobile width/zoom breaks layout**

[Original source](https://www.anime-planet.com/forum/threads/mobile-site-width-issues.360373/) · **Date:** 26 February–26 March 2026. Same user two posts. · **Type/access:** community forum; full direct browser thread.

user tested multiple Android phones/tablet and browsers, reports horizontal overflow, image viewer pinch/next state shrinks underlying page; later offers browser-config workaround with tablet tradeoff. medium. Validate narrow widths, image-viewer exit, large text and orientation. This is concrete mobile ergonomics rather than subjective visual taste. **Boundary:** no staff fix in thread; user report not reproduced here.

**F09 — Exported missing dates are historic unknowns, not a bug**

[Original source](https://www.anime-planet.com/forum/threads/exported-anime-list-json-features-several-values-of-null-for-started-and-completed-dates.361630/) · **Date:** 6–7 September 2026. User + developer + user. · **Type/access:** community forum; full direct browser thread, marked Not a bug.

user sees many null started/completed dates in JSON export. Developer explains those fields were not tracked before 2016. User accepts explanation and thanks fast reply. **Boundary:** high. Preserve Unknown dates with provenance; never fill import timestamps as original watch dates. Counterexample to blaming every missing field on current data loss.

**F10 — Kitsu import requested because MAL manga coverage is incomplete**

[Original source](https://www.anime-planet.com/forum/threads/import-list-from-kitsu-io.360395/) · **Date:** 1 March 2026. One post. · **Type/access:** community forum; full direct browser thread.

user requests Kitsu import, says MAL lacks some manga entries, links Kitsu exports. No staff reply visible. **Boundary:** medium-low isolated demand. Report import coverage and unresolved titles; avoid forced intermediary formats that silently drop unsupported titles. Verify any integration's permissions separately.

**F11 — Kitsu advanced search reportedly stops pagination**

[Original source](https://github.com/hummingbird-me/kitsu-web/issues/2446) · **Date:** 21 February 2025; still marked Open when read. · **Type/access:** primary developer issue; primary GitHub issue page directly via web; body read, no reply visible.

reporter says advanced filters stop further result loading, removing filters sometimes restores it, attaches video (not watched). **Boundary:** medium report, not reproduced. Test filter + load-more + empty/failure states together, distinguish exhausted results from request failure.

**F12 — Kitsu “More info” can be a dead-end control**

[Original source](https://github.com/hummingbird-me/kitsu-web/issues/2447) · **Date:** 23 March 2026; Open when read. · **Type/access:** primary developer issue; primary GitHub issue directly.

enhancement asks not to render More info when no extra information exists; currently merely changes label to Less info according to reporter. **Boundary:** medium-low isolated report. Hide truly absent metadata sections or explain unavailable data; avoid actions that only animate a state without useful result.

**F13 — Kitsu password autofill leaks into search UI**

[Original source](https://github.com/hummingbird-me/kitsu-web/issues/2444) · **Date:** 24 January 2025; Open when read. · **Type/access:** primary developer issue; primary GitHub issue directly.

Firefox treats search bar as username after password page; autofill UI persists across navigation until reload. **Boundary:** medium-low unreplicated UI report. Test password-manager/browser autofill in real auth flows. Not evidence of credential disclosure or security breach.

**F14 — Kitsu status separates functional website from unavailable app-store components**

[Original source](https://status.kitsu.app/) · **Date:** page updated **25 September 2026 at 09:12 UTC**, read today. · **Type/access:** official service status; official current status page directly via web.

Kitsu Web operational; website/legacy API/GraphQL/CDN roughly 99.997–100% reported 30-day uptime. iOS App Store and Google Play components labelled downtime with 0% reported 30-day uptime. List Imports currently operational, AniList import component 91.542% reported 30-day uptime, MAL 99.915%. high official reported state, uncertain actual all-user experience. Keep component-specific health and independent access/export paths. **Boundary:** monitoring definitions not independently validated; do not equate app-store component downtime with all installed apps broken, entire Kitsu dead, or MAL's global uptime. Avoid quoting precision in executive brief.

**F15 — Kitsu network incident resolved; historical importer interruptions**

[Original source](https://status.kitsu.app/incident/719509?mp=true) · **Date:** incident opened 6 September 2025, aggregate updates through 2 April 2026; resolved network issue at 04:39 UTC April2. · **Type/access:** official incident timeline; official incident timeline directly via web.

short list-import component outages/recoveries and website/API network issue. Latest incident message says networking restored. **Boundary:** high official timeline, not ongoing incident. Queue/retry imports, expose provider-specific state, avoid discarding prior history when remote service fails.

**F16 — NeoGAF: MAL app friction vs website satisfaction**

[Original source](https://www.neogaf.com/threads/anime-manga-community.1463282/page-156) · **Date:** 14 January 2025, posts #7794–7795 (previous recommendation context read). · **Type/access:** independent community forum; full primary thread page directly via web; relevant posts and replies inspected.

one participant says MAL mobile app repeatedly causes issues; reply says they always use website and recommends seasonal/simulcast list. No concrete defect specified. **Boundary:** low for cause, useful counterevidence. Distinguish service from client. A premium native client may solve interface friction without requiring users to abandon incumbent history/community. Dynamic link previews show later seasons, **do not use preview year as post date**.

**F17 — Something Awful: independent tracking and backups as refuge during host churn**

[Original source](https://forums.somethingawful.com/showthread.php?noseen=0&pagenumber=6&perpage=40&threadid=4088618) · **Date:** 27–29 March 2026 (earlier page context read too). · **Type/access:** independent community forum; full primary forum page directly via web, multi-person reply chain read.

participant exports history for safety; another creates Anime-Planet + MangaUpdates history alongside app backups. Asked whether MangaDex list can import to A-P, replies only MAL/AniDB options were available and manually adds manga. Another describes raw CSV plus compatible XML export. Discussion concerns reader-host churn but these passages are specifically tracker portability, not a recommendation of reading sources. **Boundary:** same page corrects an unsupported paywall rumor; do NOT repeat that rumor as true. Import claim is a user's March check, not current hands-on verified capability.

**F18 — ResetEra: satisfied tracker user still needs discovery**

[Original source](https://www.resetera.com/threads/need-an-anime-suggestion-app.1301859/) · **Date:** 18 September 2025, eleven posts visible in indexed thread. · **Type/access:** independent community forum; search engine returned full thread and replies; direct web open errored. Label **indexed full-thread**, not direct.

OP says Trakt check-ins on iPhone work very well but fragmented streaming makes anime discovery hard; asks seasonal/history-informed suggestions. Replies recommend MAL, LiveChart genre/season browsing, AniList, Anime-Planet manga lists, and human discussion. OP later says suggested app is perfect for past/current seasons/top rankings. **Boundary:** existing products can satisfy needs. Users' AI-company descriptions are perceptions, not verified corporate facts. Do not identify which AniList client was chosen—it isn't named.

**F19 — LiveChart official Android capabilities**

[Original source](https://play.google.com/store/apps/details?id=me.livechart.android) · **Date:** official listing says updated 29 August 2025; read Sep25 2026. · **Type/access:** official app listing; official app listing directly via web.

local-time countdowns, earliest/sub/dub release schedules, per-anime schedule choice, legal links, multiple tracking statuses, hiding statuses, opt-in release reminders. Current what's-new mentions disabled external resource button appearance/UI fixes. high documented feature benchmark. Release tracking is already specialized; Kuro needs region/language/source clarity and restrained alerts. **Boundary:** featured reviews are 2023/2024 and **excluded from 2025–2026 sentiment evidence**. Store download count not active users/market share. Product claims not hands-on verified.

**F20 — LiveChart notification granularity**

[Original source](https://www.livechart.me/notifications) · **Date:** undated official reference accessed Sep25 2026 (not dated user evidence). · **Type/access:** official feature reference; official page directly.

release reminders follow selected schedules; separate scheduling notes include delay/premiere; new titles linked to favorites/franchises/list; partner giveaways have separate notification type. **Boundary:** distinguish utility notification consent from partner promotions. Do not bundle commercial alerts with episode reminders. Existing benchmark not unmet-gap proof.

**F21 — LiveChart guest history and scope limits**

[Original source](https://www.livechart.me/pages/faq) · **Date:** undated official reference accessed Sep25 2026; one catalogue section explicitly last updated 2018. · **Type/access:** official FAQ; official FAQ directly.

guest marks live in browser storage, cannot cross browsers and are lost on clearing; explicit import needed after signup. No public API offered, RSS available; FAQ says no iOS app. Older-anime coverage section may be stale. **Boundary:** guest mode must explain local save and offer account migration; do not promise a public API integration without permission. Treat iOS/coverage statements as documentation claims requiring launch-time check, not exhaustive app-store audit.

**F23 — Anime-Planet support/revenue boundaries**

[Original source](https://www.anime-planet.com/support) · **Date:** undated official page read Sep25 2026. · **Type/access:** official funding policy; full page direct in-app browser.

says few ad units and donations pay server/site costs; no ads in profiles, minimal elsewhere, no pop-under/in-text/intrusive formats. Volunteer development model is explicit. **Boundary:** high as published policy, not audited revenue. Protect personal library/edit/progress screens from monetization; contextual useful commercial discovery may fund part of service, but need real economics and no inference this funds a salaried team.

**F24 — AniDB official precise episode/file tracking model**

[Original source](https://wiki.anidb.net/Animeentries%3AMyList-Status) · **Date:** undated reference indexed and read Sep25 2026, not recent complaint. · **Type/access:** official documentation; search source page text; colon variant direct failed, encoded URL indexed accessible.

MyList separates entries present, seen episodes, and file state; unknown episode total represented as zero, specials separate. Warns statistics can lag DB update. **Boundary:** official model background. Distinguish progress, completeness and freshness; do not present unknown total as completed or zero-length.

**F25 — AniDB/Shoko bulk-sync default creates queue surprise**

[Original source](https://github.com/ShokoAnime/ShokoServer/issues/1294) · **Date:** 16 January 2026; marked Closed at read. · **Type/access:** primary developer issue; primary developer issue directly.

novice importing multi-TB library reports six-digit MyList job queue and requests opt-out/default deprioritization, already uses another scrobbler. Third-party Shoko configuration issue, not AniDB service outage. medium report. Optional automation should explain volume, priority and provider quotas; fast manual updates should not queue behind historical imports. **Boundary:** closed does not establish implemented/deployed fix; no closure rationale returned in retrieved text.

### Native clients and tracking integrations

**C01 — MyAnimeList Official, Google Play reviews**

[Original source](https://play.google.com/store/apps/details?id=net.myanimelist.app) · **Date:** 2026-08-14 (kyla); 2026-07-07 (I Love Anime 2); 2026-07-03 (Manish Pal). Page lists app updated 2026-05-25. · **Type/access:** User review / discussion; Direct full page, three visible user reviews; developer description distinguished from reviews.

Respectively: indefinite loading at first use; desire to organize a personal collection into groups and filter by genre; English-title search difficulty and desire for grouped seasons. Third reviewer also claims missing manhwa. **Boundary:** Two reviewers open positively. No developer reply or reproduction inspected. The manhwa claim is not verified and must not be stated as MAL’s factual catalogue policy. Do not use 2021/2024 iOS featured reviews as recent evidence.

**C02 — MyAniList, Apple public review feed (iOS AniList client; NOT MyAnimeList)**

[Original source](https://itunes.apple.com/us/rss/customerreviews/id=741257899/sortby=mostrecent/json) · **Date:** 2026-06-07 through 2026-09-20; Apple RSS updated timestamps (reviews may be edited) · **Type/access:** User review / discussion; Direct Apple JSON via HTTPS; 50 most-recent reviews, exact timestamps. Web text reader cannot parse feed; shell retrieved successfully.

Review sample includes recurring upgrade prompt, perceived lifetime entitlement dilution, sorting friction, unwanted dropped-title reminders, tag overload and sync complaints. **Boundary:** July26 review praises season-level tracking; many sampled reviews praise free tracking, organization and discovery. Individual claims are not reproduced. June sorting issue explicitly corrected, not an ongoing defect. Key Apple review IDs: 14572658199 (20 September upgrade-prompt complaint), 14229862861 (26 June sorting complaint), 14248083774 (30 June edited correction: fixed/free). Dates are updated timestamps.

**C03 — MyAniList changelog, provider/client repair**

[Original source](https://apps.apple.com/us/app/myanilist/id741257899?platform=ipad) · **Date:** explicit 2025-11-26 / 2025-12-12; 2026 releases dated Jun30, Jul15, Jul31 and September within current-year history. · **Type/access:** Official developer listing/release notes; Direct official release notes and listing.

2025 notes changed launch sync to fetch fewer updates. 2026 notes report fixes to background sync, login, sorting persistence, airing cues, notification reliability and VoiceOver support. Listed product offers native tracking, offline sync and social feeds. **Boundary:** Developer-reported fixes, not hands-on verification; notes show active maintenance, so do not portray every complaint as unresolved. Premium features exist; not Kuro’s proposed model.

**C04 — ManGo: manga coverage and portability**

[Original source](https://apps.apple.com/us/app/mango-anime-manga-tracker/id1604385869) · **Date:** 2025-05-17 review; 2025-02-10 review; current release notes Sep14 2026. · **Type/access:** User review / discussion; Direct app page plus Apple feed.

May reviewer wants dependable chapter totals and new-chapter notifications; February reviewer asks for public shareable profile and import/export. Sep14 developer notes report fixes for accidental widget completion, incomplete cached lists, secondary-service repeating status and expired login tokens. **Boundary:** Unknown total is not necessarily stale data for an ongoing manga. Current client advertises MAL/AniList support; do not repeat reviewer’s 2025 MAL-only framing as current architecture. Notes describe fixed bugs, not current universal defects.

**C05 — Kitsune for MyAnimeList: conflicting design preferences**

[Original source](https://apps.apple.com/us/app/kitsune-for-myanimelist/id6466716447) · **Date:** 2025-01-13 displayed review (RSS updated2025-01-12 PST); 2025-02-28; 2026-01-05 exact RSS timestamp confirmed · **Type/access:** User review / discussion; Direct App Store page and replies; Apple XML RSS independently confirms Jan5 review year. US JSON feed empty; XML successful.

January2025 reviewer wants hideable scores. January2026 reviewer wants scores prominent and status categories accessible by swiping. February2025 reviewer praises clean UI and voluntarily buying a small one-time customization upgrade. **Boundary:** Opposing score preferences refute a universal design answer. Developer requests details rather than confirming a delivered fix. Current listing says free AniList sync but some schedules/notifications are premium; “only cosmetics are paid” would be inaccurate. January 2026 score-visibility review verified in Apple XML feed, ID 13599357667, updated 5 January; this resolves the year ambiguity in the ordinary store display.

**C07 — AL-chan #169: rapid actions hit rate limits**

[Original source](https://github.com/zend10/AL-chan/issues/169) · **Date:** 2026-07-04; open on access. · **Type/access:** User review / discussion; Full issue and empty comments via official GitHub API; direct webpage checked.

Reporter says adding many seasonal shows rapidly causes API throttling and stops subsequent data loading; requests queued writes. **Boundary:** One technically informed user report; suggested design is not implemented proof or verified root cause.

**C08 — AL-chan #168: auxiliary notifications caused launch crashes, repaired**

[Original source](https://github.com/zend10/AL-chan/issues/168) · **Date:** 2026-03-26; replies through 2026-04-01; closed/completed, implemented label. · **Type/access:** User review / discussion; Full body and maintainer replies via GitHub API. Web page only exposes issue body.

Android15 crash tied to new notification types. Maintainer identifies fallback parsing/indexing fault and says crash is being fixed; fork developer reports release with repair. **Boundary:** Maintainer participated despite commenters alleging abandonment. Closed/implemented; do not call it a current unpatched bug or AniList database failure.

**C09 — AL-chan #166: cached list survives data outage**

[Original source](https://github.com/zend10/AL-chan/issues/166) · **Date:** 2025-09-28; closed/completed on access. · **Type/access:** User review / discussion; Direct issue and GitHub API, no comments.

Reporter saw fetch error but explicitly says anime list loaded from cache. **Boundary:** Cause and fix not documented; cached fallback worked sufficiently to display the list. Closure alone does not identify shipped version.

**C10 — MALClient #357: calendar empty**

[Original source](https://github.com/Drutol/MALClient/issues/357) · **Date:** 2025-06-20; replies 2025-07-08; open on access. · **Type/access:** User review / discussion; Full body/comments via official GitHub API; page checked.

Calendar no longer loads current anime. Reply offers force-stop workaround; reporter confirms it worked. **Boundary:** Workaround does not establish root cause or general fix. It is MALClient, not MAL’s official app.

**C11 — MALClient #360: broken title details and maintenance anxiety**

[Original source](https://github.com/Drutol/MALClient/issues/360) · **Date:** 2026-08-01; replies Aug4 and Aug28; open on access. · **Type/access:** User review / discussion; Full body/comments via GitHub API; page checked.

User reports images, synopsis and favorites missing while other app functions still work. Asks if app abandoned. A fork maintainer claims repair after changing data integration; another user thanks them. **Boundary:** Store removal and fork completeness are user claims, not independently validated. People still call the app their preferred MAL client.

**C12 — MALSync #4148: wrong-title detection on Crunchyroll**

[Original source](https://github.com/MALSync/MALSync/issues/4148) · **Date:** 2026-08-12; maintainer Aug18; further user report Sep1; open on access. · **Type/access:** User review / discussion; Full body/comments via official GitHub API; webpage checked.

Wrong-show matching and correction complaints. Another user identifies added “Season 1” search suffix. Maintainer reports removing the first-season label and notes inconsistent provider data. Subsequent Hulu report exists. **Boundary:** Partial code change reported; cannot claim all detection fixed or a universal backend outage. Initial reporter says manual matching can persist, another says reuse behavior depends on closing search.

**C13 — MALSync #4137: auto-progress complaint withdrawn after further testing**

[Original source](https://github.com/MALSync/MALSync/issues/4137) · **Date:** 2026-08-05–06; closed/completed. · **Type/access:** User review / discussion; Full GitHub API issue and comments.

Reporter originally alleges progress advances without watching; maintainer cannot reproduce. Reporter later attributes behavior to interaction with other extensions/adblockers and closes issue. **Boundary:** Explicitly withdrawn as a standalone tracker defect. This record exists to prevent overstating automation evidence.

**C14 — MAL mobile information demand, not streaming**

[Original source](https://www.reddit.com/r/animeapp/comments/1vhcnqq/mal_client_app_like_anilist_ones/) · **Date:** search index explicitly 2026-08-06; direct thread uses relative age. · **Type/access:** User review / discussion; Full thread read; exact initial date from indexed record.

OP wants MAL reviews/recommendations/interest stacks in better native client; doesn't need community/forums. Reports irrelevant past-season notifications in DailyAL and rejects streaming-client substitution. Kiko developer says reviews added, stacks planned; OP acknowledges improvement. **Boundary:** Development claims not app-tested. OP preference is not all users’ preference. Shows improvement during discussion.

### MangaBaka, manga readers and specialist workflows

**G01 — Progress totals became harder to see after a redesign**

[Original source](https://mangabaka.org/forum/mangabaka/3-bring-back-0-x-and-x-x-for-chapters-volumes-read) · **Date:** approximately 17 September 2026; displayed 1 week, 19 hours on access; screenshot filenames also contain 2026-09-17. · **Type/access:** tracker-owned forum; opening post and status directly read; comments not loaded.

contributor reports that the newer UI shows current/total only for in-progress works, whereas the prior UI also displayed zero/total and complete/total. Asks for an optional setting, acknowledging others may prefer the simpler display. Status: **Considering**. retain explicit progress information in accessible detail and test compact versus information-rich cards. Do not use decorative progress shapes as the only signal. **Boundary:** Opening post and status read; comments did not load. Dates approximate from relative labels on 2026-09-25. Request does not establish community consensus.

**G02 — Home page clutter**

[Original source](https://mangabaka.org/forum/mangabaka/23-customize-home-page) · **Date:** approximately 19 September 2026 (displayed 5 days, 24 hours). · **Type/access:** tracker-owned forum; opening post directly read; comments not loaded.

user wants to hide unneeded home sections, change row counts, and optionally bring useful stats or followed creators forward. Current workaround is moving between menus. Status: **Considering**. strong default “Continue” area plus optional visibility controls later; do not build a full dashboard editor before testing whether one prominent primary action solves most friction. **Boundary:** Opening post and status read; comments did not load. Dates approximate from relative labels on 2026-09-25. Request does not establish community consensus.

**G03 — Recommendation results can be too limited**

[Original source](https://mangabaka.org/forum/mangabaka/69-view-more-results-for-mixes) · **Date:** approximately 23–24 September 2026 (displayed 1 day, 13 hours). · **Type/access:** tracker-owned forum; opening post directly read; comments not loaded.

Mix recommends from chosen seed series but returns at most 24 results; user asks for pagination or more results ordered by relevance. Status: **Considering**. small curated defaults should have an optional deeper exploration path. This is counterevidence to imposing a universal tiny recommendation ceiling. **Boundary:** Opening post and status read; comments did not load. Dates approximate from relative labels on 2026-09-25. Request does not establish community consensus.

**G04 — Recommend from this list, not my entire history**

[Original source](https://mangabaka.org/forum/mangabaka/21-custom-list-based-recommendations) · **Date:** approximately 19 September 2026 (displayed 6 days, 6 hours). · **Type/access:** tracker-owned forum; opening post directly read; comments not loaded.

request to seed recommendations from a custom list and quickly add the list to Mix. Status: **Considering**. let users narrow intent to “more like these” or a chosen collection. A whole-library taste profile can mix unrelated moods, eras, and purposes. **Boundary:** Opening post and status read; comments did not load. Dates approximate from relative labels on 2026-09-25. Request does not establish community consensus.

**G05 — Follow creators and distinguish their identities**

[Original source](https://mangabaka.org/forum/mangabaka/22-author-page-and-following-them) · **Date:** approximately 19 September 2026 (displayed 6 days). · **Type/access:** tracker-owned forum; opening post and status directly read; comments not loaded.

user describes mixed/unreliable author results and manually checking favorite creators for new works. Wants dedicated creator pages and new-work alerts. Status: **Planned**. creator follow alerts are a manga-relevant discovery hypothesis after identity quality is adequate. Do not send alerts from name-only matches; author pseudonyms and same-name people need canonical identities. **Boundary:** Opening post and status read; comments did not load. Dates approximate from relative labels on 2026-09-25. Request does not establish community consensus.

**G06 — Different publisher descriptions and chapter notes**

[Original source](https://mangabaka.org/forum/mangabaka/30-allow-mb-to-store-multiple-descriptions-from-different-offic) · **Date:** approximately 20 September 2026 (displayed 5 days, 3 hours). · **Type/access:** tracker-owned forum; opening post directly read; comments not loaded.

request to store multiple official publisher descriptions because localized titles/descriptions differ, while preserving important chapter-count notes across the description switch. Status: **Planned**. retain provenance and edition/language distinctions. Do not overwrite source descriptions with a single untraceable generated summary. A concise display can sit above expandable source detail. **Boundary:** Opening post and status read; comments did not load. Dates approximate from relative labels on 2026-09-25. Request does not establish community consensus.

**G07 — Missing protagonist filters despite many tags**

[Original source](https://mangabaka.org/forum/mangabaka/64-why-is-there-no-genre-tag-to-differentiate-who-the-protagoni) · **Date:** approximately 22 September 2026 (displayed 2 days, 17 hours). · **Type/access:** tracker-owned forum; opening post directly read; comments not loaded.

user cannot find direct male/female protagonist filtering despite related demographic/orientation tags. Status: **Pending**. use the language readers actually search with. Audience demographic, creator identity, protagonist identity, and story genre are not interchangeable. This is a candidate taxonomy audit, not a mandate to infer personal identity. **Boundary:** Opening post and status read; comments did not load. Dates approximate from relative labels on 2026-09-25. Request does not establish community consensus.

**G08 — Partial import, issue marked done**

[Original source](https://mangabaka.org/forum/mangabaka/72-import-export) · **Date:** approximately 24 September 2026 (displayed 1 day, 3 hours; closed about 18 hours before access). · **Type/access:** tracker-owned forum; opening post and status directly read; resolution explanation unavailable.

user reports 53 of 119 works imported through an intermediate service, and is unsure whether the earlier intermediary import lost entries. Status: **Done**. compare source counts at every migration step and preserve unmatched rows. Do not blame MangaBaka definitively; cause is ambiguous and the issue is closed. A reconciliation receipt is more valuable than a bare “import successful” toast. **Boundary:** Opening post and status read; comments did not load. Dates approximate from relative labels on 2026-09-25. Issue marked Done, cause/fix not independently verified.

**G09 — Chapter-only logic misread volume progress, issue marked done**

[Original source](https://mangabaka.org/forum/mangabaka/63-zero-progress-filter-includes-series-where-volumes-have-been) · **Date:** approximately 22 September 2026 (displayed 2 days, 19 hours; closed about 2 days before access). · **Type/access:** tracker-owned forum; opening post and status directly read; resolution explanation unavailable.

series with nonzero volume progress but zero chapter progress were included in a “zero progress” filter. Status: **Done**. all library filters, stats, completion logic, and exports must respect both tracking units. This is evidence of a class of modeling error, not a claim of an ongoing MangaBaka bug. **Boundary:** Opening post and status read; comments did not load. Dates approximate from relative labels on 2026-09-25. Issue marked Done, cause/fix not independently verified.

**G10 — Missing Western webtoons and coverage-policy confusion**

[Original source](https://www.reddit.com/r/webtoons/comments/1ugj84f/is_there_seriously_no_decent_app_to_track_what/) · **Date:** 26 June 2026, with later replies. · **Type/access:** community thread; post and substantive replies directly read; exact original date from search result.

reader tried MAL, AniList, Kenmei and MangaBaka, but could not immediately track all desired webtoons. In replies, a Kenmei-associated account says it has most Webtoon Originals except original English-language works; the poster clarifies Western originals are precisely the gap. Other users suggest private spreadsheets and submissions. **Boundary:** Poster corrected scope to Western originals; do not repeat claim Kenmei lacks most Originals or assume an unrestricted Webtoon API exists.

**G11 — One-way sync breaks a multi-device workflow**

[Original source](https://www.reddit.com/r/animeapp/comments/1viqnmd/any_manga_reading_app_that_supports_two_way/) · **Date:** 8–10 August 2026. · **Type/access:** community thread; full substantive text in search result; post and replies inspected there.

a reader updates MangaBaka after reading on PC and wants the Android reader to receive those changes. They report moving trackers to get their desired workflow. This is one user, not retention statistics. name the sync direction plainly and protect against overwriting a newer remote value. Two-way support needs conflict behavior and a repair path, not merely two API calls. **Boundary:** One user; cross-post in r/mangapiracy is the same incident, not an independent source. Official Mihon docs corroborate one-way behavior.

**G12 — Upcoming physical releases: source discovery, not spreadsheet software**

[Original source](https://www.reddit.com/r/MangaCollectors/comments/1uedu6h/how_do_you_keep_track_of_upcoming_manga_releases/) · **Date:** 24 June 2026. · **Type/access:** community thread; post and substantive replies directly read; exact date from search.

collector already has a spreadsheet, but retailer publisher filtering and inconsistent publisher calendars make finding future editions laborious. They want months-ahead data to prepare preorder purchases. Replies point to distributor/retailer calendars; OP marks the question resolved. Other participants describe duplicate preorders. **Boundary:** OP marked issue resolved via source suggestions. Affiliate opportunity is inference, not verified programme availability or economics.

**G13 — Completion is not the same as translation completion**

[Original source](https://www.reddit.com/r/mangapiracy/comments/1s487ln/lost_while_looking_for_manga_infodata/) · **Date:** 26 March 2026. · **Type/access:** community thread; post and substantive replies directly read; date from search.

reader cannot tell whether a niche manga is finished, on hiatus, abandoned, or merely untranslated. They see inconsistent counts and stale copied metadata. Replies recommend MangaUpdates/MangaBaka and title-specific original-language sources. separately label original publication status, latest verified original unit, available translated unit and language, and timestamp/source. Unknown stays unknown; a lack of recent translated chapters is not automatic hiatus. **Boundary:** Qualitative, purposive sample; not prevalence or market-share evidence.

**G14 — Rich metadata is a strength worth preserving**

[Original source](https://www.reddit.com/r/BoysLoveAnime/comments/1mci8ay/you_should_use_mangaupdates_a_search_engine_with/) · **Date:** 29–31 July 2025; one search-discoverability follow-up 28 March 2026. · **Type/access:** community thread; substantive post and replies in search result, not full page direct.

users praise MangaUpdates for highly specific tags, alternate/localized names, creator work lists, licensing information, sequel relationships and chapter/season details. One wants more nuanced peer reviews beyond content-warning tags. Later reply complains that general search engines surface unrelated sites instead. simplify entry paths without erasing specialist metadata. Alias-aware search, creator identity, licensing and explicit content notes solve different needs from a numeric rating. **Boundary:** Search-indexed substantive text; no full direct-page read. Positive qualitative evidence, not objective catalogue benchmark.

**G15 — Personal organization is sometimes enjoyable**

[Original source](https://www.reddit.com/r/Manhwa_BL/comments/1tcd2fq/250_titles_already_read_out_of_1300_titles_on_my/) · **Date:** 13 May 2026. · **Type/access:** community thread; post and replies directly read; exact date from search.

readers build rich spreadsheets, relationship/trope categories and personal summaries, and explicitly enjoy it. One asserts MangaUpdates cannot place a work in multiple lists, qualified “AFAIK”; this was not verified as a current product limitation. Others find maintaining tags tedious. default a fast path, but allow optional personal tags, notes, multiple collections and visual preference. Do not assume removing all organization effort improves every reader's experience. **Boundary:** Unverified commenter claim about MangaUpdates multiple-list constraint is not established product fact. Several users enjoy manual organization.

**G16 — List sharing exists but users do not discover it**

[Original source](https://www.reddit.com/r/Manhwa_BL/comments/1tng5c0/please_enlighten_me/) · **Date:** 25 May 2026. · **Type/access:** community thread; post and replies directly read; exact date from search.

reader with hundreds of completed/planned/waiting-for-completion works wants a visual shareable library because Notion entry is too laborious. After being told existing trackers support public lists, they say they had used MangaUpdates only for lookup. make sharing a simple optional output of an existing collection rather than forcing duplicate manual entry. Privacy defaults and progress disclosure must remain explicit. This is a discoverability problem, not absence of public list features. **Boundary:** Qualitative, purposive sample; not prevalence or market-share evidence.

**G17 — Chapter-first readers do manual volume conversion**

[Original source](https://www.reddit.com/r/TheStoryGraph/comments/1pusuig/anyone_tracks_the_manga_chapters_from_manga_app/) · **Date:** 24–25 December 2025; later follow-up present. · **Type/access:** community thread; substantive post/replies in search result; source also existed in earlier report.

readers of official chapter apps describe waiting for volume publication, finding chapter-to-volume boundaries and editions, and backdating entries; others keep manga in AniList/MAL instead of StoryGraph. chapters and volumes need separate progress entry. Offer reliable conversion only when the edition-specific mapping is known; never silently assume a fixed chapters-per-volume ratio. Preserve partial dates rather than fabricate reading days. **Boundary:** Search-indexed substantive text. Already included in prior report; deduplicate.

**G18 — Official integration contract: one-way is intentional**

[Original source](https://mihon.app/docs/guides/tracking) · **Date:** current documentation read 25 September 2026; page does not expose a stable publication date. · **Type/access:** official documentation; directly read primary documentation.

Mihon documents one-way updates to trackers, offline progress synchronization when connectivity returns, per-series tracker linking, privacy only for supported services, and a separate class of enhanced self-hosted services with two-way local chapter syncing. It suggests alternate titles or a direct MAL ID when search cannot find a work. **Boundary:** Current primary documentation, undated; not an independent user complaint or hands-on test.

**G19 — Official recent fixes demonstrate edge-case importance**

[Original source](https://mihon.app/changelogs/) · **Date:** 4 August 2025 through 5 August 2026, individual releases dated. · **Type/access:** official documentation; directly read primary changelog.

Official 2025–2026 release notes describe improvements to migration, notes, large libraries and identity matching, plus fixes for duplicate-chapter restore loss, MangaUpdates HTTP failures and partial MAL dates. MangaBaka tracker support was added in July 2026. These are documented implemented fixes and enhancements, not evidence of currently unresolved defects. **Boundary:** Keep combined paraphrase across all use of this source within 200 words. Fixed cases, not current bugs.

**G20 — Community-led discovery has a clear process**

[Original source](https://mangahelpers.com/forum/threads/manga-club-collective-reading-06-round-end.3033650/) · **Date:** thread started 13 February 2025; round plan edited 2 March 2025. · **Type/access:** community thread; opening post and multiple discussion replies directly read.

A small collective reading club nominates lesser-known works with reasons, votes, reads at a shared minimum pace and protects discussion beyond that point with spoiler rules. The poll shows 11 voters. This observed workflow supports testing nomination, rationale, milestones and spoiler boundaries; it does not establish demand for a new public social network. **Boundary:** Small voluntary group; observed workflow, not market-wide demand. Thread starts February 13, not February 14.

**G21 — Coverage comparisons disagree**

[Original source](https://www.reddit.com/r/mangapiracy/comments/1itepri/best_manga_tracking_site/) · **Date:** 19 February 2025 (indexed date and Reddit archive date). · **Type/access:** community thread; post and substantive replies directly read.

original poster values database breadth, organization, obscure works, one-shots and a modern UI. Replies favor different trackers: some praise AniList breadth, while another says MAL contains manga missing from their AniList migration. MangaUpdates is praised for niche metadata while criticized as dated. One commenter incorrectly doubts it has tracking; other observed use contradicts that. **Boundary:** Replies disagree about catalogue breadth; do not report subjective ranking or false claim MangaUpdates has no tracking as product facts.

**G23 — MangaBaka proposition**

[Original source](https://mangabaka.org/) · **Date:** current product page read 25 September 2026; undated. · **Type/access:** official product page; directly read.

broad manga/manhwa/manhua/novel/OEL coverage, chapter and volume tracking, notes, imports and exports, flexible card/list layouts and library-based recommendations. Its “300,000+” count is a vendor catalogue claim, not our independently deduplicated benchmark. Sources retain ownership of upstream data. Kuro cannot differentiate just by saying clean, personalized and portable. Those promises already exist; execution and a chosen audience must be tested. **Boundary:** Vendor product claims; catalogue count not independently benchmarked. Undated current reference.

**G24 — Aggregation does not eliminate freshness or rights dependencies**

[Original source](https://mangabaka.org/data/api) · **Date:** current docs read 25 September 2026; undated. · **Type/access:** official documentation; directly read.

upstream metadata providers are named; per-title refresh is described as minimum one day and maximum seven days. Schema is not yet guaranteed stable, and metadata corrections are directed upstream. assess provenance, freshness, schema stability and permitted downstream use per provider before treating any aggregator as an independent unrestricted data source. This is an integration diligence point; no legal compliance conclusion about Kuro or MangaBaka is made. **Boundary:** Current primary documentation, undated. Does not establish permission to reuse upstream metadata commercially.

### Affiliate programmes and practical commercial terms

**A01 — Thalia official partner program**

[Original source](https://www.thalia.de/vorteile/partnerprogramm) · **Date:** Undated live page; accessed 2026-09-25 · **Type/access:** official merchant program; Full text fetched

Books 11%; non-price-bound books with coupon 8%; 30-day attribution; application requires approval; daily product data. **Boundary:** Commissionable gross/net basis not established by public page. Publisher native-app traffic approval unknown. DE terms do not automatically cover AT/CH.

**A02 — Thalia DE Awin merchant profile 14158**

[Original source](https://ui.awin.com/merchant-profile/14158) · **Date:** Undated live page; accessed 2026-09-25 · **Type/access:** official affiliate network merchant profile; Full text fetched

Corroborates 11% books, 8% non-price-bound books with coupon, 30-day window, product feed and App-Tracking; cashback barred on coupon transactions. **Boundary:** App-Tracking can describe merchant-app attribution; it does not establish Kuro native-app publisher eligibility. Accepted commission base and exclusions require contract verification.

**A03 — Amazon DE standard commission schedule**

[Original source](https://partnernet.amazon.de/help/node/topic/GRXPHT8U84RAYDXZ) · **Date:** Current published schedule; accessed 2026-09-25 · **Type/access:** official merchant rate schedule; Full text fetched

German books rate currently 4.5%, not old third-party 7%; Blu-ray/DVD 6%, toys 3%. Rate applies to contractual qualifying revenue. **Boundary:** Qualifying revenue deductions defined in policies; school-linked entity exceptions; category/territory and accepted account terms govern.

**A04 — Amazon DE Associates program policies**

[Original source](https://partnernet.amazon.de/help/operating/policies) · **Date:** Updated 2026-04-14; accessed 2026-09-25 · **Type/access:** official contractual policies; Full text fetched

Qualifying revenue excludes shipping, taxes, fees, credits/rebates and other enumerated deductions. 24-hour session can terminate earlier; qualifying cart completion within 89 days. Approved free original-content mobile apps, permitted linking tools and no Amazon WebViews required; user-level subtags prohibited. **Boundary:** Kuro approval unverified; returns/refunds excluded. Native app eligibility does not by itself settle Apple rules for outbound digital purchases. Limit derivation from this page to 200 words in final report.

**A05 — Amazon US standard rates and bounty events**

[Original source](https://affiliate-program.amazon.com/help/node/topic/GRXPHT8U84RAYDXZ) · **Date:** Current published schedule; accessed 2026-09-25 · **Type/access:** official merchant rate schedule; Full text fetched

Physical books 4.5%; eligible Prime Video free trial $2, add-on subscription trial $2.50 and paid $3. Eligibility-specific actions, not every click/subscriber. **Boundary:** US values only. Do not apply to Germany. No account approval or native digital-link compliance verified. Bounties optional secondary route, not modeled baseline.

**A06 — Bookshop.org affiliate program explanation**

[Original source](https://support.bookshop.org/en/support/solutions/articles/65000191390-can-you-explain-bookshop-org-s-affiliate-program-) · **Date:** Displayed modified 11 February without year; accessed 2026-09-25 · **Type/access:** official merchant support; Full text fetched

Non-bookstore media affiliates have 48-hour attribution and last-touch assignment. Bookstore affiliation and storefront economics are a different program. **Boundary:** Do not present bookstore permanent affiliation or 30% bookstore share as Kuro economics. Native publisher-app approval not established.

**A07 — Bookshop.org terms including affiliate program**

[Original source](https://bookshop-webflow.bkshp.org/terms-of-use) · **Date:** Affiliate Terms last updated 2025-07-10; page also contains older duplicated sections; accessed 2026-09-25 · **Type/access:** official contractual terms; Full text fetched

Base media affiliate 10%; revenue gross receipts received less applicable taxes, without listed operating-cost deductions; 48-hour tracking, $20 payout threshold. Enhanced additional 5% requires at least 100k audience and exclusive physical-book affiliate placements. **Boundary:** Use the later 2025 section. US terms do not establish UK rates or eligibility. Enhanced exclusivity conflicts with neutral comparison; Kuro native-app approval is unknown.

**A08 — Bookshop.org international shipping support**

[Original source](https://support.bookshop.org/en/support/solutions/articles/65000168970-do-you-ship-to-canada-or-internationally-) · **Date:** 2025-02-21; accessed 2026-09-25 · **Type/access:** official merchant support; Full text fetched

US orders ship within US and UK orders within UK; no direct Germany fulfillment route stated. **Boundary:** Physical shipping claim; do not conflate with ebook territorial licensing.

**A09 — Rakuten Kobo US affiliate program**

[Original source](https://www.kobo.com/us/en/p/affiliate) · **Date:** Undated live page; accessed 2026-09-25 · **Type/access:** official merchant program; Full text fetched; localized AT page corroborated

Up to 5% ebooks, audiobooks and devices; up to 10% accessories; 14-day tracking; approval stated 1–2 weeks. **Boundary:** Up to is a ceiling, not accepted rate. Gross/net base, publisher native-app eligibility and exact German program terms not established. DE page fetch failed; AT localization is not proof of DE approval.

**A10 — CDJapan affiliate commission FAQ**

[Original source](https://www.cdjapan.co.jp/aff/FAQ_affiliate_3.html) · **Date:** Undated live page; accessed 2026-09-25 · **Type/access:** official merchant FAQ; Full text fetched

5–7% tiered by prior monthly qualifying product-price sales; 30-day window; paid and shipped orders count; cancellations/returns excluded. Default payout points, PayPal threshold JPY5000. **Boundary:** Commission based on qualifying product price, not total landed cost; taxes/net exact handling should be confirmed. Preorders can remain pending until shipped; app approval and destination shipping not established.

**A11 — CDJapan affiliate program terms**

[Original source](https://www.cdjapan.co.jp/aff/terms.html) · **Date:** Undated live page; accessed 2026-09-25 · **Type/access:** official contractual terms; Full text fetched

Application approval; Site definition website/blog/mailinglist; registered accepted placements only; incentives and artificial click generation prohibited; limited product asset license for sales referrals. **Boundary:** No blanket native mobile-app permission; referral asset permission does not license general tracker catalog reuse.

**A12 — EVENTIM DE Awin merchant profile 11388**

[Original source](https://ui.awin.com/merchant-profile/11388) · **Date:** Undated live page; accessed 2026-09-25 · **Type/access:** official affiliate network merchant profile; Full text fetched

20% of net presale fee, not ticket face value. Page says fee averages 8–10% net ticket value; events may be excluded. Official Eventim partner page accepts website/app applications. **Boundary:** Header says one-day attribution but body says session-based; clarify before modeling. Native-app acceptance unknown. Relevant anime-event coverage unverified.

### Publisher precedents, funding and distribution constraints

**B01 — MyAnimeList — Publisher & Bookseller Picks 2026**

[Original source](https://myanimelist.net/readthismanga/2026/publisher-bookseller-picks) · **Date:** 2026 edition; accessed 2026-09-25 · **Type/access:** Official sponsored discovery page; Direct public HTTP 200; text read

MAL identifies selections by comici MANGA, SHUEISHA and Yen Press as sponsor picks, with reading destinations. This directly demonstrates a labelled commercial discovery area connected to useful title exploration. **Boundary:** No published placement prices, campaign conversion or audience satisfaction. The existence of sponsors does not prove Kuro can sell similar inventory profitably.

**B02 — MAL×Japan — More than just anime**

[Original source](https://mxj.myanimelist.net/) · **Date:** Undated hub; includes 2025 and 2026 programmes; accessed 2026-09-25 · **Type/access:** Official programme directory; Direct public HTTP 200; text and linked programme URLs read

The hub lists licensed-sample projects, publisher picks, creator contests, quizzes, educational offerings and giveaways. It shows established tracker activity extending into industry-supported discovery and participation. **Boundary:** A programme listing does not establish cash sponsorship, profitability, present availability or audience benefit. Individual dated programmes are stronger evidence than this changing hub.

**B03 — MyAnimeList — Manga Sampler Pilot Project**

[Original source](https://myanimelist.net/sampler-test) · **Date:** Giveaway 2026-07-21 to 2026-09-15; accessed 2026-09-25 · **Type/access:** Official experimental programme and terms; Direct public HTTP 200; full page and terms read

Rights-holder-authorized opening chapters and disclosed unreviewed machine translation let overseas readers sample titles and give publishers feedback about translation demand. It is described as experimental and free for now. **Boundary:** The giveaway has ended. Region/language restrictions apply; commercial use of its content is prohibited. Publisher fees and financial results are not disclosed; Kuro must secure its own rights.

**B04 — NTT DOCOMO announces U.S. rollout of MANGA MIRAI**

[Original source](https://dcm-dpweb51.tz.nttdocomo.co.jp/english/info/media_center/pr/2025/0305_00.html) · **Date:** 2025-03-05 · **Type/access:** Official partner launch release; Web tool full text read

DOCOMO describes its partnership with MAL, Akatsuki and MEDIA DO. MAL integrates previews and purchase access into its site, providing a current-period example of discovery connecting to legitimate manga commerce. **Boundary:** This US rollout does not establish Germany availability or an affiliate rate. The release describes partner roles, not audited user outcomes, Kuro partner eligibility or revenue allocation.

**B05 — KADOKAWA launches MAL × Honeyfeed Writing Contest 2025**

[Original source](https://www.kadokawa.co.jp/topics/14058/) · **Date:** 2025-06-25 · **Type/access:** Official publisher programme announcement; Web tool full Japanese text read

KADOKAWA, qdopp/Honeyfeed and MyAnimeList jointly announced an English-language isekai contest to discover authors for possible Japanese publication. This is a concrete collaboration offering participants a creative opportunity. **Boundary:** The release does not disclose payments to MAL or prove that small private reading clubs attract sponsorship. Treat it as a programme precedent, not a Kuro sales benchmark.

**B06 — KADOKAWA announces 2025 contest winners**

[Original source](https://www.kadokawa.co.jp/topics/15663/) · **Date:** 2026-02-10 · **Type/access:** Official publisher programme result; Web tool full Japanese text read

The publisher reports 1,240 submissions, one grand-prize winner and two additional winners; the winning work is to be published in Japan. This confirms that the previously announced collaboration progressed to a concrete participant outcome. **Boundary:** Publisher-reported participation is not independent impact measurement. No platform revenue, participant satisfaction or sponsor-return figure is disclosed.

**B07 — LiveChart.me — About**

[Original source](https://www.livechart.me/pages/about) · **Date:** Undated; accessed 2026-09-25 · **Type/access:** Official operating-model description; Direct public HTTP 200; text read

LiveChart describes itself as a hobby project using a small number of text and banner advertisements to cover operational costs. It invites advertising enquiries and emphasizes service simplicity and information accuracy. **Boundary:** This is an operator statement, not a financial report or a placement audit. No ad rates or evidence of profitability at Kuro's prospective scale are provided.

**B09 — MyAnimeList — Advertising**

[Original source](https://myanimelist.net/advertising) · **Date:** Undated; accessed 2026-09-25 · **Type/access:** Official advertising sales page; Direct public HTTP 200; text read after web-reader failure

MAL sells skin, IAB-standard and mobile ad formats and accepts campaign briefs. Germany is among selectable target countries. This verifies actual advertising inventory rather than relying on speculative business-model summaries. **Boundary:** The page's self-reported 12 million monthly unique visitors and 150 million pageviews lack a measurement date; do not present them as verified 2026 market sizing. No prices disclosed.

**B10 — 33 USA — MAL33 global marketing support service**

[Original source](https://www.thirtythree-usa.com/mal33/index.html) · **Date:** Undated page, service marked established 2023; accessed 2026-09-25 · **Type/access:** Official agency service page; historical context; Web tool page read

Agency 33 describes an anime/manga global-marketing service jointly launched with MyAnimeList. It supports the existence of B2B services adjacent to an anime tracking community. **Boundary:** It does not validate white-label recommendation widgets or privacy-preserving campaign reporting specifically. Its old undated audience claims and undisclosed contract economics should not become a 2026 financial model.

**B11 — AniList API Terms of Use**

[Original source](https://docs.anilist.co/guide/terms-of-use) · **Date:** Undated live terms; accessed 2026-09-25 · **Type/access:** Official API conditions; Web tool full terms read

Terms prohibit competing non-complementary trackers, hoarding and backup/storage use. Commercial services below $150 monthly revenue are described as free; above that threshold a commercial licence is required. **Boundary:** The commercial threshold does not override the separate competition restriction or grant redistribution rights. Exact $150 wording is imprecise. Kuro's own agreement and allowed scope were not established.

**B12 — MyAnimeList API License and Developer Agreement**

[Original source](https://myanimelist.net/static/apiagreement.html) · **Date:** Last modified 2019-08-08; live retrieved 2026-09-25 · **Type/access:** Official API agreement; current dependency reference; Direct public HTTP 200; full agreement read

Commercial-app revenue needs written authorization; release and major updates including ads require notice and possible review. The agreement restricts server-side MAL personal/user-generated content and minor-targeted ads. **Boundary:** Its noncommercial definition permits some nondisruptive click/view advertising, so avoid claiming all ads are forbidden. It is an old-dated current contract reference, not contemporary user evidence; Kuro's permission remains unknown.

**B13 — Apple — App Review Guidelines**

[Original source](https://developer.apple.com/app-store/review/guidelines/) · **Date:** Live guidelines; accessed 2026-09-25 · **Type/access:** Official platform rules; Web tool and direct public HTTP; sections 2.5.18, 3.1.1, 3.1.3 and 5.1.2 read

Rules distinguish physical commerce from digital purchases, vary external-link permissions by storefront, govern ad placement/reporting and require permission for tracking. Display advertising is barred from widgets and notifications. **Boundary:** A tracker is not automatically a reader app; exact purchase/referral flows need review. US rules cannot be copied into Germany without checking applicable terms. These are dependencies, not a finding of Kuro noncompliance.

**B14 — German media authorities — Online advertising disclosure guide**

[Original source](https://www.die-medienanstalten.de/fileadmin/user_upload/die_medienanstalten/Service/Merkblaetter_Leitfaeden/Leitfaden_Werbekennzeichnung_Online-Medien_interaktiv.pdf) · **Date:** May 2025 edition · **Type/access:** Official regulator practical guidance; Web tool indexed PDF text; edition corroborated by official advertising page

The media authorities explain transparent separation and labelling of commercial online content. This supports conspicuous sponsorship disclosure where a recommendation, sample or campaign appears, instead of hiding it in a terms page. **Boundary:** Specific wording and placement depend on the format and relationship. The guide is practical supervisory guidance, not a complete legal review of Kuro's proposed implementation.

**B15 — European Commission — Digital Services Act questions and answers**

[Original source](https://digital-strategy.ec.europa.eu/en/faqs/digital-services-act-questions-and-answers) · **Date:** Current FAQ; accessed 2026-09-25 · **Type/access:** Official regulatory explanation; Web tool text read

The Commission explains restrictions on profiling-based advertisements to minors and sensitive-data targeting, plus child-protection responsibilities. Avoiding behavioural targeting is a practical design choice for an anime app that may attract younger users. **Boundary:** Kuro's service classification, size and applicable exemptions require assessment. Do not assert that every platform or very-large-platform obligation automatically applies to a small tracker.

**B16 — Germany — TDDDG Section 25**

[Original source](https://www.gesetze-im-internet.de/ttdsg/BJNR198210021.html) · **Date:** Current consolidated legislation; accessed 2026-09-25 · **Type/access:** Official legal text; Web tool text read

Section 25 generally requires consent for device storage/access, with narrow transmission and strictly necessary requested-service exceptions. Advertising cookies, tracking identifiers and SDK behaviour therefore need assessment before a monetization implementation. **Boundary:** Contextual sponsorship does not automatically mean every measurement method is exempt. Avoid broad claims that all analytics require consent or that a particular Kuro design has already been legally approved.

**B17 — EDPB — Process personal data lawfully**

[Original source](https://www.edpb.europa.eu/sme/be-compliant/process-personal-data-lawfully_en) · **Date:** Current small-business guidance; accessed 2026-09-25 · **Type/access:** Official GDPR practical guidance; Web tool text read

The EDPB explains lawful bases, consent and children's consent when applicable; a service contract is not a blanket justification for unrelated marketing. It supports separating optional campaign research from the tracking service. **Boundary:** Do not reduce GDPR to 'all marketing always needs consent'. Exact lawful basis, age threshold and national rules depend on the processing and jurisdiction; no Kuro legal audit was performed.

**B18 — EDPB — Anonymisation / pseudonymisation**

[Original source](https://www.edpb.europa.eu/topics/ai-and-technology/anonymisation-pseudonymisation_en) · **Date:** Current topic guidance; accessed 2026-09-25 · **Type/access:** Official privacy distinction; Web tool page text read

The EDPB distinguishes reduced linkability through pseudonymisation from true anonymisation. Simply removing user IDs from campaign or club reports is not enough to promise that recipients cannot identify anyone. **Boundary:** Aggregation thresholds are not a legal safe harbour. Underlying collection, rare cohorts and linkage risks still need assessment. Recommend broad campaign totals, no private history exports and no user-level sponsor datasets.

### Selected AniList and schedule evidence retained from the first pass

**S08 — Imported list not sorting correctly by Recently Added**

[Original source](https://anilist.co/forum/thread/89610) · **Date:** 2026-05-04 to 2026-05-05 · **Type/access:** platform forum/update; Direct in-app browser thread, including replies/dates, in preceding pass

Developer explains that an import cannot reconstruct missing watch dates/order from the source file. Distinguishes absent source history from a broken display. **Boundary:** Retained evidence; no signed-in or runtime test.

**S09 — Duplicate entries on anime list**

[Original source](https://anilist.co/forum/thread/91834) · **Date:** 2026-08-05 to 2026-08-30 · **Type/access:** platform forum/update; Direct in-app browser thread, including replies/dates, in preceding pass

Developer reports a fix live on 30 August; existing duplicates need manual cleanup with preservation of information. Treat as a resolved cause with recovery burden, not an unqualified current unfixed bug. **Boundary:** Retained evidence; no signed-in or runtime test.

**S10 — AniList Bugs and Issues**

[Original source](https://anilist.co/forum/thread/76237) · **Date:** Explicit updates July 2025 and August–September 2026; thread began 2024 · **Type/access:** platform forum/update; Direct in-app browser thread, including replies/dates, in preceding pass

Acknowledges rare custom-list shuffling on deletion, a following-feed issue, and delayed stats refresh; the stats issue has a likely fix deployed. Thread began in 2024. Only explicitly dated 2025–2026 entries support the recent analysis. **Boundary:** Retained evidence; no signed-in or runtime test.

**S11 — Improve AniList Search Behavior**

[Original source](https://anilist.co/forum/thread/92120) · **Date:** 2026-08-17 · **Type/access:** platform forum/update; Direct in-app browser thread, including replies/dates, in preceding pass

Describes inconsistent partial-title results; reply points to search improvements on the roadmap. User report, not a reproduced search benchmark. **Boundary:** Retained evidence; no signed-in or runtime test.

**S12 — How do I see Anime only Recommendations?**

[Original source](https://anilist.co/forum/thread/89247) · **Date:** 2026-04-19 · **Type/access:** platform forum/update; Direct in-app browser thread, including replies/dates, in preceding pass

User asks about unwanted medium mixing; reply suggests an existing list filter and disputes the premise. Evidence of filter comprehension, not proof of a missing capability. **Boundary:** Retained evidence; no signed-in or runtime test.

**S13 — Is there a way to filter tags?**

[Original source](https://anilist.co/forum/thread/91851) · **Date:** 2026-08-06 · **Type/access:** platform forum/update; Direct in-app browser thread, including replies/dates, in preceding pass

Moderator explains an existing exclusion gesture; user acknowledges the help. Particularly strong example of discoverability rather than feature absence. **Boundary:** Retained evidence; no signed-in or runtime test.

**S26 — AniList Roadmap & Changelog**

[Original source](https://anilist.co/forum/thread/3878) · **Date:** Roadmap updated 2026-08-20 · **Type/access:** platform forum/update; Direct in-app browser thread, including replies/dates, in preceding pass

Lists search/UI improvements, exports, volume-centered tracking and privacy among future work. Existing volume fields and volume-centered product behavior are not the same thing. Older changelog comments excluded. Roadmap items have no guaranteed delivery dates. **Boundary:** Retained evidence; no signed-in or runtime test.

**P06 — LiveChart release schedules**

[Original source](https://www.livechart.me/anime/9430/schedules) · **Date:** Undated official reference accessed 2026-09-25 · **Type/access:** official reference; Indexed official page text in preceding pass

Demonstrates separate broadcast, subtitled and dubbed schedules with a regional applicability warning. Used for data semantics, not current availability of the example title. **Boundary:** Retained evidence; no signed-in or runtime test.

**P08 — Community apps**

[Original source](https://anilist.co/apps) · **Date:** Undated official reference accessed 2026-09-25 · **Type/access:** official reference; Indexed official page text in preceding pass

Identifies listed apps, including MyAniList, as not maintained by or affiliated with AniList staff. Market map and naming distinction. **Boundary:** Retained evidence; no signed-in or runtime test.

### Market context, not tracker market-share estimates

**T01 — Sony / Bandai Namco / Gaudiy strategic partnership**

[Original source](https://www.bandainamco.co.jp/files/HPE794A8_E38090ENGE38091Sony_BNHD_GaudiyE58D94E6A5_2.pdf) · **Date:** 2025-05-08 · **Type/access:** primary joint corporate release; Full PDF text read

Reports MAL at 19.5 million registered users in 2025 and describes the strategic partnership. Establishes scale of an incumbent and corporate interest in the audience. **Boundary:** Self-reported registrations, not current MAU, tracker market share, Kuro reachable market or consumer demand for a new app.

**T02 — Dentsu — Anime: A Growing Opportunity for Brands**

[Original source](https://www.dentsu.com/hu/en/reports/anime__a_growing_opportunity_for_brands) · **Date:** Data collected October 2024–March 2025; companion article 2025-07-25 · **Type/access:** primary research publisher summary; Official methodology page and companion article read

The stated study covers 8,600 consumers across ten named countries; Germany is absent. A companion Dentsu article discusses anime-related consumer spending and brand opportunities. **Boundary:** Commercial research context and broad fandom sample; not a tracker-user or Kuro monetization study. No percentages are extrapolated into Kuro economics. [Companion article](https://www.dentsu.com/us/en/blog/three-reasons-marketers-should-notice-anime).

## 12. Limits and final decision boundaries

This is substantially broader research than the first edition, but it is not exhaustive access to every forum or a comparative usability trial. MAL and MangaUpdates forum access gaps remain explicit. MangaBaka comments were unavailable. Some Reddit dates come from exact search-index timestamps, some dates are approximate, and store feeds can change. No private libraries or installed competitor apps were tested. Official descriptions and status pages may differ from a particular user's experience.

User reports establish reported friction. Developer replies can clarify or report fixes, but do not independently prove a deployed repair. The report deliberately includes positive experiences, hidden existing features, corrected complaints and withdrawn allegations. It does not rank platforms by complaint counts: each platform has different access, audience, issue-reporting habits and sample coverage.

Commercial programme terms, regulations and store rules can change. Current published terms are evidence to assess a proposed route, not legal advice or confirmation of Kuro's private contracts. Merchant/app approval, data rights, precise country/channel rules and accepted commercial bases remain implementation prerequisites. A zero-revenue result remains possible.

The product direction is **trusted continuity with optional depth**. The business direction is **useful commerce and clearly separated partner-funded benefits**, with no user fee for Kuro's core. These are 18 product and 10 monetization decisions to validate—not shipped functionality, partner commitments or proven product-market fit.
