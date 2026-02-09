# Kuro Clubs + Import Reconciliation + Quality Gates — Product Specification

**Version:** 1.0
**Date:** 2026-02-09
**Status:** Draft

---

## 0) Design Philosophy — What Clubs Are NOT

Kuro Clubs are **not** a social network. They follow Kuro's core identity: editorial minimalism, privacy by design, personal curation.

**Hard rules:**

1. **No feed.** There is no global activity feed, no timeline, no "what your friends are watching" stream.
2. **No global profiles.** A user's profile is visible only to themselves. Club membership does not expose watch history, ratings, or any data beyond what the user explicitly shares at the club level.
3. **No chat.** Clubs do not have messaging, comments, or threads. Communication happens outside Kuro.
4. **Aggregates first.** Default club surfaces show only YOUR progress and GROUP aggregates (e.g., "3/5 members finished", "club average: 8.2"). Member-by-member breakdowns are one tap deeper and respect each member's sharing level.
5. **Privacy by design.** Each club has a `sharing_level` set by the club creator. Each member can further restrict their own visibility within the club. No data leaks upward.

---

## 1) Concepts

| Concept | Description |
|---------|-------------|
| **Club** | A private group (2-20 members) that shares curated rails and polls around anime/manga. Created by a user, joined via invite code. |
| **Rail** | An ordered list of anime/manga titles attached to a club (e.g., "Summer Watch Party", "Horror Classics"). Members can add items; the creator can lock the rail. |
| **Poll** | A simple single-choice vote within a club (e.g., "What should we watch next?"). Options are media titles or freeform text. |
| **Sharing Level** | Controls what club members can see about each other. Set at the club level by the creator; members can further restrict their own. |
| **Invite Code** | An 8-character alphanumeric code used to join a club. Codes expire after 7 days or after a configurable number of uses. |

### Sharing Levels

| Level | What others see about you |
|-------|--------------------------|
| `private` | Nothing. Only aggregates include your data (anonymous contribution to counts/averages). |
| `status` | Your watch/read status per rail item (Watching, Completed, etc.) but not progress numbers or ratings. |
| `progress` | Full progress (episodes/chapters watched), status, and rating. |

The club-level default is set at creation time. Each member can downgrade (never upgrade) their personal level within a club.

---

## 2) Data Model

All tables live in the `public` schema. RLS is enabled on every table. All `id` columns are `uuid` with `gen_random_uuid()` default. All tables include `created_at` and `updated_at` timestamps with the standard `set_updated_at` trigger.

### 2.1) `clubs`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `uuid` | PK, default `gen_random_uuid()` | Club identifier |
| `name` | `text` | NOT NULL, max 80 chars | Display name |
| `description` | `text` | nullable, max 500 chars | Optional club description |
| `created_by` | `uuid` | NOT NULL, FK `auth.users(id)` | Creator user ID |
| `invite_code` | `text` | UNIQUE, NOT NULL | 8-char alphanumeric join code |
| `invite_expires_at` | `timestamptz` | nullable | When the current invite code expires (null = never) |
| `invite_max_uses` | `int` | nullable, default null | Max uses for current code (null = unlimited) |
| `invite_use_count` | `int` | NOT NULL, default 0 | Current use count for the invite code |
| `sharing_level` | `text` | NOT NULL, default `'status'`, CHECK in (`'private'`, `'status'`, `'progress'`) | Default sharing level for new members |
| `max_members` | `int` | NOT NULL, default 20 | Member cap |
| `is_archived` | `boolean` | NOT NULL, default false | Soft-archive (hides from default views) |
| `created_at` | `timestamptz` | NOT NULL, default `now()` | |
| `updated_at` | `timestamptz` | NOT NULL, default `now()` | |

**Indexes:**
- `idx_clubs_invite_code` ON `clubs(invite_code)` — lookup for join flow
- `idx_clubs_created_by` ON `clubs(created_by)` — user's clubs listing

### 2.2) `club_members`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `uuid` | PK, default `gen_random_uuid()` | |
| `club_id` | `uuid` | NOT NULL, FK `clubs(id)` ON DELETE CASCADE | |
| `user_id` | `uuid` | NOT NULL, FK `auth.users(id)` | |
| `role` | `text` | NOT NULL, default `'member'`, CHECK in (`'owner'`, `'admin'`, `'member'`) | |
| `sharing_level` | `text` | nullable, CHECK in (`'private'`, `'status'`, `'progress'`) | Per-member override (null = use club default) |
| `joined_at` | `timestamptz` | NOT NULL, default `now()` | |
| `created_at` | `timestamptz` | NOT NULL, default `now()` | |
| `updated_at` | `timestamptz` | NOT NULL, default `now()` | |

**Constraints:**
- UNIQUE(`club_id`, `user_id`) — one membership per user per club

**Indexes:**
- `idx_club_members_user` ON `club_members(user_id)` — "my clubs" queries
- `idx_club_members_club` ON `club_members(club_id)` — member listing

### 2.3) `club_rails`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `uuid` | PK, default `gen_random_uuid()` | |
| `club_id` | `uuid` | NOT NULL, FK `clubs(id)` ON DELETE CASCADE | |
| `title` | `text` | NOT NULL, max 120 chars | Rail display name |
| `description` | `text` | nullable, max 500 chars | Optional description |
| `created_by` | `uuid` | NOT NULL, FK `auth.users(id)` | Who created the rail |
| `is_locked` | `boolean` | NOT NULL, default false | If true, only owner/admin can add items |
| `sort_order` | `int` | NOT NULL, default 0 | Display ordering within the club |
| `created_at` | `timestamptz` | NOT NULL, default `now()` | |
| `updated_at` | `timestamptz` | NOT NULL, default `now()` | |

**Indexes:**
- `idx_club_rails_club_sort` ON `club_rails(club_id, sort_order)` — ordered listing

### 2.4) `club_rail_items`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `uuid` | PK, default `gen_random_uuid()` | |
| `rail_id` | `uuid` | NOT NULL, FK `club_rails(id)` ON DELETE CASCADE | |
| `media_type` | `text` | NOT NULL, CHECK in (`'ANIME'`, `'MANGA'`) | |
| `media_id` | `int` | NOT NULL | FK to `anime(id)` or `manga(id)` (application-level) |
| `added_by` | `uuid` | NOT NULL, FK `auth.users(id)` | |
| `sort_order` | `int` | NOT NULL, default 0 | Position within rail |
| `note` | `text` | nullable, max 280 chars | Optional short note ("watch the director's cut") |
| `created_at` | `timestamptz` | NOT NULL, default `now()` | |
| `updated_at` | `timestamptz` | NOT NULL, default `now()` | |

**Constraints:**
- UNIQUE(`rail_id`, `media_type`, `media_id`) — no duplicate entries in a rail

**Indexes:**
- `idx_club_rail_items_rail_sort` ON `club_rail_items(rail_id, sort_order)` — ordered listing

### 2.5) `club_polls`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `uuid` | PK, default `gen_random_uuid()` | |
| `club_id` | `uuid` | NOT NULL, FK `clubs(id)` ON DELETE CASCADE | |
| `question` | `text` | NOT NULL, max 200 chars | Poll question |
| `created_by` | `uuid` | NOT NULL, FK `auth.users(id)` | |
| `closes_at` | `timestamptz` | nullable | Auto-close timestamp (null = manual close) |
| `is_closed` | `boolean` | NOT NULL, default false | |
| `created_at` | `timestamptz` | NOT NULL, default `now()` | |
| `updated_at` | `timestamptz` | NOT NULL, default `now()` | |

**Indexes:**
- `idx_club_polls_club_created` ON `club_polls(club_id, created_at DESC)` — reverse-chron listing

### 2.6) `club_poll_options`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `uuid` | PK, default `gen_random_uuid()` | |
| `poll_id` | `uuid` | NOT NULL, FK `club_polls(id)` ON DELETE CASCADE | |
| `label` | `text` | NOT NULL, max 120 chars | Display text (title or freeform) |
| `media_type` | `text` | nullable, CHECK in (`'ANIME'`, `'MANGA'`) | If option is a media title |
| `media_id` | `int` | nullable | FK to `anime(id)` or `manga(id)` |
| `sort_order` | `int` | NOT NULL, default 0 | |
| `created_at` | `timestamptz` | NOT NULL, default `now()` | |

### 2.7) `club_votes`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `uuid` | PK, default `gen_random_uuid()` | |
| `poll_id` | `uuid` | NOT NULL, FK `club_polls(id)` ON DELETE CASCADE | |
| `option_id` | `uuid` | NOT NULL, FK `club_poll_options(id)` ON DELETE CASCADE | |
| `user_id` | `uuid` | NOT NULL, FK `auth.users(id)` | |
| `created_at` | `timestamptz` | NOT NULL, default `now()` | |

**Constraints:**
- UNIQUE(`poll_id`, `user_id`) — one vote per user per poll

---

## 3) RLS Policies

All club tables have RLS enabled. The pattern is consistent: **membership gates access**.

### Helper function: `is_club_member(club_uuid)`

```sql
CREATE OR REPLACE FUNCTION public.is_club_member(p_club_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.club_members
    WHERE club_id = p_club_id AND user_id = auth.uid()
  );
$$;
```

### Helper function: `is_club_admin_or_owner(club_uuid)`

```sql
CREATE OR REPLACE FUNCTION public.is_club_admin_or_owner(p_club_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.club_members
    WHERE club_id = p_club_id AND user_id = auth.uid() AND role IN ('owner', 'admin')
  );
$$;
```

### Policy Summary

| Table | SELECT | INSERT | UPDATE | DELETE |
|-------|--------|--------|--------|--------|
| `clubs` | Member of club | Authenticated (creates + auto-adds as owner) | Owner only | Owner only |
| `club_members` | Member of club | Via `join_club` RPC only (not direct) | Own row only (sharing_level) | Own row (leave) or owner can remove |
| `club_rails` | Member of club | Member of club | Admin/owner of club | Admin/owner of club |
| `club_rail_items` | Member of club | Member of club (unless rail locked, then admin/owner) | Adder or admin/owner | Adder or admin/owner |
| `club_polls` | Member of club | Member of club | Creator or admin/owner | Creator or admin/owner |
| `club_poll_options` | Member of club | Poll creator | Poll creator | Poll creator |
| `club_votes` | Member of club | Member of club (if poll not closed) | N/A (delete+reinsert) | Own vote only |

---

## 4) API Contract (RPCs)

All RPCs are Postgres functions invoked via `supabase.rpc()` from iOS. They follow the existing pattern in `SupabaseService.swift`: typed request params via `SupabaseRPCParams.swift`, typed `Decodable` response structs.

### 4.1) `create_club`

Creates a club and inserts the caller as owner.

**Input:**
```typescript
{
  p_name: text,           // 1-80 chars
  p_description: text?,   // 0-500 chars, nullable
  p_sharing_level: text   // 'private' | 'status' | 'progress', default 'status'
}
```

**Output:**
```typescript
{
  club_id: uuid,
  invite_code: text
}
```

**Logic:**
1. Validate name length.
2. Generate 8-char alphanumeric invite code (retry on collision).
3. INSERT into `clubs`.
4. INSERT into `club_members` with role `'owner'`, sharing_level null (uses club default).
5. Return club_id + invite_code.

**iOS Codable:**
```swift
struct CreateClubParams: Encodable {
    let p_name: String
    let p_description: String?
    let p_sharing_level: String
}
struct CreateClubResponse: Decodable, Sendable {
    let club_id: String
    let invite_code: String
}
```

### 4.2) `join_club`

Joins an existing club via invite code.

**Input:**
```typescript
{
  p_invite_code: text   // 8-char code
}
```

**Output:**
```typescript
{
  club_id: uuid,
  club_name: text,
  role: text
}
```

**Logic:**
1. Look up club by invite code.
2. Validate: code not expired, use count not exceeded, member count < max_members, user not already a member.
3. INSERT into `club_members` with role `'member'`.
4. INCREMENT `invite_use_count` on club.
5. Return club_id, name, role.

**Error codes:**
- `INVALID_CODE` — code not found
- `CODE_EXPIRED` — invite code past expiry
- `CODE_EXHAUSTED` — max uses reached
- `CLUB_FULL` — member count at cap
- `ALREADY_MEMBER` — user already in club

### 4.3) `fetch_club_bundle`

Returns everything needed to render ClubDetailView in a single round-trip.

**Input:**
```typescript
{
  p_club_id: uuid
}
```

**Output:**
```typescript
{
  club: {
    id, name, description, sharing_level, max_members,
    is_archived, invite_code, created_at
  },
  members: [{
    user_id, role, sharing_level,   // effective (coalesced with club default)
    joined_at
  }],
  my_role: text,                    // caller's role
  my_sharing_level: text,           // caller's effective sharing level
  rails: [{
    id, title, description, is_locked, sort_order,
    items: [{
      id, media_type, media_id, sort_order, note, added_by,
      // Joined from anime/manga tables:
      title_display: text,
      cover_image_medium: text?,
      average_score: int?,
      year: int?,
      format: text?,
      // Aggregates from user lists across club members:
      member_status_counts: { WATCHING: int, COMPLETED: int, PLANNING: int, ... },
      my_status: text?,             // caller's status for this item
      my_progress: int?,            // caller's episode/chapter progress
      my_rating: int?               // caller's rating (if sharing allows)
    }]
  }],
  polls: [{
    id, question, is_closed, closes_at, created_by, created_at,
    options: [{
      id, label, media_type?, media_id?, sort_order,
      vote_count: int
    }],
    my_vote_option_id: uuid?        // which option caller voted for (null if not voted)
  }],
  member_count: int
}
```

**Logic:**
1. Verify caller is a member (else 403).
2. Fetch club row.
3. Fetch members (respecting sharing levels for what to return).
4. Fetch rails + items with LEFT JOIN to anime/manga for display fields.
5. For each rail item, compute aggregate status counts across members (only counting members whose effective sharing level >= `status`).
6. Include caller's own list entry data (status/progress/rating).
7. Fetch polls + options + vote counts + caller's vote.
8. Return single JSON bundle.

**iOS Codable:**
```swift
struct ClubBundle: Decodable, Sendable {
    let club: ClubInfo
    let members: [ClubMember]
    let my_role: String
    let my_sharing_level: String
    let rails: [ClubRail]
    let polls: [ClubPoll]
    let member_count: Int
}
// (nested structs ClubInfo, ClubMember, ClubRail, ClubRailItem, ClubPoll, etc.)
```

### 4.4) `leave_club`

**Input:**
```typescript
{
  p_club_id: uuid
}
```

**Output:**
```typescript
{
  success: boolean
}
```

**Logic:**
1. DELETE from `club_members` WHERE club_id + user_id = caller.
2. If caller was the owner and no other members remain, DELETE the club.
3. If caller was the owner but members remain, promote the earliest-joined admin (or member if no admins) to owner.

### 4.5) `update_club_settings`

**Input:**
```typescript
{
  p_club_id: uuid,
  p_name: text?,              // optional, 1-80 chars
  p_description: text?,       // optional, 0-500 chars
  p_sharing_level: text?,     // optional, enum
  p_is_archived: boolean?,    // optional
  p_regenerate_invite: boolean? // optional, generates a new code
}
```

**Output:**
```typescript
{
  success: boolean,
  invite_code: text?          // new code if regenerated
}
```

**Auth:** Owner only.

### 4.6) `add_rail_item`

**Input:**
```typescript
{
  p_rail_id: uuid,
  p_media_type: text,         // 'ANIME' | 'MANGA'
  p_media_id: int,
  p_note: text?               // optional, max 280 chars
}
```

**Output:**
```typescript
{
  item_id: uuid,
  sort_order: int
}
```

**Logic:**
1. Verify caller is member of the club that owns this rail.
2. If rail is locked, verify caller is admin/owner.
3. Verify media_id exists in the anime/manga table.
4. Compute sort_order = max existing + 1.
5. INSERT, return item_id.

### 4.7) `cast_vote`

**Input:**
```typescript
{
  p_poll_id: uuid,
  p_option_id: uuid
}
```

**Output:**
```typescript
{
  success: boolean
}
```

**Logic:**
1. Verify caller is member of the club that owns this poll.
2. Verify poll is not closed.
3. DELETE any existing vote by caller on this poll.
4. INSERT new vote.

### 4.8) `update_member_sharing_level`

**Input:**
```typescript
{
  p_club_id: uuid,
  p_sharing_level: text       // 'private' | 'status' | 'progress'
}
```

**Output:**
```typescript
{
  success: boolean
}
```

**Logic:**
1. Validate the requested level does not exceed the club's default (i.e., member can only downgrade).
2. UPDATE `club_members` SET `sharing_level` = value WHERE club_id + user_id = caller.

### Sharing Level Hierarchy

For validation, the hierarchy is: `private` < `status` < `progress`. A member can set their level to any value <= the club default. The effective sharing level is `LEAST(club.sharing_level, member.sharing_level)` using the ordering: private=0, status=1, progress=2.

---

## 5) iOS Screens

All screens use `KuroDesignSystem` tokens exclusively. Glass surfaces use `KuroGlassCard`. Typography follows the existing editorial hierarchy (`.kuroCaption`, `.kuroBody`, `.kuroHeadline`, etc.). Animations use `KuroAnimation.editorial` and `.fast`.

### 5.1) Navigation Integration

Clubs is added as the **6th page** in the swipe pager (after Search):

```
Concierge | Discover | Collection | Browse | Search | Clubs
```

The section title reads "CLUBS" with `kuroCaption(weight: .medium)` + tracking 2.4.

### 5.2) `ClubsView` (Main Clubs Page)

**Empty state** (no clubs):
- Glass card (like `ConciergeIntroCard`) with:
  - `KuroConciergeMark`-style icon (group glyph)
  - "CLUBS" header, `.kuroCaption(weight: .medium)`, tracking 2.4
  - Subtitle: "Watch together. Private by design."
  - `.kuroBody(weight: .light)`, `.black.opacity(0.62)`
- Two `KuroGlassPill` actions:
  - "Create a club" (systemImage: `person.2.badge.gearshape`)
  - "Join with code" (systemImage: `ticket`)

**Active state** (has clubs):
- Vertical `LazyVStack` of club cards, each showing:
  - Club name: `.kuroHeadline(weight: .light)`
  - Member count badge: `.kuroMicro(weight: .medium)`, `Color.black.opacity(0.45)`
  - Activity indicator: how many members are currently watching something on any rail
  - Active poll badge (if any open polls)
- Tapping a club card navigates to `ClubDetailView`

**Create Club sheet** (presented modally):
- Name field, optional description, sharing level picker (segmented: Private / Status / Progress)
- "CREATE" button: `.kuroCaption(weight: .medium)`, tracking 1.6, black fill, white text
- Pattern follows `ConciergeConfirmBubble` button style

**Join Club sheet** (presented modally):
- Single text field for 8-character invite code
- "JOIN" button, same style as Create
- Error states shown as `.kuroCaption()` red text (like `ConciergeView.errorText`)

### 5.3) `ClubDetailView`

Uses a segmented control at the top (like Collection's status filter):

**Segments:** `RAILS` | `THIS WEEK` | `POLLS`

#### RAILS tab

- Vertical list of `ClubRail` sections.
- Each rail section:
  - Rail title: `.kuroTitle(weight: .regular)`, left-aligned
  - Lock icon if `is_locked`: `Image(systemName: "lock.fill")`, `.kuroMicro`, `.black.opacity(0.35)`
  - Horizontal scroll of rail items (same `KuroCompactCard` / `KuroPortraitCard` pattern from Discover)
  - Each card overlay shows:
    - **Your status** badge: colored dot (green = watching, blue = completed, etc.)
    - **Club aggregate** pill: "3/5" (members who finished), `.kuroMicro`
  - Tapping a card presents `MediaDetailSheet(kind:id:)` (existing pattern)
  - Long-press or "+" button to add items (search-based, reusing `EditorialSearchView` pattern)

#### THIS WEEK tab

- Shows only rail items where **your** status is WATCHING/READING.
- Grouped by rail.
- Each item shows:
  - Cover image (small, 48x68pt)
  - Title: `.kuroBody(weight: .regular)`
  - Your progress: "EP 5/12" or "CH 23/?"
  - Club aggregate: "2 others watching" / "1 member finished"
- This is the "at a glance" view for active watching.

#### POLLS tab

- Vertical list of polls (open first, then closed).
- Each poll card (glass bubble, like `ConciergeBubble`):
  - Question: `.kuroBody(weight: .regular)`
  - Options as tappable rows with radio dots (same pattern as `ConciergeMatchRow`)
  - Vote count per option: `.kuroMicro`, shown after you vote
  - "CLOSED" badge if poll is closed
  - Creator can close poll with a button

### 5.4) Club Progress in `MediaDetailSheet`

When viewing a media item that belongs to any club rail the user is in, a **club section** appears in the detail view:

- Section header: "IN YOUR CLUBS", `.kuroCaption(weight: .medium)`, tracking 1.6
- For each club that has this item in a rail:
  - Club name: `.kuroCaption()`, `.black.opacity(0.55)`
  - Aggregate progress bar (e.g., 3/5 members completed)
  - If sharing level allows: mini member list showing status icons

### 5.5) Settings (per-club)

Accessible from ClubDetailView's header (gear icon):

- Club name (editable by owner)
- Description (editable by owner)
- Sharing level picker (owner only)
- **Your sharing level** picker (any member, can only go lower than club default)
- Invite code display + "REGENERATE" button (owner only)
- Member list with role badges
- "LEAVE CLUB" button (destructive, red text)
- Archive toggle (owner only)

---

## 6) Import Reconciliation

This extends the existing concierge parse+apply pipeline to detect entries that already exist in the user's collection, and propose Add/Update/Skip actions instead of blindly adding everything.

### 6.1) Backend Changes (Edge Functions)

#### `concierge-parse` Extensions

The parse response gains a new field per item:

```typescript
interface ConciergeParseItem {
  raw: string;
  normalized: string;
  parsed: ConciergeParseItemParsed;
  candidates: ConciergeCandidate[];
  candidateError: string | null;
  // NEW:
  existing_entry: {
    media_type: string;        // 'ANIME' | 'MANGA'
    media_id: number;
    status: string;            // current list status
    progress_episodes: number | null;
    progress_chapters: number | null;
    progress_volumes: number | null;
    rating: number | null;
    updated_at: string;        // ISO timestamp
  } | null;
}
```

**Logic change in `concierge-parse`:**
After candidate resolution, for each item where a top candidate is selected with score >= 0.60, check `anime_user_lists` / `manga_user_lists` for an existing row matching (user_id, media_type, media_id). If found, attach the `existing_entry` object.

#### `concierge-apply` Extensions

The apply request gains new fields per item:

```typescript
interface ApplyItem {
  // Existing fields:
  raw: string;
  mediaType: string;
  mediaId: number;
  status: string;
  confidence: number;
  progressEpisodes?: number;
  progressChapters?: number;
  progressVolumes?: number;
  // NEW:
  action: 'add' | 'update' | 'skip';   // default 'add' for backwards compat
  diff?: {
    status?: { from: string; to: string };
    progress_episodes?: { from: number; to: number };
    progress_chapters?: { from: number; to: number };
    progress_volumes?: { from: number; to: number };
    rating?: { from: number | null; to: number | null };
  };
}
```

**Logic change in `concierge-apply`:**
- `action: 'add'` — current behavior (upsert into user list).
- `action: 'update'` — only update the fields present in `diff`. Record the `from` values in `import_session_items` so undo can restore them.
- `action: 'skip'` — do nothing, but still record in `import_session_items` for audit.

#### `concierge-undo` Extensions

For items with `action: 'update'`, undo restores the previous values (from the `from` fields stored in `import_session_items`). For `action: 'add'`, undo deletes the entry (current behavior).

#### `import_session_items` Schema Extension

Add column:

```sql
ALTER TABLE import_session_items
  ADD COLUMN IF NOT EXISTS action text NOT NULL DEFAULT 'add'
    CHECK (action IN ('add', 'update', 'skip')),
  ADD COLUMN IF NOT EXISTS previous_state jsonb;
```

`previous_state` stores the full previous user-list row as JSON when `action = 'update'`, enabling accurate undo.

### 6.2) iOS Changes

#### New Codable Types

```swift
extension SupabaseService {
    struct ConciergeExistingEntry: Decodable, Sendable {
        let media_type: String
        let media_id: Int
        let status: String
        let progress_episodes: Int?
        let progress_chapters: Int?
        let progress_volumes: Int?
        let rating: Int?
        let updated_at: String
    }
}
```

`ConciergeParseItem` gains:
```swift
let existingEntry: ConciergeExistingEntry?
```

#### `ConciergeReconcileBubble` (New View)

Replaces `ConciergeConfirmBubble` when any items have `existing_entry != null`. Follows the same glass-bubble pattern.

**Layout per item:**

- **New items** (no existing entry): Same as current `ConciergeMatchRow` with "ADD" badge.
- **Existing items** (has existing entry): Show a diff view:
  - Title: `.kuroBody(weight: .regular)`
  - Current status/progress shown in `.kuroCaption`, `.black.opacity(0.45)` (dimmed)
  - Proposed change shown in `.kuroCaption(weight: .medium)`, `.black` (bold)
  - Diff lines: `"EP 3/12 -> EP 8/12"`, `"PLANNING -> WATCHING"`
  - Action picker (three-state segmented): `ADD` / `UPDATE` / `SKIP`
    - Default for new items: `ADD`
    - Default for existing items: `UPDATE` if parsed progress > existing progress, else `SKIP`
  - Skip items shown dimmed (`.opacity(0.4)`)

**Auto-apply safety rule:**
Auto-apply (the all-high-confidence path) is **disabled** when any item has an `existing_entry`. The user must always see the reconcile bubble to review updates. This prevents silent overwrites.

**Undo for updates:**
When an update is undone, the toast shows "Restored previous values" instead of "Removed from collection".

### 6.3) Structured Diff Computation

The diff is computed client-side by comparing `existing_entry` fields with the parsed values:

```swift
func computeDiff(existing: ConciergeExistingEntry, parsed: ConciergeParseItemParsed) -> ImportDiff? {
    var diff = ImportDiff()
    if let parsedStatus = parsed.status,
       parsedStatus.uppercased() != existing.status.uppercased() {
        diff.status = (from: existing.status, to: parsedStatus.uppercased())
    }
    if let ep = parsed.progressEpisodes,
       ep != (existing.progress_episodes ?? 0) {
        diff.progressEpisodes = (from: existing.progress_episodes ?? 0, to: ep)
    }
    // ... chapters, volumes, rating
    return diff.isEmpty ? nil : diff
}
```

---

## 7) Quality Gates

Quality gates are checks that run before code ships. They are divided into **ship gates** (must pass to merge/deploy) and **warnings** (advisory, logged but non-blocking).

### 7.1) Ship Gates (Blocking)

These MUST pass. CI fails if any gate fails.

| Gate | What it checks | Where it runs |
|------|---------------|---------------|
| **Swift build** | `xcodebuild build` succeeds with zero errors | CI (GitHub Actions) |
| **Migration lint** | All SQL files in `supabase/migrations/` parse without syntax errors; no `DROP TABLE` without `IF EXISTS`; no raw `DELETE FROM` without `WHERE` | CI script: `scripts/lint_migrations.sh` |
| **RLS audit** | Every new table in a migration has `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` and at least one policy | CI script: `scripts/audit_rls.sh` |
| **Edge function deploy check** | All edge functions in `supabase/functions/*/index.ts` pass `deno check --no-lock` (type-check only, no deploy) | CI script: `scripts/check_edge_functions.sh` |
| **No secrets in code** | `grep -rn` for patterns matching JWT tokens, API keys, `service_role`, `sk_live_` in tracked files (excluding `.env*` and known false positives) | CI script: `scripts/scan_secrets.sh` |
| **Schema snapshot diff** | After applying all migrations to a clean database, the resulting schema matches the expected snapshot (catches migration ordering bugs) | CI script: `scripts/verify_schema_snapshot.sh` |

### 7.2) Warnings (Non-blocking)

These are logged in CI output but do not fail the build. They flag things that should be addressed but are not release-blockers.

| Warning | What it checks |
|---------|---------------|
| **Missing indexes** | Tables with > 10k expected rows that lack indexes on FK columns or common query patterns |
| **Large migration** | Any single migration file > 200 lines (suggests it should be split) |
| **Unused RPC** | RPCs defined in migrations that are not referenced in any Swift file or edge function |
| **Missing Codable** | Edge function response fields that don't have a corresponding Decodable property in Swift structs |
| **Stale cache TTL** | In-memory cache TTLs in `SupabaseService.swift` that exceed 1 hour (may serve stale data) |

### 7.3) Local Development Gates

Scripts that developers run locally before pushing:

| Script | Command | Description |
|--------|---------|-------------|
| `scripts/lint_migrations.sh` | `bash scripts/lint_migrations.sh` | Parse-checks all migration SQL files |
| `scripts/audit_rls.sh` | `bash scripts/audit_rls.sh` | Verifies RLS + policies on all public tables |
| `scripts/scan_secrets.sh` | `bash scripts/scan_secrets.sh` | Scans for accidentally committed secrets |
| `scripts/check_edge_functions.sh` | `bash scripts/check_edge_functions.sh` | Type-checks all Deno edge functions |

### 7.4) Pre-commit Hook (Optional)

A lightweight pre-commit hook that runs `scan_secrets.sh` to prevent accidental credential commits:

```bash
#!/bin/bash
bash scripts/scan_secrets.sh
if [ $? -ne 0 ]; then
  echo "BLOCKED: Possible secrets detected. See output above."
  exit 1
fi
```

---

## 8) Implementation Notes

### 8.1) Conventions to Follow

- **`@Observable` pattern** — all new service/model classes use `@Observable`, not Combine.
- **Edge function invocation** — use the existing `client.functions.invoke()` pattern with `Task.detached(priority: .userInitiated)` for decode-off-main-actor.
- **RPC invocation** — use `client.rpc("name", params: ...)` via typed Encodable param structs in `SupabaseRPCParams.swift`.
- **Glass surfaces** — use `KuroGlassCard` for cards, `KuroGlassPill` for action buttons. Do not create new surface primitives.
- **Typography** — all text must use `Font.kuro*` tokens. No raw `.system()` or `.caption`.
- **Spacing** — use `KuroDesignSpacing.*` and `KuroRadius.*`. No magic numbers.
- **Animations** — use `KuroAnimation.*` tokens. No raw `withAnimation(.easeInOut(...))`.
- **Error display** — errors appear as inline red text (`.kuroCaption()`, `.red.opacity(0.85)`) or `KuroToast` with `.error` kind. No alerts.
- **Haptics** — `KuroAccessibility.impactHaptic(.light)` on user actions.

### 8.2) Migration Naming

Follow the existing pattern: `YYYYMMDDHHMMSS_descriptive_snake_case.sql`. All migrations must be idempotent where possible (`CREATE TABLE IF NOT EXISTS`, `CREATE OR REPLACE FUNCTION`, etc.).

### 8.3) Performance Budget

- `fetch_club_bundle` must return in < 200ms for a club with 20 members, 5 rails, 50 items, 3 polls.
- Club-related data is NOT prefetched at app launch. It loads lazily when the user navigates to the Clubs page.
- Club bundle is cached in-memory with a 5-minute TTL (same `TimedCache` pattern as `discoverBundleCache`).

### 8.4) Telemetry

Club actions should be logged to `concierge_runs` (reuse existing) with a new `action_type` prefix: `club_create`, `club_join`, `club_leave`, `club_vote`, `club_add_rail_item`. This reuses the existing ops observability pipeline.

---

## 9) Out of Scope (Explicitly Deferred)

- **Notifications / push** — no push notifications for club activity in v1.
- **Real-time sync** — no Supabase Realtime subscriptions for clubs in v1. Data refreshes on pull-to-refresh and view appear.
- **Media syncing from AniList** — club members must have media in the Kuro catalog. No cross-platform sync.
- **Multiple votes per poll** — single choice only in v1.
- **Club discovery / public clubs** — all clubs are private, invite-only in v1.
- **Rich text in notes/descriptions** — plain text only.
- **Club-level recommendations** — no "recommend to club" flow in v1.

---

## 10) Revision History

| Date | Version | Changes |
|------|---------|---------|
| 2026-02-09 | 1.0 | Initial spec |
