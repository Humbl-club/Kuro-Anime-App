#if DEBUG
//
//  ConciergeHapticScroll.swift
//  Kuro
//
//  Haptic feedback system for recommendation rails with satisfying "click" feedback
//  as cards snap to center during horizontal scrolling.
//

import SwiftUI

// MARK: - Haptic Engine

/// Centralized haptic feedback manager for consistent feedback across the app
@MainActor
final class HapticEngine {
    static let shared = HapticEngine()
    
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let notificationGenerator = UINotificationFeedbackGenerator()
    
    private init() {
        // Prepare generators for immediate responsiveness
        selectionGenerator.prepare()
        impactLight.prepare()
        impactMedium.prepare()
        notificationGenerator.prepare()
    }
    
    /// Call when selection changes - the satisfying "click" for rail scrolling
    func selectionChanged() {
        selectionGenerator.selectionChanged()
        // Keep generator ready for next selection
        selectionGenerator.prepare()
    }
    
    /// Light impact for subtle interactions
    func lightImpact(intensity: CGFloat = 0.3) {
        impactLight.impactOccurred(intensity: intensity)
        impactLight.prepare()
    }
    
    /// Medium impact for more prominent feedback
    func mediumImpact(intensity: CGFloat = 0.5) {
        impactMedium.impactOccurred(intensity: intensity)
        impactMedium.prepare()
    }
    
    /// Notification feedback for success/warning/error
    func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        notificationGenerator.notificationOccurred(type)
        notificationGenerator.prepare()
    }
}

// MARK: - Center Detection Preference Key

/// Preference key for tracking card positions during scroll
struct CardCenterPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - Haptic Scroll Modifier

/// ViewModifier that adds haptic feedback and scale effects to scrollable content
/// Triggers a satisfying "click" haptic when cards snap to center
struct HapticScrollModifier: ViewModifier {
    let itemCount: Int
    let cardWidth: CGFloat
    let centerThreshold: CGFloat
    
    @State private var lastCenteredIndex: Int? = nil
    @State private var screenCenter: CGFloat = UIScreen.main.bounds.width / 2
    @State private var cardPositions: [String: CGFloat] = [:]
    
    private let feedbackGenerator = UISelectionFeedbackGenerator()
    
    init(
        itemCount: Int,
        cardWidth: CGFloat = 280,
        centerThreshold: CGFloat = 70
    ) {
        self.itemCount = itemCount
        self.cardWidth = cardWidth
        self.centerThreshold = centerThreshold
        // Prepare generator on init for immediate first-use responsiveness
        feedbackGenerator.prepare()
    }
    
    func body(content: Content) -> some View {
        content
            .onPreferenceChange(CardCenterPreferenceKey.self) { positions in
                cardPositions = positions
                checkForCenterChange()
            }
            .onAppear {
                // Recalculate screen center on appear (handles orientation changes)
                screenCenter = UIScreen.main.bounds.width / 2
            }
    }
    
    /// Determines which card is closest to center and triggers haptic if changed
    private func checkForCenterChange() {
        guard !cardPositions.isEmpty else { return }
        
        // Find the card whose center is closest to screen center
        var closestItemID: String?
        var smallestDistance: CGFloat = .infinity
        
        for (itemID, midX) in cardPositions {
            let distance = abs(midX - screenCenter)
            if distance < smallestDistance {
                smallestDistance = distance
                closestItemID = itemID
            }
        }
        
        // Only trigger haptic when the centered card actually CHANGES
        // and is within the threshold distance
        if let itemID = closestItemID,
           smallestDistance <= centerThreshold,
           itemID != lastCenteredIndex?.description {
            
            // Trigger the satisfying "click" haptic
            feedbackGenerator.selectionChanged()
            
            // Prepare for next selection (keeps generator responsive)
            feedbackGenerator.prepare()
            
            // Update state
            lastCenteredIndex = Int(itemID)
        }
    }
}

// MARK: - Card Center Tracker

/// View modifier that tracks an individual card's position relative to screen center
struct CardCenterTracker: ViewModifier {
    let itemID: String
    @Binding var centeredItemID: String?
    let centerThreshold: CGFloat
    
    @State private var midX: CGFloat = 0
    @State private var isCentered: Bool = false
    
    private let screenCenter = UIScreen.main.bounds.width / 2
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    Color.clear
                        .preference(
                            key: CardCenterPreferenceKey.self,
                            value: [itemID: geometry.frame(in: .global).midX]
                        )
                        .onAppear {
                            let frame = geometry.frame(in: .global)
                            updateCenterState(midX: frame.midX)
                        }
                        .onChange(of: geometry.frame(in: .global).midX) { _, newMidX in
                            updateCenterState(midX: newMidX)
                        }
                }
            )
    }
    
    private func updateCenterState(midX: CGFloat) {
        let distance = abs(midX - screenCenter)
        let wasCentered = isCentered
        isCentered = distance <= centerThreshold
        
        // Update centered item ID when this card becomes centered
        if isCentered && !wasCentered {
            centeredItemID = itemID
        } else if !isCentered && wasCentered && centeredItemID == itemID {
            centeredItemID = nil
        }
    }
}

// MARK: - Scale Effect Modifier

/// Calculates and applies scale effect based on distance from screen center
struct CenterScaleModifier: ViewModifier {
    let centerScale: CGFloat
    let edgeScale: CGFloat
    let centerThreshold: CGFloat
    
    @State private var scale: CGFloat = 1.0
    
    private let screenCenter = UIScreen.main.bounds.width / 2
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .overlay(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear {
                            updateScale(geometry: geometry)
                        }
                        .onChange(of: geometry.frame(in: .global).midX) { _, _ in
                            updateScale(geometry: geometry)
                        }
                }
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: scale)
    }
    
    private func updateScale(geometry: GeometryProxy) {
        let midX = geometry.frame(in: .global).midX
        let distance = abs(midX - screenCenter)
        
        // Normalize distance to 0...1 range within threshold
        let normalizedDistance = min(distance / (centerThreshold * 2), 1.0)
        
        // Interpolate between center scale and edge scale
        let newScale = centerScale - (normalizedDistance * (centerScale - edgeScale))
        
        // Only update if significantly different to reduce unnecessary state changes
        if abs(newScale - scale) > 0.001 {
            scale = newScale
        }
    }
}

// MARK: - Haptic Recommendation Rail

/// A horizontally scrolling recommendation rail with haptic feedback and scale effects
/// Provides satisfying "click" feedback as cards snap to center
struct HapticRecommendationRail: View {
    let items: [RecommendationItem]
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let spacing: CGFloat
    let centerThreshold: CGFloat
    
    @State private var centeredItemID: String?
    @State private var isDragging: Bool = false
    
    init(
        items: [RecommendationItem],
        cardWidth: CGFloat = 280,
        cardHeight: CGFloat = 420,
        spacing: CGFloat = 16,
        centerThreshold: CGFloat = 70
    ) {
        self.items = items
        self.cardWidth = cardWidth
        self.cardHeight = cardHeight
        self.spacing = spacing
        self.centerThreshold = centerThreshold
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: spacing) {
                // Leading spacer for first card centering
                Spacer(minLength: calculateLeadingInset())
                
                ForEach(items) { item in
                    HapticRecommendationCard(item: item)
                        .frame(width: cardWidth, height: cardHeight)
                        .modifier(CardCenterTracker(
                            itemID: item.id,
                            centeredItemID: $centeredItemID,
                            centerThreshold: centerThreshold
                        ))
                        .modifier(CenterScaleModifier(
                            centerScale: 1.02,
                            edgeScale: 0.95,
                            centerThreshold: centerThreshold
                        ))
                        .id(item.id)
                }
                
                // Trailing spacer for last card centering
                Spacer(minLength: calculateTrailingInset())
            }
        }
        .scrollTargetBehavior(.viewAligned)
        .onChange(of: centeredItemID) { oldValue, newValue in
            // Trigger haptic when centered item changes
            if oldValue != newValue && newValue != nil {
                HapticEngine.shared.selectionChanged()
            }
        }
    }
    
    /// Calculates leading inset so first card can be centered
    private func calculateLeadingInset() -> CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        return (screenWidth - cardWidth) / 2
    }
    
    /// Calculates trailing inset so last card can be centered
    private func calculateTrailingInset() -> CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        return (screenWidth - cardWidth) / 2
    }
}

// MARK: - Recommendation Item Model

/// Data model for recommendation items displayed in the rail
struct RecommendationItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let imageURL: URL?
    let type: ItemType
    let rating: Double?
    
    enum ItemType: String {
        case anime = "Anime"
        case manga = "Manga"
        case movie = "Movie"
        case series = "Series"
    }
}

// MARK: - Recommendation Card View

/// Individual card view for the recommendation rail
struct HapticRecommendationCard: View {
    let item: RecommendationItem
    
    @State private var isPressed: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Poster Image
            posterImage
            
            // Info Section
            infoSection
        }
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(
            color: .black.opacity(isPressed ? 0.15 : 0.1),
            radius: isPressed ? 8 : 12,
            x: 0,
            y: isPressed ? 2 : 4
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isPressed)
        .onTapGesture {
            HapticEngine.shared.lightImpact()
            // Handle tap action
        }
        .pressEvents {
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = true
            }
        } onRelease: {
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = false
            }
        }
    }
    
    private var posterImage: some View {
        ZStack {
            // Placeholder gradient
            LinearGradient(
                colors: [
                    Color.purple.opacity(0.8),
                    Color.blue.opacity(0.8)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Async image (placeholder for actual implementation)
            // AsyncImage(url: item.imageURL) { phase in ... }
            
            // Type badge
            VStack {
                HStack {
                    Spacer()
                    Text(item.type.rawValue)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                }
                .padding(12)
                
                Spacer()
            }
        }
        .frame(height: 320)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 16,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 16
            )
        )
    }
    
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(.primary)
            
            Text(item.subtitle)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(.secondary)
            
            if let rating = item.rating {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                    Text(String(format: "%.1f", rating))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 100)
    }
}

// MARK: - View Extensions

extension View {
    /// Adds haptic feedback tracking to a scroll view for recommendation rails
    /// - Parameters:
    ///   - itemCount: Number of items in the rail
    ///   - cardWidth: Width of each card (default: 280)
    ///   - centerThreshold: Distance from center to trigger "centered" state (default: 70pt)
    func hapticScroll(
        itemCount: Int,
        cardWidth: CGFloat = 280,
        centerThreshold: CGFloat = 70
    ) -> some View {
        modifier(HapticScrollModifier(
            itemCount: itemCount,
            cardWidth: cardWidth,
            centerThreshold: centerThreshold
        ))
    }
    
    /// Adds scale effect based on distance from screen center
    /// - Parameters:
    ///   - centerScale: Scale when centered (default: 1.02)
    ///   - edgeScale: Scale at edges (default: 0.95)
    ///   - threshold: Distance threshold for center detection (default: 70pt)
    func centerScaled(
        centerScale: CGFloat = 1.02,
        edgeScale: CGFloat = 0.95,
        threshold: CGFloat = 70
    ) -> some View {
        modifier(CenterScaleModifier(
            centerScale: centerScale,
            edgeScale: edgeScale,
            centerThreshold: threshold
        ))
    }
    
    /// Tracks card position and updates centered item ID
    /// - Parameters:
    ///   - itemID: Unique identifier for this card
    ///   - centeredItemID: Binding to track which item is centered
    ///   - threshold: Distance threshold for center detection (default: 70pt)
    func trackCenter(
        itemID: String,
        centeredItemID: Binding<String?>,
        threshold: CGFloat = 70
    ) -> some View {
        modifier(CardCenterTracker(
            itemID: itemID,
            centeredItemID: centeredItemID,
            centerThreshold: threshold
        ))
    }
    
    /// Adds press detection handlers
    func pressEvents(
        onPress: @escaping () -> Void,
        onRelease: @escaping () -> Void
    ) -> some View {
        self.simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in onPress() }
                .onEnded { _ in onRelease() }
        )
    }
}

// MARK: - Preview

#Preview("Haptic Recommendation Rail") {
    struct PreviewContainer: View {
        let sampleItems: [RecommendationItem] = [
            RecommendationItem(
                id: "1",
                title: "Attack on Titan",
                subtitle: "Action • Drama • Fantasy",
                imageURL: nil,
                type: .anime,
                rating: 9.1
            ),
            RecommendationItem(
                id: "2",
                title: "Demon Slayer",
                subtitle: "Action • Supernatural",
                imageURL: nil,
                type: .anime,
                rating: 8.7
            ),
            RecommendationItem(
                id: "3",
                title: "Jujutsu Kaisen",
                subtitle: "Action • Supernatural",
                imageURL: nil,
                type: .anime,
                rating: 8.6
            ),
            RecommendationItem(
                id: "4",
                title: "Chainsaw Man",
                subtitle: "Action • Horror • Comedy",
                imageURL: nil,
                type: .anime,
                rating: 8.5
            ),
            RecommendationItem(
                id: "5",
                title: "Spy x Family",
                subtitle: "Action • Comedy • Slice of Life",
                imageURL: nil,
                type: .anime,
                rating: 8.5
            ),
            RecommendationItem(
                id: "6",
                title: "One Piece",
                subtitle: "Action • Adventure • Fantasy",
                imageURL: nil,
                type: .anime,
                rating: 8.9
            ),
            RecommendationItem(
                id: "7",
                title: "My Hero Academia",
                subtitle: "Action • Superhero",
                imageURL: nil,
                type: .anime,
                rating: 7.9
            ),
            RecommendationItem(
                id: "8",
                title: "Death Note",
                subtitle: "Psychological • Thriller",
                imageURL: nil,
                type: .anime,
                rating: 9.0
            )
        ]
        
        var body: some View {
            VStack(spacing: 20) {
                Text("Haptic Recommendation Rail")
                    .font(.title2.weight(.bold))
                    .padding(.top)
                
                Text("Scroll slowly to feel the satisfying \"click\" as each card snaps to center")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Spacer()
                
                HapticRecommendationRail(
                    items: sampleItems,
                    cardWidth: 280,
                    cardHeight: 420,
                    spacing: 16,
                    centerThreshold: 70
                )
                .frame(height: 440)
                
                Spacer()
                
                VStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "hand.tap.fill")
                        Text("Tap cards for light haptic")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left.arrow.right")
                        Text("Scroll for center snap haptic")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
        }
    }
    
    return PreviewContainer()
}

#Preview("Single Card - Scale Effect Demo") {
    struct ScaleDemoPreview: View {
        let item = RecommendationItem(
            id: "demo",
            title: "Sample Title",
            subtitle: "Genre • Info",
            imageURL: nil,
            type: .anime,
            rating: 8.5
        )
        
        var body: some View {
            VStack {
                Text("Center Scale Effect")
                    .font(.headline)
                    .padding()
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        ForEach(0..<5) { index in
                            HapticRecommendationCard(item: item)
                                .frame(width: 200, height: 300)
                                .centerScaled(centerScale: 1.02, edgeScale: 0.95, threshold: 70)
                        }
                    }
                    .padding(.horizontal, 100)
                }
                
                Spacer()
            }
            .background(Color(.systemGroupedBackground))
        }
    }
    
    return ScaleDemoPreview()
}

#endif
