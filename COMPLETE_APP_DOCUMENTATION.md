# KURO ANIME APP - COMPLETE DOCUMENTATION
## Single Source of Truth - iOS 26 Mobile Application

**Version:** 1.0.0  
**Last Updated:** October 8, 2025  
**Platform:** iOS 26.0+  
**Design System:** Elevated Minimalism / Editorial Minimalism

---

## TABLE OF CONTENTS

1. [Application Identity](#1-application-identity)
2. [Technology Stack](#2-technology-stack)
3. [Project Structure](#3-project-structure)
4. [Navigation Architecture](#4-navigation-architecture)
5. [Design System](#5-design-system)
6. [Views & Components](#6-views--components)
7. [Data Layer](#7-data-layer)
8. [Database Schema](#8-database-schema)
9. [User Experience Flow](#9-user-experience-flow)
10. [Responsive Design](#10-responsive-design)
11. [Accessibility](#11-accessibility)
12. [Performance](#12-performance)
13. [Known Limitations](#13-known-limitations)
14. [Build & Run](#14-build--run)

---

## 1. APPLICATION IDENTITY

### 1.1 Brand
**Name:** KURO  
**Meaning:** "Black" in Japanese  
**Tagline:** CURATED ANIME

### 1.2 Design Philosophy

**"Elevated Minimalism"** - A design approach that combines:
- **Swiss Design Foundation:** Grid-based, systematic, ultra-clean
- **Fashion Editorial Influence:** Like Hermès, Bottega Veneta apps
- **Gallery Aesthetic:** Content-first, interface disappears

**Core Characteristics:**
- **Spatial Luxury:** Generous whitespace, breathing room
- **Typography Hierarchy:** Clear, intentional text hierarchy
- **Color Restraint:** Only black, white, and opacity variations
- **Subtle Animations:** Smooth, purposeful (0.3-0.4s ease-in-out)
- **Fixed Header Pattern:** Three-part layout that stays visible
- **Swipe Navigation:** Horizontal page-style navigation
- **Minimal Indicators:** Tiny dot indicators (5-6px circles)

---

## 2. TECHNOLOGY STACK

### 2.1 Frontend
- **Framework:** SwiftUI
- **Language:** Swift 5.9+
- **iOS Version:** iOS 26.0+
- **Devices:** iPhone SE to iPad Pro (universal)
- **Design Pattern:** MVVM with Environment Objects
- **Concurrency:** Swift async/await

### 2.2 Backend
- **Database:** Supabase (PostgreSQL)
- **Project URL:** `https://bkdifromsqxkndnllmdj.supabase.co`
- **Service Key:** `SUPABASE_SERVICE_KEY_REDACTED`
- **Authentication:** Anonymous sign-in (enabled)
- **CDN:** Supabase Storage
- **Edge Functions:** Deno-based serverless

### 2.3 External APIs
- **Data Source:** AniList GraphQL API
- **Sync Method:** Bulk import via edge functions
- **Rate Limit:** 90 requests/minute
- **Import Status:** 250+ anime, 33+ manga imported

### 2.4 Dependencies
- **Supabase Swift SDK:** Latest (via Swift Package Manager)
- **No other external dependencies**

---

## 3. PROJECT STRUCTURE

### 3.1 File Organization
```
/Kuro/
├── KuroApp.swift                           # App entry point
├── ContentView.swift                       # Main UI & navigation
├── Models/
│   └── SupabaseModels.swift               # Anime, Manga, UserList models
├── Services/
│   └── SupabaseService.swift              # Backend integration
├── Design/
│   └── KuroDesignSystem.swift             # Design tokens & utilities
└── Views/
    ├── DetailPages/
    │   ├── AnimeDetailView.swift          # Anime detail
    │   └── MangaDetailView.swift          # Manga detail
    ├── Collection/
    │   └── CollectionManagementView.swift # User lists
    └── EnhancedContentView.swift          # Enhanced views (optional)

/Database Scripts/
├── 01_delete_all_tables.sql
├── 02_comprehensive_table_creation.sql
├── 03_updated_edge_function.js
├── 04_manga_edge_function.js
├── 05_fix_triggers_and_episodes.sql
├── 06_anime_edge_function_with_episodes.js
└── 07_manga_edge_function_with_chapters.js

/Documentation/
├── README.md
├── COMPLETE_DATABASE_SCHEMA.sql
├── FIXES_FOR_MISSING_DATA.md
└── COMPLETE_APP_DOCUMENTATION.md (this file)
```

---

## 4. NAVIGATION ARCHITECTURE

### 4.1 App Entry Flow

```
KuroApp
  ↓
ContentView (injects SupabaseService)
  ↓
KuroRootView (manages launch screen)
  ↓
├─ [Launch Screen] (2 seconds)
│   └─ KuroLaunchView
│       ├─ "KURO" logo (fade in 1.2s)
│       ├─ "CURATED ANIME" subtitle (fade in 1.2s + 0.3s delay)
│       └─ Auto-dismiss after 2s
│
└─ [Main Interface] (fade in 0.6s)
    └─ KuroMainView
```

### 4.2 Main Navigation System

**Type:** Horizontal swipe-based paging

**Implementation:**
```swift
struct KuroMainView: View {
    @State private var currentSection = 0      // Active section (0-2)
    @State private var dragOffset: CGFloat = 0 // Gesture tracking
    
    let sections = ["DISCOVER", "COLLECTION", "SEARCH"]
}
```

**Three Sections:**

**1. DISCOVER (Index 0)**
- **Default Active:** Yes (app opens here)
- **Purpose:** Content discovery and browsing
- **Content:** Featured anime/manga cards
- **Data Source:** `supabaseService.animeItems`
- **Layout:** Vertical scroll, large featured cards

**2. COLLECTION (Index 1)**
- **Purpose:** User's personal lists
- **Content:** Filtered anime/manga by status
- **Data Source:** User's saved items (TODO: fetch from user_lists table)
- **Layout:** Grid layout (2-5 columns responsive)

**3. SEARCH (Index 2)**
- **Purpose:** Search and advanced filtering
- **Content:** Search results
- **Data Source:** Filtered `animeItems`
- **Layout:** Vertical list with search field

### 4.3 Swipe Gesture Implementation

**Gesture Logic:**
```swift
.gesture(
    DragGesture()
        .onChanged { value in
            dragOffset = value.translation.width
        }
        .onEnded { value in
            let threshold = UIScreen.main.bounds.width / 3
            
            if value.translation.width > threshold && currentSection > 0 {
                currentSection -= 1  // Swipe right
            } else if value.translation.width < -threshold && currentSection < 2 {
                currentSection += 1  // Swipe left
            }
            dragOffset = 0
        }
)
```

**Parameters:**
- **Threshold:** 33% of screen width (e.g., 125px on 375px screen)
- **Animation:** Spring (response: 0.4, dampingFraction: 0.8)
- **Haptic:** Light impact on successful navigation
- **Velocity:** Not currently used (could add velocity-based snapping)

**Visual Feedback:**
```swift
.offset(x: -CGFloat(currentSection) * geometry.size.width + dragOffset)
```
- Real-time drag tracking
- Snap to nearest section on release
- Smooth spring animation

---

### 4.4 Fixed Header Component

**Structure:**
```
┌─────────────────────────────────────┐
│  KURO    DISCOVER    [M]            │ ← Fixed header (never scrolls)
├─────────────────────────────────────┤
│  ─────────────────────────────────  │ ← 0.5px divider
└─────────────────────────────────────┘
```

**Three-Part Layout:**

**Left: Brand (30% opacity)**
```swift
Text("KURO")
    .font(.system(size: 11, weight: .regular))
    .tracking(1.5)
    .foregroundColor(.black.opacity(0.3))
```

**Center: Section (100% opacity)**
```swift
Text(currentSection)  // "DISCOVER", "COLLECTION", or "SEARCH"
    .font(.system(size: 11, weight: .regular))
    .tracking(1.5)
    .foregroundColor(.black)
```

**Right: Profile (minimal interaction)**
```swift
Button {
    showProfile.toggle()
} label: {
    Circle()
        .fill(Color.black.opacity(0.08))
        .frame(width: 32, height: 32)
        .overlay(
            Text("M")
                .font(.system(size: 14, weight: .light))
                .foregroundColor(.black)
        )
}
```

**Responsive Behavior:**
- **Padding scales:** 16px → 20px → 24px → 32px → 40px
- **Safe area handling:** Top inset + 60px base height
- **Divider:** Always 0.5px, black 8% opacity

---

### 4.5 Dot Pagination Indicators

**Position:** Bottom of screen, centered

**Design:**
```swift
HStack(spacing: 8) {
    Circle() // DISCOVER
    Circle() // COLLECTION
    Circle() // SEARCH
}
```

**States:**
- **Active:** 
  - Fill: Black (100% opacity)
  - Size: 6px diameter
  - Scale: 1.2x
- **Inactive:**
  - Fill: Black (20% opacity)
  - Size: 6px diameter
  - Scale: 1.0x

**Padding:**
- Vertical: 12px (reduced from 20px for more content space)
- Bottom: 16px (additional bottom padding)

**Animation:**
- **Timing:** Spring (response: 0.3)
- **Property:** Scale and opacity
- **Value:** Synced to `currentSection`

**Interaction:**
- **Tappable:** Yes (each dot can be tapped)
- **Action:** Jump to that section with animation
- **Haptic:** Light impact on tap

---

## 5. DESIGN SYSTEM

### 5.1 Color Palette

**Foundation:** Pure black and white only

**Color Definitions:**
```swift
// Primary
Color.kuroBlack          // #000000
Color.kuroWhite          // #FFFFFF

// Opacity Variations (8px base unit philosophy)
Color.kuroBlack80        // rgba(0,0,0,0.8)  - Primary text
Color.kuroBlack60        // rgba(0,0,0,0.6)  - Secondary text
Color.kuroBlack30        // rgba(0,0,0,0.3)  - Tertiary text
Color.kuroBlack08        // rgba(0,0,0,0.08) - Subtle backgrounds

// Functional Accents (very subtle)
Color.kuroAnime          // Blue opacity(0.8) - Anime badges only
Color.kuroManga          // Green opacity(0.8) - Manga badges only

// System Colors
Color.kuroBackground              // Adapts to system
Color.kuroSecondaryBackground     // Adapts to system
Color.kuroTertiaryBackground      // Adapts to system
```

**Usage Rules:**
- **No gradients** (except subtle overlays on images)
- **No bright colors** (only subtle blue/green for badges)
- **All variations through opacity**
- **Force light mode:** `.preferredColorScheme(.light)`

### 5.2 Typography System

**Font Hierarchy:**

**Micro (10-11pt)** - Labels, captions, metadata
```swift
Font.kuroMicro(weight: .light)
// Use: Labels, genre tags, episode counts
```

**Body (14-16pt)** - Content, descriptions
```swift
Font.kuroBody(weight: .light)
// Use: Descriptions, body text, readable content
```

**Display (24-32pt)** - Titles, heroes
```swift
Font.kuroDisplay(weight: .ultraLight)
// Use: Page titles, hero titles (serif design)
```

**Navigation (11pt)** - Tab labels
```swift
Font.kuroNavigation(weight: .regular)
// Use: Header navigation, tab labels
```

**Card Title (18-20pt)** - Content cards
```swift
Font.kuroCardTitle(weight: .ultraLight)
// Use: Featured card titles (serif design)
```

**Letter Spacing (Tracking):**
- Labels/Navigation: 1.5pt
- Titles: 0.5-1.0pt
- Body: 0.5pt
- Micro: 0.5-1.0pt

**Text Transform:**
- Most text: UPPERCASE
- Descriptions: Sentence case
- Titles: UPPERCASE

### 5.3 Spacing System

**8px Base Unit Philosophy:**

```swift
KuroSpacing.xs    = 4px   // 0.5 units
KuroSpacing.sm    = 8px   // 1 unit
KuroSpacing.md    = 16px  // 2 units
KuroSpacing.lg    = 24px  // 3 units
KuroSpacing.xl    = 32px  // 4 units
KuroSpacing.xxl   = 48px  // 6 units
KuroSpacing.xxxl  = 64px  // 8 units
```

**Responsive Scaling:**
```swift
KuroSpacing.adaptive(base, screenWidth)

// iPhone SE:     base * 0.8
// iPhone:        base * 1.0
// iPhone Plus:   base * 1.2
// iPad Portrait: base * 1.5
// iPad Landscape: base * 2.0
```

**Common Applications:**
- Card padding: lg (24px)
- Section spacing: xl (32px)
- Featured card spacing: xxl (48px)
- Component gaps: sm-md (8-16px)

### 5.4 Corner Radius System

```swift
KuroRadius.xs  = 4px   // Small elements
KuroRadius.sm  = 8px   // Cards, buttons
KuroRadius.md  = 12px  // Large cards
KuroRadius.lg  = 16px  // Hero elements

// Responsive
KuroRadius.adaptive(base, width)
```

### 5.5 Shadow System

```swift
// Subtle Shadow
color: .kuroBlack08
radius: 4
offset: (0, 2)

// Card Shadow
color: .kuroBlack08
radius: 8
offset: (0, 4)

// Hero Shadow
color: .kuroBlack08
radius: 16
offset: (0, 8)
```

### 5.6 Animation System

**Timing Functions:**
```swift
KuroAnimation.fast       // 0.2s easeInOut
KuroAnimation.standard   // 0.3s easeInOut
KuroAnimation.slow       // 0.4s easeInOut
KuroAnimation.spring     // Spring(response: 0.4, damping: 0.8)
KuroAnimation.springBouncy // Spring(response: 0.5, damping: 0.6)
```

**Animation Rules:**
- **Opacity:** Primary animation method
- **Scale:** 0.95-1.05 max (very subtle)
- **No rotation** unless absolutely necessary
- **No bouncy effects** (damping 0.6-0.8)
- **Respect Reduce Motion:** Not yet implemented

**Common Animations:**
- Filter selection: 0.3s ease-in-out
- Section navigation: 0.4s spring
- Sheet presentation: iOS default
- Button press: 0.2s scale to 0.95

---

## 6. VIEWS & COMPONENTS

### 6.1 Launch Screen

**File:** `ContentView.swift` → `KuroLaunchView`

**Duration:** 2.0 seconds

**Animation Sequence:**
```
0.0s → Logo opacity 0 → 1 (1.2s ease-out)
0.3s → Subtitle opacity 0 → 1 (1.2s ease-out)
2.0s → Dismiss launch, show main (0.6s ease-in-out)
```

**Layout:**
```
ZStack
├── White Background (ignores safe area)
└── VStack (centered)
    ├── "KURO"
    │   Font: 24pt (responsive), ultraLight, serif
    │   Tracking: 8pt
    │   Color: Black
    │
    └── "CURATED ANIME"
        Font: 10pt, light
        Tracking: 3pt
        Color: Black 50% opacity
```

### 6.2 Main Navigation View

**File:** `ContentView.swift` → `KuroMainView`

**Structure:**
```
ZStack
├── White Background
└── VStack
    ├── KuroHeader (fixed, 60px + safe area)
    ├── Content Area (swipeable)
    │   └── HStack (3 sections side-by-side)
    │       ├── DiscoverViewSimple
    │       ├── CollectionViewSimple
    │       └── SearchViewSimple
    └── Dot Indicators (6px circles)
```

**State Management:**
```swift
@State private var currentSection = 0
@State private var showProfile = false
@State private var searchText = ""
@State private var selectedMood: String? = nil  // Not used
@State private var dragOffset: CGFloat = 0
```

---

### 6.3 DISCOVER Section

**Component:** `DiscoverViewSimple`

**Purpose:** Browse curated content

**Layout:**
```
GeometryReader
└── ScrollView (vertical)
    └── VStack
        └── Featured Content
            ├── Featured Card (anime/manga)
            ├── Featured Card
            ├── ... (up to 10 items)
```

**Data Flow:**
```swift
.onAppear {
    Task {
        await supabaseService.fetchAnime(limit: 20)
    }
}
```

**Loading States:**
1. **Initial Load:** Shows 3 skeleton cards
2. **Empty:** "LOADING YOUR COLLECTION..."
3. **Loaded:** Displays anime cards

**Card Spacing:** 48px between cards (adaptive)

---

### 6.4 Featured Card Component

**Type:** `FeaturedCardReal`

**Size:** Full width, 420px height + content

**Structure:**
```
Button (tappable, opens detail)
└── VStack
    ├── AsyncImage
    │   Size: Full width × 420px
    │   Mode: AspectFill
    │   Corner: None (sharp edges)
    │
    └── Content VStack (24px vertical padding)
        ├── Title (20pt, serif, ultraLight, uppercase)
        ├── Year (11pt, regular, 1.5 tracking, 50% opacity)
        └── Description (11pt, light, 1.0 tracking, 60% opacity, 3 lines, 4px line spacing)
```

**Interaction:**
```swift
Button {
    KuroAccessibility.impactHaptic(.light)
    showDetail = true
}
.sheet(isPresented: $showDetail) {
    if let anime = media as? Anime {
        AnimeDetailView(anime: anime)
    } else if let manga = media as? Manga {
        MangaDetailView(manga: manga)
    }
}
```

---

### 6.5 COLLECTION Section

**Component:** `CollectionViewSimple`

**Purpose:** User's curated anime/manga lists

**Layout:**
```
VStack
├── Filter Tabs (horizontal scroll)
│   └── HStack (32px spacing)
│       ├── ALL
│       ├── WATCHING
│       ├── COMPLETED
│       └── PLANNED
│
└── Content Grid (vertical scroll)
    └── LazyVGrid (3 columns, 12px spacing, 16px row spacing)
        ├── CollectionCardReal
        ├── CollectionCardReal
        └── ...
```

**Filter Tab Design:**
```swift
VStack
├── Text (status name)
│   Active: Black 100%, medium weight
│   Inactive: Black 30%, light weight
│
└── Rectangle (underline indicator)
    Height: 0.5px
    ScaleX: Active=1.0, Inactive=0.0
    Animation: 0.3s ease-out
```

**Grid Configuration:**
- **Columns:** 3 × GridItem(.flexible(), spacing: 12)
- **Row Spacing:** 16px
- **Padding:** 24px horizontal

---

### 6.6 Collection Card Component

**Type:** `CollectionCardReal`

**Size:** Flexible width, 0.7 aspect ratio + content

**Structure:**
```
Button (tappable)
└── VStack
    ├── AsyncImage
    │   Aspect: 0.7 (portrait)
    │   Corner: 4px
    │   Mode: AspectFill
    │
    └── Info VStack (8px top padding)
        ├── Title (10pt, regular, 0.5 tracking, 80% opacity, 2 lines, uppercase)
        ├── Year · Episodes (9pt, light, 0.5 tracking, 50% opacity)
        └── Rating (if available)
            ★ {score} (8pt, 40% opacity)
```

**Computed Text:**
```swift
private var episodeText: String {
    if let episodes = media.episodes { "\(episodes) EPS" }
    else if let chapters = media.chapters { "\(chapters) CH" }
    else { "Movie" }
}
```

---

### 6.7 SEARCH Section

**Component:** `SearchViewSimple`

**Purpose:** Search and filter content

**Layout:**
```
VStack
├── Search Field (24px horizontal, 24px top)
│   └── HStack
│       ├── Magnifying Glass Icon
│       └── TextField ("SEARCH ANIME")
│
├── Category Pills (horizontal scroll, 20px vertical)
│   └── HStack (12px spacing)
│       ├── TRENDING
│       ├── NEW SEASON
│       ├── CLASSICS
│       └── HIDDEN GEMS
│
└── Results Area
    ├── [Empty State] or [Loading] or [Results List]
```

**Search Field Styling:**
```swift
.padding(.horizontal, 20)
.padding(.vertical, 16)
.background(Color.black.opacity(0.05))
.cornerRadius(0)  // Sharp corners
```

**Category Pill:**
```swift
// Selectable, multiple selection allowed
Text(category)
    .font(.kuroMicro)
    .tracking(1.0)
    .foregroundColor(isSelected ? .kuroBlack : .kuroBlack60)
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(
        Capsule()
            .stroke(isSelected ? .kuroBlack80 : .kuroBlack15, lineWidth: 0.5)
            .background(
                Capsule()
                    .fill(isSelected ? .kuroBlack05 : .clear)
            )
    )
```

**Filter Logic:**
```swift
// Text Search
title.contains(searchText) ||
description.contains(searchText) ||
genres.contains(searchText)

// Category Filters
TRENDING:    averageScore > 80
NEW SEASON:  year >= 2020
CLASSICS:    year < 2010
HIDDEN GEMS: averageScore > 85 AND year < 2015
```

**Search Result Row:**
```
HStack (12px vertical padding)
├── Cover Image (50×70px, 4px corner radius)
├── VStack (left-aligned, 4px spacing)
│   ├── Title (12pt, regular, 0.5 tracking, 80% opacity, uppercase, 1 line)
│   ├── Year · Genre (10pt, light, 0.5 tracking, 50% opacity)
│   └── Episode Count (9pt, light, 0.5 tracking, 30% opacity)
├── Spacer
├── Rating (if available)
│   └── VStack
│       ├── Score (11pt, regular, 80% opacity)
│       └── Star ★ (8pt, 30% opacity)
└── Chevron Right (10pt, 20% opacity)
```

**Dividers:**
- Between rows: 0.5px, black 8% opacity

---

## 7. DATA LAYER

### 7.1 Data Models

**File:** `SupabaseModels.swift`

**MediaDisplayable Protocol:**
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

**Purpose:**
- UI abstraction layer
- Works with both Anime and Manga
- Enables polymorphic UI components

**Anime Model (Simplified View):**
```swift
struct Anime: Identifiable, Codable, MediaDisplayable {
    // Database Properties (snake_case mapped to camelCase)
    let id: Int                    // Internal SERIAL PRIMARY KEY
    let anilistId: Int?           // External AniList ID
    let malId: Int?               // External MAL ID
    let kitsuId: String?          // External Kitsu ID
    
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
    
    // Counts (RENAMED to avoid protocol conflicts)
    let episodeCount: Int?        // Maps to DB "episodes"
    let duration: Int?
    let totalDuration: Int?
    
    // Release
    let season: String?
    let seasonYear: Int?
    let startDateYear: Int?
    let startDateMonth: Int?
    let startDateDay: Int?
    let endDateYear: Int?
    let endDateMonth: Int?
    let endDateDay: Int?
    
    // Next Episode
    let nextAiringEpisode: Int?
    let nextAiringAt: Date?
    
    // Scores
    let averageScore: Int?        // 0-100 scale from AniList
    let meanScore: Int?
    let popularity: Int?
    let trending: Int?
    let favourites: Int?
    
    // Categories (RENAMED)
    let genreList: [String]?      // Maps to DB "genres"
    let tags: String?             // JSONB stored as string
    
    // Rating
    let isAdult: Bool
    let ageRating: String?
    
    // External
    let siteUrl: String?
    let trailerUrl: String?
    let source: String?
    let countryOfOrigin: String?
    
    // Timestamps
    let createdAt: Date
    let updatedAt: Date
    let lastSyncedAt: Date?
}
```

**Critical Mappings (CodingKeys):**
```swift
case episodeCount = "episodes"    // Avoid protocol conflict
case genreList = "genres"         // Avoid protocol conflict
case anilistId = "anilist_id"     // Snake case conversion
case malId = "id_mal"
case coverImageLarge = "cover_image_large"
// ... etc for all snake_case fields
```

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

**Protocol Conformance:**
```swift
extension Anime: MediaDisplayable {
    var title: String { displayTitle }
    var imageURL: String? { displayImage.isEmpty ? nil : displayImage }
    var year: String { displayYear }
    var displayDescription: String { description ?? "No description available" }
    var episodes: Int? { episodeCount }   // Map renamed property
    var chapters: Int? { nil }            // Anime has no chapters
    var rating: Double? { 
        averageScore.map { Double($0) / 10.0 }  // 0-100 → 0-10
    }
    var genres: [String]? { genreList }   // Map renamed property
}
```

**Manga Model:**
```swift
struct Manga: Identifiable, Codable, MediaDisplayable {
    // Similar to Anime but with:
    let chapterCount: Int?        // Maps to DB "chapters"
    let volumeCount: Int?         // Maps to DB "volumes"
    
    // NO episodes, duration, season, nextAiring
    // Simpler release tracking
}
```

**Protocol Conformance:**
```swift
extension Manga: MediaDisplayable {
    var title: String { displayTitle }
    var imageURL: String? { displayImage.isEmpty ? nil : displayImage }
    var year: String { startDateYear?.description ?? "TBA" }
    var displayDescription: String { description ?? "No description available" }
    var episodes: Int? { nil }            // Manga has no episodes
    var chapters: Int? { chapterCount }   // Map renamed property
    var rating: Double? {
        averageScore.map { Double($0) / 10.0 }
    }
    var genres: [String]? { genreList }
}
```

---

### 7.2 Supabase Service

**File:** `SupabaseService.swift`

**Class Definition:**
```swift
@MainActor
class SupabaseService: ObservableObject {
    private var client: SupabaseClient
    
    @Published var animeItems: [Anime] = []
    @Published var mangaItems: [Manga] = []
    @Published var userLists: [UserList] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isAuthenticated = false
}
```

**Initialization:**
```swift
init() {
    client = SupabaseClient(
        supabaseURL: URL(string: "https://bkdifromsqxkndnllmdj.supabase.co")!,
        supabaseKey: "SUPABASE_SERVICE_KEY_REDACTED"
    )
    
    Task {
        do {
            try await signInAnonymously()
            await fetchAnime(limit: 20)
        } catch {
            print("❌ Auto-initialization failed: \(error)")
        }
    }
}
```

**Key Methods:**

**Authentication:**
```swift
func signInAnonymously() async throws {
    let response = try await client.auth.signInAnonymously()
    isAuthenticated = true
    print("✅ Signed in anonymously")
}
```

**Fetch Anime:**
```swift
func fetchAnime(limit: Int = 20) async {
    isLoading = true
    
    do {
        let response: [Anime] = try await client
            .from("anime")
            .select()
            .order("popularity", ascending: false)
            .limit(limit)
            .execute()
            .value
        
        animeItems = response
        isLoading = false
    } catch {
        errorMessage = error.localizedDescription
        isLoading = false
    }
}
```

**Fetch Manga:**
```swift
func fetchManga(limit: Int = 20) async {
    // Similar to fetchAnime but queries "manga" table
}
```

**Search (TODO):**
```swift
func searchContent(query: String) async {
    // Full-text search not yet implemented
    // Currently filters animeItems in memory
}
```

**User Lists (TODO):**
```swift
func addToList(mediaId: Int, mediaType: String, status: ListStatus) async
func updateProgress(listId: Int, progress: Int) async
func removeFromList(listId: Int) async
func fetchUserLists() async
```

---

## 8. DATABASE SCHEMA

### 8.1 Core Tables

**anime Table:**
- **22 normalized tables total**
- **Internal IDs:** SERIAL PRIMARY KEY
- **External IDs:** anilist_id, mal_id, kitsu_id (UNIQUE)
- **Arrays:** genres (TEXT[])
- **Timestamps:** created_at, updated_at (auto-managed)

**Key Columns:**
- id, anilist_id, mal_id, kitsu_id
- title_english, title_romaji, title_native, title_synonyms
- cover_image_large, cover_image_medium, banner_image
- format, status, description, description_normalized
- episodes, duration, season, season_year
- average_score, popularity, trending
- genres (array), source, is_adult
- created_at, updated_at, last_synced_at

**manga Table:**
- Similar structure
- **Key differences:** chapters, volumes (not episodes)
- No season, duration fields
- next_chapter_number, next_chapter_at

**Normalized Entity Tables:**
1. characters (shared between anime/manga)
2. studios (anime only)
3. authors (manga only)
4. staff (shared)
5. tags (shared)

**Relationship Tables:**
1. anime_characters (anime_id → character_id)
2. manga_characters (manga_id → character_id)
3. anime_studios (anime_id → studio_id)
4. manga_authors (manga_id → author_id)
5. anime_staff (anime_id → staff_id, role)
6. manga_staff (manga_id → staff_id, role)
7. anime_tags (anime_id → tag_id, rank)
8. manga_tags (manga_id → tag_id, rank)

**User Data Tables:**
1. anime_user_lists (user_id, anime_id, status, progress)
2. manga_user_lists (user_id, manga_id, status, progress)
3. anime_comments
4. manga_comments

**Support Tables:**
1. episodes (anime_id, number, title, thumbnail)
2. chapters (manga_id, number, title)
3. manga_volumes (manga_id, number, title)
4. streaming_links
5. reading_links
6. anime_relations
7. recommendations
8. rankings
9. score_distribution

### 8.2 Indexes

**Performance Indexes:**
```sql
CREATE INDEX idx_anime_anilist_id ON anime(anilist_id);
CREATE INDEX idx_anime_popularity ON anime(popularity DESC);
CREATE INDEX idx_anime_average_score ON anime(average_score DESC);
CREATE INDEX idx_anime_genres ON anime USING GIN(genres);
CREATE INDEX idx_anime_title_english ON anime(title_english);

-- Full-text search
CREATE INDEX idx_anime_description_fts 
    ON anime USING GIN(to_tsvector('english', description_normalized));
```

### 8.3 Triggers

**Auto-update Timestamps:**
```sql
CREATE TRIGGER update_anime_updated_at
BEFORE UPDATE ON anime
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();
```

**Description Normalization:**
```sql
CREATE TRIGGER set_anime_description_normalized
BEFORE INSERT OR UPDATE OF description ON anime
FOR EACH ROW
EXECUTE FUNCTION normalize_description();
```

**Issue:** Trigger exists but description_normalized is NULL (needs SQL fix script)

---

## 9. USER EXPERIENCE FLOW

### 9.1 First-Time User Journey

```
1. App Launch
   ↓
2. Launch Screen (2s)
   ├─ "KURO" appears
   └─ "CURATED ANIME" appears
   ↓
3. Main Screen (DISCOVER active)
   ├─ Anonymous auth in background
   ├─ Fetches 20 anime from Supabase
   └─ Displays featured cards
   ↓
4. Browse Content
   ├─ Scroll vertical to see more cards
   ├─ Swipe left → COLLECTION
   ├─ Swipe left → SEARCH
   └─ Swipe right → back to DISCOVER
   ↓
5. Tap Card
   ↓
6. Detail Sheet Opens
   ├─ View full information
   ├─ Read synopsis
   ├─ See episodes/chapters
   └─ Tap "ADD TO LIST"
   ↓
7. Add to List Sheet
   ├─ Select status (Planning, Watching, etc.)
   ├─ Set progress
   ├─ Rate (0-10 stars)
   ├─ Add notes
   └─ Save
   ↓
8. Return to Browse
```

### 9.2 Core User Actions

**Browse:**
- Scroll DISCOVER for featured content
- Navigate sections via swipe
- View different content types

**Explore:**
- Tap card to open detail
- Read full synopsis
- View episodes/chapters
- Check ratings and stats

**Organize:**
- Add to WATCHING/READING
- Set progress (episode/chapter)
- Rate content
- Add personal notes
- View filtered collection

**Search:**
- Text search across titles
- Filter by categories
- Multiple filters simultaneously

---

## 10. RESPONSIVE DESIGN

### 10.1 Device Breakpoints

**iPhone SE (375px width or less):**
- Padding: 16-20px
- Font scale: 0.9x
- Image height: 0.7x base
- Grid: 2 columns
- Tighter spacing overall

**iPhone Standard (375-414px):**
- Padding: 20-24px
- Font scale: 1.0x (base)
- Image height: 1.0x base
- Grid: 3 columns
- Standard spacing

**iPhone Plus/Pro Max (414-768px):**
- Padding: 24px
- Font scale: 1.1x
- Image height: 1.2x base
- Grid: 3 columns
- Enhanced spacing

**iPad Portrait (768-1024px):**
- Padding: 32px
- Font scale: 1.2x
- Image height: 1.5x base
- Grid: 4 columns
- Generous spacing

**iPad Landscape (1024px+):**
- Padding: 40px
- Font scale: 1.3x
- Image height: 2.0x base
- Grid: 5 columns
- Maximum spacing

### 10.2 Adaptive Components

**All spacing uses:**
```swift
KuroSpacing.adaptive(baseValue, for: screenWidth)
```

**All fonts use:**
```swift
ResponsiveLayout.fontSize(baseSize)
```

**All layouts use:**
```swift
ResponsiveLayout.padding()
ResponsiveLayout.imageHeight(base)
```

**GeometryReader Usage:**
- Used extensively for responsive calculations
- Screen width passed to child components
- Enables context-aware sizing

---

## 11. ACCESSIBILITY

### 11.1 Current Implementation

**Haptic Feedback:**
- ✅ Light impact: Navigation, selections
- ✅ Medium impact: Important actions
- ✅ Success haptic: Save operations
- ✅ Error haptic: Failed operations

**Dynamic Type:**
- ✅ System fonts used (inherits Dynamic Type)
- ⚠️ Hard-coded sizes may not scale perfectly

**Touch Targets:**
- ✅ Buttons: 44pt minimum
- ✅ Cards: Large tap areas
- ✅ Pills: Adequate spacing

**Color Contrast:**
- ⚠️ Some text at 30% opacity may fail WCAG AA
- ⚠️ Gray on white needs validation

### 11.2 Not Yet Implemented

- ❌ VoiceOver labels
- ❌ Accessibility identifiers
- ❌ Reduce Motion support
- ❌ Alternative navigation for swipe-only UI
- ❌ Screen reader descriptions
- ❌ High contrast mode

---

## 12. PERFORMANCE

### 12.1 Optimizations

**Lazy Loading:**
```swift
LazyVGrid        // Collection grid
LazyVStack       // Search results
```

**Async Images:**
```swift
AsyncImage       // Built-in caching
```

**Data Limits:**
- Initial: 20 items
- Discover: 10 displayed
- Collection: 50 max
- Search: Filtered subset

### 12.2 Bottlenecks

**Identified Issues:**
1. Loading 50 large images simultaneously in collection
2. No pagination (loads all eventually)
3. In-memory filtering (not database-side)
4. No image size optimization
5. Full-size images for small cards

**Recommendations:**
- Implement pagination
- Use thumbnail URLs for grids
- Backend search implementation
- Image size variants
- Memory cleanup for offscreen content

---

## 13. KNOWN LIMITATIONS

### 13.1 Backend Integration

**Not Yet Connected:**
- ❌ User list CRUD operations
- ❌ Progress tracking persistence
- ❌ Rating/notes save
- ❌ Real-time sync
- ❌ User authentication (beyond anonymous)

### 13.2 Features

**Not Implemented:**
- ❌ Full-text search (backend)
- ❌ Advanced filtering
- ❌ Sorting options
- ❌ Episode/chapter detail data
- ❌ Character pages
- ❌ Studio/Author pages
- ❌ User profile
- ❌ Settings
- ❌ Share functionality
- ❌ Favorites system

### 13.3 Data Gaps

- ❌ Episodes table empty (AniList limitation)
- ❌ Chapters are placeholders only
- ❌ Volume covers not available
- ❌ description_normalized NULL (trigger issue)

---

## 14. BUILD & RUN

### 14.1 Requirements

**Development Environment:**
- macOS 13.0 Ventura or later
- Xcode 16.2 or later
- iOS 26.0+ Simulator or Device
- Active internet connection

**Supabase Setup:**
- Project created at Supabase.com
- Anonymous auth enabled
- Tables created via SQL scripts
- Edge functions deployed

### 14.2 Setup Steps

1. **Open Project:** `Kuro.xcodeproj`
2. **Resolve Packages:** File → Packages → Resolve
3. **Select Target:** iPhone 15 Pro simulator
4. **Build:** ⌘B
5. **Run:** ⌘R

### 14.3 First Launch

**Expected Behavior:**
1. Launch screen (2s)
2. Auto sign-in (anonymous)
3. Fetch 20 anime
4. Display DISCOVER screen with real data
5. Cards are tappable
6. Navigation works via swipe

**Troubleshooting:**
- No data? Check Supabase credentials
- Build errors? Verify package dependencies
- Crashes? Check console for auth errors

---

## APPENDIX

### A. File Reference Table

| File | Purpose | Lines | Status |
|------|---------|-------|--------|
| KuroApp.swift | Entry point | ~30 | ✅ Complete |
| ContentView.swift | Main UI | ~1200 | ✅ Complete |
| SupabaseService.swift | Backend | ~300 | ⚠️ Partial |
| SupabaseModels.swift | Data models | ~400 | ✅ Complete |
| KuroDesignSystem.swift | Design tokens | ~300 | ✅ Complete |
| AnimeDetailView.swift | Anime details | ~450 | ✅ Complete |
| MangaDetailView.swift | Manga details | ~400 | ✅ Complete |
| CollectionManagementView.swift | User lists | ~350 | ⚠️ Partial |

### B. Database Statistics

**Tables:** 22 normalized tables
**Anime Records:** 250+
**Manga Records:** 33+
**Characters:** 500+
**Studios:** 100+
**Tags:** 200+
**Authors:** 50+

### C. Design Token Reference

**Colors:** 10 defined (black, white, 6 opacity variations, 2 accents)
**Fonts:** 5 styles (micro, body, display, navigation, card title)
**Spacing:** 7 sizes (xs through xxxl, 8px base)
**Radius:** 4 sizes (xs through lg)
**Animations:** 5 presets (fast, standard, slow, spring, bouncy)

---

**END OF DOCUMENTATION**

*This document represents the complete, current state of the KURO anime/manga application as of October 8, 2025. All information is accurate and reflects the actual implementation in the codebase.*
