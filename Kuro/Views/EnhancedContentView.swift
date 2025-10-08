import SwiftUI

// MARK: - ENHANCED CONTENT VIEW - iOS 26 Mobile-First
// Using Kuro Design System for optimal mobile experience

struct EnhancedContentView: View {
    @Environment(SupabaseService.self) private var supabaseService
    
    var body: some View {
        EnhancedKuroRootView()
            .environment(supabaseService)
    }
}

// MARK: - Enhanced Root View with iOS 26 Features
struct EnhancedKuroRootView: View {
    @State private var showLaunch = true
    @State private var launchProgress: Double = 0.0
    
    var body: some View {
        ZStack {
            if showLaunch {
                EnhancedKuroLaunchView(progress: $launchProgress)
                    .onAppear {
                        startLaunchSequence()
                    }
            } else {
                EnhancedKuroMainView()
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.95)),
                        removal: .opacity
                    ))
            }
        }
        .preferredColorScheme(.light) // Force light mode for minimalism
    }
    
    private func startLaunchSequence() {
        // iOS 26 enhanced launch sequence
        withAnimation(.easeInOut(duration: 0.8)) {
            launchProgress = 0.3
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 0.6)) {
                launchProgress = 0.7
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeInOut(duration: 0.4)) {
                launchProgress = 1.0
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(KuroAnimation.spring) {
                showLaunch = false
            }
        }
    }
}

// MARK: - Enhanced Launch View - iOS 26 Optimized
struct EnhancedKuroLaunchView: View {
    @Binding var progress: Double
    @State private var logoOpacity: Double = 0
    @State private var subtitleOpacity: Double = 0
    @State private var progressOpacity: Double = 0
    
    var body: some View {
        ZStack {
            // Background with subtle gradient for iOS 26
            LinearGradient(
                colors: [Color.kuroWhite, Color.kuroWhite.opacity(0.98)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: KuroSpacing.adaptive(KuroSpacing.lg, for: KuroScreen.width)) {
                Spacer()
                
                // Logo with enhanced typography
                VStack(spacing: KuroSpacing.sm) {
                    Text("KURO")
                        .font(.system(size: ResponsiveLayout.fontSize(28), weight: .ultraLight, design: .serif))
                        .tracking(8)
                        .foregroundColor(.kuroBlack)
                        .opacity(logoOpacity)
                    
                    Text("CURATED ANIME")
                        .font(.kuroMicro(weight: .light))
                        .tracking(3)
                        .foregroundColor(.kuroBlack30)
                        .opacity(subtitleOpacity)
                }
                
                // Enhanced progress indicator
                VStack(spacing: KuroSpacing.sm) {
                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .kuroBlack))
                        .scaleEffect(x: 1, y: 0.5)
                        .opacity(progressOpacity)
                    
                    Text("LOADING COLLECTION...")
                        .font(.kuroMicro(weight: .light))
                        .tracking(1.0)
                        .foregroundColor(.kuroBlack30)
                        .opacity(progressOpacity)
                }
                .frame(width: 200)
                
                Spacer()
            }
        }
        .onAppear {
            startAnimations()
        }
    }
    
    private func startAnimations() {
        // Staggered animations for smooth appearance
        withAnimation(.easeOut(duration: 1.2)) {
            logoOpacity = 1.0
        }
        
        withAnimation(.easeOut(duration: 1.2).delay(0.3)) {
            subtitleOpacity = 1.0
        }
        
        withAnimation(.easeOut(duration: 0.8).delay(0.6)) {
            progressOpacity = 1.0
        }
    }
}

// MARK: - Enhanced Main View - Mobile-First Design
struct EnhancedKuroMainView: View {
    @State private var currentSection = 0
    @State private var showProfile = false
    @State private var searchText = ""
    @State private var dragOffset: CGFloat = 0
    @State private var hapticFeedback = UIImpactFeedbackGenerator(style: .light)
    
    let sections = ["DISCOVER", "COLLECTION", "SEARCH"]
    
    var body: some View {
        ZStack {
            Color.kuroBackground.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Enhanced Header with iOS 26 features
                EnhancedKuroHeader(
                    currentSection: sections[currentSection],
                    showProfile: $showProfile
                )
                
                // Content with enhanced swipe navigation
                ZStack {
                    GeometryReader { geometry in
                        HStack(spacing: 0) {
                            EnhancedDiscoverView()
                                .frame(width: geometry.size.width)
                            
                            EnhancedCollectionView()
                                .frame(width: geometry.size.width)
                            
                            EnhancedSearchView(searchText: $searchText)
                                .frame(width: geometry.size.width)
                        }
                        .offset(x: -CGFloat(currentSection) * geometry.size.width + dragOffset)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    dragOffset = value.translation.width
                                }
                                .onEnded { value in
                                    let threshold = KuroScreen.width / 3
                                    let velocity = value.velocity.width
                                    
                                    // Enhanced haptic feedback for iOS 26
                                    if abs(velocity) > 500 {
                                        KuroAccessibility.impactHaptic(.medium)
                                    }
                                    
                                    withAnimation(KuroAnimation.spring) {
                                        if value.translation.width > threshold && currentSection > 0 {
                                            currentSection -= 1
                                            KuroAccessibility.impactHaptic(.light)
                                        } else if value.translation.width < -threshold && currentSection < sections.count - 1 {
                                            currentSection += 1
                                            KuroAccessibility.impactHaptic(.light)
                                        }
                                        dragOffset = 0
                                    }
                                }
                        )
                    }
                }
                
                // Enhanced dot indicators with iOS 26 animations
                HStack(spacing: KuroSpacing.sm) {
                    ForEach(0..<sections.count, id: \.self) { index in
                        Circle()
                            .fill(Color.kuroBlack.opacity(index == currentSection ? 1.0 : 0.2))
                            .frame(width: 6, height: 6)
                            .scaleEffect(index == currentSection ? 1.2 : 1.0)
                            .animation(KuroAnimation.spring, value: currentSection)
                            .onTapGesture {
                                withAnimation(KuroAnimation.spring) {
                                    currentSection = index
                                }
                                KuroAccessibility.impactHaptic(.light)
                            }
                    }
                }
                .padding(.vertical, KuroSpacing.adaptive(KuroSpacing.md, for: KuroScreen.width))
                .padding(.bottom, KuroSpacing.adaptive(KuroSpacing.lg, for: KuroScreen.width))
            }
        }
    }
}

// MARK: - Enhanced Header - iOS 26 Optimized
struct EnhancedKuroHeader: View {
    let currentSection: String
    @Binding var showProfile: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Safe area handling for all iOS devices
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // Top safe area
                    Spacer()
                        .frame(height: geometry.safeAreaInsets.top)
                    
                    // Three-part layout with enhanced spacing
                    HStack {
                        // Left: Brand
                        Text("KURO")
                            .font(.kuroNavigation())
                            .tracking(1.5)
                            .foregroundColor(.kuroBlack30)
                        
                        Spacer()
                        
                        // Center: Section with enhanced typography
                        Text(currentSection)
                            .font(.kuroNavigation(weight: .medium))
                            .tracking(1.5)
                            .foregroundColor(.kuroBlack)
                        
                        Spacer()
                        
                        // Right: Profile with iOS 26 enhanced interaction
                        Button(action: {
                            KuroAccessibility.impactHaptic(.light)
                            showProfile.toggle()
                        }) {
                            Circle()
                                .fill(Color.kuroBlack08)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Text("M")
                                        .font(.kuroBody(weight: .light))
                                        .foregroundColor(.kuroBlack)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .scaleEffect(showProfile ? 0.95 : 1.0)
                        .animation(KuroAnimation.spring, value: showProfile)
                    }
                    .padding(.horizontal, ResponsiveLayout.padding())
                    .padding(.vertical, KuroSpacing.adaptive(KuroSpacing.lg, for: KuroScreen.width))
                    
                    // Enhanced divider
                    Rectangle()
                        .fill(Color.kuroBlack08)
                        .frame(height: 0.5)
                }
            }
            .frame(height: KuroScreen.safeAreaTop + 60)
        }
    }
}

// MARK: - Enhanced Discover View - Mobile-First
struct EnhancedDiscoverView: View {
    @Environment(SupabaseService.self) private var supabaseService
    @State private var currentIndex = 0
    @State private var dragOffset: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: KuroSpacing.adaptive(KuroSpacing.xxl, for: geometry.size.width)) {
                    if supabaseService.isLoading {
                        VStack(spacing: KuroSpacing.adaptive(KuroSpacing.xl, for: geometry.size.width)) {
                            ForEach(0..<3, id: \.self) { _ in
                                EnhancedFeaturedCardLoading()
                            }
                        }
                    } else if supabaseService.animeItems.isEmpty {
                        EmptyStateView()
                    } else {
                        // Enhanced featured content with swipe navigation
                        TabView(selection: $currentIndex) {
                            ForEach(Array(supabaseService.animeItems.prefix(10).enumerated()), id: \.element.id) { index, anime in
                                EnhancedFeaturedCard(
                                    media: anime,
                                    screenWidth: geometry.size.width
                                )
                                .tag(index)
                            }
                        }
                        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                        .frame(height: ResponsiveLayout.imageHeight(400) + 200)
                        .onChange(of: currentIndex) { _ in
                            KuroAccessibility.impactHaptic(.light)
                        }
                    }
                }
                .padding(.top, KuroSpacing.adaptive(KuroSpacing.lg, for: geometry.size.width))
            }
        }
        .onAppear {
            Task {
                await supabaseService.fetchAnime(limit: 20)
            }
        }
    }
}

// MARK: - Enhanced Featured Card - iOS 26 Optimized
struct EnhancedFeaturedCard: View {
    let media: any MediaDisplayable
    let screenWidth: CGFloat
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Media type badge with iOS 26 styling
            HStack {
                Spacer()
                KuroStyle.mediaBadge(
                    media.episodes != nil ? "ANIME" : "MANGA",
                    isAnime: media.episodes != nil
                )
            }
            .padding(.horizontal, ResponsiveLayout.padding())
            .padding(.top, KuroSpacing.sm)
            
            // Enhanced image with iOS 26 optimizations
            AsyncImage(url: URL(string: media.imageURL ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.kuroBlack08)
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.8)
                            .foregroundColor(.kuroBlack30)
                    )
            }
            .frame(maxWidth: .infinity)
            .frame(height: ResponsiveLayout.imageHeight(300))
            .clipped()
            .cornerRadius(KuroRadius.adaptive(KuroRadius.md, for: screenWidth))
            
            // Enhanced content information
            VStack(alignment: .leading, spacing: KuroSpacing.adaptive(KuroSpacing.md, for: screenWidth)) {
                // Title with enhanced typography
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: KuroSpacing.xs) {
                        Text(media.title.uppercased())
                            .font(.system(size: ResponsiveLayout.fontSize(20), weight: .ultraLight, design: .serif))
                            .tracking(0.5)
                            .foregroundColor(.kuroBlack)
                            .lineLimit(2)
                        
                        Text(media.year)
                            .font(.kuroMicro(weight: .regular))
                            .tracking(1.5)
                            .foregroundColor(.kuroBlack60)
                    }
                    
                    Spacer()
                    
                    // Episode/Chapter info with iOS 26 styling
                    VStack(alignment: .trailing, spacing: KuroSpacing.xs) {
                        if let episodes = media.episodes {
                            Text("\(episodes) EPS")
                                .font(.kuroMicro(weight: .light))
                                .tracking(0.5)
                                .foregroundColor(.kuroBlack60)
                        } else if let chapters = media.chapters {
                            Text("\(chapters) CH")
                                .font(.kuroMicro(weight: .light))
                                .tracking(0.5)
                                .foregroundColor(.kuroBlack60)
                        }
                    }
                }
                
                // Enhanced description
                Text(media.displayDescription)
                    .font(.kuroMicro(weight: .light))
                    .tracking(1.0)
                    .foregroundColor(.kuroBlack60)
                    .lineSpacing(4)
                    .lineLimit(3)
            }
            .padding(.horizontal, ResponsiveLayout.padding())
            .padding(.vertical, KuroSpacing.adaptive(KuroSpacing.lg, for: screenWidth))
        }
        .background(KuroStyle.card())
        .padding(.horizontal, ResponsiveLayout.padding())
    }
}

// MARK: - Enhanced Loading Card
struct EnhancedFeaturedCardLoading: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color.kuroBlack08)
                .frame(maxWidth: .infinity)
                .frame(height: ResponsiveLayout.imageHeight(300))
                .overlay(
                    ProgressView()
                        .scaleEffect(0.8)
                        .foregroundColor(.kuroBlack30)
                )
            
            VStack(alignment: .leading, spacing: KuroSpacing.md) {
                Rectangle()
                    .fill(Color.kuroBlack08)
                    .frame(height: 20)
                    .frame(maxWidth: .infinity)
                
                Rectangle()
                    .fill(Color.kuroBlack08)
                    .frame(height: 12)
                    .frame(width: 60)
                
                Rectangle()
                    .fill(Color.kuroBlack08)
                    .frame(height: 12)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, KuroSpacing.lg)
        }
        .background(KuroStyle.card())
        .padding(.horizontal, ResponsiveLayout.padding())
    }
}

// MARK: - Empty State View
struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: KuroSpacing.lg) {
            Text("NO CONTENT AVAILABLE")
                .font(.kuroMicro(weight: .light))
                .tracking(1.0)
                .foregroundColor(.kuroBlack30)
            
            Text("Add some anime and manga to your database")
                .font(.kuroMicro(weight: .light))
                .tracking(0.5)
                .foregroundColor(.kuroBlack30)
        }
        .padding(.top, 80)
    }
}

// MARK: - Placeholder Views for Collection and Search
struct EnhancedCollectionView: View {
    var body: some View {
        VStack {
            Text("COLLECTION")
                .font(.kuroDisplay())
                .foregroundColor(.kuroBlack30)
        }
    }
}

struct EnhancedSearchView: View {
    @Binding var searchText: String
    
    var body: some View {
        VStack {
            Text("SEARCH")
                .font(.kuroDisplay())
                .foregroundColor(.kuroBlack30)
        }
    }
}

