# KURO - COMPLETE CLOUD KNOWLEDGE BASE
**Living Document - Single Source of Truth**
**Last Updated:** October 8, 2025 (15:05 PM - Major Design Update)
**iOS Version:** 26.0+
**Architecture:** SwiftUI + Supabase PostgreSQL
**Design Philosophy:** Elevated Minimalism / Editorial Minimalism

---

## 🆕 RECENT UPDATES (October 8, 2025)

**⭐ MAJOR REDESIGN - SLEEK, POLISHED, WELL-DESIGNED:**
1. ✅ **Complete DISCOVER overhaul** - Netflix-style with hero featured, horizontal scrolling, 2-column grids
2. ✅ **Data filtering fixed** - Real Calendar-based season detection (no more wrong data!)
3. ✅ **Score badges** - Added to ALL cards for instant quality feedback
4. ✅ **Mixed layouts** - Hero + horizontal sections + grid sections = engaging experience
5. ✅ **New file: DiscoverView.swift** (533 lines) - Replaces DiscoverViewSimple entirely
6. ✅ **5 smart sections** - Featured, Current Season, Trending, Top Rated, Just Added
7. ✅ **Proportional everything** - All sizing uses `max(width * %, min)` pattern

**Earlier Updates:**
- ✅ Header optimized (48px vs 60px, adaptive padding)
- ✅ Dot indicators repositioned (safe area handling)
- ✅ Smart layout refactoring (91% code reduction)

**See:** [SLEEK_REDESIGN_COMPLETE.md](SLEEK_REDESIGN_COMPLETE.md) for complete redesign details

---

## 📋 TABLE OF CONTENTS

1. [Design System Deep Dive](#design-system-deep-dive)
2. [Navigation Architecture](#navigation-architecture)
3. [Frontend Implementation](#frontend-implementation)
4. [Backend Architecture](#backend-architecture)
5. [File Organization](#file-organization)
6. [Data Flow](#data-flow)
7. [Component Anatomy](#component-anatomy)
8. [Responsive Design](#responsive-design)
9. [Animation System](#animation-system)
10. [State Management](#state-management)

---

## 🎨 DESIGN SYSTEM DEEP DIVE

### Visual Language: "Elevated Minimalism"

**Inspirations:**
- Swiss Design: Grid-based, systematic, mathematical precision
- Fashion Editorial: Hermès, Bottega Veneta app aesthetics
- Gallery Aesthetic: Content first, interface invisible

**Core Principles:**
1. **Spatial Luxury** - Generous whitespace as a luxury element
2. **Typography Hierarchy** - Clear, intentional text relationships
3. **Color Restraint** - Only black, white, opacity variations
4. **Subtle Motion** - Smooth, purposeful animations (0.3-0.4s)
5. **Fixed Header Pattern** - Three-part layout stays visible
6. **Swipe-First Navigation** - Horizontal page-style browsing
7. **Minimal Indicators** - Tiny 6px dot indicators

### Color System

**File:** [KuroDesignSystem.swift:9-28](Kuro/Design/KuroDesignSystem.swift#L9-28)

```swift
// Primary Palette
.kuroBlack         // #000000 (100% opacity)
.kuroWhite         // #FFFFFF (100% opacity)

// Opacity Scale (8px base unit philosophy)
.kuroBlack80       // rgba(0,0,0,0.8)  - Primary text, headings
.kuroBlack60       // rgba(0,0,0,0.6)  - Secondary text, descriptions
.kuroBlack30       // rgba(0,0,0,0.3)  - Tertiary text, labels
.kuroBlack08       // rgba(0,0,0,0.08) - Subtle backgrounds, dividers

// Functional Accents (minimal use)
.kuroAnime         // Blue opacity(0.8) - Anime type badge only
.kuroManga         // Green opacity(0.8) - Manga type badge only
```

**Design Rules:**
- ❌ NO gradients (except image overlays)
- ❌ NO bright colors (except badges)
- ✅ ALL variations through opacity only
- ✅ Force light mode: `.preferredColorScheme(.light)`

**Usage Examples:**
```swift
// Header text: KURO brand
.foregroundColor(.black.opacity(0.3))  // Very subtle

// Navigation section names: DISCOVER, COLLECTION
.foregroundColor(.black)  // Full opacity

// Body descriptions
.foregroundColor(.black.opacity(0.6))  // Readable but subtle
```

### Typography System

**File:** [KuroDesignSystem.swift:30-56](Kuro/Design/KuroDesignSystem.swift#L30-56)

**5 Type Styles:**

1. **Micro (10-11pt)** - Labels, metadata, captions
   ```swift
   Font.kuroMicro(weight: .light)
   // Use: Genre tags, year labels, episode counts
   ```

2. **Body (14-16pt)** - Content, descriptions
   ```swift
   Font.kuroBody(weight: .light)
   // Use: Descriptions, body text, readable paragraphs
   ```

3. **Display (24-32pt)** - Titles, heroes
   ```swift
   Font.kuroDisplay(weight: .ultraLight)
   // Use: Page titles, hero titles (serif design for elegance)
   ```

4. **Navigation (11pt)** - Tab labels
   ```swift
   Font.kuroNavigation(weight: .regular)
   // Use: Header navigation, section labels
   ```

5. **Card Title (18-20pt)** - Content cards
   ```swift
   Font.kuroCardTitle(weight: .ultraLight)
   // Use: Featured card titles (serif design)
   ```

**Letter Spacing (Tracking):**
- **Labels/Navigation:** 1.5pt (loose for uppercase labels)
- **Titles:** 0.5-1.0pt (balanced for readability)
- **Body:** 0.5pt (natural reading)
- **Micro:** 0.5-1.0pt (clarity at small sizes)

**Text Transform:**
- **Most UI text:** UPPERCASE (labels, titles, nav)
- **Descriptions:** Sentence case (natural reading)
- **Titles:** UPPERCASE (editorial style)

### Spacing System

**File:** [KuroDesignSystem.swift:58-79](Kuro/Design/KuroDesignSystem.swift#L58-79)

**8px Base Unit Philosophy:**
All spacing follows 8px increments for mathematical harmony.

```swift
KuroSpacing.xs    = 4px   // 0.5 units - Tight spacing
KuroSpacing.sm    = 8px   // 1 unit   - Small gaps
KuroSpacing.md    = 16px  // 2 units  - Standard padding
KuroSpacing.lg    = 24px  // 3 units  - Card padding
KuroSpacing.xl    = 32px  // 4 units  - Section spacing
KuroSpacing.xxl   = 48px  // 6 units  - Featured cards
KuroSpacing.xxxl  = 64px  // 8 units  - Major sections
```

**Responsive Scaling:**
```swift
KuroSpacing.adaptive(base, screenWidth)

// iPhone SE (< 375px):     base * 0.8
// iPhone Standard (375-414px): base * 1.0
// iPhone Plus (414-768px):  base * 1.2
// iPad Portrait (768-1024px): base * 1.5
// iPad Landscape (1024px+): base * 2.0
```

**Common Applications:**
- Card internal padding: `lg` (24px)
- Between sections: `xl` (32px)
- Featured card vertical gap: `xxl` (48px)
- Component internal gaps: `sm-md` (8-16px)

### Animation System

**File:** [KuroDesignSystem.swift:131-149](Kuro/Design/KuroDesignSystem.swift#L131-149)

**Timing Functions:**
```swift
KuroAnimation.fast       // 0.2s easeInOut - Button press
KuroAnimation.standard   // 0.3s easeInOut - Filter selection
KuroAnimation.slow       // 0.4s easeInOut - Sheet presentation
KuroAnimation.spring     // Spring(0.4, 0.8) - Section navigation
KuroAnimation.springBouncy // Spring(0.5, 0.6) - Playful interactions
```

**Animation Principles:**
- **Opacity:** Primary animation method (fade in/out)
- **Scale:** 0.95-1.05 max (very subtle scale on press)
- **No rotation** unless absolutely necessary
- **No bouncy effects** (damping 0.6-0.8 for smoothness)
- **Haptic feedback:** Synchronized with animations

**Implementation Examples:**
```swift
// Filter tab selection
withAnimation(.easeInOut(duration: 0.3)) {
    filter = filterOption
}

// Section navigation with haptic
withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
    currentSection += 1
}
KuroAccessibility.impactHaptic(.light)

// Button press
.scaleEffect(isPressed ? 0.95 : 1.0)
.animation(.easeInOut(duration: 0.2), value: isPressed)
```

---

## 🧭 NAVIGATION ARCHITECTURE

### App Entry Flow

**File:** [ContentView.swift:6-34](Kuro/ContentView.swift#L6-34)

```
KuroApp (@main)
  ↓
ContentView (injects SupabaseService)
  ↓
KuroRootView (manages launch)
  ↓
├─ KuroLaunchView (2 seconds)
│   ├─ "KURO" logo (fade 1.2s)
│   ├─ "CURATED ANIME" subtitle (fade 1.2s + 0.3s delay)
│   └─ Auto-dismiss at 2.0s
│
└─ KuroMainView (main interface)
```

**Launch Animation Sequence:**
```swift
// ContentView.swift:36-68
0.0s → Logo opacity 0→1 (1.2s ease-out)
0.3s → Subtitle opacity 0→1 (1.2s ease-out)
2.0s → Dismiss launch, show main (0.6s ease-in-out)
```

### Main Navigation System

**Type:** Horizontal swipe-based paging (Instagram-style)

**File:** [ContentView.swift:70-141](Kuro/ContentView.swift#L70-141)

**Three Sections:**

```swift
let sections = ["DISCOVER", "COLLECTION", "SEARCH"]
@State private var currentSection = 0  // 0, 1, or 2
```

**1. DISCOVER (Index 0)**
- **Default Active:** Yes
- **Purpose:** Browse curated featured content
- **Data:** `supabaseService.animeItems` (top 10)
- **Layout:** Vertical scroll, large 420px featured cards
- **Spacing:** 48px between cards (adaptive)

**2. COLLECTION (Index 1)**
- **Purpose:** User's personal anime/manga library
- **Data:** User lists filtered by status (TODO: from user_lists table)
- **Layout:** 3-column grid (2-5 columns responsive)
- **Filters:** ALL, WATCHING, COMPLETED, PLANNED

**3. SEARCH (Index 2)**
- **Purpose:** Search and advanced filtering
- **Data:** Filtered `animeItems` (in-memory currently)
- **Layout:** Vertical list with search field + category pills
- **Categories:** TRENDING, NEW SEASON, CLASSICS, HIDDEN GEMS

### Swipe Gesture Implementation

**File:** [ContentView.swift:106-122](Kuro/ContentView.swift#L106-122)

**How It Works:**

```swift
// Real-time drag tracking
.offset(x: -CGFloat(currentSection) * geometry.size.width + dragOffset)

// Gesture detection
DragGesture()
    .onChanged { value in
        dragOffset = value.translation.width  // Track finger position
    }
    .onEnded { value in
        let threshold = UIScreen.main.bounds.width / 3  // 33% of screen

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            if value.translation.width > threshold && currentSection > 0 {
                currentSection -= 1  // Swipe RIGHT → previous section
            } else if value.translation.width < -threshold && currentSection < 2 {
                currentSection += 1  // Swipe LEFT → next section
            }
            dragOffset = 0
        }
    }
```

**Parameters:**
- **Threshold:** 33% of screen width (~125px on 375px iPhone)
- **Animation:** Spring (response: 0.4, damping: 0.8)
- **Haptic:** Light impact on successful navigation
- **Direction:** Swipe LEFT = next, Swipe RIGHT = previous

**Visual Feedback:**
- Real-time finger tracking (content follows swipe)
- Snap to nearest section on release
- Smooth spring animation back to position
- Dot indicators update in sync

### Fixed Header Component

**File:** [ContentView.swift:143-221](Kuro/ContentView.swift#L143-221)

**Structure:**
```
┌──────────────────────────────────────────┐
│  KURO      DISCOVER            [M]       │ ← 60px + safe area
├──────────────────────────────────────────┤
│  ─────────────────────────────────────── │ ← 0.5px divider
└──────────────────────────────────────────┘
```

**Three-Part Layout:**

**Left: Brand Identity (30% opacity)**
```swift
Text("KURO")
    .font(.system(size: 11, weight: .regular))
    .tracking(1.5)
    .foregroundColor(.black.opacity(0.3))  // Very subtle
```

**Center: Section Name (100% opacity)**
```swift
Text(currentSection)  // "DISCOVER", "COLLECTION", "SEARCH"
    .font(.system(size: 11, weight: .regular))
    .tracking(1.5)
    .foregroundColor(.black)  // Full black
```
**Changes dynamically** as user swipes between sections.

**Right: Profile Button (minimal interaction)**
```swift
Button { showProfile.toggle() } label: {
    Circle()
        .fill(Color.black.opacity(0.08))  // Subtle background
        .frame(width: 32, height: 32)
        .overlay(
            Text("M")  // User initial
                .font(.system(size: 14, weight: .light))
                .foregroundColor(.black)
        )
}
```

**Responsive Padding:**
```swift
// ContentView.swift:201-214
< 375px:    16px  // iPhone SE
375-414px:  20px  // iPhone standard
414-768px:  24px  // iPhone Plus
768-1024px: 32px  // iPad Portrait
1024px+:    40px  // iPad Landscape
```

### Dot Pagination Indicators

**File:** [ContentView.swift:126-138](Kuro/ContentView.swift#L126-138)

**Position:** Bottom center of screen

**Design:**
```swift
HStack(spacing: 8) {
    ForEach(0..<3) { index in
        Circle()
            .fill(Color.black.opacity(index == currentSection ? 1.0 : 0.2))
            .frame(width: 6, height: 6)
            .scaleEffect(index == currentSection ? 1.2 : 1.0)
    }
}
.padding(.vertical, 12)
.padding(.bottom, 16)
```

**States:**
- **Active:** Black 100% opacity, 6px × 1.2 scale = 7.2px
- **Inactive:** Black 20% opacity, 6px normal size

**Animation:**
- **Timing:** Spring (response: 0.3)
- **Properties:** Scale and opacity simultaneously
- **Sync:** Updates with `currentSection` state

**Interaction:**
- **Tappable:** Yes (each dot jumps to section)
- **Haptic:** Light impact on tap
- **Use Case:** Direct navigation without swiping

---

## 🎨 FRONTEND IMPLEMENTATION

### View Architecture

**Component Hierarchy:**
```
KuroMainView
├── KuroHeader (fixed)
├── Content Area (swipeable)
│   ├── DiscoverViewSimple
│   │   └── FeaturedCardReal × 10
│   ├── CollectionViewSimple
│   │   ├── Filter Tabs (horizontal scroll)
│   │   └── CollectionCardReal × 50 (3-col grid)
│   └── SearchViewSimple
│       ├── Search Field
│       ├── Category Pills (horizontal scroll)
│       └── SearchResultRowReal (lazy list)
└── Dot Indicators (fixed bottom)
```

### DISCOVER Section

**File:** [ContentView.swift:223-289](Kuro/ContentView.swift#L223-289)

**Purpose:** Browse curated featured anime/manga

**Data Loading:**
```swift
.onAppear {
    Task {
        await supabaseService.fetchAnime(limit: 20)
    }
}
```

**Layout:**
```swift
ScrollView(.vertical) {
    VStack(spacing: adaptiveSpacing(for: width)) {
        ForEach(animeItems.prefix(10), id: \.id) { anime in
            FeaturedCardReal(media: anime)
        }
    }
}
```

**Loading States:**
1. **Initial:** 3 skeleton cards (`FeaturedCardLoading`)
2. **Empty:** "LOADING YOUR COLLECTION..." with ProgressView
3. **Loaded:** Real anime cards with images

**Adaptive Spacing:**
```swift
// ContentView.swift:275-288
< 375px:    32px  // Compact
375-414px:  40px  // Standard
414-768px:  48px  // Spacious
768-1024px: 56px  // Generous
1024px+:    64px  // Maximum
```

### Featured Card Component

**File:** [ContentView.swift:886-944](Kuro/ContentView.swift#L886-944)

**Type:** `FeaturedCardReal`

**Size:** Full width × 420px + content padding

**Structure:**
```
Button (opens detail sheet)
└── VStack(spacing: 0)
    ├── AsyncImage
    │   Size: width × 420px
    │   Mode: AspectFill (covers area)
    │   Corner: 0 (sharp edges)
    │
    └── Content VStack (24px padding)
        ├── Title (20pt serif ultraLight uppercase)
        ├── Year (11pt regular 1.5 tracking 50% opacity)
        └── Description (11pt light 1.0 tracking 60% opacity, 3 lines, 4px line spacing)
```

**Interaction:**
```swift
Button {
    KuroAccessibility.impactHaptic(.light)  // Haptic feedback
    showDetail = true
}
.sheet(isPresented: $showDetail) {
    if let anime = media as? Anime {
        AnimeDetailView(anime: anime)  // Full detail view
    } else if let manga = media as? Manga {
        MangaDetailView(manga: manga)
    }
}
```

**Why Sharp Corners?**
Editorial minimalism aesthetic - clean, magazine-like presentation.

### COLLECTION Section

**File:** [ContentView.swift:291-349](Kuro/ContentView.swift#L291-349)

**Purpose:** User's curated anime/manga lists (like MyAnimeList)

**Filter Tabs:**
```swift
let filters = ["ALL", "WATCHING", "COMPLETED", "PLANNED"]
@State private var filter = "ALL"
```

**Tab Design:**
```
ALL  WATCHING  COMPLETED  PLANNED
 ¯                                  (active underline)
```

**Implementation:**
```swift
VStack(spacing: 8) {
    Text(status)
        .foregroundColor(isSelected ? .black : .black.opacity(0.3))

    Rectangle()  // Underline indicator
        .frame(height: 0.5)
        .scaleEffect(x: isSelected ? 1.0 : 0.0)  // Animates width
        .animation(.easeOut(duration: 0.3))
}
```

**Grid Configuration:**
```swift
LazyVGrid(
    columns: [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ],
    spacing: 16  // Row spacing
)
```
**Result:** 3 equal columns, 12px gap between cards, 16px between rows

**Responsive Columns:**
- iPhone SE: 2 columns
- iPhone: 3 columns (default)
- iPad Portrait: 4 columns
- iPad Landscape: 5 columns

### Collection Card Component

**File:** [ContentView.swift:629-701](Kuro/ContentView.swift#L629-701)

**Type:** `CollectionCardReal`

**Size:** Flexible width × 0.7 aspect ratio (portrait) + info text

**Structure:**
```
Button (tappable)
└── VStack(spacing: 0)
    ├── AsyncImage
    │   Aspect: 0.7 (portrait cover)
    │   Corner: 4px (subtle rounding)
    │   Mode: AspectFill
    │
    └── Info VStack (8px top padding)
        ├── Title (10pt regular 0.5 tracking 80% opacity, 2 lines max, uppercase)
        ├── Year · Episodes (9pt light 0.5 tracking 50% opacity)
        └── Rating ★ 8.5 (8pt 40% opacity)
```

**Computed Episode Text:**
```swift
private var episodeText: String {
    if let episodes = media.episodes {
        return "\(episodes) EPS"
    } else if let chapters = media.chapters {
        return "\(chapters) CH"
    } else {
        return "Movie"
    }
}
```

### SEARCH Section

**File:** [ContentView.swift:351-502](Kuro/ContentView.swift#L351-502)

**Purpose:** Search anime/manga by text or category filters

**Search Field Design:**
```swift
HStack {
    Image(systemName: "magnifyingglass")
        .foregroundColor(.black.opacity(0.3))

    TextField("SEARCH ANIME", text: $searchText)
        .font(.system(size: 14, weight: .light))
        .tracking(0.5)
}
.padding(.horizontal, 20)
.padding(.vertical, 16)
.background(Color.black.opacity(0.05))  // Subtle background
.cornerRadius(0)  // Sharp corners
```

**Category Pills:**
```
[TRENDING] [NEW SEASON] [CLASSICS] [HIDDEN GEMS]
```

**Pill Design:**
```swift
Text(category)
    .font(.kuroMicro)
    .foregroundColor(isSelected ? .kuroBlack : .kuroBlack60)
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(
        Capsule()
            .stroke(isSelected ? .kuroBlack80 : .kuroBlack15, lineWidth: 0.5)
            .background(
                Capsule().fill(isSelected ? .kuroBlack05 : .clear)
            )
    )
```

**Selection State:**
- Unselected: Gray stroke, no fill
- Selected: Black stroke, subtle black fill

**Filter Logic:**
```swift
// ContentView.swift:372-386
switch category {
case "TRENDING":
    return (media.averageScore ?? 0) > 80
case "NEW SEASON":
    return Int(media.year) ?? 0 >= 2020
case "CLASSICS":
    return Int(media.year) ?? 0 < 2010
case "HIDDEN GEMS":
    return (media.averageScore ?? 0) > 85 && Int(media.year) ?? 0 < 2015
}
```

**Search Result Row:**
```
[Cover 50×70] TITLE                    8.5 ›
              2023 · Action              ★
              12 EPS
```

**Implementation:**
```swift
HStack(spacing: 16) {
    AsyncImage(url: URL(string: media.imageURL))
        .frame(width: 50, height: 70)
        .cornerRadius(4)

    VStack(alignment: .leading, spacing: 4) {
        Text(media.title.uppercased())
            .font(.system(size: 12))
            .lineLimit(1)

        Text("\(media.year) · \(media.genres?.first ?? "")")
            .font(.system(size: 10))

        Text("\(media.episodes ?? 0) EPS")
            .font(.system(size: 9))
    }

    Spacer()

    VStack {
        Text(String(format: "%.1f", media.rating ?? 0))
        Text("★")
    }

    Image(systemName: "chevron.right")
}
.padding(.vertical, 12)
```

---

## 🗄️ BACKEND ARCHITECTURE

### Supabase Configuration

**File:** [SupabaseService.swift:23-40](Kuro/Services/SupabaseService.swift#L23-40)

**Credentials:**
```swift
supabaseURL: "https://bkdifromsqxkndnllmdj.supabase.co"
supabaseKey: "SUPABASE_SERVICE_KEY_REDACTED"
```

**Initialization:**
```swift
@MainActor
@Observable
class SupabaseService {
    static let shared = SupabaseService()
    private let client: SupabaseClient

    var animeItems: [Anime] = []
    var mangaItems: [Manga] = []
    var userLists: [UserList] = []
    var isLoading = false
    var errorMessage: String?

    init() {
        client = SupabaseClient(...)

        // Auto-initialize on launch
        Task {
            try await signInAnonymously()
            await fetchAnime(limit: 20)
        }
    }
}
```

**Why @Observable?**
New Swift observation framework (replaces @Published) - automatic UI updates when properties change.

### Authentication

**File:** [SupabaseService.swift:42-46](Kuro/Services/SupabaseService.swift#L42-46)

**Method:** Anonymous sign-in

```swift
func signInAnonymously() async throws {
    try await client.auth.signInAnonymously()
    print("✅ Signed in anonymously to Supabase")
}
```

**Why Anonymous?**
- No user registration required
- Instant app access
- Still tracks user lists per anonymous session
- Can upgrade to real auth later

### Data Fetching

**Fetch Anime:**
```swift
// SupabaseService.swift:48-70
func fetchAnime(limit: Int = 50) async {
    isLoading = true
    errorMessage = nil

    do {
        let response: [Anime] = try await client.database
            .from("anime")
            .select()
            .order("popularity", ascending: false)  // Most popular first
            .limit(limit)
            .execute()
            .value

        animeItems = response
        print("✅ Fetched \(response.count) anime")
    } catch {
        errorMessage = "Failed to fetch anime: \(error.localizedDescription)"
    }

    isLoading = false
}
```

**Query Breakdown:**
1. `.from("anime")` - Query anime table
2. `.select()` - Get all columns
3. `.order("popularity", ascending: false)` - Sort by most popular
4. `.limit(50)` - Max 50 results
5. `.execute()` - Run query
6. `.value` - Decode to `[Anime]`

**Search Implementation:**
```swift
// SupabaseService.swift:96-127
func searchContent(query: String) async {
    let animeResponse: [Anime] = try await client.database
        .from("anime")
        .select()
        .textSearch("title_english,title_romaji,description_normalized", query: query)
        .execute()
        .value

    animeItems = animeResponse
}
```

**Full-Text Search:**
Uses PostgreSQL full-text search on indexed columns:
- `title_english`
- `title_romaji`
- `description_normalized`

### Database Schema

**File:** [SupabaseModels.swift:78-221](Kuro/Models/SupabaseModels.swift#L78-221)

**Anime Table Structure:**

```swift
struct Anime: Identifiable, Codable {
    // IDs
    let id: Int                    // PRIMARY KEY (internal SERIAL)
    let idMal: Int?               // MyAnimeList ID
    let idKitsu: String?          // Kitsu ID

    // Titles
    let titleEnglish: String?
    let titleRomaji: String?
    let titleNative: String?
    let titleSynonyms: [String]?

    // Images
    let coverImageLarge: String?
    let coverImageMedium: String?
    let coverImageColor: String?
    let bannerImage: String?

    // Content
    let format: String?           // TV, MOVIE, OVA, ONA, SPECIAL
    let status: String?           // FINISHED, RELEASING, NOT_YET_RELEASED
    let description: String?
    let descriptionNormalized: String?

    // Numbers
    let episodeCount: Int?        // Total episodes
    let duration: Int?            // Episode duration (minutes)
    let totalDuration: Int?

    // Release
    let season: String?           // WINTER, SPRING, SUMMER, FALL
    let seasonYear: Int?
    let startDateYear: Int?
    let startDateMonth: Int?
    let startDateDay: Int?
    let endDateYear: Int?
    let endDateMonth: Int?
    let endDateDay: Int?

    // Airing
    let nextAiringEpisode: Int?
    let nextAiringAt: Date?

    // Scores (AniList scale: 0-100)
    let averageScore: Int?
    let meanScore: Int?
    let popularity: Int?
    let trending: Int?
    let favourites: Int?

    // Categories
    let genreList: [String]?      // TEXT[] array
    let tags: String?             // JSONB stored as JSON string

    // Rating
    let isAdult: Bool
    let ageRating: String?

    // External
    let siteUrl: String?
    let trailerUrl: String?
    let source: String?           // MANGA, LIGHT_NOVEL, ORIGINAL
    let countryOfOrigin: String?

    // Timestamps
    let createdAt: Date
    let updatedAt: Date
    let lastSyncedAt: Date?
}
```

**CodingKeys Mapping:**
```swift
enum CodingKeys: String, CodingKey {
    case id
    case idMal = "id_mal"         // Snake case → camelCase
    case episodeCount = "episodes" // Renamed to avoid conflicts
    case genreList = "genres"      // Renamed to avoid conflicts
    case coverImageLarge = "cover_image_large"
    // ... all snake_case fields mapped
}
```

**Why Rename?**
`episodeCount` instead of `episodes` to avoid conflict with `MediaDisplayable` protocol property.

**Computed Properties:**
```swift
var displayTitle: String {
    titleEnglish ?? titleRomaji ?? titleNative ?? "Unknown"
}

var displayImage: String {
    coverImageLarge ?? coverImageMedium ?? ""
}

var displayYear: String {
    seasonYear?.description ?? "TBA"
}

var episodeText: String {
    if let eps = episodeCount {
        return eps == 1 ? "FILM" : "\(eps) EPS"
    }
    return "ONGOING"
}
```

### MediaDisplayable Protocol

**File:** [SupabaseModels.swift:4-28](Kuro/Models/SupabaseModels.swift#L4-28)

**Purpose:** Unified interface for UI components to work with both Anime and Manga

```swift
protocol MediaDisplayable {
    var id: Int { get }
    var title: String { get }
    var imageURL: String? { get }
    var year: String { get }
    var displayDescription: String { get }
    var episodes: Int? { get }
    var chapters: Int? { get }
    var rating: Double? { get }
    var genres: [String]? { get }
}
```

**Anime Conformance:**
```swift
extension Anime: MediaDisplayable {
    var title: String { displayTitle }
    var imageURL: String? { displayImage.isEmpty ? nil : displayImage }
    var year: String { displayYear }
    var displayDescription: String { description ?? "No description available" }
    var episodes: Int? { episodeCount }
    var chapters: Int? { nil }  // Anime has no chapters
    var rating: Double? {
        averageScore.map { Double($0) / 10.0 }  // 0-100 → 0-10
    }
    var genres: [String]? { genreList }
}
```

**Manga Conformance:**
```swift
extension Manga: MediaDisplayable {
    var title: String { displayTitle }
    var episodes: Int? { nil }  // Manga has no episodes
    var chapters: Int? { chapterCount }
    // ... similar mappings
}
```

**Why This Pattern?**
Allows components like `FeaturedCardReal` and `CollectionCardReal` to accept both Anime and Manga without type checking.

```swift
struct FeaturedCardReal: View {
    let media: any MediaDisplayable  // Works with both!

    var body: some View {
        Text(media.title)  // Polymorphic access
        Text(media.year)
    }
}
```

### Database Tables

**22 Normalized Tables Total:**

**Core Content:**
1. `anime` - Main anime table (250+ records)
2. `manga` - Main manga table (33+ records)

**Normalized Entities:**
3. `characters` - Shared between anime/manga (500+ records)
4. `studios` - Anime production companies (100+ records)
5. `authors` - Manga creators (50+ records)
6. `staff` - Voice actors, directors, writers
7. `tags` - Granular content tags (200+ records)

**Relationship Tables:**
8. `anime_characters` - Many-to-many: anime ↔ characters
9. `manga_characters` - Many-to-many: manga ↔ characters
10. `anime_studios` - Many-to-many: anime ↔ studios
11. `manga_authors` - Many-to-many: manga ↔ authors
12. `anime_staff` - Many-to-many: anime ↔ staff (with role)
13. `manga_staff` - Many-to-many: manga ↔ staff (with role)
14. `anime_tags` - Many-to-many: anime ↔ tags (with rank)
15. `manga_tags` - Many-to-many: manga ↔ tags (with rank)

**User Data:**
16. `anime_user_lists` - User's anime tracking
17. `manga_user_lists` - User's manga tracking
18. `anime_comments` - User comments on anime
19. `manga_comments` - User comments on manga

**Support Tables:**
20. `episodes` - Episode details (currently empty - AniList limitation)
21. `chapters` - Chapter details (placeholders)
22. `manga_volumes` - Volume covers and info

**Additional:**
- `streaming_links` - Where to watch (Crunchyroll, Netflix, etc.)
- `reading_links` - Where to read
- `anime_relations` - Sequels, prequels, spin-offs
- `recommendations` - Related content suggestions
- `rankings` - Historical ranking data
- `score_distribution` - Rating breakdowns

---

## 📁 FILE ORGANIZATION

### Project Structure

```
/Kuro/
├── KuroApp.swift                    # App entry point (@main)
│   └── Lines: 21
│   └── Purpose: Inject SupabaseService, set light mode
│
├── ContentView.swift                # Main UI + Navigation
│   └── Lines: 981
│   └── Purpose: All views, navigation, components
│   └── Contains:
│       ├── KuroRootView (launch manager)
│       ├── KuroLaunchView (splash screen)
│       ├── KuroMainView (main navigation)
│       ├── KuroHeader (fixed header)
│       ├── DiscoverViewSimple (section 1)
│       ├── CollectionViewSimple (section 2)
│       ├── SearchViewSimple (section 3)
│       └── All card components
│
├── Models/
│   └── SupabaseModels.swift         # Data models
│       └── Lines: 403
│       └── Purpose: Anime, Manga, UserList, Episode models
│       └── Contains:
│           ├── MediaDisplayable protocol
│           ├── Anime struct (22+ properties)
│           ├── Manga struct
│           ├── UserList struct
│           ├── ListStatus enum
│           └── Episode struct
│
├── Services/
│   └── SupabaseService.swift        # Backend integration
│       └── Lines: 260
│       └── Purpose: Database queries, auth, state management
│       └── Contains:
│           ├── @Observable class
│           ├── signInAnonymously()
│           ├── fetchAnime()
│           ├── fetchManga()
│           ├── searchContent()
│           ├── addToList()
│           └── filterByGenre()
│
├── Design/
│   └── KuroDesignSystem.swift       # Design tokens
│       └── Lines: 318
│       └── Purpose: Colors, fonts, spacing, animations
│       └── Contains:
│           ├── Color extensions (kuroBlack, etc.)
│           ├── Font extensions (kuroMicro, etc.)
│           ├── KuroSpacing (8px system)
│           ├── KuroRadius (corner radii)
│           ├── KuroShadow (shadow styles)
│           ├── KuroAnimation (timing functions)
│           ├── KuroScreen (device detection)
│           ├── ResponsiveLayout (adaptive sizing)
│           └── KuroAccessibility (haptics, a11y)
│
└── Views/
    ├── DetailPages/
    │   ├── AnimeDetailView.swift    # Anime detail sheet
    │   │   └── Lines: 518
    │   │   └── Contains:
    │   │       ├── HeroSection (parallax banner)
    │   │       ├── TitleSection
    │   │       ├── StatsGrid (score, episodes, status)
    │   │       ├── DescriptionSection (expandable)
    │   │       ├── GenresSection (flow layout)
    │   │       ├── EpisodesSection (list preview)
    │   │       ├── ActionButtons (add to list, etc.)
    │   │       └── FlowLayout helper (custom layout)
    │   │
    │   └── MangaDetailView.swift    # Manga detail sheet
    │       └── Similar to AnimeDetailView
    │
    └── Collection/
        └── CollectionManagementView.swift
            └── Lines: 350
            └── Purpose: User list management UI
            └── Contains:
                ├── AddToListSheet
                ├── Status picker
                ├── Progress tracking
                └── Notes/rating input
```

### Key File Relationships

**App Launch Flow:**
```
KuroApp.swift
  ↓ creates
SupabaseService.shared
  ↓ injected into
ContentView
  ↓ renders
KuroRootView
  ↓ shows
KuroLaunchView → KuroMainView
```

**Data Flow:**
```
SupabaseService
  ↓ @Observable
animeItems, mangaItems
  ↓ accessed by
DiscoverViewSimple, CollectionViewSimple, SearchViewSimple
  ↓ rendered as
FeaturedCardReal, CollectionCardReal, SearchResultRowReal
  ↓ models
Anime, Manga (from SupabaseModels.swift)
```

**Design System Usage:**
```
KuroDesignSystem.swift
  ↓ provides
Colors, Fonts, Spacing, Animations
  ↓ used by
All View files
  ↓ ensures
Consistent design language
```

---

## 🔄 DATA FLOW

### State Management Pattern

**@Observable (New Swift Observation):**

```swift
@MainActor
@Observable
class SupabaseService {
    var animeItems: [Anime] = []  // No @Published needed!
    var isLoading = false
}
```

**View Access:**
```swift
struct DiscoverViewSimple: View {
    @Environment(SupabaseService.self) private var supabaseService

    var body: some View {
        ForEach(supabaseService.animeItems) { anime in
            // UI automatically updates when animeItems changes
        }
    }
}
```

**Why This Pattern?**
- **Simpler:** No @Published, no ObservableObject
- **Faster:** Better performance than Combine
- **Cleaner:** Less boilerplate code
- **Modern:** iOS 17+ observation framework

### Data Loading Lifecycle

**1. App Launch:**
```
KuroApp init
  ↓
SupabaseService.shared init
  ↓ Task
signInAnonymously()
  ↓ await
fetchAnime(limit: 20)
  ↓ executes
Supabase query
  ↓ decodes
[Anime] array
  ↓ assigns
animeItems = response
  ↓ triggers
UI update (all views observing)
```

**2. Section Navigation:**
```
User swipes to COLLECTION
  ↓
CollectionViewSimple appears
  ↓ .onAppear
Checks if animeItems.isEmpty
  ↓ if empty
Task { await supabaseService.fetchAnime() }
  ↓ else
Uses cached animeItems
```

**3. Search:**
```
User types in search field
  ↓ .onChange(of: searchText)
performSearch()
  ↓ Task
await supabaseService.searchContent(query: searchText)
  ↓ Supabase full-text search
.textSearch("title_english,title_romaji,description_normalized", query)
  ↓ Updates
animeItems with filtered results
  ↓ UI
SearchResultRowReal list updates
```

### Loading States

**Three States Pattern:**

```swift
if supabaseService.isLoading {
    // Show loading skeleton
    ForEach(0..<3) { _ in
        FeaturedCardLoading()
    }
} else if supabaseService.animeItems.isEmpty {
    // Show empty state
    Text("LOADING YOUR COLLECTION...")
    ProgressView()
} else {
    // Show real data
    ForEach(supabaseService.animeItems) { anime in
        FeaturedCardReal(media: anime)
    }
}
```

**Loading Components:**
- `FeaturedCardLoading` - Skeleton for large cards
- `CollectionCardLoading` - Skeleton for grid cards
- `ProgressView` - System loading indicator

---

## 🎯 COMPONENT ANATOMY

### FeaturedCardReal Deep Dive

**File:** [ContentView.swift:886-944](Kuro/ContentView.swift#L886-944)

**Visual Breakdown:**
```
┌─────────────────────────────────────┐
│                                     │
│                                     │
│           AsyncImage                │
│         (420px height)              │
│       AspectFill, clipped           │
│                                     │
│                                     │
└─────────────────────────────────────┘
  STEINS;GATE                  ← 20pt serif ultraLight
  2011                         ← 11pt regular 50% opacity
  A self-proclaimed mad        ← 11pt light 60% opacity
  scientist discovers time     ← 3 lines max, 4px spacing
  travel abilities...
```

**Implementation:**
```swift
Button(action: {
    KuroAccessibility.impactHaptic(.light)
    showDetail = true
}) {
    VStack(alignment: .leading, spacing: 0) {
        // Image
        AsyncImage(url: URL(string: media.imageURL ?? "")) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .overlay(
                    Text("IMAGE")
                        .font(.system(size: 24, weight: .ultraLight))
                        .foregroundColor(.black.opacity(0.3))
                )
        }
        .frame(maxWidth: .infinity)
        .frame(height: 420)
        .clipped()

        // Content
        VStack(alignment: .leading, spacing: 12) {
            Text(media.title.uppercased())
                .font(.system(size: 20, weight: .ultraLight, design: .serif))
                .tracking(0.5)
                .foregroundColor(.black)

            Text("\(media.year)")
                .font(.system(size: 11, weight: .regular))
                .tracking(1.5)
                .foregroundColor(.black.opacity(0.5))

            Text(media.displayDescription)
                .font(.system(size: 11, weight: .light))
                .tracking(1.0)
                .foregroundColor(.black.opacity(0.6))
                .lineSpacing(4)
                .lineLimit(3)
        }
        .padding(.vertical, 24)
    }
}
.buttonStyle(PlainButtonStyle())  // Removes blue tint
.sheet(isPresented: $showDetail) {
    if let anime = media as? Anime {
        AnimeDetailView(anime: anime)
    } else if let manga = media as? Manga {
        MangaDetailView(manga: manga)
    }
}
```

**Design Decisions:**
1. **No corner radius** - Sharp editorial look
2. **Serif title** - Elegant, magazine-like
3. **UltraLight weight** - Maximum minimalism
4. **3-line description** - Teaser, not full synopsis
5. **24px padding** - Breathing room for text
6. **Light haptic** - Subtle feedback on tap

### CollectionCardReal Deep Dive

**File:** [ContentView.swift:629-701](Kuro/ContentView.swift#L629-701)

**Visual Breakdown:**
```
┌──────────────┐
│              │
│              │
│    Image     │  0.7 aspect
│   (portrait) │  ratio
│              │
│              │
└──────────────┘
FULLMETAL       ← 10pt regular 80% opacity
ALCHEMIST         2 lines max, uppercase
2003 · 51 EPS   ← 9pt light 50% opacity
★ 8.5           ← 8pt 40% opacity
```

**Implementation:**
```swift
Button(action: {
    KuroAccessibility.impactHaptic(.light)
    showDetail = true
}) {
    VStack(alignment: .leading, spacing: 0) {
        // Cover Image
        AsyncImage(url: URL(string: media.imageURL ?? "")) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .overlay(
                    Text("IMG")
                        .font(.system(size: 12, weight: .light))
                        .foregroundColor(.black.opacity(0.3))
                )
        }
        .aspectRatio(0.7, contentMode: .fill)  // Portrait ratio
        .clipped()
        .cornerRadius(4)  // Subtle rounding

        // Info
        VStack(alignment: .leading, spacing: 4) {
            Text(media.title.uppercased())
                .font(.system(size: 10, weight: .regular))
                .tracking(0.5)
                .foregroundColor(.black.opacity(0.8))
                .lineLimit(2)

            Text("\(media.year) · \(episodeText)")
                .font(.system(size: 9, weight: .light))
                .tracking(0.5)
                .foregroundColor(.black.opacity(0.5))

            if let rating = media.rating {
                HStack(spacing: 2) {
                    Text("★")
                        .font(.system(size: 8))
                        .foregroundColor(.black.opacity(0.4))
                    Text(String(format: "%.1f", rating))
                        .font(.system(size: 8, weight: .light))
                        .foregroundColor(.black.opacity(0.4))
                }
            }
        }
        .padding(.top, 8)
    }
}
.buttonStyle(PlainButtonStyle())
.sheet(isPresented: $showDetail) {
    if let anime = media as? Anime {
        AnimeDetailView(anime: anime)
    } else if let manga = media as? Manga {
        MangaDetailView(manga: manga)
    }
}

private var episodeText: String {
    if let episodes = media.episodes {
        return "\(episodes) EPS"
    } else if let chapters = media.chapters {
        return "\(chapters) CH"
    } else {
        return "Movie"
    }
}
```

**Design Decisions:**
1. **4px corner radius** - Subtle softness vs. featured cards
2. **0.7 aspect ratio** - Standard anime cover proportion
3. **2-line title** - More compact than featured
4. **Smaller fonts** - Dense information display
5. **Optional rating** - Only if available
6. **Year · Episodes** - Quick metadata scan

### AnimeDetailView Deep Dive

**File:** [AnimeDetailView.swift:6-63](Kuro/Views/DetailPages/AnimeDetailView.swift#L6-63)

**Structure:**
```
ScrollView (vertical)
├── HeroSection (parallax banner, 400px)
│   ├── Banner/Cover Image (parallax effect)
│   ├── Gradient overlay (fade to background)
│   └── "ANIME" badge (top right)
│
├── TitleSection (24px padding)
│   ├── Native title (Japanese)
│   ├── Main title (English/Romaji, 24pt serif)
│   └── Year · Format (2011 · TV)
│
├── StatsGrid (3 columns)
│   ├── SCORE (8.5 ★)
│   ├── EPISODES (24)
│   └── STATUS (Finished)
│
├── DescriptionSection
│   ├── "SYNOPSIS" header
│   ├── Description text (expandable)
│   └── "READ MORE" button (if > 200 chars)
│
├── GenresSection
│   ├── "GENRES" header
│   └── Genre pills (flow layout)
│
├── EpisodesSection (if episodes exist)
│   ├── "EPISODES" header · "24 TOTAL"
│   ├── Episode rows (first 5)
│   └── "VIEW ALL 24 EPISODES" button
│
└── ActionButtons
    ├── "ADD TO LIST" (primary, full black)
    └── "FAVORITE" | "SHARE" (secondary, gray)
```

**Parallax Effect:**
```swift
AsyncImage(...)
    .offset(y: scrollOffset * 0.5)  // Half-speed parallax

// Scroll tracking
ScrollView {
    ...
}
.onScroll { offset in
    scrollOffset = offset
}
```

**Stats Grid:**
```swift
LazyVGrid(
    columns: [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ],
    spacing: KuroSpacing.md
) {
    StatCard(label: "SCORE", value: "8.5", icon: "star.fill")
    StatCard(label: "EPISODES", value: "24", icon: "play.circle.fill")
    StatCard(label: "STATUS", value: "Finished", icon: "circle.fill")
}
```

**StatCard Component:**
```
   ★               ← Icon (30% opacity)
  8.5              ← Value (card title font)
 SCORE             ← Label (micro font 60% opacity)
```

**Expandable Description:**
```swift
@State private var showFullDescription = false

Text(description)
    .lineLimit(showFull ? nil : 4)

if description.count > 200 {
    Button("READ MORE") {
        withAnimation(KuroAnimation.spring) {
            showFull.toggle()
        }
    }
}
```

**Flow Layout for Genres:**
```swift
FlowLayout(spacing: KuroSpacing.sm) {
    ForEach(genres) { genre in
        GenreTag(genre: genre)
    }
}

// FlowLayout wraps tags to next line automatically
// [Action] [Adventure] [Drama]
// [Sci-Fi] [Thriller]
```

**Custom Back Button:**
```swift
// Floating over hero image
Button {
    dismiss()
} label: {
    Circle()
        .fill(Color.kuroWhite.opacity(0.9))
        .frame(width: 40, height: 40)
        .overlay(
            Image(systemName: "chevron.left")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.kuroBlack)
        )
        .shadow(color: .kuroBlack08, radius: 8)
}
```

---

## 📱 RESPONSIVE DESIGN

### Device Breakpoints

**File:** [KuroDesignSystem.swift:70-78](Kuro/Design/KuroDesignSystem.swift#L70-78)

**5 Breakpoint System:**

```swift
static func adaptive(_ base: CGFloat, for width: CGFloat) -> CGFloat {
    switch width {
    case 0..<375:    return base * 0.8   // iPhone SE, mini
    case 375..<414:  return base * 1.0   // iPhone 13, 14, 15
    case 414..<768:  return base * 1.2   // iPhone Pro Max, Plus
    case 768..<1024: return base * 1.5   // iPad Portrait
    default:         return base * 2.0   // iPad Landscape, larger
    }
}
```

**Example Application:**

```swift
// Base spacing: 48px
KuroSpacing.adaptive(48, for: 320)  → 38.4px  (iPhone SE)
KuroSpacing.adaptive(48, for: 390)  → 48px    (iPhone 15)
KuroSpacing.adaptive(48, for: 430)  → 57.6px  (iPhone 15 Pro Max)
KuroSpacing.adaptive(48, for: 820)  → 72px    (iPad Portrait)
KuroSpacing.adaptive(48, for: 1180) → 96px    (iPad Landscape)
```

### Responsive Components

**Header Padding:**
```swift
// ContentView.swift:201-214
private func adaptiveHorizontalPadding(for width: CGFloat) -> CGFloat {
    switch width {
    case 0..<375:    return 16px  // Tight on small screens
    case 375..<414:  return 20px  // Standard iPhone
    case 414..<768:  return 24px  // Large iPhone
    case 768..<1024: return 32px  // iPad Portrait
    default:         return 40px  // iPad Landscape
    }
}
```

**Grid Columns:**
```swift
// Collection grid columns adjust automatically
GeometryReader { geometry in
    LazyVGrid(
        columns: Array(
            repeating: GridItem(.flexible()),
            count: columnCount(for: geometry.size.width)
        )
    ) {
        // Cards
    }
}

func columnCount(for width: CGFloat) -> Int {
    switch width {
    case 0..<375:    return 2  // iPhone SE: 2 columns
    case 375..<768:  return 3  // iPhone: 3 columns
    case 768..<1024: return 4  // iPad Portrait: 4 columns
    default:         return 5  // iPad Landscape: 5 columns
    }
}
```

**Font Scaling:**
```swift
// KuroDesignSystem.swift:195-203
static func fontSize(_ base: CGFloat) -> CGFloat {
    switch KuroScreen.width {
    case 0..<375:    return base * 0.9   // Slightly smaller
    case 375..<414:  return base * 1.0   // Base size
    case 414..<768:  return base * 1.1   // Slightly larger
    case 768..<1024: return base * 1.2   // Comfortable reading
    default:         return base * 1.3   // Maximum size
    }
}

// Usage
Text("STEINS;GATE")
    .font(.system(
        size: ResponsiveLayout.fontSize(24),  // 24 * multiplier
        weight: .ultraLight,
        design: .serif
    ))
```

**Image Heights:**
```swift
// KuroDesignSystem.swift:205-214
static func imageHeight(_ base: CGFloat = 300) -> CGFloat {
    switch KuroScreen.width {
    case 0..<375:    return base * 0.7   // 210px (compact)
    case 375..<414:  return base * 1.0   // 300px (standard)
    case 414..<768:  return base * 1.2   // 360px (spacious)
    case 768..<1024: return base * 1.5   // 450px (generous)
    default:         return base * 2.0   // 600px (cinematic)
    }
}

// Usage in FeaturedCard
.frame(height: ResponsiveLayout.imageHeight(420))
```

### Device Detection

**File:** [KuroDesignSystem.swift:151-185](Kuro/Design/KuroDesignSystem.swift#L151-185)

```swift
struct KuroScreen {
    static var width: CGFloat {
        UIScreen.main.bounds.width
    }

    static var height: CGFloat {
        UIScreen.main.bounds.height
    }

    static var safeAreaTop: CGFloat {
        UIApplication.shared.windows.first?.safeAreaInsets.top ?? 0
    }

    static var safeAreaBottom: CGFloat {
        UIApplication.shared.windows.first?.safeAreaInsets.bottom ?? 0
    }

    static var isIPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    static var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    static var isSmallScreen: Bool {
        width < 375  // iPhone SE, mini
    }

    static var isLargeScreen: Bool {
        width > 768  // iPad and larger
    }
}
```

---

## 🎬 ANIMATION SYSTEM

### Animation Philosophy

**Core Principles:**
1. **Subtle and Purposeful** - Every animation serves a function
2. **Consistent Timing** - Standard durations (0.2s, 0.3s, 0.4s)
3. **Natural Motion** - Spring animations for organic feel
4. **Performance** - Prefer opacity/position over scale/rotation
5. **Synchronized Haptics** - Tactile feedback with visual changes

### Standard Animations

**File:** [KuroDesignSystem.swift:131-149](Kuro/Design/KuroDesignSystem.swift#L131-149)

**1. Filter Tab Selection:**
```swift
// ContentView.swift:306-309
withAnimation(.easeInOut(duration: 0.3)) {
    filter = filterOption
}

// Visual change
Rectangle()  // Underline indicator
    .scaleEffect(x: isSelected ? 1.0 : 0.0)  // Width animates
    .animation(.easeOut(duration: 0.3))
```

**2. Section Navigation:**
```swift
// ContentView.swift:113-120
withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
    currentSection += 1
}

// Position change
.offset(x: -CGFloat(currentSection) * geometry.size.width + dragOffset)
```
**Result:** Smooth spring-based slide with natural deceleration

**3. Dot Indicator:**
```swift
// ContentView.swift:132-133
Circle()
    .scaleEffect(index == currentSection ? 1.2 : 1.0)
    .animation(.spring(response: 0.3), value: currentSection)
```
**Result:** Active dot grows slightly with bounce

**4. Button Press:**
```swift
@State private var isPressed = false

Button { ... } label: { ... }
    .scaleEffect(isPressed ? 0.95 : 1.0)
    .animation(.easeInOut(duration: 0.2), value: isPressed)
    .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity) {
        // Never triggered
    } onPressingChanged: { pressing in
        isPressed = pressing
    }
```
**Result:** Subtle scale-down on press, scale-up on release

**5. Description Expand:**
```swift
// AnimeDetailView.swift:246-250
Button("READ MORE") {
    withAnimation(KuroAnimation.spring) {
        showFull.toggle()
    }
    KuroAccessibility.impactHaptic(.light)
}

Text(description)
    .lineLimit(showFull ? nil : 4)
```
**Result:** Smooth height change with spring physics

### Haptic Feedback

**File:** [KuroDesignSystem.swift:241-254](Kuro/Design/KuroDesignSystem.swift#L241-254)

**Three Types:**

**1. Light Impact** - Subtle feedback for minor actions
```swift
KuroAccessibility.impactHaptic(.light)

// Use cases:
// - Card tap
// - Navigation swipe
// - Dot indicator tap
// - Back button
```

**2. Medium Impact** - Noticeable feedback for primary actions
```swift
KuroAccessibility.impactHaptic(.medium)

// Use cases:
// - "Add to List" button
// - Filter selection
// - Major state changes
```

**3. Success/Error Notification** - System-level feedback
```swift
KuroAccessibility.successHaptic()  // Success pattern
KuroAccessibility.errorHaptic()    // Error pattern

// Use cases:
// - Successfully added to list
// - Failed to save
// - Completed action confirmation
```

### Animation Examples

**Launch Screen:**
```swift
// ContentView.swift:58-64
.onAppear {
    withAnimation(.easeOut(duration: 1.2)) {
        logoOpacity = 1.0
    }
    withAnimation(.easeOut(duration: 1.2).delay(0.3)) {
        subtitleOpacity = 1.0
    }
}
```
**Timeline:**
```
0.0s  → Logo starts fading in
1.0s  → Logo fully visible
1.3s  → Subtitle starts fading in
2.0s  → Both fully visible, dismiss launch screen
```

**Sheet Presentation:**
```swift
// System default sheet animation (no custom timing needed)
.sheet(isPresented: $showDetail) {
    AnimeDetailView(anime: anime)
}
```
**Result:** iOS standard modal slide-up with blur backdrop

---

## 🔧 STATE MANAGEMENT

### @Observable Pattern

**Modern Swift Observation (iOS 17+):**

```swift
@MainActor
@Observable
class SupabaseService {
    // No @Published needed - automatic observation
    var animeItems: [Anime] = []
    var mangaItems: [Manga] = []
    var isLoading = false
    var errorMessage: String?
}
```

**View Access:**
```swift
struct DiscoverViewSimple: View {
    @Environment(SupabaseService.self) private var supabaseService

    var body: some View {
        // Automatically updates when animeItems changes
        ForEach(supabaseService.animeItems) { anime in
            FeaturedCardReal(media: anime)
        }
    }
}
```

**Injection at Root:**
```swift
// KuroApp.swift:11-18
@main
struct KuroApp: App {
    @State private var supabaseService = SupabaseService.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(supabaseService)  // Inject here
        }
    }
}
```

### Local State

**@State for View-Local Data:**

```swift
struct KuroMainView: View {
    @State private var currentSection = 0        // Navigation
    @State private var showProfile = false       // Modal
    @State private var searchText = ""           // Input
    @State private var dragOffset: CGFloat = 0   // Gesture

    // Updates trigger view re-render
}
```

**@Binding for Parent-Child Communication:**

```swift
struct KuroHeader: View {
    let currentSection: String              // Read-only
    @Binding var showProfile: Bool          // Two-way binding

    // Child can modify parent's state
}

// Parent
KuroHeader(
    currentSection: sections[currentSection],
    showProfile: $showProfile  // $ passes binding
)
```

### Computed Properties

**Derived State (No Storage):**

```swift
struct CollectionViewSimple: View {
    @Environment(SupabaseService.self) private var supabaseService
    @State private var filter = "ALL"

    // Computed on-demand, no storage
    private var filteredItems: [Anime] {
        switch filter {
        case "WATCHING":
            return supabaseService.animeItems.filter { $0.status == "WATCHING" }
        case "COMPLETED":
            return supabaseService.animeItems.filter { $0.status == "COMPLETED" }
        default:
            return supabaseService.animeItems
        }
    }

    var body: some View {
        ForEach(filteredItems) { anime in
            // Uses computed property
        }
    }
}
```

### State Lifecycle

**Initialization:**
```
App Launch
  ↓
KuroApp.init
  ↓
@State private var supabaseService = SupabaseService.shared
  ↓
SupabaseService.init
  ↓
Task {
    try await signInAnonymously()
    await fetchAnime(limit: 20)
}
  ↓
animeItems = response  // Triggers UI update
```

**View Appears:**
```
DiscoverViewSimple.onAppear
  ↓
Task {
    await supabaseService.fetchAnime()
}
  ↓
isLoading = true  // UI shows loading state
  ↓
Supabase query executes
  ↓
animeItems = response  // UI shows data
  ↓
isLoading = false  // UI hides loading
```

**User Interaction:**
```
User taps filter tab
  ↓
Button action
  ↓
withAnimation(.easeInOut(duration: 0.3)) {
    filter = "WATCHING"  // State changes
}
  ↓
filteredItems computed property recalculates
  ↓
ForEach rebuilds with new items
  ↓
UI animates to new state
```

---

## 📝 CURRENT STATUS & TODOS

### ✅ Completed Features

**Design System:**
- ✅ Complete color system (8 shades)
- ✅ Typography hierarchy (5 styles)
- ✅ Spacing system (8px base)
- ✅ Animation system (5 presets)
- ✅ Responsive breakpoints (5 ranges)
- ✅ Haptic feedback integration

**Navigation:**
- ✅ Horizontal swipe navigation
- ✅ Dot pagination indicators
- ✅ Fixed header with three-part layout
- ✅ Section name updates on swipe
- ✅ Smooth spring animations
- ✅ Gesture threshold detection

**Frontend Views:**
- ✅ Launch screen (2s animation)
- ✅ DISCOVER section (featured cards)
- ✅ COLLECTION section (grid layout)
- ✅ SEARCH section (text + category filters)
- ✅ Anime detail view (full sheet)
- ✅ Manga detail view (full sheet)
- ✅ Loading states (skeletons)
- ✅ Empty states (placeholders)

**Backend:**
- ✅ Supabase client initialized
- ✅ Anonymous authentication
- ✅ Fetch anime (popularity sorted)
- ✅ Fetch manga (popularity sorted)
- ✅ Search (full-text search)
- ✅ Filter by genre
- ✅ Data models (Anime, Manga, UserList)
- ✅ MediaDisplayable protocol

**Database:**
- ✅ 22 normalized tables
- ✅ 250+ anime records
- ✅ 33+ manga records
- ✅ 500+ characters
- ✅ 100+ studios
- ✅ Full-text search indexes
- ✅ Timestamp triggers

### ⚠️ Partially Implemented

**User Lists:**
- ⚠️ Add to list UI (designed, not connected)
- ⚠️ Progress tracking (UI only)
- ⚠️ Rating system (UI only)
- ⚠️ Notes (UI only)
- ❌ Backend CRUD operations (TODO)
- ❌ Real-time sync (TODO)

**Collection Filters:**
- ⚠️ Filter tabs (designed, not functional)
- ❌ "WATCHING", "COMPLETED", "PLANNED" (need user_lists data)
- ❌ Filter persistence (TODO)

**Search:**
- ⚠️ Category filters (UI designed, basic logic)
- ❌ Backend full-text search (using in-memory filter currently)
- ❌ Advanced filters (genre, year, score) (TODO)
- ❌ Sort options (TODO)

### ❌ Not Yet Implemented

**Features:**
- ❌ Episode list (table exists but empty)
- ❌ Chapter list (placeholders only)
- ❌ Character pages
- ❌ Studio/Author pages
- ❌ User profile settings
- ❌ Share functionality
- ❌ Favorites system (separate from lists)
- ❌ Recommendations based on history
- ❌ Streaming links integration
- ❌ Trailer player

**Accessibility:**
- ❌ VoiceOver labels
- ❌ Accessibility identifiers
- ❌ Reduce Motion support
- ❌ High contrast mode
- ❌ Alternative navigation (non-swipe)
- ❌ Screen reader descriptions

**Performance:**
- ❌ Pagination (loads all at once)
- ❌ Image size variants (uses full-res)
- ❌ Memory cleanup for offscreen content
- ❌ Background refresh
- ❌ Cache management

**User Authentication:**
- ❌ Email/password sign-up
- ❌ Social auth (Google, Apple)
- ❌ Profile customization
- ❌ Cross-device sync

### 🐛 Known Issues

**Data:**
- ❌ `description_normalized` is NULL (trigger not working)
- ❌ Episodes table is empty (AniList API limitation)
- ❌ Some anime missing cover images
- ❌ Tags stored as JSON string (not proper JSONB queries)

**UI:**
- ⚠️ Collection grid shows all anime (not user's actual lists)
- ⚠️ Search uses in-memory filtering (not backend search)
- ⚠️ No pagination (performance issue with many items)
- ⚠️ Color contrast at 30% opacity may fail WCAG AA

**Backend:**
- ❌ No error handling UI (errors only in console)
- ❌ No retry logic for failed requests
- ❌ No offline support
- ❌ No optimistic updates

---

## 🎓 DESIGN INSIGHTS

### Why This Design Works

**1. Spatial Luxury Creates Premium Feel**
Generous whitespace (48-64px between cards) makes content feel curated and valuable, not crowded.

**2. Swipe Navigation Feels Natural**
Horizontal swiping is intuitive from Instagram, Snapchat - users already know this pattern.

**3. Fixed Header Provides Context**
Always seeing "DISCOVER" / "COLLECTION" / "SEARCH" prevents disorientation.

**4. Dot Indicators Offer Control**
Users can see total sections (3 dots) and directly tap to jump, not just swipe.

**5. Sharp Corners Feel Editorial**
No rounded corners on featured images creates magazine/art gallery aesthetic vs. typical iOS app.

**6. Opacity Instead of Colors**
Black at varying opacities (80%, 60%, 30%) creates clear hierarchy without visual noise.

**7. Serif Titles Add Elegance**
`.design(.serif)` on large titles evokes luxury fashion branding (Hermès, Vogue).

**8. UltraLight Weight Maximizes Minimalism**
`.weight(.ultraLight)` on titles keeps interface feeling delicate and refined.

**9. Spring Animations Feel Organic**
Spring physics (damping 0.6-0.8) creates natural motion vs. linear animations.

**10. Haptics Reinforce Actions**
Light haptic on every tap provides tactile confirmation without being intrusive.

### Design Anti-Patterns Avoided

**❌ We Don't:**
- Use bright accent colors (only subtle blue/green badges)
- Round every corner (featured cards are sharp)
- Bounce animations (damping kept above 0.6)
- Gradients everywhere (only on image overlays)
- Heavy shadows (max 8px blur radius)
- Multiple font families (system font only)
- Complex transitions (opacity and position only)
- Cluttered information (generous spacing)

**✅ Instead We:**
- Use opacity for hierarchy
- Mix sharp and subtle corners strategically
- Keep motion smooth and subtle
- Use single-color overlays
- Minimal shadows for depth only
- Vary weight and tracking within one family
- Simple, predictable animations
- Embrace whitespace as design element

---

## 🔄 UPDATE PROTOCOL

**This document must be updated when:**

1. **New features added** - Document component structure, data flow
2. **Design system changes** - Update color/font/spacing definitions
3. **Navigation changes** - Update architecture diagrams, gesture logic
4. **Backend changes** - Update API calls, data models, database schema
5. **Performance optimizations** - Document what was improved and how
6. **Bug fixes** - Remove from "Known Issues" section
7. **Major refactors** - Update file organization, component anatomy

**Update format:**
- Add to relevant section (don't create new sections)
- Include file references: `[File.swift:line](path/to/File.swift#Lline)`
- Include code snippets for complex logic
- Update "Current Status & TODOs" section
- Update "Last Updated" date at top

**Keep this document:**
- As single source of truth
- Always in sync with codebase
- Detailed but scannable (good hierarchy)
- Practical (code examples, not just theory)

---

**END OF CLOUD KNOWLEDGE BASE**

*This document represents the complete, internalized understanding of the KURO anime/manga application. It should be referenced for all future development work and updated continuously as the app evolves.*
