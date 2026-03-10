# KURO SQL DEPLOYMENT GUIDE
## Countdown Timers & Notifications Setup

---

## 🎯 **WHAT THIS ENABLES:**

- ⏱️ Countdown timers on Collection cards ("EP 25 IN 2D 5H")
- 🔔 Push notifications (1 hour before + "airing now")
- 📱 User-scoped upcoming anime (only shows YOUR saved anime)
- 🔄 Auto-updates every minute

---

## ⚠️ **CRITICAL: RUN IN THIS EXACT ORDER**

The SQL files **MUST** be executed in sequence. Running out of order will fail.

---

## 📋 **DEPLOYMENT STEPS:**

### **Step 1: Migrate user_id to TEXT**
**File:** `12_fix_user_id_type.sql`
**Time:** ~5 seconds
**What it does:**
- Changes `anime_user_lists.user_id` from INTEGER → TEXT
- Changes `manga_user_lists.user_id` from INTEGER → TEXT
- Drops/recreates RLS policies to match
- Adds performance indexes
- Verifies migration succeeded

**Why:** Supabase auth returns UUID (text), not integers. Without this, addToList() fails with type mismatch error.

**In Supabase SQL Editor:**
```sql
-- Copy/paste entire contents of 12_fix_user_id_type.sql
-- Click "Run"
-- Should see: "Migration complete. Verifying..." messages
-- Should see: "user_id type: text" confirmation
```

---

### **Step 2: Create Upcoming Airings View**
**File:** `10_create_user_airing_next_view.sql`
**Time:** ~1 second
**What it does:**
- Creates `public.user_airing_next` view
- Shows anime with future `next_airing_at`
- Joins `anime_user_lists` + `anime` tables
- Includes: title, episode number, air date, list type, progress

**Why:** Provides efficient query for "what anime am I watching that's airing soon?"

**In Supabase SQL Editor:**
```sql
-- Copy/paste entire contents of 10_create_user_airing_next_view.sql
-- Click "Run"
-- Should see: "CREATE VIEW" success message
```

**Verify:**
```sql
SELECT * FROM user_airing_next LIMIT 5;
```

---

### **Step 3: Create RPC Function (Optional)**
**File:** `11_airing_next_rpc.sql`
**Time:** ~1 second
**What it does:**
- Creates `airing_next(days)` function
- Easier to call from app than querying view
- Auto-filters by auth.uid()
- Takes days parameter (default 7)

**Why:** Simpler app code - call `rpc("airing_next", params: ["days": 7])`

**In Supabase SQL Editor:**
```sql
-- Copy/paste entire contents of 11_airing_next_rpc.sql
-- Click "Run"
-- Should see: "CREATE FUNCTION" success message
```

**Verify:**
```sql
SELECT * FROM airing_next(7);
```

---

## ✅ **VERIFICATION CHECKLIST:**

After running all 3 SQL files:

```sql
-- 1. Check user_id type changed
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'anime_user_lists'
  AND column_name = 'user_id';
-- Expected: "text" or "character varying"

-- 2. Check view exists
SELECT COUNT(*) FROM information_schema.views
WHERE table_name = 'user_airing_next';
-- Expected: 1

-- 3. Check RPC exists
SELECT COUNT(*) FROM information_schema.routines
WHERE routine_name = 'airing_next';
-- Expected: 1

-- 4. Test view (if you have anime with next_airing_at)
SELECT * FROM user_airing_next LIMIT 5;
-- Expected: Rows for upcoming anime, or empty if none

-- 5. Test RPC (if created)
SELECT * FROM airing_next(7);
-- Expected: Same as view but filtered to 7 days
```

---

## 🔧 **TROUBLESHOOTING:**

### **Error: "cannot cast type integer to text"**
**Cause:** Step 1 (12_fix_user_id_type.sql) didn't run
**Fix:** Run 12_fix_user_id_type.sql first, then retry

### **Error: "relation does not exist"**
**Cause:** View references tables that don't exist
**Fix:** Ensure 02_comprehensive_table_creation.sql ran successfully

### **Error: "column does not exist"**
**Cause:** Schema mismatch
**Fix:** Verify columns in your actual anime/anime_user_lists tables match

### **View returns 0 rows**
**Cause:** No anime in database with future `next_airing_at`
**Fix:** Normal if no airing anime. Wait for edge functions to import data

---

## 🚀 **AFTER DEPLOYMENT:**

### **App Behavior:**

1. **Launch App:**
   - Fetches upcoming airings (line 90 in SupabaseService)
   - Populates `countdownByAnimeId` dictionary
   - Starts 1-minute timer for updates

2. **Add Anime to Collection:**
   - Requests notification permission (first time)
   - Schedules 2 notifications per anime
   - Refreshes upcoming list
   - Countdown appears on card

3. **Collection View:**
   - Cards show: "⏱️ EP 25 IN 2D 5H"
   - Updates every minute
   - Only for RELEASING anime with future air dates

4. **Notifications:**
   - "1 hour before" alert
   - "Airs now" alert
   - Canceled when removed from collection

---

## 📊 **SCHEMA COMPATIBILITY:**

### **Before Migration:**
```sql
anime_user_lists.user_id: INTEGER
❌ App tries to insert UUID → Type error
```

### **After Migration:**
```sql
anime_user_lists.user_id: TEXT
✅ App inserts UUID → Works perfectly
```

### **View/RPC Requirements:**
```
✅ anime.id (INTEGER)
✅ anime.title_english (TEXT)
✅ anime.title_romaji (TEXT)
✅ anime.next_episode_number (INTEGER)
✅ anime.next_airing_at (TIMESTAMP WITH TIME ZONE)
✅ anime_user_lists.user_id (TEXT - after migration)
✅ anime_user_lists.anime_id (INTEGER FK)
✅ anime_user_lists.list_type (TEXT)
✅ anime_user_lists.progress (INTEGER)
```

All columns exist in your schema! ✅

---

## 🎉 **EXPECTED OUTCOME:**

After running all 3 SQL files:
- ✅ addToList() works (no more UUID → INTEGER errors)
- ✅ Countdown timers appear on Collection cards
- ✅ Notifications schedule automatically
- ✅ Updates every minute
- ✅ Production-ready countdown system

**Total Time:** ~10 seconds to run all 3 files
**Impact:** Full countdown + notification system activated!
