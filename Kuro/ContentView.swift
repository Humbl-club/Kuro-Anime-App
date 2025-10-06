import SwiftUI

// MARK: - KURO APP - Single Source of Truth
// "Elevated Minimalism" / "Editorial Minimalism" Design System

// MARK: - Content View
struct ContentView: View {
    @EnvironmentObject var supabaseService: SupabaseService
    
    var body: some View {
        KuroRootView()
            .environmentObject(supabaseService)
    }
}

// MARK: - Root View with Launch
struct KuroRootView: View {
    @State private var showLaunch = true
    
    var body: some View {
        if showLaunch {
            KuroLaunchView()
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            showLaunch = false
                        }
                    }
                }
        } else {
            KuroMainView()
        }
    }
}

// MARK: - Launch View
struct KuroLaunchView: View {
    @State private var logoOpacity: Double = 0
    @State private var subtitleOpacity: Double = 0
    
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            
            VStack(spacing: 8) {
                Text("KURO")
                    .font(.system(size: 24, weight: .ultraLight, design: .serif))
                    .tracking(8)
                    .foregroundColor(.black)
                    .opacity(logoOpacity)
                
                Text("CURATED ANIME")
                    .font(.system(size: 10, weight: .light))
                    .tracking(3)
                    .foregroundColor(.black.opacity(0.5))
                    .opacity(subtitleOpacity)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 1.2)) {
                    logoOpacity = 1.0
                }
                withAnimation(.easeOut(duration: 1.2).delay(0.3)) {
                    subtitleOpacity = 1.0
                }
            }
        }
    }
}

// MARK: - Main View
struct KuroMainView: View {
    // @EnvironmentObject var firebaseService: FirebaseService
    @State private var currentSection = 0
    @State private var showProfile = false
    @State private var searchText = ""
    @State private var selectedMood: String? = "Contemplative"
    @State private var dragOffset: CGFloat = 0
    
    let sections = ["DISCOVER", "COLLECTION", "SEARCH"]
    
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Fixed Header - Three-part layout
                KuroHeader(
                    currentSection: sections[currentSection],
                    showProfile: $showProfile
                )
                
                // Content with swipe navigation
                ZStack {
                    GeometryReader { geometry in
                        HStack(spacing: 0) {
                            DiscoverViewSimple(selectedMood: $selectedMood)
                                .frame(width: geometry.size.width)
                            
                            CollectionViewSimple()
                                .frame(width: geometry.size.width)
                            
                            SearchViewSimple(searchText: $searchText)
                                .frame(width: geometry.size.width)
                        }
                        .offset(x: -CGFloat(currentSection) * geometry.size.width + dragOffset)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    dragOffset = value.translation.width
                                }
                                .onEnded { value in
                                    let threshold = UIScreen.main.bounds.width / 3
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        if value.translation.width > threshold && currentSection > 0 {
                                            currentSection -= 1
                                        } else if value.translation.width < -threshold && currentSection < sections.count - 1 {
                                            currentSection += 1
                                        }
                                        dragOffset = 0
                                    }
                                }
                        )
                    }
                }
                
                // Dot indicators - Minimal (5-6px circles)
                HStack(spacing: 8) {
                    ForEach(0..<sections.count, id: \.self) { index in
                        Circle()
                            .fill(Color.black.opacity(index == currentSection ? 1.0 : 0.2))
                            .frame(width: 6, height: 6)
                            .scaleEffect(index == currentSection ? 1.2 : 1.0)
                            .animation(.spring(response: 0.3), value: currentSection)
                    }
                }
                .padding(.vertical, 20)
                .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Fixed Header Component
struct KuroHeader: View {
    let currentSection: String
    @Binding var showProfile: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: UIApplication.shared.windows.first?.safeAreaInsets.top ?? 0)
            
            // Three-part layout: Brand / Section / Action
            HStack {
                // Left: Brand (30% opacity)
                Text("KURO")
                    .font(.system(size: 11, weight: .regular))
                    .tracking(1.5)
                    .foregroundColor(.black.opacity(0.3))
                
                Spacer()
                
                // Center: Section (full opacity)
                Text(currentSection)
                    .font(.system(size: 11, weight: .regular))
                    .tracking(1.5)
                    .foregroundColor(.black)
                
                Spacer()
                
                // Right: Action (minimal interaction)
                Button(action: { showProfile.toggle() }) {
                    Circle()
                        .fill(Color.black.opacity(0.08))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Text("M")
                                .font(.system(size: 14, weight: .light))
                                .foregroundColor(.black)
                        )
                }
            }
            .padding(.horizontal, 24) // 24px standard margin
            .padding(.vertical, 20)
            
            // Subtle divider
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(height: 0.5)
        }
    }
}

// MARK: - Discover View with Firebase Data
struct DiscoverViewSimple: View {
    @EnvironmentObject var firebaseService: FirebaseService
    @Binding var selectedMood: String?
    let moods = ["Contemplative", "Energetic", "Melancholic", "Uplifting", "Mysterious"]
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                // Mood selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 32) {
                        ForEach(moods, id: \.self) { mood in
                            MoodPillSimple(mood: mood, isSelected: selectedMood == mood) {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    selectedMood = mood
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.vertical, 24)
                
                // Featured content from Firebase
                if firebaseService.isLoading {
                    VStack(spacing: 24) {
                        ForEach(0..<3, id: \.self) { _ in
                            FeaturedCardLoading()
                        }
                    }
                } else if firebaseService.mediaItems.isEmpty {
                    VStack(spacing: 16) {
                        Text("LOADING YOUR 20K+ COLLECTION...")
                            .font(.system(size: 14, weight: .light))
                            .tracking(1.0)
                            .foregroundColor(.black.opacity(0.6))
                        
                        Text("Connecting to Firebase...")
                            .font(.system(size: 12, weight: .light))
                            .tracking(0.5)
                            .foregroundColor(.black.opacity(0.3))
                        
                        ProgressView()
                            .scaleEffect(0.8)
                            .padding(.top, 20)
                    }
                    .padding(.top, 80)
                } else {
                    VStack(spacing: 48) {
                        ForEach(Array(firebaseService.mediaItems.prefix(10)), id: \.id) { media in
                            FeaturedCardReal(media: media)
                        }
                    }
                }
            }
        }
        .onAppear {
            Task {
                await firebaseService.loadMediaItems()
            }
        }
        .refreshable {
            await firebaseService.loadMediaItems()
        }
    }
}

struct CollectionViewSimple: View {
    @EnvironmentObject var firebaseService: FirebaseService
    @State private var filter = "ALL"
    let filters = ["ALL", "WATCHING", "COMPLETED", "PLANNED"]
    
    var body: some View {
        VStack(spacing: 0) {
            // Filter tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 32) {
                    ForEach(filters, id: \.self) { filterOption in
                        FilterTabSimple(
                            title: filterOption,
                            isSelected: filter == filterOption,
                            action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    filter = filterOption
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.vertical, 20)
            
            // Collection grid with real Firebase data
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 16
                ) {
                    if firebaseService.isLoading {
                        ForEach(0..<9, id: \.self) { _ in
                            CollectionCardLoading()
                        }
                    } else {
                        ForEach(firebaseService.mediaItems.prefix(50), id: \.id) { media in
                            CollectionCardReal(media: media)
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 32)
        }
        .onAppear {
            if firebaseService.mediaItems.isEmpty {
                Task {
                    await firebaseService.loadMediaItems()
                }
            }
        }
    }
}

struct SearchViewSimple: View {
    @EnvironmentObject var firebaseService: FirebaseService
    @Binding var searchText: String
    @State private var selectedCategories: Set<String> = []
    
    // Filter results based on search and categories
    private var filteredResults: [Media] {
        var results = firebaseService.mediaItems
        
        // Apply text search
        if !searchText.isEmpty {
            results = results.filter { media in
                media.title.localizedCaseInsensitiveContains(searchText) ||
                media.description.localizedCaseInsensitiveContains(searchText) ||
                media.genres.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }
        
        // Apply category filters
        if !selectedCategories.isEmpty {
            results = results.filter { media in
                selectedCategories.contains { category in
                    switch category {
                    case "TRENDING":
                        return media.rating ?? 0 > 8.0
                    case "NEW SEASON":
                        return media.year >= 2020
                    case "CLASSICS":
                        return media.year < 2010
                    case "HIDDEN GEMS":
                        return (media.rating ?? 0) > 8.5 && media.year < 2015
                    default:
                        return false
                    }
                }
            }
        }
        
        return results
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.black.opacity(0.3))
                    .font(.system(size: 16, weight: .light))
                
                TextField("SEARCH ANIME", text: $searchText)
                    .font(.system(size: 14, weight: .light))
                    .tracking(0.5)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.black.opacity(0.05))
            .cornerRadius(0)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            
            // Category pills with selection
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(["TRENDING", "NEW SEASON", "CLASSICS", "HIDDEN GEMS"], id: \.self) { category in
                        CategoryPillSelectable(
                            title: category,
                            isSelected: selectedCategories.contains(category)
                        ) {
                            if selectedCategories.contains(category) {
                                selectedCategories.remove(category)
                            } else {
                                selectedCategories.insert(category)
                            }
                            // Trigger search with new filters
                            performSearch()
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.vertical, 20)
            
            // Search Results with real data
            if !searchText.isEmpty || !selectedCategories.isEmpty {
                if firebaseService.isLoading {
                    ProgressView("Searching...")
                        .padding(.top, 40)
                } else if filteredResults.isEmpty {
                    VStack(spacing: 8) {
                        Text("NO RESULTS FOUND")
                            .font(.system(size: 11, weight: .regular))
                            .tracking(1.5)
                            .foregroundColor(.black.opacity(0.3))
                        
                        Text("Try adjusting your search or filters")
                            .font(.system(size: 10, weight: .light))
                            .tracking(1.0)
                            .foregroundColor(.black.opacity(0.2))
                    }
                    .padding(.top, 60)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredResults) { media in
                                SearchResultRowReal(media: media)
                                Rectangle()
                                    .fill(Color.black.opacity(0.08))
                                    .frame(height: 0.5)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
            } else {
                Spacer()
                
                VStack(spacing: 8) {
                    Text("BEGIN TYPING TO SEARCH")
                        .font(.system(size: 11, weight: .regular))
                        .tracking(1.5)
                        .foregroundColor(.black.opacity(0.3))
                    
                    Text("DISCOVER YOUR NEXT OBSESSION")
                        .font(.system(size: 10, weight: .light))
                        .tracking(1.0)
                        .foregroundColor(.black.opacity(0.2))
                }
                .padding(.top, 80)
                
                Spacer()
            }
        }
        .onChange(of: searchText) { _ in
            performSearch()
        }
        .onAppear {
            // Load data if not already loaded
            Task {
                if firebaseService.mediaItems.isEmpty {
                    await firebaseService.loadInitialData()
                }
            }
        }
    }
    
    private func performSearch() {
        // Perform search with current text and filters
        Task {
            await firebaseService.searchMedia(
                query: searchText,
                filters: SearchFilters(
                    genres: Array(selectedCategories)
                )
            )
        }
    }
}

// MARK: - Enhanced Components

struct CategoryPillSelectable: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .regular))
                .tracking(1.0)
                .foregroundColor(.black.opacity(isSelected ? 1.0 : 0.6))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .stroke(Color.black.opacity(isSelected ? 0.8 : 0.15), lineWidth: 0.5)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(isSelected ? 0.05 : 0.0))
                        )
                )
        }
    }
}

struct SearchResultRowReal: View {
    let media: Media
    
    var body: some View {
        HStack(spacing: 16) {
            AsyncImage(url: URL(string: media.imageURL ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.black.opacity(0.05))
                    .overlay(
                        Text("IMG")
                            .font(.system(size: 8, weight: .light))
                            .foregroundColor(.black.opacity(0.3))
                    )
            }
            .frame(width: 50, height: 70)
            .clipped()
            .cornerRadius(4)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(media.title.uppercased())
                    .font(.system(size: 12, weight: .regular))
                    .tracking(0.5)
                    .foregroundColor(.black.opacity(0.8))
                    .lineLimit(1)
                
                Text("\(media.year) · \(media.genres.first ?? "Unknown")")
                    .font(.system(size: 10, weight: .light))
                    .tracking(0.5)
                    .foregroundColor(.black.opacity(0.5))
                
                if let episodes = media.episodes {
                    Text("\(episodes) EPS")
                        .font(.system(size: 9, weight: .light))
                        .tracking(0.5)
                        .foregroundColor(.black.opacity(0.3))
                }
            }
            
            Spacer()
            
            // Rating if available
            if let rating = media.rating {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.1f", rating))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.black.opacity(0.8))
                    
                    Text("★")
                        .font(.system(size: 8))
                        .foregroundColor(.black.opacity(0.3))
                }
            }
            
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .light))
                .foregroundColor(.black.opacity(0.2))
        }
        .padding(.vertical, 12)
    }
}

struct CollectionCardLoading: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .aspectRatio(0.7, contentMode: .fill)
                .overlay(
                    ProgressView()
                        .scaleEffect(0.6)
                        .foregroundColor(.black.opacity(0.3))
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Rectangle()
                    .fill(Color.black.opacity(0.1))
                    .frame(height: 10)
                    .frame(maxWidth: .infinity)
                
                Rectangle()
                    .fill(Color.black.opacity(0.05))
                    .frame(height: 9)
                    .frame(width: 40)
            }
            .padding(.top, 8)
        }
    }
}

struct CollectionCardReal: View {
    let media: Media
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
            .aspectRatio(0.7, contentMode: .fill)
            .clipped()
            .cornerRadius(4)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(media.title.uppercased())
                    .font(.system(size: 10, weight: .regular))
                    .tracking(0.5)
                    .foregroundColor(.black.opacity(0.8))
                    .lineLimit(2)
                
                let episodeText = media.episodes != nil ? "\(media.episodes!) EPS" : "Movie"
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
}

// MARK: - Simple Components
struct MoodPillSimple: View {
    let mood: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(mood.uppercased())
                    .font(.system(size: 11, weight: .regular))
                    .tracking(1.5)
                    .foregroundColor(.black.opacity(isSelected ? 1.0 : 0.3))
                
                Rectangle()
                    .fill(Color.black)
                    .frame(height: 0.5)
                    .scaleEffect(x: isSelected ? 1.0 : 0.0, anchor: .center)
                    .opacity(isSelected ? 1.0 : 0.0)
                    .animation(.easeOut(duration: 0.3), value: isSelected)
            }
        }
    }
}

struct FeaturedCardSimple: View {
    let title: String
    let year: String
    let description: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Placeholder image
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .frame(maxWidth: .infinity)
                .frame(height: 420)
                .overlay(
                    Text("IMAGE")
                        .font(.system(size: 24, weight: .ultraLight))
                        .foregroundColor(.black.opacity(0.3))
                )
            
            VStack(alignment: .leading, spacing: 12) {
                Text(title.uppercased())
                    .font(.system(size: 20, weight: .ultraLight, design: .serif))
                    .tracking(0.5)
                    .foregroundColor(.black)
                
                Text(year)
                    .font(.system(size: 11, weight: .regular))
                    .tracking(1.5)
                    .foregroundColor(.black.opacity(0.5))
                
                Text(description)
                    .font(.system(size: 11, weight: .light))
                    .tracking(1.0)
                    .foregroundColor(.black.opacity(0.6))
                    .lineSpacing(4)
            }
            .padding(.vertical, 24)
        }
    }
}

struct CollectionCardSimple: View {
    let title: String
    let year: String
    let episodeText: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .aspectRatio(0.7, contentMode: .fill)
                .overlay(
                    Text("IMG")
                        .font(.system(size: 12, weight: .light))
                        .foregroundColor(.black.opacity(0.3))
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .regular))
                    .tracking(0.5)
                    .foregroundColor(.black.opacity(0.8))
                    .lineLimit(2)
                
                Text("\(year) · \(episodeText)")
                    .font(.system(size: 9, weight: .light))
                    .tracking(0.5)
                    .foregroundColor(.black.opacity(0.5))
            }
            .padding(.top, 8)
        }
    }
}

struct FilterTabSimple: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 11, weight: .regular))
                    .tracking(1.5)
                    .foregroundColor(.black.opacity(isSelected ? 1.0 : 0.3))
                
                Rectangle()
                    .fill(Color.black)
                    .frame(height: 0.5)
                    .scaleEffect(x: isSelected ? 1.0 : 0.0, anchor: .center)
                    .opacity(isSelected ? 1.0 : 0.0)
            }
        }
    }
}

struct CategoryPillSimple: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .regular))
            .tracking(1.0)
            .foregroundColor(.black.opacity(0.6))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .stroke(Color.black.opacity(0.15), lineWidth: 0.5)
            )
    }
}

struct SearchResultRowSimple: View {
    let title: String
    let year: String
    let genre: String
    
    var body: some View {
        HStack(spacing: 16) {
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .frame(width: 50, height: 70)
                .overlay(
                    Text("IMG")
                        .font(.system(size: 8, weight: .light))
                        .foregroundColor(.black.opacity(0.3))
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .regular))
                    .tracking(0.5)
                    .foregroundColor(.black.opacity(0.8))
                    .lineLimit(1)
                
                Text("\(year) · \(genre)")
                    .font(.system(size: 10, weight: .light))
                    .tracking(0.5)
                    .foregroundColor(.black.opacity(0.5))
                
                Text("12 EPS")
                    .font(.system(size: 9, weight: .light))
                    .tracking(0.5)
                    .foregroundColor(.black.opacity(0.3))
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .light))
                .foregroundColor(.black.opacity(0.2))
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Real Firebase Data Components
struct FeaturedCardReal: View {
    let media: Media
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Real image or placeholder
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
            
            VStack(alignment: .leading, spacing: 12) {
                Text(media.title.uppercased())
                    .font(.system(size: 20, weight: .ultraLight, design: .serif))
                    .tracking(0.5)
                    .foregroundColor(.black)
                
                Text("\(media.year)")
                    .font(.system(size: 11, weight: .regular))
                    .tracking(1.5)
                    .foregroundColor(.black.opacity(0.5))
                
                Text(media.description)
                    .font(.system(size: 11, weight: .light))
                    .tracking(1.0)
                    .foregroundColor(.black.opacity(0.6))
                    .lineSpacing(4)
                    .lineLimit(3)
            }
            .padding(.vertical, 24)
        }
    }
}

struct FeaturedCardLoading: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .frame(maxWidth: .infinity)
                .frame(height: 420)
                .overlay(
                    ProgressView()
                        .scaleEffect(0.8)
                        .foregroundColor(.black.opacity(0.3))
                )
            
            VStack(alignment: .leading, spacing: 12) {
                Rectangle()
                    .fill(Color.black.opacity(0.1))
                    .frame(height: 20)
                    .frame(maxWidth: .infinity)
                
                Rectangle()
                    .fill(Color.black.opacity(0.05))
                    .frame(height: 12)
                    .frame(width: 60)
                
                Rectangle()
                    .fill(Color.black.opacity(0.05))
                    .frame(height: 12)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 24)
        }
    }
}
