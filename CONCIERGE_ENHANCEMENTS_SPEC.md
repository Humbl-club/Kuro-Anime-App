# Kuro Concierge - Enhancement Implementation Spec

## Features Selected:
1. ✅ Smart Suggestion Chips (Context-aware)
2. ✅ Batch Import Progress (Large list handling)
3. ✅ Haptic "Click" on Card Snap (Physical feedback)
4. ✅ Interactive Widgets (Home Screen quick actions)
5. ✅ Shortcuts App Integration (Siri automation)
6. ✅ Dark Mode Polish (Elegant glass morphism)

---

## 1. SMART SUGGESTION CHIPS

### What It Does
As the user types, intelligent chips appear above the input suggesting completions, filters, or categories.

```
User types: "I want something funny"
                 ↓
[Funny] [Comedy] [Not childish] [Short episodes]
─────────────────────────────────────────────────
Start typing, paste, or ask...              [↑]
```

### Implementation

**File:** `ConciergeSmartSuggestions.swift`

```swift
struct SmartSuggestionBar: View {
    @Binding var text: String
    let onSuggestionTap: (String) -> Void
    
    private var suggestions: [SuggestionChip] {
        generateSuggestions(from: text)
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions) { suggestion in
                    SuggestionChipView(suggestion: suggestion)
                        .onTapGesture {
                            onSuggestionTap(suggestion.completion)
                        }
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(height: suggestions.isEmpty ? 0 : 36)
        .animation(.spring(response: 0.3), value: suggestions.isEmpty)
    }
    
    private func generateSuggestions(from text: String) -> [SuggestionChip] {
        var chips: [SuggestionChip] = []
        let lowercased = text.lowercased()
        
        // Genre suggestions
        if lowercased.contains("funny") || lowercased.contains("laugh") {
            chips.append(SuggestionChip(
                icon: "😄",
                text: "Comedy",
                completion: text + " comedy",
                color: .yellow
            ))
        }
        
        // Format suggestions
        if !lowercased.contains("movie") && !lowercased.contains("series") {
            chips.append(SuggestionChip(
                icon: "🎬",
                text: "Movie",
                completion: text + " movie",
                color: .blue
            ))
        }
        
        // Length suggestions
        if !lowercased.contains("short") && !lowercased.contains("long") {
            chips.append(SuggestionChip(
                icon: "⏱️",
                text: "Under 12 episodes",
                completion: text + " short series",
                color: .green
            ))
        }
        
        // Time-aware
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 22 || hour <= 2 {
            chips.append(SuggestionChip(
                icon: "🌙",
                text: "Calm before bed",
                completion: "something relaxing",
                color: .indigo
            ))
        }
        
        return chips.prefix(4)
    }
}

struct SuggestionChip: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
    let completion: String
    let color: Color
}

struct SuggestionChipView: View {
    let suggestion: SuggestionChip
    
    var body: some View {
        HStack(spacing: 4) {
            Text(suggestion.icon)
                .font(.caption)
            Text(suggestion.text)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(suggestion.color)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(suggestion.color.opacity(0.12))
                .overlay(
                    Capsule()
                        .stroke(suggestion.color.opacity(0.3), lineWidth: 0.5)
                )
        )
    }
}
```

**Difficulty:** ⭐⭐ Easy  
**Time:** 2-3 hours  
**Dependencies:** None

---

## 2. BATCH IMPORT PROGRESS

### What It Does
When importing 50+ titles, show a progress card that updates in real-time and continues in background.

```
┌─────────────────────────────────────────┐
│  IMPORTING...                    [PAUSE]│
│                                         │
│  ████████████████░░░░  68 of 100       │
│                                         │
│  Found: 68 matches                      │
│  In library: 12 already tracked         │
│  Processing: Hunter x Hunter...         │
│                                         │
│  [Cancel]              [Background]     │
└─────────────────────────────────────────┘
```

### Implementation

**File:** `ConciergeBatchImport.swift`

```swift
import SwiftUI
import Combine

@MainActor
final class BatchImportViewModel: ObservableObject {
    @Published var totalItems: Int = 0
    @Published var processedItems: Int = 0
    @Published var matchedItems: Int = 0
    @Published var existingItems: Int = 0
    @Published var currentItem: String = ""
    @Published var status: ImportStatus = .idle
    @Published var canContinueInBackground: Bool = false
    
    enum ImportStatus: Equatable {
        case idle
        case processing(current: String, progress: Double)
        case paused
        case completed(success: Int, failed: Int)
        case failed(Error)
    }
    
    private var importTask: Task<Void, Never>?
    private let supabaseService: SupabaseService
    
    func startImport(items: [String]) {
        totalItems = items.count
        processedItems = 0
        status = .processing(current: items.first ?? "", progress: 0)
        canContinueInBackground = true
        
        importTask = Task { [weak self] in
            await self?.processItems(items)
        }
    }
    
    func pauseImport() {
        importTask?.cancel()
        status = .paused
    }
    
    func resumeImport() {
        // Resume from processedItems
    }
    
    private func processItems(_ items: [String]) async {
        for (index, item) in items.enumerated() {
            // Check for cancellation
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                currentItem = item
                status = .processing(
                    current: item,
                    progress: Double(index) / Double(items.count)
                )
            }
            
            // Process item
            do {
                let result = try await supabaseService.conciergeParse(text: item)
                await MainActor.run {
                    processedItems += 1
                    matchedItems += result.items.count
                }
            } catch {
                // Handle error but continue
            }
            
            // Small delay to show progress
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        }
        
        await MainActor.run {
            status = .completed(success: matchedItems, failed: 0)
            canContinueInBackground = false
        }
    }
}

struct BatchImportProgressCard: View {
    @StateObject private var viewModel = BatchImportViewModel()
    let items: [String]
    let onComplete: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("IMPORTING...")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.5)
                }
                .foregroundColor(.secondary)
                
                Spacer()
                
                Button("PAUSE") {
                    viewModel.pauseImport()
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.accentColor)
            }
            
            // Progress bar
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary.opacity(0.2))
                        
                        RoundedRectangle(cornerRadius: 2)
                            .fill(progressGradient)
                            .frame(width: geo.size.width * progress)
                            .animation(.linear(duration: 0.3), value: progress)
                    }
                }
                .frame(height: 4)
                
                HStack {
                    Text("\(viewModel.processedItems) of \(viewModel.totalItems)")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            
            // Stats
            VStack(alignment: .leading, spacing: 4) {
                StatRow(icon: "✓", text: "Found: \(viewModel.matchedItems) matches", color: .green)
                StatRow(icon: "📚", text: "In library: \(viewModel.existingItems) already tracked", color: .blue)
                StatRow(icon: "▶", text: "Processing: \(viewModel.currentItem)", color: .orange)
            }
            .font(.system(size: 12))
            
            // Actions
            HStack(spacing: 12) {
                Button("Cancel") {
                    viewModel.pauseImport()
                    onCancel()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                if viewModel.canContinueInBackground {
                    Button("Background") {
                        // Trigger Live Activity
                        startLiveActivity()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .onAppear {
            viewModel.startImport(items: items)
        }
    }
    
    private var progress: Double {
        guard viewModel.totalItems > 0 else { return 0 }
        return Double(viewModel.processedItems) / Double(viewModel.totalItems)
    }
    
    private var progressGradient: LinearGradient {
        LinearGradient(
            colors: [.blue, .purple],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    private func startLiveActivity() {
        // iOS 16.1+ Live Activity
        if #available(iOS 16.1, *) {
            // Start Live Activity here
        }
    }
}

struct StatRow: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 6) {
            Text(icon)
                .foregroundColor(color)
            Text(text)
                .foregroundColor(.primary)
        }
    }
}
```

**Difficulty:** ⭐⭐⭐ Medium  
**Time:** 4-6 hours  
**Dependencies:** SupabaseService, Live Activities (optional)

---

## 3. HAPTIC "CLICK" ON CARD SNAP

### What It Does
As recommendation cards snap to center during scrolling, a micro-haptic gives physical feedback like a watch crown or high-end knob.

### Implementation

**File:** Add to `ConciergeRecommendationRails.swift`

```swift
struct HapticScrollingModifier: ViewModifier {
    @State private var lastCenteredIndex: Int?
    let itemCount: Int
    let generator = UIImpactFeedbackGenerator(style: .light)
    
    func body(content: Content) -> some View {
        content
            .onChange(of: centeredIndex) { oldIndex, newIndex in
                if oldIndex != newIndex {
                    generator.impactOccurred(intensity: 0.3)
                }
            }
    }
    
    private var centeredIndex: Int {
        // Calculate based on scroll offset
        // This is handled by the parent view
        return 0
    }
}

// Usage in RecommendationRail:
// Add to the ScrollView
.onPreferenceChange(CenteredCardPreferenceKey.self) { index in
    if index != lastCenteredIndex {
        UIImpactFeedbackGenerator(style: .light)
            .impactOccurred(intensity: 0.3)
        lastCenteredIndex = index
    }
}
```

**Simplified Implementation:**

```swift
struct RecommendationRailWithHaptics: View {
    let items: [ConciergeRecommendItem]
    @State private var centeredItemID: String?
    private let hapticGenerator = UISelectionFeedbackGenerator()
    
    init(items: [ConciergeRecommendItem]) {
        self.items = items
        hapticGenerator.prepare()
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(items) { item in
                    GeometryReader { geo in
                        RecommendationCard(item: item)
                            .scaleEffect(scale(for: geo))
                            .onChange(of: geo.frame(in: .global).midX) { oldX, newX in
                                checkIfCentered(itemID: item.id, midX: newX)
                            }
                    }
                    .frame(width: 140, height: 200)
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    private func scale(for geo: GeometryProxy) -> CGFloat {
        let midX = geo.frame(in: .global).midX
        let screenMidX = UIScreen.main.bounds.midX
        let distance = abs(midX - screenMidX)
        let maxDistance: CGFloat = 200
        
        // Scale 1.0 at center, 0.9 at edges
        let normalized = min(distance / maxDistance, 1.0)
        return 1.0 - (normalized * 0.1)
    }
    
    private func checkIfCentered(itemID: String, midX: CGFloat) {
        let screenMidX = UIScreen.main.bounds.midX
        let isCentered = abs(midX - screenMidX) < 70 // Half card width
        
        if isCentered && centeredItemID != itemID {
            hapticGenerator.selectionChanged()
            centeredItemID = itemID
        }
    }
}
```

**Difficulty:** ⭐ Easy  
**Time:** 1 hour  
**Dependencies:** None

---

## 4. INTERACTIVE WIDGETS

### What It Does
Home Screen widgets with quick actions to add anime or get recommendations without opening the app.

```
┌─────────────────┐
│  KURO           │
│                 │
│  Quick Add      │
│                 │
│  [+] Tap to add │
│                 │
└─────────────────┘
```

### Implementation

**Files:**
- `KuroWidget.swift` (Widget target)
- `ConciergeWidget.intentdefinition` (Siri Intents)

**Widget Code:**

```swift
import WidgetKit
import SwiftUI
import AppIntents

struct KuroWidgetEntry: TimelineEntry {
    let date: Date
    let suggestedAction: WidgetAction
    let lastAddedTitle: String?
}

enum WidgetAction: String {
    case quickAdd = "Quick Add"
    case todayRecs = "Today's Picks"
    case continueWatching = "Continue"
}

struct KuroWidgetProvider: AppIntentTimelineProvider {
    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<KuroWidgetEntry> {
        // Get context from app
        let entry = KuroWidgetEntry(
            date: Date(),
            suggestedAction: determineAction(),
            lastAddedTitle: getLastAddedTitle()
        )
        
        return Timeline(entries: [entry], policy: .atEnd)
    }
    
    private func determineAction() -> WidgetAction {
        let hour = Calendar.current.component(.hour, from: Date())
        
        // Morning: Recommendations
        if hour < 12 {
            return .todayRecs
        }
        // Evening: Continue watching
        else if hour > 18 {
            return .continueWatching
        }
        // Default: Quick add
        else {
            return .quickAdd
        }
    }
}

struct KuroWidgetView: View {
    var entry: KuroWidgetProvider.Entry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

struct SmallWidgetView: View {
    let entry: KuroWidgetEntry
    
    var body: some View {
        ZStack {
            ContainerRelativeShape()
                .fill(.black)
            
            VStack(spacing: 8) {
                Image(systemName: "moon.stars.fill")
                    .font(.title2)
                    .foregroundColor(.white)
                
                Text(entry.suggestedAction.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                
                if let lastAdded = entry.lastAddedTitle {
                    Text(lastAdded)
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }
            .padding()
        }
    }
}

// App Intent for widget interaction
struct QuickAddIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Add Anime"
    static var description = IntentDescription("Quickly add an anime to your list")
    
    @Parameter(title: "Anime Title")
    var title: String
    
    func perform() async throws -> some IntentResult {
        // Deep link to app with quick add
        await openApp(with: "kuro://quick-add?title=\(title)")
        return .result()
    }
}

@main
struct KuroWidget: Widget {
    let kind: String = "KuroWidget"
    
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: ConfigurationAppIntent.self,
            provider: KuroWidgetProvider()
        ) { entry in
            KuroWidgetView(entry: entry)
        }
        .configurationDisplayName("Kuro Quick Actions")
        .description("Quickly add anime or see recommendations")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
```

**Widget Configuration:**

Add to `Info.plist`:
```xml
<key>NSWidgetWantsLocation</key>
<false/>
```

Add Widget Extension target in Xcode.

**Difficulty:** ⭐⭐⭐ Medium  
**Time:** 3-4 hours  
**Dependencies:** WidgetKit, AppIntents

**Where to put them:**
- **Small widget:** Quick Add button (tap → opens app to input)
- **Medium widget:** Today's recommendations preview (tap → opens Discover)
- **Lock Screen widget:** Continue watching (iOS 16+)

---

## 5. SHORTCUTS APP INTEGRATION

### What It Does
Allow users to create automations:
- "Add anime when I say 'Track this'"
- "Get recommendations every Friday at 6pm"
- "Import from clipboard when I copy a list"

### Implementation

**File:** `ConciergeShortcuts.swift`

```swift
import AppIntents

// MARK: - Add Anime Shortcut

struct AddAnimeIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Anime to List"
    static var description = IntentDescription("Add an anime to your Kuro list")
    
    @Parameter(title: "Anime Title", requestValueDialog: "What anime would you like to add?")
    var title: String
    
    @Parameter(title: "Status", default: .planning)
    var status: WatchStatus
    
    @Parameter(title: "Progress", default: 0)
    var progress: Int
    
    static var parameterSummary: some ParameterSummary {
        Summary("Add \($title) to my list as \($status)")
    }
    
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let supabase = SupabaseService.shared
        
        // Search for anime
        let results = try await supabase.searchAnime(query: title)
        
        guard let firstMatch = results.first else {
            throw IntentError.noMatchesFound
        }
        
        // Add to list
        try await supabase.addToList(
            animeId: firstMatch.id,
            status: status.rawValue,
            progress: progress
        )
        
        return .result(value: "Added \(firstMatch.title) to your list")
    }
}

enum WatchStatus: String, AppEnum {
    case planning = "Planning"
    case watching = "Watching"
    case completed = "Completed"
    case dropped = "Dropped"
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Watch Status"
    }
    
    static var caseDisplayRepresentations: [WatchStatus: DisplayRepresentation] {
        [
            .planning: "Planning to Watch",
            .watching: "Currently Watching",
            .completed: "Completed",
            .dropped: "Dropped"
        ]
    }
}

// MARK: - Get Recommendations Shortcut

struct GetRecommendationsIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Anime Recommendations"
    static var description = IntentDescription("Get personalized anime recommendations from Kuro")
    
    @Parameter(title: "Vibe or Genre", default: "")
    var vibe: String
    
    func perform() async throws -> some IntentResult & ReturnsValue<[AnimeEntity]> {
        let supabase = SupabaseService.shared
        
        let recommendations = try await supabase.conciergeRecommend(
            prompt: vibe.isEmpty ? "Something good" : vibe
        )
        
        let entities = recommendations.map { AnimeEntity(from: $0) }
        
        return .result(value: entities)
    }
}

struct AnimeEntity: AppEntity {
    let id: String
    let title: String
    let year: Int
    let rating: Double
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Anime"
    }
    
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title) (\(year))")
    }
}

// MARK: - Import from Clipboard Shortcut

struct ImportFromClipboardIntent: AppIntent {
    static var title: LocalizedStringResource = "Import Anime from Clipboard"
    static var description = IntentDescription("Import a list of anime from your clipboard")
    
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let clipboardText = UIPasteboard.general.string else {
            throw IntentError.clipboardEmpty
        }
        
        let supabase = SupabaseService.shared
        let result = try await supabase.conciergeParse(text: clipboardText)
        
        return .result(value: "Found \(result.items.count) anime to import")
    }
}

// MARK: - Error Handling

enum IntentError: Error, CustomStringConvertible {
    case noMatchesFound
    case clipboardEmpty
    case networkError
    
    var description: String {
        switch self {
        case .noMatchesFound:
            return "Couldn't find that anime. Try a different title."
        case .clipboardEmpty:
            return "Your clipboard is empty. Copy a list first."
        case .networkError:
            return "Couldn't connect to Kuro. Check your internet."
        }
    }
}

// MARK: - App Shortcuts Provider

struct KuroAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        [
            AppShortcut(
                intent: AddAnimeIntent(),
                phrases: [
                    "Add \(.applicationName)",
                    "Track \(.applicationName)",
                    "Add anime to \(.applicationName)"
                ],
                shortTitle: "Add Anime",
                systemImageName: "plus.circle"
            ),
            AppShortcut(
                intent: GetRecommendationsIntent(),
                phrases: [
                    "Recommend something on \(.applicationName)",
                    "What should I watch on \(.applicationName)",
                    "Get recommendations from \(.applicationName)"
                ],
                shortTitle: "Get Recommendations",
                systemImageName: "sparkles"
            ),
            AppShortcut(
                intent: ImportFromClipboardIntent(),
                phrases: [
                    "Import clipboard to \(.applicationName)",
                    "Paste list into \(.applicationName)"
                ],
                shortTitle: "Import List",
                systemImageName: "doc.on.clipboard"
            )
        ]
    }
}
```

**Usage Examples:**

1. **Siri:** "Add Attack on Titan to Kuro"
2. **Shortcuts App:** Create automation "When I say 'Track this' → Add Anime"
3. **Focus Mode:** "When Work focus ends → Get recommendations"

**Difficulty:** ⭐⭐ Medium  
**Time:** 3-4 hours  
**Dependencies:** AppIntents framework

---

## 6. DARK MODE POLISH

### What It Changes
Elegant dark mode with proper glass morphism that doesn't look muddy.

### Implementation

**File:** `ConciergeDarkMode.swift`

```swift
import SwiftUI

// MARK: - Dark Mode Colors

extension Color {
    // Dark mode glass backgrounds
    static let glassDark = Color.white.opacity(0.05)
    static let glassDarkBorder = Color.white.opacity(0.15)
    static let glassDarkGlow = Color.purple.opacity(0.2)
    
    // Accent glows
    static let accentGlow = Color.accentColor.opacity(0.3)
}

// MARK: - Glass Card (Dark Mode Aware)

struct AdaptiveGlassCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat
    let content: Content
    
    init(cornerRadius: CGFloat, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }
    
    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundStyle)
                    .overlay(borderOverlay)
                    .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
    
    private var backgroundStyle: some View {
        Group {
            if colorScheme == .dark {
                // Dark mode: subtle glass with inner glow
                Color.white.opacity(0.08)
                    .overlay(
                        // Inner glow at top
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.1),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            } else {
                // Light mode: ultra thin material
                .ultraThinMaterial
            }
        }
    }
    
    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: colorScheme == .dark ?
                        [Color.white.opacity(0.25), Color.white.opacity(0.05)] :
                        [Color.white.opacity(0.72), Color.white.opacity(0.18)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: colorScheme == .dark ? 0.8 : 0.8
            )
    }
    
    private var shadowColor: Color {
        colorScheme == .dark ?
            Color.black.opacity(0.5) :
            Color.black.opacity(0.08)
    }
    
    private var shadowRadius: CGFloat {
        colorScheme == .dark ? 20 : 16
    }
    
    private var shadowY: CGFloat {
        colorScheme == .dark ? 8 : 10
    }
}

// MARK: - Dark Mode Message Bubbles

struct DarkModeMessageBubble: View {
    let message: ConciergeMessage
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
                userBubble
            } else {
                assistantBubble
                Spacer()
            }
        }
    }
    
    private var userBubble: some View {
        Text(message.text)
            .font(.system(size: 15))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(colorScheme == .dark ?
                        // Dark mode: subtle purple tint
                        Color.purple.opacity(0.3) :
                        Color.black.opacity(0.88)
                    )
                    .overlay(
                        // Subtle gradient overlay
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.1),
                                        Color.clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
    }
    
    private var assistantBubble: some View {
        AdaptiveGlassCard(cornerRadius: 20) {
            Text(message.text)
                .font(.system(size: 15))
                .foregroundColor(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
    }
}

// MARK: - Dark Mode Input Field

struct DarkModeInputField: View {
    @Binding var text: String
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack {
            TextField("", text: $text)
                .font(.system(size: 15))
                .focused($isFocused)
                .overlay(placeholder)
            
            Button(action: {}) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(text.isEmpty ? .secondary : .primary)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark ?
                                Color.purple.opacity(0.3) :
                                Color.clear
                            )
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(colorScheme == .dark ?
                    Color.white.opacity(0.05) :
                    .ultraThinMaterial
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            isFocused ?
                                (colorScheme == .dark ?
                                    Color.purple.opacity(0.5) :
                                    Color.accentColor.opacity(0.3)
                                ) :
                                Color.white.opacity(colorScheme == .dark ? 0.1 : 0.3),
                            lineWidth: isFocused ? 1.5 : 0.5
                        )
                )
                .shadow(
                    color: isFocused ?
                        (colorScheme == .dark ?
                            Color.purple.opacity(0.2) :
                            Color.accentColor.opacity(0.1)
                        ) :
                        Color.clear,
                    radius: isFocused ? 12 : 0
                )
        )
    }
    
    private var placeholder: some View {
        Group {
            if text.isEmpty {
                Text("Start typing...")
                    .foregroundColor(.secondary.opacity(0.5))
                    .allowsHitTesting(false)
            }
        }
    }
}
```

**Dark Mode Visual Changes:**

| Element | Light Mode | Dark Mode |
|---------|-----------|-----------|
| Background | White | Pure black (#000000) |
| Glass | ultraThinMaterial | White 5-8% opacity |
| Border | White 72% → 18% | White 25% → 5% |
| Shadow | Black 8% | Black 50% |
| User bubble | Black 88% | Purple 30% tint |
| Input glow | Accent color | Purple glow |
| Mascot | Black outline | White/purple glow |

**Difficulty:** ⭐⭐ Easy  
**Time:** 2-3 hours  
**Dependencies:** None (uses @Environment colorScheme)

---

## 📊 Implementation Priority Matrix

| Feature | Impact | Difficulty | Time | Priority |
|---------|--------|------------|------|----------|
| **Dark Mode** | High | Easy | 2-3h | 1st |
| **Haptic Click** | Medium | Easy | 1h | 2nd |
| **Smart Suggestions** | High | Easy | 2-3h | 3rd |
| **Batch Import** | High | Medium | 4-6h | 4th |
| **Widgets** | Medium | Medium | 3-4h | 5th |
| **Shortcuts** | High | Medium | 3-4h | 6th |

**Total Time:** ~15-23 hours

---

## 🚀 Next Steps

1. **Start with Dark Mode** - Biggest visual impact, easiest to implement
2. **Add Haptic Click** - Quick win for satisfaction
3. **Smart Suggestions** - Makes input feel psychic
4. **Batch Import** - Essential for power users
5. **Widgets + Shortcuts** - Deep iOS integration

**Which one should we build first?**
