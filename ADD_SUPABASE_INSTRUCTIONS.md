# 📦 Add Supabase to Xcode

## Step-by-Step Instructions:

1. **In Xcode, select your project** in the navigator (top item)
2. **Go to "Package Dependencies" tab**
3. **Click the "+" button**
4. **Enter this URL:** `https://github.com/supabase/supabase-swift`
5. **Click "Add Package"**
6. **Select these products:**
   - ✅ **Supabase** (the main package)
   - ✅ **Realtime** (for real-time subscriptions)
   - ✅ **PostgREST** (for database queries)
   - ✅ **Storage** (for CDN/file storage)
7. **Click "Add Package"**

## ✅ After Adding:
- Clean build folder: `Cmd + Shift + K`
- Build and run: `Cmd + R`

The app will now use Supabase as the single source of truth for all data!
