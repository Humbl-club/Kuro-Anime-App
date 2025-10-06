# 🎨 Kuro - Elevated Minimalism Anime App

**Design System:** "Elevated Minimalism" / "Editorial Minimalism"  
**Backend:** Supabase (Database, Auth, CDN, Storage)  
**Platform:** iOS 17+ with SwiftUI  
**Status:** Production-ready with clean architecture

---

## 🎯 **Project Overview**

Kuro is a beautifully minimal anime and manga discovery app that embodies the "Hermès of anime apps" vision - sophisticated, elegant, and content-first.

### **Design Philosophy**
- **Swiss Design Foundation:** Grid-based, systematic, ultra-clean
- **Fashion Editorial Influence:** Like Hermès, Bottega Veneta apps
- **Gallery Aesthetic:** Content-first, interface disappears

---

## 🏗️ **Architecture**

### **File Structure**
```
Kuro/
├── KuroApp.swift          ← Main app entry point
├── ContentView.swift      ← Complete UI (white minimalist design)
├── Models/
│   └── SupabaseModels.swift
├── Services/
│   └── SupabaseService.swift
└── Assets.xcassets/
```

### **Tech Stack**
- **Frontend:** SwiftUI
- **Backend:** Supabase
- **Database:** PostgreSQL (via Supabase)
- **Auth:** Supabase Auth (anonymous/email)
- **Storage:** Supabase Storage (CDN)
- **Real-time:** Supabase Realtime

---

## 🎨 **Design System**

### **Color Palette**
- **Background:** Pure white (#FFFFFF)
- **Text:** Pure black (#000000)
- **Variations:** Opacity only (80%, 60%, 30%, 8%)
- **No gradients, no colors**

### **Typography**
```
MICRO: 10-11pt, uppercase, tracked out (labels)
BODY: 14-16pt, light weight (content)
DISPLAY: 24-32pt, ultralight (heroes)
```

### **Spacing**
- **Base unit:** 8px
- **Scale:** 8-16-24-32-48-56
- **Margins:** 24px standard

### **Animation**
- **Timing:** 0.3-0.4s easeInOut
- **Scale:** 0.95-1.05 max
- **Primary method:** Opacity
- **No bouncy, no rotation**

---

## 🔧 **Supabase Setup**

### **1. Install Supabase SDK**
```swift
// Add via Swift Package Manager
https://github.com/supabase/supabase-swift
```

### **2. Configure Supabase**
In `SupabaseService.swift`, update:
```swift
supabaseURL: URL(string: "https://your-project.supabase.co")!
supabaseKey: "your-anon-key"
```

### **3. Database Schema**
```sql
-- media table
CREATE TABLE media (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title TEXT NOT NULL,
    year INTEGER NOT NULL,
    description TEXT,
    image_url TEXT,
    type TEXT NOT NULL, -- 'anime', 'manga', 'manhwa'
    genres TEXT[],
    episodes INTEGER,
    chapters INTEGER,
    status TEXT,
    rating DECIMAL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- user_lists table
CREATE TABLE user_lists (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id),
    media_id UUID REFERENCES media(id),
    list_type TEXT, -- 'watching', 'completed', 'planned'
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

---

## 🚀 **Features**

### **Discover Section**
- Mood-based content filtering
- Featured anime/manga cards
- Horizontal mood selector
- Real-time content updates

### **Collection Section**
- 3-column grid layout
- Filter tabs (ALL, WATCHING, COMPLETED, PLANNED)
- Long-press to add/remove
- Swipe gestures

### **Search Section**
- Real-time search
- Category pills
- Clean results list
- Genre filtering

---

## 📱 **Development**

### **Run the App**
1. Open `Kuro.xcodeproj` in Xcode
2. Add Supabase Swift package
3. Configure Supabase credentials
4. Build and run (Cmd+R)

### **Testing**
- Unit tests in `KuroTests/`
- UI tests in `KuroUITests/`

---

## ✨ **Key Principles**

1. **Single source of truth** - No duplicate implementations
2. **Supabase only** - No Firebase, no other databases
3. **White design only** - No dark mode, no variations
4. **Content-first** - Interface disappears
5. **Minimal interactions** - Swipe, tap, long-press

---

**This is the "Hermès of anime apps" - elegant, minimal, and sophisticated.** 🎨
