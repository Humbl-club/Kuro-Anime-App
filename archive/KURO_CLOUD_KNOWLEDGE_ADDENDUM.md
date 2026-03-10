# KURO - CLOUD KNOWLEDGE ADDENDUM
**Additional Components & Features Discovered**
**Date:** October 8, 2025

---

## 🔍 ADDITIONAL VIEWS DISCOVERED

### MangaDetailView

**File:** [MangaDetailView.swift](Kuro/Views/DetailPages/MangaDetailView.swift)

**Structure:** Nearly identical to AnimeDetailView with manga-specific adaptations

**Key Differences from AnimeDetailView:**

1. **Badge:** Shows "MANGA" badge with green accent (vs. blue for anime)
2. **Stats Grid:** Shows SCORE / CHAPTERS / VOLUMES (vs. EPISODES)
3. **Icons:**
   - `book.fill` for chapters
   - `books.vertical.fill` for volumes
4. **Sections:**
   - ChaptersSection (shows first 5 chapters)
   - VolumesSection (shows first 6 volumes in 3-col grid)

**ChaptersSection Component:**
```swift
// Lines: 204-256
VStack {
    HStack {
        Text("CHAPTERS")
        Spacer()
        Text("\(chapterCount) TOTAL")
    }

    ForEach(1...min(chapterCount, 5)) { chapter in
        ChapterRow(chapterNumber: chapter)  // "CH 1" with chevron
    }

    if chapterCount > 5 {
        Button("VIEW ALL \(chapterCount) CHAPTERS") { ... }
    }
}
```

**VolumesSection Component:**
```swift
// Lines: 282-341
LazyVGrid(columns: 3) {
    ForEach(1...min(volumeCount, 6)) { volume in
        VolumeCard(volumeNumber: volume)
    }
}

// VolumeCard shows:
// book.fill icon
// "VOL 1" text
// Subtle background with 8px border radius
```

**Design Consistency:**
- Same parallax hero effect
- Same description expansion
- Same genre flow layout
- Same action buttons (ADD TO LIST, FAVORITE, SHARE)
- Reuses: `DescriptionSection`, `GenresSection`, `BackButton`

---

## 📱 COLLECTION MANAGEMENT VIEW

**File:** [CollectionManagementView.swift](Kuro/Views/Collection/CollectionManagementView.swift)

**Purpose:** Full user list management system (not yet used in main app)

### Structure

```
VStack
├── CollectionHeader ("MY COLLECTION")
├── StatusFilterBar (6 statuses)
└── CollectionItemCard (grid)
```

**StatusFilterBar:**
```swift
// Lines: 98-122
ScrollView(.horizontal) {
    HStack(spacing: KuroSpacing.xl) {
        ForEach(ListStatus.allCases) { status in
            StatusFilterButton(status)
        }
    }
}

// ListStatus enum (SupabaseModels.swift):
.current    → "Watching"
.planning   → "Planned"
.completed  → "Completed"
.dropped    → "Dropped"
.paused     → "Paused"
.repeating  → "Rewatching"
```

**Visual Design:**
```
Text(status.uppercased())
    .font(.kuroMicro)
    .foregroundColor(isSelected ? .kuroBlack : .kuroBlack60)

Rectangle()  // Underline
    .frame(height: 1)
    .scaleEffect(x: isSelected ? 1.0 : 0.0)
```

**CollectionItemCard Features:**
```swift
// Lines: 148-200
VStack {
    AsyncImage (0.7 aspect, 8px radius)
    ProgressBar (2px height, black fill)
    Title (2 lines, uppercase)
    Episode text
}

// ProgressBar component
ZStack(alignment: .leading) {
    Rectangle()  // Background (8% opacity)
    Rectangle()  // Progress (100% opacity)
        .frame(width: width * progress)
}
.frame(height: 2)
```
**Shows current progress**: 5/24 episodes visually

**EmptyCollectionView:**
```swift
// Lines: 228-293
VStack {
    Image(systemName: emptyIcon)  // play.circle, clock, checkmark, etc.
        .font(.system(size: 48, weight: .ultraLight))

    Text("NO \(status.uppercased()) ITEMS")
    Text(emptyMessage)

    Button("EXPLORE CONTENT") { ... }
}
```

---

## ➕ ADD TO LIST SHEET

**File:** [CollectionManagementView.swift:295-430](Kuro/Views/Collection/CollectionManagementView.swift#L295-430)

**Purpose:** Complete UI for adding anime/manga to user lists

### Components

**1. MediaPreview:**
```swift
// Lines: 432-481
HStack {
    AsyncImage (80×120px, 8px radius)

    VStack {
        Title (2 lines, medium weight)
        Year
        Episode/Chapter count
    }
}
.padding(KuroSpacing.md)
.background(Color.kuroBlack08)
```

**2. Status Selection Grid:**
```swift
// Lines: 313-336
LazyVGrid(columns: 2) {
    ForEach(ListStatus.allCases) { status in
        StatusCard(status)
    }
}
```

**StatusCard Design:**
```swift
// Lines: 483-522
VStack {
    Image(systemName: statusIcon)  // play.circle.fill, clock.fill, etc.
        .font(.kuroCardTitle)
        .foregroundColor(isSelected ? .kuroBlack : .kuroBlack30)

    Text(status.displayName.uppercased())
        .font(.kuroMicro)
}
.padding(.vertical, KuroSpacing.lg)
.background(isSelected ? Color.kuroBlack08 : .clear)
.overlay(
    RoundedRectangle()
        .stroke(isSelected ? .kuroBlack : .kuroBlack15, lineWidth: 1)
)
```

**Icons for each status:**
- CURRENT: `play.circle.fill`
- PLANNING: `clock.fill`
- COMPLETED: `checkmark.circle.fill`
- DROPPED: `xmark.circle.fill`
- PAUSED: `pause.circle.fill`
- REPEATING: `arrow.clockwise.circle.fill`

**3. Progress Tracker:**
```swift
// Lines: 338-357
if selectedStatus == .current {
    VStack {
        Text("PROGRESS")

        Stepper(value: $progress, in: 0...(episodes ?? chapters ?? 100)) {
            Text("\(progress) / \(total)")
        }
        .padding(KuroSpacing.md)
        .background(Color.kuroBlack08)
    }
}
```

**4. Score Rating:**
```swift
// Lines: 359-378
HStack {
    ForEach(1...10) { star in
        Button {
            score = star
        } label: {
            Image(systemName: star <= score ? "star.fill" : "star")
                .foregroundColor(star <= score ? .kuroBlack : .kuroBlack30)
        }
    }
}
```
**10-star rating system** (not 5-star)

**5. Notes TextEditor:**
```swift
// Lines: 380-394
TextEditor(text: $notes)
    .font(.kuroMicro(weight: .light))
    .frame(height: 100)
    .padding(KuroSpacing.sm)
    .background(Color.kuroBlack08)
```

**6. Save Button:**
```swift
// Lines: 396-406
Button("ADD TO LIST") {
    saveToList()  // TODO: Actually save to Supabase
}
.padding(.vertical, KuroSpacing.lg)
.background(Color.kuroBlack)
```

**Current Status:**
- ⚠️ UI complete and designed
- ❌ Backend integration missing (`saveToList()` is TODO)
- ❌ Not yet called from main app

---

## 🚀 ENHANCED CONTENT VIEW

**File:** [EnhancedContentView.swift](Kuro/Views/EnhancedContentView.swift)

**Purpose:** Alternative implementation with iOS 26 enhancements (not currently used)

**Key Differences from Standard ContentView:**

### 1. Enhanced Launch Sequence

**Standard Launch:** Simple 2-second fade
```swift
// ContentView.swift
0.0s → Logo fades in
0.3s → Subtitle fades in
2.0s → Dismiss
```

**Enhanced Launch:** Progress-based with loading text
```swift
// EnhancedContentView.swift:38-61
0.0s → Progress 0% → 30% (0.8s)
0.5s → Progress 30% → 70% (0.6s)
1.2s → Progress 70% → 100% (0.4s)
2.0s → Dismiss with scale transition

// Includes:
- LinearGradient background (subtle)
- ProgressView bar (0.5 scale height)
- "LOADING COLLECTION..." text
```

### 2. Velocity-Based Swipe Detection

**Standard:** Threshold-only (33% of screen)
**Enhanced:** Threshold + velocity check
```swift
// EnhancedContentView.swift:179-196
let velocity = value.velocity.width

if abs(velocity) > 500 {
    KuroAccessibility.impactHaptic(.medium)  // Stronger haptic for fast swipe
}
```

### 3. TabView-Based Discover

**Standard:** Manual HStack + offset
**Enhanced:** Native TabView with page style
```swift
// EnhancedContentView.swift:309-322
TabView(selection: $currentIndex) {
    ForEach(animeItems.prefix(10)) { anime in
        EnhancedFeaturedCard(media: anime)
            .tag(index)
    }
}
.tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
.onChange(of: currentIndex) { _ in
    KuroAccessibility.impactHaptic(.light)
}
```

### 4. Enhanced Featured Card

**Differences from standard FeaturedCardReal:**
- **Rounded corners:** Uses adaptive radius (vs. sharp corners)
- **Badge position:** Top-right over image (vs. bottom)
- **Card background:** White card with shadow (vs. flush to background)
- **Episode/Chapter info:** Top-right alignment (vs. in text block)
- **Layout:** More compact, card-based design

```swift
// EnhancedContentView.swift:336-422
VStack {
    HStack {
        Spacer()
        KuroStyle.mediaBadge("ANIME", isAnime: true)  // Top right
    }

    AsyncImage(...)
        .cornerRadius(KuroRadius.adaptive(KuroRadius.md, for: width))

    VStack {
        HStack(alignment: .top) {
            VStack(alignment: .leading) {
                Title
                Year
            }

            Spacer()

            VStack(alignment: .trailing) {
                Text("\(episodes) EPS")  // Top right
            }
        }

        Description (3 lines)
    }
}
.background(KuroStyle.card())  // White card with shadow
```

**Why Not Used:**
- Standard ContentView chosen for more editorial/magazine feel
- Sharp corners preferred for minimalism
- EnhancedContentView kept as alternative iOS 26 reference

---

## 📊 COMPONENT STATUS MATRIX

| Component | File | Lines | Status | Used In App |
|-----------|------|-------|--------|-------------|
| KuroMainView | ContentView.swift | 70-141 | ✅ Production | Main navigation |
| AnimeDetailView | AnimeDetailView.swift | 6-518 | ✅ Production | Anime sheets |
| MangaDetailView | MangaDetailView.swift | 6-403 | ✅ Production | Manga sheets |
| CollectionManagementView | CollectionManagementView.swift | 6-523 | ⚠️ Designed | Not used yet |
| AddToListSheet | CollectionManagementView.swift | 295-430 | ⚠️ Designed | Not connected |
| EnhancedContentView | EnhancedContentView.swift | 6-502 | ⚠️ Alternative | Not used |
| EnhancedFeaturedCard | EnhancedContentView.swift | 336-422 | ⚠️ Alternative | Not used |

---

## 🎨 DESIGN SYSTEM EXTENSIONS

### Additional Components Found

**1. ProgressBar** (for watch/read progress)
```swift
// CollectionManagementView.swift:202-226
GeometryReader { geometry in
    ZStack(alignment: .leading) {
        Rectangle()
            .fill(Color.kuroBlack08)  // Track
            .frame(height: 2)

        Rectangle()
            .fill(Color.kuroBlack)  // Progress
            .frame(width: geometry.size.width * progress, height: 2)
    }
}
```
**Usage:** Shows 5/24 episodes visually beneath collection cards

**2. StatusCard** (for list status selection)
- Grid layout (2 columns)
- Icon + Text vertical stack
- Selected: Black border + subtle fill
- Unselected: Gray border + no fill

**3. VolumeCard** (for manga volumes)
- 3-column grid layout
- Book icon + "VOL X" text
- Subtle background (8% opacity)
- Same styling as StatCard

**4. ChapterRow / EpisodeRow** (list items)
- Horizontal layout
- "CH X" / "EP X" text
- Chevron right icon
- Tap to view details
- Subtle background (8% opacity)

---

## 🔄 ANIMATION ENHANCEMENTS

### Found in EnhancedContentView

**Scale + Opacity Transition:**
```swift
.transition(.asymmetric(
    insertion: .opacity.combined(with: .scale(scale: 0.95)),
    removal: .opacity
))
```
**Usage:** Launch → Main transition (more dynamic than standard fade)

**Button Press Feedback:**
```swift
Circle()
    .scaleEffect(showProfile ? 0.95 : 1.0)
    .animation(KuroAnimation.spring, value: showProfile)
```
**Usage:** Profile button in enhanced header

**Velocity-Based Haptics:**
```swift
if abs(velocity) > 500 {
    KuroAccessibility.impactHaptic(.medium)  // Fast swipe
} else {
    KuroAccessibility.impactHaptic(.light)   // Normal swipe
}
```

---

## 📝 TODOS DISCOVERED IN CODE

**From SupabaseService.swift:**
```swift
// Line 129-147
func fetchUserLists() async { ... }          // ❌ TODO: Connect to UI
func addToList(...) async { ... }            // ❌ TODO: Call from AddToListSheet
```

**From CollectionManagementView.swift:**
```swift
// Line 43-46
private var filteredItems: [Anime] {
    // TODO: Filter by user's list status
    supabaseService.animeItems  // Currently shows all items
}

// Line 425-429
private func saveToList() {
    // TODO: Save to Supabase
    KuroAccessibility.successHaptic()
    dismiss()
}
```

**From ContentView.swift:**
```swift
// Line 76
@State private var selectedMood: String? = nil  // Not used anymore
```

**From SearchViewSimple:**
```swift
// Line 496-501
private func performSearch() {
    // Perform search with current text and filters
    Task {
        await supabaseService.searchContent(query: searchText)
    }
}
// Currently uses in-memory filtering, not backend full-text search
```

---

## 🗂️ DATABASE IMPORT SCRIPTS

**Found in root directory:**

**Edge Functions (Deno-based):**
1. `03_updated_edge_function.js` (16,679 bytes)
   - Imports anime from AniList API
   - Bulk import with rate limiting (90 req/min)

2. `04_manga_edge_function.js` (10,844 bytes)
   - Imports manga from AniList API

3. `06_anime_edge_function_with_episodes.js` (12,249 bytes)
   - Imports anime + episode details
   - ⚠️ Episodes come back empty from AniList

4. `07_manga_edge_function_with_chapters.js` (12,653 bytes)
   - Imports manga + chapter details
   - ⚠️ Chapters are placeholders

**Test Scripts:**
1. `test_supabase_connection.js` (3,675 bytes)
   - Tests Supabase connection
   - Verifies credentials

2. `test_import.js` (4,066 bytes)
   - Tests anime import

3. `test_manga_import.js` (5,681 bytes)
   - Tests manga import

4. `test_manga_with_chapters.js` (7,363 bytes)
   - Tests manga + chapters import

**SQL Scripts:**
1. `01_delete_all_tables.sql` (3,656 bytes)
   - Drops all tables for clean slate
   - Use with caution!

2. `02_comprehensive_table_creation.sql` (26,696 bytes)
   - Creates all 22 tables
   - Includes indexes, triggers, constraints

3. `05_fix_triggers_and_episodes.sql` (4,542 bytes)
   - Fixes `description_normalized` trigger
   - Creates episode-related functions

---

## 🔍 ADDITIONAL INSIGHTS

### Why Two ContentView Implementations?

**Standard ContentView (Used):**
- Sharp corners → editorial magazine feel
- Manual offset calculation → more control
- Flush featured cards → gallery aesthetic
- Chosen for **maximum minimalism**

**EnhancedContentView (Not Used):**
- Rounded corners → typical iOS feel
- TabView → native iOS behavior
- Card-based layout → familiar mobile pattern
- Kept as **iOS 26 reference implementation**

### ListStatus Enum Design

```swift
enum ListStatus: String, Codable, CaseIterable {
    case current = "CURRENT"      // Raw value for DB
    case planning = "PLANNING"
    case completed = "COMPLETED"
    case dropped = "DROPPED"
    case paused = "PAUSED"
    case repeating = "REPEATING"

    var displayName: String {     // Friendly name for UI
        switch self {
        case .current: return "Watching"
        case .planning: return "Planned"
        // ...
        }
    }
}
```
**Smart design:** Raw value matches database, displayName for UI

### Progress Tracking Design

**Two-tier system:**
1. **Episodes/Chapters:** Primary progress (e.g., 5/24)
2. **Volumes:** Secondary progress for manga (e.g., 1/3)

```swift
struct UserList {
    let progress: Int              // Episodes or chapters
    let progressVolumes: Int?      // Manga only
}
```

---

## 📈 UPDATED STATISTICS

**Swift Files:** 13 total
- Production: 8 files
- Alternative: 1 file (EnhancedContentView)
- Test files: 2 files

**Total Lines of Swift Code:** ~4,500 lines
- ContentView.swift: 981 lines
- AnimeDetailView.swift: 518 lines
- MangaDetailView.swift: 403 lines
- CollectionManagementView.swift: 523 lines
- EnhancedContentView.swift: 502 lines
- SupabaseService.swift: 260 lines
- SupabaseModels.swift: 403 lines
- KuroDesignSystem.swift: 318 lines

**Components:** 40+ reusable components
- 6 major views
- 20+ card/row components
- 10+ button/input components
- 5+ layout helpers

**Animations:** 8 distinct animation types
- Launch fade-ins
- Section navigation
- Filter tab animations
- Progress bar fills
- Button press feedback
- Sheet presentations
- Dot indicators
- Velocity-based haptics

---

**END OF ADDENDUM**

*This addendum adds details on MangaDetailView, CollectionManagementView, AddToListSheet, EnhancedContentView, and all discovered database scripts. It should be read alongside the main KURO_CLOUD_KNOWLEDGE.md file.*
