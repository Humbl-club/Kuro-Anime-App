# KURO DESIGN UPDATE
**Date:** October 8, 2025
**Changes:** Navigation optimization + 2-column elegant DISCOVER layout

---

## 🎯 CHANGES IMPLEMENTED

### 1. Header Height Optimization (Pushed Higher)

**Before:**
- Base height: 60px + safe area top
- Vertical padding: 20px (fixed)

**After:**
- Base height: **48px** + safe area top (20% reduction)
- Vertical padding: **Adaptive** 12-20px based on device

**Implementation:**
```swift
// ContentView.swift:238-243
private func adaptiveHeaderHeight() -> CGFloat {
    let safeAreaTop = UIApplication.shared.windows.first?.safeAreaInsets.top ?? 0
    return safeAreaTop + 48  // Reduced from 60
}

private func adaptiveVerticalPadding(for width: CGFloat) -> CGFloat {
    switch width {
    case 0..<375:    return 12  // iPhone SE
    case 375..<414:  return 14  // iPhone standard
    case 414..<768:  return 16  // iPhone Plus
    case 768..<1024: return 18  // iPad Portrait
    default:         return 20  // iPad Landscape
    }
}
```

**Result:** Header is more compact, pushed closer to top edge, maximizes content space

---

### 2. Dot Indicators Repositioned (Pushed Lower)

**Before:**
- Padding: `.vertical(12)` + `.bottom(16)` = 28px bottom total
- Not adaptive to device safe areas

**After:**
- Padding: `.top(8)` + adaptive bottom based on safe area
- Respects home indicator on newer iPhones

**Implementation:**
```swift
// ContentView.swift:81-85
private func adaptiveBottomPadding() -> CGFloat {
    let safeAreaBottom = UIApplication.shared.windows.first?.safeAreaInsets.bottom ?? 0
    return max(safeAreaBottom + 8, 20)  // Minimum 20px, adds 8px to safe area
}

// Usage:
.padding(.top, 8)
.padding(.bottom, adaptiveBottomPadding())
```

**Result:**
- iPhone SE: ~20px bottom padding
- iPhone 15 Pro: ~42px bottom padding (respects home indicator)
- iPad: ~28px bottom padding

---

### 3. DISCOVER Section - Complete Redesign (2-Column Elegant Grid)

**Before:** Vertical scroll, large featured cards (420px height)
```swift
VStack(spacing: 40-64px) {
    ForEach(animeItems.prefix(10)) { anime in
        FeaturedCardReal(media: anime)  // Full-width, 420px tall
    }
}
```

**After:** 2-column elegant grid, compact cards
```swift
LazyVGrid(
    columns: [
        GridItem(.flexible(), spacing: 12-28px),
        GridItem(.flexible(), spacing: 12-28px)
    ],
    spacing: 20-36px  // Row spacing
) {
    ForEach(animeItems.prefix(20)) { anime in
        DiscoverCardElegant(media: anime)
    }
}
```

**Spacing System (Responsive):**
```swift
Column Spacing:
- iPhone SE: 12px
- iPhone: 16px
- iPhone Plus: 20px
- iPad Portrait: 24px
- iPad Landscape: 28px

Row Spacing:
- iPhone SE: 20px
- iPhone: 24px
- iPhone Plus: 28px
- iPad Portrait: 32px
- iPad Landscape: 36px

Horizontal Padding:
- iPhone SE: 16px
- iPhone: 20px
- iPhone Plus: 24px
- iPad Portrait: 32px
- iPad Landscape: 40px
```

---

### 4. New Component: DiscoverCardElegant

**Design Philosophy:** Maximum minimalism, elegant serif typography, sharp corners

**Structure:**
```
Button (tappable)
└── VStack(spacing: 0)
    ├── AsyncImage
    │   Aspect: 0.68 (elegant portrait)
    │   Corner: 0 (sharp, editorial)
    │   Mode: AspectFill
    │
    └── Info VStack (8px top, 4px bottom padding)
        ├── Title (13pt serif light uppercase, 2 lines)
        └── Year · Rating (9pt light, minimal metadata)
```

**Typography:**
- **Title:** 13pt, light weight, serif design, 0.5 tracking, 90% opacity
- **Metadata:** 9pt, light weight, 0.8 tracking, 50% opacity

**Aspect Ratio:** 0.68 (slightly taller than standard 0.7 for elegance)

**Code:**
```swift
// ContentView.swift:948-1018
struct DiscoverCardElegant: View {
    let media: any MediaDisplayable
    @State private var showDetail = false

    var body: some View {
        Button(action: {
            KuroAccessibility.impactHaptic(.light)
            showDetail = true
        }) {
            VStack(alignment: .leading, spacing: 0) {
                AsyncImage(url: URL(string: media.imageURL ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Color.black.opacity(0.05))
                        .overlay(ProgressView().scaleEffect(0.6))
                }
                .aspectRatio(0.68, contentMode: .fill)
                .clipped()
                .cornerRadius(0)  // Sharp corners

                VStack(alignment: .leading, spacing: 6) {
                    Text(media.title.uppercased())
                        .font(.system(size: 13, weight: .light, design: .serif))
                        .tracking(0.5)
                        .foregroundColor(.black.opacity(0.9))
                        .lineLimit(2)

                    HStack(spacing: 4) {
                        Text(media.year)
                            .font(.system(size: 9, weight: .light))
                            .tracking(0.8)
                            .foregroundColor(.black.opacity(0.5))

                        if let rating = media.rating {
                            Text("·").foregroundColor(.black.opacity(0.3))
                            Text(String(format: "%.1f", rating))
                                .font(.system(size: 9, weight: .light))
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 4)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showDetail) {
            if let anime = media as? Anime {
                AnimeDetailView(anime: anime)
            }
        }
    }
}
```

---

### 5. New Component: DiscoverCardLoading

**Purpose:** Skeleton loading state for 2-column grid

**Design:** Matches DiscoverCardElegant layout exactly

**Code:**
```swift
// ContentView.swift:1020-1050
struct DiscoverCardLoading: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .aspectRatio(0.68, contentMode: .fill)
                .overlay(
                    ProgressView()
                        .scaleEffect(0.6)
                        .foregroundColor(.black.opacity(0.3))
                )

            VStack(alignment: .leading, spacing: 6) {
                Rectangle()
                    .fill(Color.black.opacity(0.08))
                    .frame(height: 13)
                    .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(Color.black.opacity(0.05))
                    .frame(height: 9)
                    .frame(width: 60)
            }
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
    }
}
```

---

## 📊 COMPARISON

### Space Utilization

**Header:**
- Before: 60px base + 20px padding = 80px total (plus safe area)
- After: 48px base + 12-20px padding = 60-68px total (plus safe area)
- **Savings:** ~12-20px per device

**Content Area:**
- Before: Vertical cards, ~10 items visible initially
- After: 2-column grid, ~12-16 items visible initially
- **Improvement:** 20-60% more content visible

**Footer:**
- Before: 28px total bottom padding
- After: 20-42px adaptive bottom padding
- **Result:** Better safe area handling

### Visual Density

**Before (Featured Cards):**
- 1 column × full width
- 420px image + ~100px info = ~520px per card
- Large spacing: 40-64px between cards
- **Density:** ~1.5 items per screen height

**After (Elegant Grid):**
- 2 columns × half width each
- Portrait aspect 0.68 + ~40px info
- Compact spacing: 20-36px between rows
- **Density:** ~4-6 items per screen height

### Typography Hierarchy

**Before:**
- Title: 20pt serif ultraLight
- Year: 11pt regular
- Description: 11pt light (3 lines shown)

**After:**
- Title: 13pt serif light (more compact)
- Year: 9pt light (minimal)
- Rating: 9pt light (added)
- Description: Removed (cleaner)

---

## 🎨 DESIGN RATIONALE

### Why 2-Column Grid?

1. **Gallery Aesthetic:** Mimics art gallery/museum wall layouts
2. **Editorial Influence:** Fashion magazines often use multi-column layouts
3. **Information Density:** More content visible without scrolling
4. **Minimalism:** Less text per card = more visual focus
5. **Elegance:** Portrait aspect ratio (0.68) is more refined than landscape

### Why Sharp Corners?

1. **Consistency:** Matches original editorial minimalism philosophy
2. **Distinction:** Separates from typical iOS rounded-corner pattern
3. **Gallery Feel:** Art/photo galleries use sharp-edged frames
4. **Swiss Design:** Grid-based, mathematical precision

### Why Serif Title?

1. **Elegance:** Serif fonts convey sophistication
2. **Editorial:** Magazines use serif for titles
3. **Hierarchy:** Distinguishes from sans-serif metadata
4. **Brand:** Matches KURO launch screen logo (serif)

### Why Removed Description?

1. **Minimalism:** Less is more - focus on visuals
2. **Speed:** Faster scanning of content
3. **Elegance:** Cleaner card design
4. **Detail View:** Full description available in detail sheet

---

## 🔧 TECHNICAL DETAILS

### Files Modified

1. **ContentView.swift**
   - Lines modified: ~100 lines
   - New components: DiscoverCardElegant, DiscoverCardLoading
   - Modified: KuroMainView, KuroHeader, DiscoverViewSimple
   - Added: Adaptive padding functions

### Build Status

✅ **BUILD SUCCEEDED** (verified October 8, 2025)

Warnings (non-critical):
- UIScreen.main deprecated (iOS 26) - low priority
- UIApplication.shared.windows deprecated (iOS 15) - low priority
- Database access deprecated - Supabase API change

### Performance Impact

**Positive:**
- LazyVGrid: Only renders visible items
- Smaller image areas: Less memory per card
- Removed description text: Faster rendering

**Neutral:**
- Same data fetching logic
- Same sheet presentation
- Same navigation system

### Responsive Behavior

All new components fully responsive across:
- iPhone SE (320-375px)
- iPhone Standard (375-414px)
- iPhone Plus/Pro (414-768px)
- iPad Portrait (768-1024px)
- iPad Landscape (1024px+)

---

## 📱 VISUAL COMPARISON

### Header

```
BEFORE:
┌──────────────────────────────────────┐
│  [Safe Area Top: 44-59px]           │
│                                      │
│  KURO    DISCOVER           [M]     │ ← 60px + 20px padding
│  ────────────────────────────────   │
└──────────────────────────────────────┘

AFTER:
┌──────────────────────────────────────┐
│  [Safe Area Top: 44-59px]           │
│  KURO    DISCOVER           [M]     │ ← 48px + 12-20px padding
│  ────────────────────────────────   │
└──────────────────────────────────────┘
```

### DISCOVER Layout

```
BEFORE (Vertical Featured Cards):

[─────────────────────]
[                     ]
[   Large Image      ]
[    420px tall      ]
[                     ]
[─────────────────────]
  STEINS;GATE
  2011
  A self-proclaimed mad...

      [48px gap]

[─────────────────────]
[                     ]
[   Large Image      ]
[                     ]
[─────────────────────]


AFTER (2-Column Grid):

[──────────] [──────────]
[   Img    ] [   Img    ]
[          ] [          ]
[──────────] [──────────]
 STEINS;GATE  COWBOY
 2011 · 8.8   1998 · 8.9

    [24px gap]

[──────────] [──────────]
[   Img    ] [   Img    ]
[          ] [          ]
[──────────] [──────────]
```

---

## ✅ WHAT STAYED THE SAME

**Navigation:**
- ✅ Swipe gesture logic (unchanged)
- ✅ Three-dot indicators (design unchanged)
- ✅ Three sections: DISCOVER, COLLECTION, SEARCH
- ✅ Spring animations (same timing)
- ✅ Haptic feedback (same implementation)

**Design System:**
- ✅ Color palette (all opacity values)
- ✅ Typography system (added serif usage)
- ✅ Spacing 8px base unit
- ✅ Sharp corners philosophy
- ✅ Minimal black & white aesthetic

**Other Sections:**
- ✅ COLLECTION view (3-column grid unchanged)
- ✅ SEARCH view (layout unchanged)
- ✅ Detail views (anime/manga sheets unchanged)

---

## 🚀 NEXT STEPS (Optional)

### Potential Enhancements:

1. **Dynamic columns** based on device orientation
   - Portrait: 2 columns
   - Landscape: 3 columns

2. **Pull-to-refresh** on DISCOVER scroll

3. **Infinite scroll** pagination for more content

4. **Filter chips** above grid (genre filters)

5. **Sort options** (popularity, rating, year)

---

**END OF UPDATE DOCUMENT**

*All changes maintain the "Elevated Minimalism" design philosophy while maximizing content visibility and elegance.*
