import SwiftUI

// MARK: - COLLECTION MANAGEMENT VIEW - iOS 26 Mobile-First
// Complete user list management with elegant design

struct CollectionManagementView: View {
    @Environment(SupabaseService.self) private var supabaseService
    @State private var selectedStatus: ListStatus = .current
    @State private var showAddSheet = false
    @State private var searchText = ""
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Header
                CollectionHeader()
                
                // Status Filter
                StatusFilterBar(selectedStatus: $selectedStatus)
                
                // Collection Grid
                ScrollView(.vertical, showsIndicators: false) {
                    if filteredItems.isEmpty {
                        EmptyCollectionView(status: selectedStatus)
                    } else {
                        LazyVGrid(
                            columns: adaptiveColumns(for: geometry.size.width),
                            spacing: KuroSpacing.adaptive(KuroSpacing.lg, for: geometry.size.width)
                        ) {
                            ForEach(filteredItems) { item in
                                CollectionItemCard(item: item)
                            }
                        }
                        .padding(.horizontal, ResponsiveLayout.padding())
                        .padding(.top, KuroSpacing.lg)
                    }
                }
                .background(Color.kuroBackground)
            }
        }
    }
    
    private var filteredItems: [Anime] {
        // TODO: Filter by user's list status
        supabaseService.animeItems
    }
    
    private func adaptiveColumns(for width: CGFloat) -> [GridItem] {
        let columnCount: Int
        switch width {
        case 0..<375:    columnCount = 2
        case 375..<768:  columnCount = 3
        case 768..<1024: columnCount = 4
        default:         columnCount = 5
        }
        return Array(repeating: GridItem(.flexible(), spacing: KuroSpacing.md), count: columnCount)
    }
}

// MARK: - Collection Header
struct CollectionHeader: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: KuroSpacing.xs) {
                    Text("MY COLLECTION")
                        .font(.kuroCardTitle(weight: .light))
                        .tracking(1.0)
                        .foregroundColor(.kuroBlack)
                    
                    Text("Track your anime & manga")
                        .font(.kuroMicro(weight: .light))
                        .tracking(0.5)
                        .foregroundColor(.kuroBlack60)
                }
                
                Spacer()
                
                Button(action: {
                    KuroAccessibility.impactHaptic(.light)
                    // Add new item
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.kuroCardTitle())
                        .foregroundColor(.kuroBlack)
                }
            }
            .padding(.horizontal, ResponsiveLayout.padding())
            .padding(.vertical, KuroSpacing.lg)
            
            Rectangle()
                .fill(Color.kuroBlack08)
                .frame(height: 0.5)
        }
    }
}

// MARK: - Status Filter Bar
struct StatusFilterBar: View {
    @Binding var selectedStatus: ListStatus
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: KuroSpacing.xl) {
                ForEach(ListStatus.allCases, id: \.self) { status in
                    StatusFilterButton(
                        status: status,
                        isSelected: selectedStatus == status
                    ) {
                        withAnimation(KuroAnimation.spring) {
                            selectedStatus = status
                        }
                        KuroAccessibility.impactHaptic(.light)
                    }
                }
            }
            .padding(.horizontal, ResponsiveLayout.padding())
            .padding(.vertical, KuroSpacing.lg)
        }
        .background(Color.kuroBackground)
    }
}

// MARK: - Status Filter Button
struct StatusFilterButton: View {
    let status: ListStatus
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: KuroSpacing.xs) {
                Text(status.displayName.uppercased())
                    .font(.kuroMicro(weight: isSelected ? .medium : .light))
                    .tracking(1.0)
                    .foregroundColor(isSelected ? .kuroBlack : .kuroBlack60)
                
                Rectangle()
                    .fill(Color.kuroBlack)
                    .frame(height: 1)
                    .scaleEffect(x: isSelected ? 1.0 : 0.0, anchor: .center)
                    .opacity(isSelected ? 1.0 : 0.0)
            }
        }
    }
}

// MARK: - Collection Item Card
struct CollectionItemCard: View {
    let item: Anime
    @State private var showDetail = false
    @State private var showProgress = false
    
    var body: some View {
        Button(action: {
            KuroAccessibility.impactHaptic(.light)
            showDetail = true
        }) {
            VStack(alignment: .leading, spacing: KuroSpacing.xs) {
                // Cover Image
                AsyncImage(url: URL(string: item.displayImage)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.kuroBlack08)
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.6)
                        )
                }
                .aspectRatio(0.7, contentMode: .fill)
                .clipped()
                .cornerRadius(KuroRadius.sm)
                
                // Progress Bar (if watching/reading)
                ProgressBar(current: 5, total: item.episodeCount ?? 1)
                
                // Title
                Text(item.displayTitle.uppercased())
                    .font(.kuroMicro(weight: .medium))
                    .tracking(0.5)
                    .foregroundColor(.kuroBlack80)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                // Episode/Chapter count
                Text(item.episodeText)
                    .font(.kuroMicro(weight: .light))
                    .tracking(0.5)
                    .foregroundColor(.kuroBlack60)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showDetail) {
            AnimeDetailView(anime: item)
        }
    }
}

// MARK: - Progress Bar
struct ProgressBar: View {
    let current: Int
    let total: Int
    
    var progress: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.kuroBlack08)
                    .frame(height: 2)
                
                Rectangle()
                    .fill(Color.kuroBlack)
                    .frame(width: geometry.size.width * progress, height: 2)
            }
        }
        .frame(height: 2)
    }
}

// MARK: - Empty Collection View
struct EmptyCollectionView: View {
    let status: ListStatus
    
    var body: some View {
        VStack(spacing: KuroSpacing.lg) {
            Image(systemName: emptyIcon)
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundColor(.kuroBlack30)
            
            VStack(spacing: KuroSpacing.xs) {
                Text(emptyTitle)
                    .font(.kuroBody(weight: .light))
                    .tracking(1.0)
                    .foregroundColor(.kuroBlack80)
                
                Text(emptyMessage)
                    .font(.kuroMicro(weight: .light))
                    .tracking(0.5)
                    .foregroundColor(.kuroBlack60)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: {
                KuroAccessibility.impactHaptic(.medium)
                // Navigate to discover
            }) {
                Text("EXPLORE CONTENT")
                    .font(.kuroMicro(weight: .medium))
                    .tracking(1.5)
                    .foregroundColor(.kuroWhite)
                    .padding(.horizontal, KuroSpacing.xl)
                    .padding(.vertical, KuroSpacing.md)
                    .background(Color.kuroBlack)
                    .cornerRadius(KuroRadius.sm)
            }
        }
        .padding(.top, 80)
    }
    
    private var emptyIcon: String {
        switch status {
        case .current: return "play.circle"
        case .planning: return "clock"
        case .completed: return "checkmark.circle"
        case .dropped: return "xmark.circle"
        case .paused: return "pause.circle"
        case .repeating: return "arrow.clockwise.circle"
        }
    }
    
    private var emptyTitle: String {
        "NO \(status.displayName.uppercased()) ITEMS"
    }
    
    private var emptyMessage: String {
        switch status {
        case .current: return "Start watching or reading something new"
        case .planning: return "Add items you plan to watch or read"
        case .completed: return "Items you've finished will appear here"
        case .dropped: return "Dropped items will appear here"
        case .paused: return "Paused items will appear here"
        case .repeating: return "Items you're rewatching will appear here"
        }
    }
}

// MARK: - Add to List Sheet
struct AddToListSheet: View {
    @Environment(\.dismiss) private var dismiss
    let media: any MediaDisplayable
    @State private var selectedStatus: ListStatus = .planning
    @State private var progress: Int = 0
    @State private var score: Int = 0
    @State private var notes: String = ""
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: KuroSpacing.adaptive(KuroSpacing.xl, for: geometry.size.width)) {
                        // Media Preview
                        MediaPreview(media: media)
                        
                        // Status Selection
                        VStack(alignment: .leading, spacing: KuroSpacing.md) {
                            Text("STATUS")
                                .font(.kuroMicro(weight: .medium))
                                .tracking(1.5)
                                .foregroundColor(.kuroBlack80)
                            
                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible()),
                                    GridItem(.flexible())
                                ],
                                spacing: KuroSpacing.md
                            ) {
                                ForEach(ListStatus.allCases, id: \.self) { status in
                                    StatusCard(
                                        status: status,
                                        isSelected: selectedStatus == status
                                    ) {
                                        selectedStatus = status
                                        KuroAccessibility.impactHaptic(.light)
                                    }
                                }
                            }
                        }
                        
                        // Progress
                        if selectedStatus == .current {
                            VStack(alignment: .leading, spacing: KuroSpacing.md) {
                                Text("PROGRESS")
                                    .font(.kuroMicro(weight: .medium))
                                    .tracking(1.5)
                                    .foregroundColor(.kuroBlack80)
                                
                                HStack {
                                    Stepper(value: $progress, in: 0...(media.episodes ?? media.chapters ?? 100)) {
                                        Text("\(progress) / \(media.episodes ?? media.chapters ?? 0)")
                                            .font(.kuroBody(weight: .light))
                                            .foregroundColor(.kuroBlack80)
                                    }
                                }
                                .padding(KuroSpacing.md)
                                .background(Color.kuroBlack08)
                                .cornerRadius(KuroRadius.sm)
                            }
                        }
                        
                        // Score
                        VStack(alignment: .leading, spacing: KuroSpacing.md) {
                            Text("YOUR SCORE")
                                .font(.kuroMicro(weight: .medium))
                                .tracking(1.5)
                                .foregroundColor(.kuroBlack80)
                            
                            HStack(spacing: KuroSpacing.sm) {
                                ForEach(1...10, id: \.self) { star in
                                    Button(action: {
                                        score = star
                                        KuroAccessibility.impactHaptic(.light)
                                    }) {
                                        Image(systemName: star <= score ? "star.fill" : "star")
                                            .font(.kuroBody())
                                            .foregroundColor(star <= score ? .kuroBlack : .kuroBlack30)
                                    }
                                }
                            }
                        }
                        
                        // Notes
                        VStack(alignment: .leading, spacing: KuroSpacing.md) {
                            Text("NOTES")
                                .font(.kuroMicro(weight: .medium))
                                .tracking(1.5)
                                .foregroundColor(.kuroBlack80)
                            
                            TextEditor(text: $notes)
                                .font(.kuroMicro(weight: .light))
                                .foregroundColor(.kuroBlack80)
                                .frame(height: 100)
                                .padding(KuroSpacing.sm)
                                .background(Color.kuroBlack08)
                                .cornerRadius(KuroRadius.sm)
                        }
                        
                        // Save Button
                        Button(action: saveToList) {
                            Text("ADD TO LIST")
                                .font(.kuroMicro(weight: .medium))
                                .tracking(1.5)
                                .foregroundColor(.kuroWhite)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, KuroSpacing.lg)
                                .background(Color.kuroBlack)
                                .cornerRadius(KuroRadius.sm)
                        }
                    }
                    .padding(ResponsiveLayout.padding())
                }
            }
            .background(Color.kuroBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.kuroMicro(weight: .light))
                    .foregroundColor(.kuroBlack80)
                }
            }
        }
    }
    
    private func saveToList() {
        // TODO: Save to Supabase
        KuroAccessibility.successHaptic()
        dismiss()
    }
}

// MARK: - Media Preview
struct MediaPreview: View {
    let media: any MediaDisplayable
    
    var body: some View {
        HStack(spacing: KuroSpacing.md) {
            AsyncImage(url: URL(string: media.imageURL ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.kuroBlack08)
            }
            .frame(width: 80, height: 120)
            .clipped()
            .cornerRadius(KuroRadius.sm)
            
            VStack(alignment: .leading, spacing: KuroSpacing.xs) {
                Text(media.title.uppercased())
                    .font(.kuroBody(weight: .medium))
                    .tracking(0.5)
                    .foregroundColor(.kuroBlack)
                    .lineLimit(2)
                
                Text(media.year)
                    .font(.kuroMicro(weight: .light))
                    .tracking(0.5)
                    .foregroundColor(.kuroBlack60)
                
                if let episodes = media.episodes {
                    Text("\(episodes) EPISODES")
                        .font(.kuroMicro(weight: .light))
                        .tracking(0.5)
                        .foregroundColor(.kuroBlack60)
                } else if let chapters = media.chapters {
                    Text("\(chapters) CHAPTERS")
                        .font(.kuroMicro(weight: .light))
                        .tracking(0.5)
                        .foregroundColor(.kuroBlack60)
                }
            }
            
            Spacer()
        }
        .padding(KuroSpacing.md)
        .background(Color.kuroBlack08)
        .cornerRadius(KuroRadius.sm)
    }
}

// MARK: - Status Card
struct StatusCard: View {
    let status: ListStatus
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: KuroSpacing.sm) {
                Image(systemName: statusIcon)
                    .font(.kuroCardTitle())
                    .foregroundColor(isSelected ? .kuroBlack : .kuroBlack30)
                
                Text(status.displayName.uppercased())
                    .font(.kuroMicro(weight: isSelected ? .medium : .light))
                    .tracking(0.5)
                    .foregroundColor(isSelected ? .kuroBlack : .kuroBlack60)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, KuroSpacing.lg)
            .background(isSelected ? Color.kuroBlack08 : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: KuroRadius.sm)
                    .stroke(isSelected ? Color.kuroBlack : Color.kuroBlack.opacity(0.15), lineWidth: 1)
            )
            .cornerRadius(KuroRadius.sm)
        }
    }
    
    private var statusIcon: String {
        switch status {
        case .current: return "play.circle.fill"
        case .planning: return "clock.fill"
        case .completed: return "checkmark.circle.fill"
        case .dropped: return "xmark.circle.fill"
        case .paused: return "pause.circle.fill"
        case .repeating: return "arrow.clockwise.circle.fill"
        }
    }
}
