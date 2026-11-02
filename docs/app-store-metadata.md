# Kuro — integrated release submission preparation

**DRAFT / NOT SUBMITTED.** The scope ends at qualified TestFlight; public App Store submission requires a separate reviewed authorization. Build/version, backend identity, screenshots, provider qualification, privacy-policy availability and reviewer credentials remain unresolved. No App Store Connect values were changed.

## Candidate metadata

Name: **Kuro: Anime & Manga Tracker** (owner, 2026-11-02). Home-screen name: **Kuro** (bundle display name follows PRODUCT_NAME). Subtitle: **Curated picks & private clubs**. Retain the existing category choices only after reviewing the actual installed product and current age-rating questionnaire.

Proposed promotional text:

> Track anime and manga, explore curated picks, and share private clubs with friends. Your Home brings together progress and upcoming releases.

Proposed English description, held until the included workflows pass:

> Kuro brings your anime and manga collection, curated discovery and private clubs together.
>
> Use Home to resume a title and see upcoming releases. Open a series to explore its seasons and available episode or chapter information. Update progress, status, notes and ratings in your collection.
>
> Import Anime and Manga from AniList, connect a MyAnimeList account, or import a MyAnimeList export file. Review import results and any items that need attention.
>
> Discover editorial picks and search the catalog. Use Concierge for list imports and mood-based recommendations. Create private clubs to share rails, polls and title discussions according to your sharing preferences.
>
> Supported progress actions are saved on your device and synchronized when connectivity returns. Club content requires current access. On-device features depend on device support and available models.

MAL account wording above is mandatory for the agreed release **only after** registered-client consent, both-medium ingestion and installed qualification pass. Both-medium account ingestion is now implemented and source-reviewed, but do not publish this wording before controlled provider and installed qualification. The MAL account list API omits private comments/custom-list memberships; Kuro records those fields as unavailable and preserves existing Kuro notes/lists, while XML preserves fields present in the file. Do not replace the required connector with XML to unblock this release.

Proposed German description, held to the same gates:

> Kuro verbindet deine Anime- und Manga-Sammlung mit kuratierten Empfehlungen und privaten Clubs.
>
> Auf Home kannst du Titel fortsetzen und kommende Veröffentlichungen sehen. Serienansichten zeigen verfügbare Staffeln, Folgen und Kapitel. Fortschritt, Status, Notizen und Bewertungen verwaltest du in deiner Sammlung.
>
> Importiere Anime und Manga aus AniList, verbinde dein MyAnimeList-Konto oder importiere eine MyAnimeList-Exportdatei. Prüfe die Ergebnisse und Einträge, die noch Aufmerksamkeit brauchen.
>
> Entdecke redaktionelle Empfehlungen und durchsuche den Katalog. Concierge hilft bei Listenimporten und Empfehlungen nach Stimmung. Teile Sammlungen, Umfragen und Diskussionen in privaten Clubs entsprechend deinen Freigabeeinstellungen.
>
> Unterstützte Fortschrittsänderungen werden auf dem Gerät gespeichert und bei verfügbarer Verbindung synchronisiert. Club-Inhalte benötigen eine aktuelle Zugriffsberechtigung. On-Device-Funktionen hängen vom Gerät und verfügbaren Modellen ab.

Proposed What's New:

- Home with shared tracking, series navigation and upcoming releases.
- Durable progress recovery and account-scoped imports.
- More consistent Anime/Manga detail and collection workflows.
- Private club content and account transition safeguards.

No fixed import speed, universal offline guarantee or every-device AI claim is made. Actual screenshots must come from the qualified populated native build.

## Privacy declaration preparation

The app manifest now describes confirmed source collection. Categories and purposes follow [Apple's data-type reference](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes/nsprivacycollecteddatatype), [purpose reference](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes/nsprivacycollecteddatatypepurposes) and [manifest dictionary guidance](https://developer.apple.com/documentation/technotes/tn3184-adding-data-collection-details-to-your-privacy-manifest). App Store answers must include relevant partner collection; app functionality alone is not an exemption. See [Apple's privacy-details guidance](https://developer.apple.com/app-store/app-privacy-details/).

| Collected type | Confirmed source | Draft purposes |
| --- | --- | --- |
| Name | Apple full name persisted in Auth metadata | App functionality |
| Email address | Email/password and Auth identity | App functionality |
| User ID | Auth UUID, account-owned rows and telemetry | App functionality, analytics, product personalization |
| Other user content | Notes, import data, club names/polls, private title comments | App functionality |
| Product interaction | Tracking/ratings/reactions/votes and persisted events | App functionality, analytics, product personalization |
| Performance data | Persisted interaction latency | Analytics, app functionality |
| Search history | Account-bound normalized recommendation query cache and retrieval feedback | App functionality, personalization, analytics |
| Contacts | Stored private-club social graph and co-member access | App functionality; no phone address-book access |

These retained paths are account-linked. Tracking is declared false based on reviewed source; confirm vendors/configuration before final App Store answers. Uploaded catalog mirrors and disposable probe images do not prove user-photo collection. No current app PhotosPicker/upload or direct message workflow was found. Re-evaluate if an advertised upload capability is added.

Optional Groq narration receives sanitized user prompt text; sanitization does not remove personal information. Supabase request/IP logging, Groq retention/training and effective provider settings remain unknown.

Still required: inspect effective server retention and deletion for events/query caches; confirm Supabase/Groq/provider retention and SDK privacy manifests; review signed archive privacy report/required-reason API usage; reconcile App Store Connect answers and published policy. KuroPerf's local OSLog intervals alone do not prove remotely collected crash/performance data. OAuth secrets stay in account-scoped Keychain and never appear in metadata or reviewer notes.

Required-reason declarations retain UserDefaults (`CA92.1`) and add file metadata (`C617.1` for app-container detail/Home cache eviction; `3B52.1` for metadata of the user-selected export file). Source uses `contentModificationDateKey` for local cache ordering and the file picker grants access before import metadata reads. These local metadata values are not fingerprinted or sent as file timestamps. See [Apple's required API/reason reference](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype). Confirm third-party usage in the archive report.

The app's existing privacy link is `https://kuro.app/privacy`; this tool could not verify it. Confirm the real policy is reachable and accurate before submission. Do not substitute a draft or invent a support contact.

## Reviewer notes and concrete inputs

- Supply the exact installed bundle `com.Kuro.app`, version/build, frozen source digest and deployed backend manifest after qualification. These are not assigned by this draft.
- Supply one dedicated approved reviewer account securely through App Store Connect. Do not paste a password into this repository. Confirm its release cohort enables foundation before Home; ordinary accounts remain tested separately.
- Explain navigation: Taste ← Home → Discover → Collection → Clubs; global Search opens from the header. Concierge remains reachable through the agreed entry points.
- Give reviewed AniList username, controlled MAL account consent instructions and a valid export file with both media. Confirm supported fields, partial/unmatched import treatment and provider permissions. Provider consent is not bypassed.
- Explain private clubs and membership revocation. No public discussion access is promised. Show account deletion through Profile and provide the qualified cleanup/recovery evidence.
- Note that Foundation Models require supported devices/models, optional enrichment may be unavailable, Resolve/retrieval and unrelated staged features remain disabled.
- Attach representative populated Anime/Manga screenshots, accessibility notes and the six installed journey results. Avoid an exhaustive screenshot matrix.
- Complete content-rights/provider permission, support/privacy URL and age-rating questionnaire review using the actual product. The older Infrequent/Mild assumption below is not a completed current questionnaire.

Submission inputs remain **BLOCKED** until the five integrated release gates and the disclosure checks above pass. This document prepares reviewable copy; it does not authorize public submission.

---

## Historical metadata — retained for reference

The copy below predates the integrated release. Its broad offline, entire-list-in-seconds, AI and feature claims are not current qualification evidence and must not be pasted without review.

# Kuro — App Store Connect Metadata

Historical draft; not approved release copy.

---

## App Name (30 char max)

```
Kuro — Anime & Manga
```

## Subtitle (30 char max)

```
Curated picks & private clubs
```

## Keywords (100 char max, comma-separated)

```
anime,manga,watchlist,tracker,recommendations,curated,clubs,import,discover,list,otaku,weeb
```

**Keyword strategy:**
- High-volume: anime, manga, watchlist, tracker, recommendations
- Mid-volume differentiators: curated, clubs, import, discover
- Long-tail/community: otaku, weeb, list
- Excluded (already in title/subtitle): Kuro, picks, private

---

## Promotional Text (170 char max — can be updated without a new build)

```
Import your entire anime list in one paste. Get curated picks, not algorithms. Create private clubs with friends. Available in English and German.
```

---

## Description (4000 char max)

```
Kuro is a curated anime and manga app for people who care about quality over quantity.

You won't find 27,000 titles dumped into a search bar. Instead, you'll find 50 hand-picked editorial rails — collections like "The Cut," "Soft Evenings," "Dark, Not Empty," and "The Canon" — designed to surface the best anime and manga, not just the most popular.

DISCOVER WITH INTENTION
Browse curated sections that put the right titles in front of you: essentials, classics, trending picks, and personalized recommendations based on what you already watch. Every section is editorial — built by taste, not by algorithm.

CONCIERGE — YOUR PERSONAL ASSISTANT
Paste your anime or manga list from MyAnimeList, AniList, or anywhere else. Kuro recognizes titles, status, and progress automatically — your entire library, imported in seconds.

Or describe a mood. Type something like "dark, short, no gore" and get two curated rails of titles that match. The Concierge uses deterministic routing first for speed, with optional AI narration for context.

PRIVATE CLUBS
Create private watch groups with 2–20 friends. Share curated watchlists (rails), vote in polls, react with emoji, and track who's watching what. See pace sync ("3 episodes behind the group") and celebrate when everyone finishes a title. Everything stays private — you control who sees your progress.

SMART ON-DEVICE FEATURES
Search your collection using natural language ("short comedy manga from 2020"). Get spoiler-free 2-sentence synopsis for every title. See personalized "Next Up" picks on every detail page. All powered by on-device AI — fast, private, no internet required.

BUILT FOR QUALITY
- Editorial design with serif typography and a clean monochrome palette
- Full catalog with genre, format, decade, and status filters
- Personal collection with progress tracking and ratings
- Title-level social activity with friends who share your clubs
- Works offline with visual connection indicator
- Full German language support (Deutsch)
- No ads. No tracking. No algorithmic feeds.

Kuro is for the anime fan who already knows what they like — and wants to find what they'll love next.
```

---

## Description — German (DE) Localization

```
Kuro ist eine kuratierte Anime- und Manga-App für Menschen, denen Qualität wichtiger ist als Masse.

Hier findest du keine 27.000 Titel in einer Suchleiste. Stattdessen erwarten dich 50 handverlesene redaktionelle Sammlungen — wie „The Cut", „Sanfte Abende", „Dunkel, nicht leer" und „Der Kanon" — die das Beste aus Anime und Manga zeigen, nicht nur das Beliebteste.

ENTDECKEN MIT ABSICHT
Durchstöbere kuratierte Bereiche, die dir die richtigen Titel präsentieren: Essentials, Klassiker, Trends und personalisierte Empfehlungen basierend auf dem, was du bereits schaust.

CONCIERGE — DEIN PERSÖNLICHER ASSISTENT
Füge deine Anime- oder Manga-Liste ein — von MyAnimeList, AniList oder anderswo. Kuro erkennt Titel, Status und Fortschritt automatisch. Deine gesamte Bibliothek, importiert in Sekunden.

Oder beschreibe eine Stimmung. Tippe etwas wie „düster, kurz, kein Gore" und erhalte zwei kuratierte Sammlungen passender Titel.

PRIVATE CLUBS
Erstelle private Gruppen mit 2–20 Freunden. Teile kuratierte Watchlists, stimme in Umfragen ab, reagiere mit Emoji und verfolge, wer was schaut.

INTELLIGENTE ON-DEVICE-FEATURES
Durchsuche deine Sammlung mit natürlicher Sprache. Erhalte spoilerfreie 2-Satz-Beschreibungen für jeden Titel. Alles mit On-Device-KI — schnell, privat, ohne Internet.

Keine Werbung. Kein Tracking. Keine algorithmischen Feeds.
```

---

## App Store Categories

- **Primary:** Entertainment
- **Secondary:** Social Networking

## Age Rating

- **Frequency of mature content:** Infrequent/Mild (anime catalog may include Cartoon or Fantasy Violence)
- **No user-generated content visible publicly** (clubs are private, comments visible only to club co-members)

---

## What's New (Release Notes for v1.0)

```
Welcome to Kuro.

- Browse 50 curated editorial rails across anime and manga
- Import your entire watchlist in one paste
- Get mood-based recommendations from the Concierge
- Create private clubs with friends (2–20 members)
- Smart on-device search, synopsis, and "Next Up" picks
- Full German language support
- Works offline
```
