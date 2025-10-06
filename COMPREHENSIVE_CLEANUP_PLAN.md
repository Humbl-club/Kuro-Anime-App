# 🧹 Comprehensive Cleanup Plan for Kuro

## 🎯 **Goal:**
- Keep ONLY the white "Elevated Minimalism" design
- Use ONLY Supabase (database, auth, CDN, storage)
- Remove ALL Firebase references
- Remove ALL old design files
- Remove ALL unnecessary documentation
- Single source of truth architecture

---

## 📋 **Files to DELETE:**

### **1. Firebase-Related Files (DELETE ALL)**
```
❌ Kuro.xcodeproj/FirebaseConnectionTest.swift
❌ Kuro.xcodeproj/FirebaseDataSeeder.swift
❌ Kuro.xcodeproj/FirebaseDiagnosticsView.swift
❌ Kuro/Services/FirebaseService.swift
❌ Kuro/DatabaseStatusView.swift
❌ Kuro/SimpleDatabaseChecker.swift
❌ QuickDatabaseCheck.swift
❌ Kuro/FirebaseTestView.swift
```

### **2. Old Documentation Files (DELETE ALL)**
```
❌ Kuro.xcodeproj/TEST_RESULTS.md
❌ Kuro/COMPILATION_FIXES_SUMMARY.md
❌ Kuro/DATABASE_CHECK_GUIDE.md
❌ Kuro/Services/FINAL_ERROR_FIXES.md
❌ MANUAL_CLEANUP_REQUIRED.md
❌ Kuro/SimpleConsoleLogger.swift
```

### **3. Firebase Models (DELETE - Replace with Supabase)**
```
❌ Kuro/Models/MediaModels.swift (Firebase-specific)
```

---

## ✅ **Files to KEEP:**

### **Core App Files**
```
✅ Kuro/KuroApp.swift - Main app entry point
✅ Kuro/ContentView.swift - White minimalist design
✅ Kuro/Assets.xcassets/ - App icons and assets
```

### **Test Files (Keep for now)**
```
✅ KuroTests/KuroTests.swift
✅ KuroUITests/KuroUITests.swift
✅ KuroUITests/KuroUITestsLaunchTests.swift
```

---

## 🔧 **Files to CREATE:**

### **1. Supabase Service**
```
📄 Kuro/Services/SupabaseService.swift
- Supabase client initialization
- Authentication (anonymous/email)
- Database queries
- Real-time subscriptions
- CDN/Storage operations
```

### **2. Supabase Models**
```
📄 Kuro/Models/SupabaseModels.swift
- Media model (anime/manga/manhwa)
- UserList model
- SearchFilters model
- All Supabase-specific types
```

### **3. Single Documentation**
```
📄 README.md
- Project overview
- Supabase setup
- Design system specs
- Development guide
```

---

## 🗑️ **Cleanup Actions:**

### **Phase 1: Remove Firebase**
1. Delete all Firebase-related Swift files
2. Delete all Firebase documentation
3. Remove Firebase packages from Xcode
4. Remove GoogleService-Info.plist

### **Phase 2: Remove Old Docs**
1. Delete all scattered MD files
2. Delete all JS files (if any)
3. Delete all test/debug files

### **Phase 3: Create Supabase Integration**
1. Create SupabaseService.swift
2. Create SupabaseModels.swift
3. Update ContentView to use Supabase
4. Test connection to Supabase

### **Phase 4: Final Cleanup**
1. Remove build artifacts
2. Remove derived data references
3. Clean Xcode project structure
4. Create single README.md

---

## 📁 **Final Structure:**

```
Kuro/
├── Kuro.xcodeproj/
├── Kuro/
│   ├── KuroApp.swift          ← Main entry point
│   ├── ContentView.swift      ← White minimalist UI
│   ├── Models/
│   │   └── SupabaseModels.swift
│   ├── Services/
│   │   └── SupabaseService.swift
│   └── Assets.xcassets/
├── KuroTests/
├── KuroUITests/
└── README.md
```

---

## ✅ **Expected Results:**

- **Clean codebase** with only essential files
- **Single database** (Supabase only)
- **Single design** (White "Elevated Minimalism")
- **No technical debt**
- **No conflicting implementations**
- **Easy to maintain**

---

**Ready to execute this cleanup plan?**
