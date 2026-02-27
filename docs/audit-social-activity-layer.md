# Audit Prompt: Social Activity Layer — Full-Stack Wiring Verification

**Purpose**: You are a senior code reviewer. Your job is to verify that the Social Activity Layer feature was implemented correctly, end-to-end, from database to iOS UI. You must check every wire, every connection, every contract between layers. Flag anything that is broken, missing, mismatched, or silently failing.

**Do NOT fix anything. Only report findings.** Produce a structured report at the end.

---

## Context

A 6-phase feature was just implemented in the Kuro iOS app (SwiftUI + Supabase backend). The feature adds:
- Title-level comments (one per user per anime/manga title, 500 char max)
- Thumbs up/down reactions on others' comments
- Friend tracking indicators on cards (how many friends are watching/reading a title)
- "Add to Club" context menu on cards
- Removal of the Club Chat tab (replaced by this social layer)

"Friends" = users who share at least one non-archived club (implicit, no follow system).

### Files to audit (read ALL of these):

**Database**:
- `/Applications/Kuro/supabase/migrations/20260224150000_social_activity_layer.sql`

**Service layer**:
- `/Applications/Kuro/Kuro/Services/SupabaseService.swift` — search for "MARK: - Social Activity" or "FriendActivityResponse" or "friendTrackingCounts" to find the new section (file is ~4900 lines)
- `/Applications/Kuro/Kuro/Services/SupabaseRPCParams.swift` — search for "RPCFetchFriendActivity" to find the new param structs

**Feature flag**:
- `/Applications/Kuro/Kuro/Services/FeatureFlags.swift` — verify `social_activity_v1` exists, `clubs_chat_v1` is removed

**New UI**:
- `/Applications/Kuro/Kuro/Views/DetailPages/FriendsActivitySection.swift`

**Modified UI — detail pages**:
- `/Applications/Kuro/Kuro/Views/DetailPages/AnimeDetailView.swift` — search for "FriendsActivitySection"
- `/Applications/Kuro/Kuro/Views/DetailPages/MangaDetailView.swift` — search for "FriendsActivitySection"

**Modified UI — cards (friend indicators + context menu)**:
- `/Applications/Kuro/Kuro/Views/KuroRefinedCard.swift` — search for "person.2" and "AddToClub"
- `/Applications/Kuro/Kuro/Views/Cards.swift` — search for "person.2"

**Modified UI — prefetch triggers**:
- `/Applications/Kuro/Kuro/Views/EditorialDiscoverView.swift` — search for "prefetchFriendCounts"
- `/Applications/Kuro/Kuro/Views/BrowseView.swift` — search for "prefetchFriendCounts"
- `/Applications/Kuro/Kuro/Views/EditorialCollectionView.swift` — search for "prefetchFriendCounts"

**Modified UI — chat removal**:
- `/Applications/Kuro/Kuro/Views/ClubDetailView.swift` — verify no chat tab, no ClubChatTab struct, no ClubChatBubble struct

**Made public**:
- `/Applications/Kuro/Kuro/Views/DetailPages/ClubActivitySection.swift` — search for "AddToClubRailSheet" and verify it's NOT `private struct`

---

## Audit Checklist — Go through EVERY item

### 1. DATABASE MIGRATION INTEGRITY

Read `/Applications/Kuro/supabase/migrations/20260224150000_social_activity_layer.sql` in full.

**1.1 Table schemas**:
- [ ] `title_comments` has columns: `id` (uuid PK), `user_id` (uuid FK → auth.users), `media_type` (text, CHECK IN ('ANIME','MANGA')), `media_id` (integer), `text` (text, CHECK 1-500 chars), `created_at` (timestamptz), `updated_at` (timestamptz)
- [ ] `title_comments` has UNIQUE constraint on `(user_id, media_type, media_id)` — enforces one comment per user per title
- [ ] `title_comments` has indexes on `(media_type, media_id)` and `(user_id)`
- [ ] `title_comments` has `set_updated_at()` trigger
- [ ] `title_comment_reactions` has columns: `id` (uuid PK), `comment_id` (uuid FK → title_comments CASCADE), `user_id` (uuid FK → auth.users CASCADE), `reaction_type` (text, CHECK IN ('up','down')), `created_at` (timestamptz)
- [ ] `title_comment_reactions` has UNIQUE constraint on `(comment_id, user_id)` — one reaction per user per comment
- [ ] `title_comment_reactions` has index on `comment_id`
- [ ] Both tables have `ENABLE ROW LEVEL SECURITY`

**1.2 RLS policies**:
- [ ] `title_comments` SELECT: user can see own comments + comments from friends (via `shares_club_with()`)
- [ ] `title_comments` INSERT: user can only insert own (`user_id = auth.uid()`)
- [ ] `title_comments` UPDATE: user can only update own
- [ ] `title_comments` DELETE: user can only delete own
- [ ] `title_comment_reactions` SELECT: reasonable policy (at minimum own + friends' reactions)
- [ ] `title_comment_reactions` INSERT: can only insert own reactions
- [ ] `title_comment_reactions` DELETE: can only delete own reactions
- [ ] All policies use `(SELECT auth.uid())` pattern (initplan optimization, not bare `auth.uid()`)

**1.3 Helper function**:
- [ ] `shares_club_with(p_other_user_id uuid)` exists
- [ ] Is `SECURITY DEFINER` with `SET search_path = public, extensions` (or `public`)
- [ ] Logic: checks if caller (`auth.uid()`) and `p_other_user_id` share at least one non-archived club via `club_members` JOIN
- [ ] Handles edge case: does NOT return true when `p_other_user_id = auth.uid()` (self)

**1.4 RPCs — verify each exists with correct signature and logic**:

- [ ] `upsert_title_comment(p_media_type text, p_media_id int, p_text text)`:
  - SECURITY DEFINER, SET search_path
  - Rate limited (check `rate_limit_hit()` call — should be ~10/5min)
  - Uses INSERT ON CONFLICT (UPSERT on unique constraint)
  - Returns the comment row or at least confirmation

- [ ] `delete_title_comment(p_media_type text, p_media_id int)`:
  - SECURITY DEFINER, SET search_path
  - Deletes only caller's comment for the given title

- [ ] `toggle_comment_reaction(p_comment_id uuid, p_reaction_type text)`:
  - SECURITY DEFINER, SET search_path
  - Rate limited (~30/min)
  - Prevents reacting to own comment (CHECK: does it verify comment.user_id != auth.uid()?)
  - Toggle logic: if same reaction exists → delete, if different reaction → update, if no reaction → insert
  - Returns new state

- [ ] `fetch_friend_activity_for_title(p_media_type text, p_media_id int)`:
  - SECURITY DEFINER, SET search_path
  - Returns JSON with `friends_tracking` array and `comments` array
  - Friends derived from `shares_club_with` or equivalent CTE
  - Comments include: `up_count`, `down_count`, `my_reaction`, `is_own`, `display_name`
  - Friends tracking includes: `display_name`, `status`, `progress`, `rating`

- [ ] `count_friends_tracking(p_items jsonb)`:
  - SECURITY DEFINER, SET search_path
  - Takes array of `{media_type, media_id}` objects
  - Returns array of `{media_type, media_id, count}` for items with count > 0
  - Computes friend set ONCE via CTE (not per-item)
  - **CRITICAL**: verify the friend set CTE correctly joins `club_members` to find mutual club members

**1.5 Feature flag + chat deprecation**:
- [ ] `social_activity_v1` inserted into `feature_flags` table at 0% rollout
- [ ] `clubs_chat_v1` disabled (set to 0% or enabled=false)
- [ ] `prune_club_messages` cron unscheduled

---

### 2. iOS SERVICE LAYER — MODEL/RPC CONTRACT MATCH

Read the social activity section in `SupabaseService.swift` and the RPC params in `SupabaseRPCParams.swift`.

**2.1 Models match DB return shapes**:
- [ ] `TitleComment` fields match what `fetch_friend_activity_for_title` returns in the `comments` array
  - Must have: `id`, `user_id`, `display_name`, `text`, `created_at`, `updated_at`, `is_own`, `up_count`, `down_count`, `my_reaction`
  - Types must match: `my_reaction` should be `String?` (nullable), counts should be `Int`
- [ ] `FriendTitleActivity` fields match what the RPC returns in `friends_tracking` array
  - Must have: `user_id`, `display_name`, `status`, `progress`, `rating`, `updated_at`
  - All optional fields marked as `String?` / `Int?` appropriately
- [ ] `FriendActivityResponse` wraps both: `friends_tracking: [FriendTitleActivity]`, `comments: [TitleComment]`
- [ ] `FriendCountItem` matches `count_friends_tracking` return: `media_type: String`, `media_id: Int`, `count: Int`
- [ ] `TitleComment` conforms to `Identifiable` (needed for `ForEach` in SwiftUI)

**2.2 RPC param structs match RPC signatures**:
- [ ] `RPCFetchFriendActivityParams` encodes `p_media_type` and `p_media_id` — names must EXACTLY match the SQL parameter names
- [ ] `RPCUpsertTitleCommentParams` encodes `p_media_type`, `p_media_id`, `p_text`
- [ ] `RPCDeleteTitleCommentParams` encodes `p_media_type`, `p_media_id`
- [ ] `RPCToggleCommentReactionParams` encodes `p_comment_id`, `p_reaction_type`
- [ ] `RPCCountFriendsTrackingParams` encodes `p_items` — verify it's a JSON string (since the RPC takes jsonb, but the Swift SDK may serialize differently)
- [ ] All param structs use `nonisolated func encode(to:)` pattern (Sendable conformance)
- [ ] All param structs use `CodingKeys` with snake_case matching the SQL parameter names

**2.3 Service function → RPC wiring**:
- [ ] `fetchFriendActivityForTitle(mediaType:, mediaId:)` calls `.rpc("fetch_friend_activity_for_title", params:)` and decodes to `FriendActivityResponse`
- [ ] `upsertTitleComment(mediaType:, mediaId:, text:)` calls `.rpc("upsert_title_comment", params:)`
- [ ] `deleteTitleComment(mediaType:, mediaId:)` calls `.rpc("delete_title_comment", params:)`
- [ ] `toggleCommentReaction(commentId:, reactionType:)` calls `.rpc("toggle_comment_reaction", params:)`
- [ ] `prefetchFriendCounts(items:)` calls `.rpc("count_friends_tracking", params:)` and updates `friendTrackingCounts` cache

**2.4 Friend count cache**:
- [ ] `friendTrackingCounts` is a `[String: Int]` dictionary with keys like `"ANIME-123"`
- [ ] `friendCount(mediaId:, mediaType:)` reads from cache synchronously — returns 0 if not found
- [ ] `prefetchFriendCounts` cancels previous task before starting new one (debounce)
- [ ] Cache key format in `prefetchFriendCounts` matches what `friendCount()` reads (EXACT same format)
- [ ] **CRITICAL**: verify the mediaType casing is consistent — if the RPC returns `"ANIME"` but the card passes `"anime"`, the cache key won't match

---

### 3. FRIENDS ACTIVITY SECTION — UI WIRING

Read `/Applications/Kuro/Kuro/Views/DetailPages/FriendsActivitySection.swift` in full.

**3.1 Data flow**:
- [ ] Gets `SupabaseService` from environment
- [ ] Calls `supabaseService.fetchFriendActivityForTitle(mediaType:, mediaId:)` on `.task(id: mediaId)`
- [ ] Passes `mediaType` and `mediaId` correctly to the service call
- [ ] Stores result in `@State private var activity: SupabaseService.FriendActivityResponse?`

**3.2 Rendering**:
- [ ] Only renders if `hasClubs` (user is in at least one club) — checks `!supabaseService.myClubs.isEmpty`
- [ ] Shows loading state while fetching
- [ ] Shows friend tracking pills when `activity.friends_tracking` is non-empty
- [ ] Shows comments when `activity.comments` is non-empty
- [ ] Shows comment input (inline text field, 500 char limit)
- [ ] Shows empty state "No friends tracking this yet" when no data

**3.3 Comment CRUD**:
- [ ] Submit calls `supabaseService.upsertTitleComment(mediaType:, mediaId:, text:)` — verify params passed correctly
- [ ] After submit, clears text and reloads activity
- [ ] Edit mode: sets `isEditing = true`, pre-fills `commentText` with existing comment text
- [ ] Cancel edit: resets `isEditing` and clears text
- [ ] `canSubmit` validates non-empty trimmed text and not already submitting

**3.4 Reactions**:
- [ ] Thumbs up/down only shown on OTHER people's comments (not own — check `!comment.is_own`)
- [ ] Own comments show reaction counts without toggle buttons
- [ ] Toggle calls `supabaseService.toggleCommentReaction(commentId:, reactionType:)` — verify `comment.id` is passed (not `comment.user_id`)
- [ ] After toggle, reloads activity to get fresh counts
- [ ] Active state uses `.fill` icon variant, inactive uses outline

**3.5 Design system compliance**:
- [ ] Uses KuroDesignSystem tokens (`.kuroCaption`, `.kuroBody`, `.kuroMicro`, `KuroDesignSpacing`, `KuroRadius`)
- [ ] Uses `EditorialLayout.divider()`
- [ ] Monochrome palette only (black.opacity variants, no colors)
- [ ] Header "FRIENDS" with tracking 1.6
- [ ] Haptic feedback via `KuroAccessibility.impactHaptic`

---

### 4. DETAIL PAGE INTEGRATION

**4.1 AnimeDetailView**:
- [ ] `FriendsActivitySection(mediaId: anime.id, mediaType: "ANIME")` is present
- [ ] Placed AFTER `ClubActivitySection`
- [ ] Gated by `FeatureFlags.shared.isSocialActivityV1Enabled`
- [ ] `mediaType` is `"ANIME"` (uppercase) — must match what the RPC expects

**4.2 MangaDetailView**:
- [ ] `FriendsActivitySection(mediaId: manga.id, mediaType: "MANGA")` is present
- [ ] Placed AFTER `ClubActivitySection`
- [ ] Gated by `FeatureFlags.shared.isSocialActivityV1Enabled`
- [ ] `mediaType` is `"MANGA"` (uppercase)

---

### 5. CARD FRIEND INDICATORS — WIRING VERIFICATION

**5.1 KuroRefinedCard.swift** — all 3 card types:

For each of KuroPortraitCard, KuroCompactCard, KuroHeroCard:
- [ ] Friend count indicator is present
- [ ] Reads from `supabaseService.friendCount(mediaId: media.id, mediaType: mediaType.uppercased())`
- [ ] Only shows when count > 0
- [ ] Uses `Image(systemName: "person.2")` + count text
- [ ] Gated by `FeatureFlags.shared.isSocialActivityV1Enabled`
- [ ] **CRITICAL**: verify `mediaType.uppercased()` — what is the source of `mediaType` in each card type? Is it already uppercase? Could it produce `"ANIME"` or `"anime"`? Must match the cache key format.

**5.2 Cards.swift** — SharedVerticalAnimeCard + SharedHorizontalAnimeCard:
- [ ] Friend count indicator is present in both card types
- [ ] Uses `supabaseService.friendCount(mediaId: anime.id, mediaType: "ANIME")` — hardcoded "ANIME" since these are anime-only cards
- [ ] Gated by `FeatureFlags.shared.isSocialActivityV1Enabled`
- [ ] Both cards have `@Environment(SupabaseService.self)` to access the cache

**5.3 Prefetch triggers** — verify the batch call is wired:

- [ ] **EditorialDiscoverView.swift**: calls `supabaseService.prefetchFriendCounts(items:)` after discover bundle loads. Items are collected from the right arrays (essentials, trending, etc.). MediaType is set to "ANIME" or "MANGA" correctly based on the array source.
- [ ] **BrowseView.swift**: calls `prefetchFriendCounts` after page loads. Uses correct mediaType for anime vs manga browse modes.
- [ ] **EditorialCollectionView.swift**: calls `prefetchFriendCounts` after collection feed loads. Uses `$0.kind == .anime ? "ANIME" : "MANGA"` to determine type.
- [ ] All prefetch calls are gated by `FeatureFlags.shared.isSocialActivityV1Enabled`
- [ ] **CRITICAL**: the mediaType strings in prefetch calls ("ANIME"/"MANGA") must EXACTLY match what `friendCount()` reads in the card views. Any casing mismatch = indicators never show.

---

### 6. ADD TO CLUB CONTEXT MENU

**6.1 AddToClubRailSheet accessibility**:
- [ ] In `ClubActivitySection.swift`, `AddToClubRailSheet` is `struct` (NOT `private struct`)
- [ ] It takes `mediaId: Int` and `mediaType: String` as parameters

**6.2 KuroRefinedCard context menu** — all 3 card types:
- [ ] "Add to Club…" button exists in `.contextMenu`
- [ ] Only shows when `!supabaseService.myClubs.isEmpty`
- [ ] Sets `@State private var showAddToClub = false` → toggles to `true`
- [ ] `.sheet(isPresented: $showAddToClub)` presents `AddToClubRailSheet(mediaId: media.id, mediaType: mediaType.uppercased())`
- [ ] **CRITICAL**: verify `mediaType.uppercased()` produces what `AddToClubRailSheet` expects. Check what the existing `addRailItem()` RPC in SupabaseService expects for media_type — is it "ANIME"/"MANGA" or "anime"/"manga"?

---

### 7. CHAT REMOVAL VERIFICATION

**7.1 ClubDetailView.swift**:
- [ ] `Tab` enum does NOT contain `.chat`
- [ ] `visibleCases` returns `[.rails, .thisWeek, .polls]` — no conditional chat append
- [ ] No `if selectedTab == .chat` branch in the body
- [ ] No `case .chat:` in switch statements
- [ ] `ClubChatTab` struct is completely gone (search for "ClubChatTab" — should find 0 results)
- [ ] `ClubChatBubble` struct is completely gone (search for "ClubChatBubble" — should find 0 results)
- [ ] `ClubMilestoneCard` struct still exists and is intact (it was adjacent to chat code — verify it wasn't accidentally damaged)
- [ ] `ClubPollCard` struct still exists and is intact

**7.2 FeatureFlags.swift**:
- [ ] `isClubsChatV1Enabled` is removed (no property, no evaluate call)
- [ ] `isSocialActivityV1Enabled` exists

**7.3 No dangling references**:
- [ ] Search entire `Kuro/` directory for "ClubChatTab" — 0 results
- [ ] Search entire `Kuro/` directory for "ClubChatBubble" — 0 results
- [ ] Search entire `Kuro/` directory for "isClubsChatV1Enabled" — 0 results
- [ ] Search entire `Kuro/` directory for "clubs_chat_v1" — 0 results

---

### 8. CROSS-CUTTING CONCERNS

**8.1 mediaType casing consistency** (this is the #1 risk for silent failures):
- Map out every place mediaType flows and verify casing is consistent:
  - DB CHECK constraint: `'ANIME'`, `'MANGA'` (uppercase)
  - RPC parameters: what does each RPC expect?
  - iOS service calls: what does each function pass?
  - Card indicator reads: what does `friendCount(mediaId:, mediaType:)` use as key?
  - Prefetch calls: what casing do they use?
  - FriendsActivitySection: what does it pass?
  - AddToClubRailSheet: what does it expect?
  - Any `.uppercased()` calls — are they in the right places?

**8.2 Observable reactivity**:
- [ ] `friendTrackingCounts` dictionary — is the `SupabaseService` class `@Observable`? If so, will changes to this dictionary trigger SwiftUI re-renders in card views?
- [ ] If `friendTrackingCounts` is not `@Published` (since this uses `@Observable` not Combine), verify that property access is tracked by the observation system

**8.3 Error handling**:
- [ ] Service functions: do they throw? Are callers using try/catch appropriately?
- [ ] FriendsActivitySection: silent fail on load is OK (shows empty state), but does it handle errors on comment submit? Reaction toggle?
- [ ] `print()` statements: all wrapped in `#if DEBUG`?

**8.4 Memory/performance**:
- [ ] `prefetchFriendCounts` cancels previous task — verify `friendCountPrefetchTask?.cancel()` is called before creating new task
- [ ] Batch is capped (e.g., `.prefix(100)`) to avoid sending huge payloads
- [ ] No N+1 queries — cards read from cache, not making individual RPC calls

---

### 9. BUILD VERIFICATION

- [ ] Run: `xcodebuild -scheme Kuro -destination 'generic/platform=iOS' build` — must produce `BUILD SUCCEEDED`
- [ ] No new compiler warnings related to the social activity code

---

## Output Format

Produce a report with these sections:

### P0 — Broken Wiring (will cause crashes or silent data loss)
### P1 — Incorrect Behavior (wrong data shown, logic errors)
### P2 — Missing Edge Cases (not catastrophic but should be fixed)
### P3 — Style/Convention Issues (non-functional, cleanup)

For each finding:
- **File**: exact path and line number
- **Issue**: what's wrong
- **Expected**: what should be there
- **Impact**: what happens if not fixed

If everything checks out for a section, explicitly state: "Section X: PASS — no issues found."
