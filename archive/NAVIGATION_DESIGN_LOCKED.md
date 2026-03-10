# NAVIGATION DESIGN - LOCKED & FROZEN
**Date:** October 8, 2025
**Status:** 🔒 FROZEN - DO NOT MODIFY

---

## 🚫 NAVIGATION DESIGN IS LOCKED

The navigation system design is **completely frozen** and must **never be changed**.

### What Is Frozen

**1. Three-Section Structure**
- ✅ Exactly 3 sections: DISCOVER, COLLECTION, SEARCH
- ✅ Cannot add more sections
- ✅ Cannot remove sections
- ✅ Cannot rename sections

**2. Swipe Navigation**
- ✅ Horizontal swipe gestures
- ✅ Threshold: 33% of screen width
- ✅ Spring animation (response: 0.4, damping: 0.8)
- ✅ Real-time drag tracking
- ✅ Haptic feedback on navigation

**3. Fixed Header**
- ✅ Three-part layout: KURO / SECTION NAME / [M]
- ✅ Height: 44px (iOS standard nav bar)
- ✅ Horizontal padding: 5% of width, min 16px
- ✅ Vertical padding: 20% of header height, min 12px
- ✅ Divider: 0.5px, 8% opacity black
- ✅ Always visible at top

**4. Dot Indicators**
- ✅ Three dots (one per section)
- ✅ Size: 6px diameter
- ✅ Active: 100% black opacity, 1.2x scale
- ✅ Inactive: 20% black opacity, 1.0x scale
- ✅ Spacing: 8px between dots
- ✅ Position: Bottom center, adaptive safe area padding
- ✅ Animation: Spring (response: 0.3)
- ✅ Tappable: Yes, jumps to section

**5. Typography**
- ✅ Brand: 11pt regular, 1.5 tracking, 30% opacity
- ✅ Section name: 11pt regular, 1.5 tracking, 100% opacity
- ✅ Profile initial: 14pt light, 100% opacity

**6. Colors**
- ✅ Background: Pure white (#FFFFFF)
- ✅ Text: Pure black (#000000) with opacity variations
- ✅ Divider: Black 8% opacity
- ✅ Profile circle: Black 8% opacity

---

## ✅ WHAT CAN BE CHANGED

Only the **content within each section** can be modified:

### DISCOVER Section
- ✅ Layout (grid, list, cards, etc.)
- ✅ Content sections (Current Season, Trending, etc.)
- ✅ Card design
- ✅ Spacing and padding
- ✅ Number of items shown

### COLLECTION Section
- ✅ Grid layout
- ✅ Filter tabs design
- ✅ Card design
- ✅ Empty states

### SEARCH Section
- ✅ Search field design
- ✅ Category pills
- ✅ Results layout
- ✅ Filtering logic

---

## 🔒 LOCKED COMPONENTS

**Do NOT modify these files/components for navigation:**

1. **KuroMainView** - Swipe navigation logic
   - Lines: 81-144 (ContentView.swift)
   - Locked: Gesture handling, section management, dot indicators

2. **KuroHeader** - Fixed header design
   - Lines: 147-198 (ContentView.swift)
   - Locked: Three-part layout, typography, spacing

3. **Dot Indicators**
   - Lines: 126-141 (ContentView.swift)
   - Locked: Size, opacity, animation, positioning

4. **Section Array**
   - `let sections = ["DISCOVER", "COLLECTION", "SEARCH"]`
   - Locked: Cannot add/remove/rename

---

## 📐 EXACT SPECIFICATIONS

### Header Dimensions
```swift
Height: 44px (fixed)
Horizontal padding: max(width * 0.05, 16)  // 5% of width, min 16px
Vertical padding: max(height * 0.2, 12)    // 20% of header height, min 12px
Divider height: 0.5px
```

### Dot Indicators
```swift
Size: 6px × 6px
Active scale: 1.2 (= 7.2px visual size)
Inactive scale: 1.0 (= 6px)
Spacing: 8px horizontal
Top padding: 8px
Bottom padding: max(safeAreaBottom + 8, 20)
Container height: 40px
```

### Swipe Gesture
```swift
Threshold: UIScreen.main.bounds.width / 3
Animation: .spring(response: 0.4, dampingFraction: 0.8)
Haptic: .light (on successful navigation)
Velocity detection: abs(velocity) > 500 → .medium haptic
```

### Colors (Exact Values)
```swift
Background: Color.white (RGB: 255, 255, 255)
Brand text: Color.black.opacity(0.3)
Section text: Color.black (opacity: 1.0)
Divider: Color.black.opacity(0.08)
Profile circle: Color.black.opacity(0.08)
Active dot: Color.black (opacity: 1.0)
Inactive dot: Color.black.opacity(0.2)
```

---

## 🎯 RATIONALE FOR LOCKING

**Why is navigation frozen?**

1. **Design Identity** - The swipe navigation IS the KURO signature
2. **User Learning** - Consistency helps users learn the interface
3. **Brand Recognition** - Three dots = KURO navigation
4. **Simplicity** - 3 sections is perfect (not too few, not too many)
5. **Minimalism** - Matches "Elevated Minimalism" philosophy
6. **Proven Pattern** - Instagram/Snapchat swipe pattern (familiar)

**What if I want to add a 4th section?**
- ❌ Don't. Use tabs/filters within existing sections instead.
- ✅ Example: Add "PROFILE" content to COLLECTION section

**What if I want different navigation?**
- ❌ Don't. This is the KURO navigation system.
- ✅ Focus energy on making section content amazing instead.

---

## 📋 NAVIGATION CHECKLIST

Before making ANY changes, ask:

- [ ] Am I modifying the number of sections? → ❌ STOP
- [ ] Am I changing the swipe gesture? → ❌ STOP
- [ ] Am I adjusting header layout? → ❌ STOP
- [ ] Am I changing dot indicators? → ❌ STOP
- [ ] Am I modifying section names? → ❌ STOP
- [ ] Am I only changing content within sections? → ✅ PROCEED

---

## 🔄 VERSION HISTORY

**v1.0 (October 8, 2025)**
- Initial navigation design locked
- Three sections: DISCOVER, COLLECTION, SEARCH
- Swipe navigation with dot indicators
- Fixed header with three-part layout

**Future Versions:**
- Navigation design will NOT change
- Only content within sections will evolve

---

## 📝 ENFORCEMENT

**All developers must:**
1. Read this document before modifying KURO
2. Never touch navigation components
3. Focus improvements on section content only
4. Maintain the frozen navigation design forever

**If you see someone trying to change navigation:**
- 🛑 Stop them immediately
- 📖 Point them to this document
- 💡 Suggest improving section content instead

---

**END OF LOCKED NAVIGATION DOCUMENTATION**

*This navigation design is the KURO signature and must remain unchanged. All innovation should focus on making the content within each section exceptional, not on changing the navigation system itself.*
