#if DEBUG
// MARK: - CONCIERGE IMPORT CONFIRMATION CARDS
// Production-ready import confirmation UI with rich media cards,
// match confidence indicators, and candidate selection.
// iOS 26+ optimized with smooth 60fps animations.

import SwiftUI

// Prototype UI uses the real Concierge models without leaking names into the rest of the module.
typealias ProtoConciergeCandidate = SupabaseService.ConciergeCandidate
typealias ProtoConciergeParseItemParsed = SupabaseService.ConciergeParseItemParsed
typealias ProtoConciergeExistingEntry = SupabaseService.ConciergeExistingEntry
typealias ProtoConciergeParseItem = SupabaseService.ConciergeParseItem

// MARK: - Import Section Type

enum ImportSection: String, CaseIterable {
    case willAdd = "WILL ADD"
    case willUpdate = "WILL UPDATE"
    case willSkip = "WILL SKIP"
    
    var opacity: Double {
        switch self {
        case .willAdd, .willUpdate: return 1.0
        case .willSkip: return 0.4
        }
    }
    
    var caption: String? {
        switch self {
        case .willSkip: return "Already up to date"
        default: return nil
        }
    }
}

// MARK: - Match Ring Component

struct MatchRing: View {
    let percentage: Double
    let isSelected: Bool
    let isAutoSelected: Bool
    
    @State private var animatedProgress: Double = 0
    @State private var showCheckmark: Bool = false
    @State private var sparkleTrigger: Bool = false
    
    private var ringColor: Color {
        let pct = percentage * 100
        switch pct {
        case 98...100: return .green
        case 75..<98: return .orange
        default: return .yellow
        }
    }
    
    private var lineWidth: CGFloat { isSelected ? 3 : 2 }
    
    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(ringColor.opacity(0.15), lineWidth: lineWidth)
            
            // Progress ring
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: ringColor.opacity(0.3), radius: isSelected ? 4 : 0)
            
            // Checkmark or percentage
            if showCheckmark {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(ringColor)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Text("\(Int(percentage * 100))")
                    .font(.kuroMicro(weight: .bold))
                    .foregroundColor(ringColor)
            }
            
            // Sparkle effect for auto-selection
            if isAutoSelected && sparkleTrigger {
                MatchRingSparkleEffect()
                    .offset(x: 14, y: -14)
            }
            
            // "Auto" badge
            if isAutoSelected {
                AutoBadge()
                    .offset(x: 10, y: 12)
            }
        }
        .frame(width: 28, height: 28)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                animatedProgress = percentage
            }
            withAnimation(.easeInOut(duration: 0.3).delay(0.5)) {
                showCheckmark = isSelected
            }
        }
        .onChange(of: isSelected) { _, newValue in
            withAnimation(.easeInOut(duration: 0.2)) {
                showCheckmark = newValue
            }
        }
        .onChange(of: isAutoSelected) { _, newValue in
            if newValue {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    sparkleTrigger = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation {
                        sparkleTrigger = false
                    }
                }
            }
        }
    }
}

// MARK: - Auto Badge

private struct AutoBadge: View {
    var body: some View {
        Text("AUTO")
            .font(.system(size: 6, weight: .heavy))
            .tracking(0.5)
            .foregroundColor(.white)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(
                Capsule()
                    .fill(Color.blue)
            )
            .overlay(
                Capsule()
                    .stroke(Color.white, lineWidth: 0.5)
            )
    }
}

// MARK: - Sparkle Effect

private struct MatchRingSparkleEffect: View {
    @State private var scale: CGFloat = 0
    @State private var rotation: Double = 0
    @State private var opacity: Double = 0
    
    var body: some View {
        ZStack {
            Image(systemName: "sparkle")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.yellow)
            
            Image(systemName: "sparkle")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.orange)
                .offset(x: -6, y: 4)
            
            Image(systemName: "sparkle")
                .font(.system(size: 6, weight: .bold))
                .foregroundColor(.yellow.opacity(0.8))
                .offset(x: 4, y: 6)
        }
        .scaleEffect(scale)
        .rotationEffect(.degrees(rotation))
        .opacity(opacity)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                scale = 1.2
                rotation = 15
                opacity = 1
            }
            withAnimation(.easeOut(duration: 0.8).delay(0.2)) {
                scale = 0.8
                opacity = 0
                rotation = 45
            }
        }
    }
}

// MARK: - Import Poster View

struct ImportPosterView: View {
    let url: URL?
    let scrollOffset: CGFloat
    
    @State private var imageLoaded: Bool = false
    
    private var parallaxOffset: CGFloat {
        // Subtle parallax based on scroll position
        scrollOffset * 0.15
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Placeholder
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.kuroSecondaryBackground)
                
                // Async image with crossfade
                KuroCachedAsyncImage(
                    url: url,
                    transaction: Transaction(animation: .easeInOut(duration: 0.2))
                ) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .offset(y: parallaxOffset)
                            .onAppear {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    imageLoaded = true
                                }
                            }
                    default:
                        Color.clear
                    }
                }
                .opacity(imageLoaded ? 1 : 0)
            }
            .clipped()
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
            )
        }
        .frame(width: 70, height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Import Confirm Card

struct ImportConfirmCard: View {
    let item: ProtoConciergeParseItem
    let selectedCandidate: ProtoConciergeCandidate?
    let isAutoSelected: Bool
    let section: ImportSection
    let scrollOffset: CGFloat
    let onSelect: (ProtoConciergeCandidate) -> Void
    let onToggleExclude: (() -> Void)?
    
    @State private var isExpanded: Bool = false
    @State private var showReasoningTooltip: Bool = false
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false
    
    private var posterURL: URL? {
        guard let path = selectedCandidate?.cover_image_medium else { return nil }
        return URL(string: path)
    }
    
    private var matchPercentage: Double {
        selectedCandidate?.score ?? 0
    }
    
    private var isExcluded: Bool {
        selectedCandidate == nil
    }
    
    var body: some View {
        cardContent
            .opacity(section.opacity)
            .offset(x: dragOffset.width)
            .rotationEffect(.degrees(Double(dragOffset.width) * 0.03))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        guard onToggleExclude != nil else { return }
                        isDragging = true
                        withAnimation(.interactiveSpring()) {
                            dragOffset = value.translation
                        }
                    }
                    .onEnded { value in
                        isDragging = false
                        let threshold: CGFloat = 80
                        
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            if value.translation.width < -threshold {
                                // Swipe left - exclude
                                dragOffset = .zero
                                triggerHaptic(.light)
                                onToggleExclude?()
                            } else if value.translation.width > threshold {
                                // Swipe right - pin to top (future feature)
                                dragOffset = .zero
                                triggerHaptic(.light)
                            } else {
                                dragOffset = .zero
                            }
                        }
                    }
            )
            .background(
                ZStack {
                    // Exclude background (red)
                    if dragOffset.width < -30 {
                        RoundedRectangle(cornerRadius: KuroRadius.md)
                            .fill(Color.red.opacity(min(0.3, abs(dragOffset.width) / 200.0)))
                    }
                    // Pin background (blue)
                    if dragOffset.width > 30 {
                        RoundedRectangle(cornerRadius: KuroRadius.md)
                            .fill(Color.blue.opacity(min(0.3, dragOffset.width / 200.0)))
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: KuroRadius.md))
    }
    
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            HStack(alignment: .top, spacing: 12) {
                // Poster
                ImportPosterView(url: posterURL, scrollOffset: scrollOffset)
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 8) {
                        // Title
                        Text(cardTitle)
                            .font(.kuroTitle(weight: .medium))
                            .foregroundColor(.black.opacity(0.9))
                            .lineLimit(2)
                            .textCase(.uppercase)
                        
                        Spacer(minLength: 4)
                        
                        // Match ring
                        if let candidate = selectedCandidate {
                            MatchRing(
                                percentage: candidate.score,
                                isSelected: true,
                                isAutoSelected: isAutoSelected
                            )
                            .onTapGesture {
                                if isAutoSelected {
                                    withAnimation(.spring(response: 0.3)) {
                                        showReasoningTooltip.toggle()
                                    }
                                }
                            }
                        }
                    }
                    
                    // Year · Format · Episodes
                    HStack(spacing: 4) {
                        if let year = selectedCandidate?.year {
                            Text(String(year))
                                .foregroundColor(.black.opacity(0.5))
                        }
                        
                        if selectedCandidate?.year != nil && formatText != nil {
                            Text("·")
                                .foregroundColor(.black.opacity(0.3))
                        }
                        
                        if let format = formatText {
                            Text(format)
                                .foregroundColor(.black.opacity(0.5))
                        }
                        
                        if let episodes = episodeText {
                            Text("·")
                                .foregroundColor(.black.opacity(0.3))
                            Text(episodes)
                                .foregroundColor(.black.opacity(0.5))
                        }
                    }
                    .font(.kuroCaption())
                    
                    // Match% · Studio
                    HStack(spacing: 4) {
                        Text("\(Int(matchPercentage * 100))% match")
                            .foregroundColor(matchColor)
                        
                        if studioText != nil {
                            Text("·")
                                .foregroundColor(.black.opacity(0.3))
                            Text(studioText!)
                                .foregroundColor(.black.opacity(0.5))
                        }
                    }
                    .font(.kuroCaption())
                    
                    // Section caption (for skip items)
                    if let caption = section.caption {
                        Text(caption)
                            .font(.kuroCaption())
                            .foregroundColor(.black.opacity(0.4))
                            .padding(.top, 2)
                    }
                }
            }
            
            // Reasoning tooltip (auto-selected only)
            if isAutoSelected && showReasoningTooltip {
                ReasoningTooltip(reason: "Selected based on your text")
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
            
            // Candidate expansion
            if canExpand {
                Button(action: toggleExpansion) {
                    HStack(spacing: 4) {
                        Text("Other possibilities")
                            .font(.kuroCaption())
                            .foregroundColor(.black.opacity(0.55))
                        
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.black.opacity(0.4))
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
                
                if isExpanded {
                    CandidateList(
                        item: item,
                        selectedCandidate: selectedCandidate,
                        onSelect: { candidate in
                            triggerHaptic(.light)
                            onSelect(candidate)
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .padding(.top, 8)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.72), Color.white.opacity(0.18), Color.black.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                )
        )
    }
    
    // MARK: - Computed Properties
    
    private var cardTitle: String {
        selectedCandidate?.title_raw ?? item.normalized
    }
    
    private var formatText: String? {
        selectedCandidate?.format?.uppercased()
    }
    
    private var episodeText: String? {
        // Could derive from parsed data if available
        nil
    }
    
    private var studioText: String? {
        // Studio info could be added to candidate
        nil
    }
    
    private var matchColor: Color {
        let pct = matchPercentage * 100
        switch pct {
        case 98...100: return .green
        case 75..<98: return .orange
        default: return .yellow
        }
    }
    
    private var canExpand: Bool {
        item.candidates.count > 1 && section != .willSkip
    }
    
    // MARK: - Actions
    
    private func toggleExpansion() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isExpanded.toggle()
        }
        triggerHaptic(.light)
    }
    
    private func triggerHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
        #endif
    }
}

// MARK: - Reasoning Tooltip

private struct ReasoningTooltip: View {
    let reason: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 10))
                .foregroundColor(.blue)
            
            Text(reason)
                .font(.kuroCaption())
                .foregroundColor(.black.opacity(0.7))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous)
                .fill(Color.blue.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous)
                        .stroke(Color.blue.opacity(0.2), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Candidate List

private struct CandidateList: View {
    let item: ProtoConciergeParseItem
    let selectedCandidate: ProtoConciergeCandidate?
    let onSelect: (ProtoConciergeCandidate) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(item.candidates.prefix(4), id: \.media_id) { candidate in
                CandidateRow(
                    candidate: candidate,
                    isSelected: selectedCandidate?.media_id == candidate.media_id
                )
                .onTapGesture {
                    onSelect(candidate)
                }
            }
        }
    }
}

// MARK: - Candidate Row

private struct CandidateRow: View {
    let candidate: ProtoConciergeCandidate
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 10) {
            // Radio button
            ZStack {
                Circle()
                    .stroke(Color.black.opacity(0.25), lineWidth: 1.5)
                    .frame(width: 16, height: 16)
                
                if isSelected {
                    Circle()
                        .fill(Color.black)
                        .frame(width: 10, height: 10)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            
            // Title
            Text(candidate.title_raw)
                .font(.kuroCaption())
                .foregroundColor(.black.opacity(0.85))
                .lineLimit(1)
            
            Spacer(minLength: 0)
            
            // Year
            if let year = candidate.year {
                Text(String(year))
                    .font(.kuroCaption())
                    .foregroundColor(.black.opacity(0.45))
            }
            
            // Match percentage
            Text("\(Int(candidate.score * 100))%")
                .font(.kuroCaption(weight: .medium))
                .foregroundColor(matchColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous)
                .fill(isSelected ? Color.black.opacity(0.06) : Color.black.opacity(0.03))
        )
    }
    
    private var matchColor: Color {
        let pct = candidate.score * 100
        switch pct {
        case 98...100: return .green
        case 75..<98: return .orange
        default: return .yellow
        }
    }
}

// MARK: - Import Section Header

struct ImportSectionHeader: View {
    let section: ImportSection
    let count: Int
    
    var body: some View {
        HStack(spacing: KuroDesignSpacing.sm) {
            Text(section.rawValue)
                .font(.kuroCaption(weight: .medium))
                .tracking(1.6)
                .foregroundColor(.black.opacity(0.50))
            
            Text("\(count)")
                .font(.kuroCaption(weight: .medium))
                .foregroundColor(.black.opacity(0.40))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.06))
                )
            
            Spacer()
        }
    }
}

// MARK: - Import Card Container (with scroll tracking)

struct ImportCardContainer: View {
    let items: [ProtoConciergeParseItem]
    let selectedByItemId: [String: ProtoConciergeCandidate]
    let autoSelectedIds: Set<String>
    let itemActions: [String: ImportItemAction]
    let excludedItemIds: Set<String>
    let onSelect: (ProtoConciergeParseItem, ProtoConciergeCandidate) -> Void
    let onToggleExclude: (String) -> Void
    
    @State private var scrollOffset: CGFloat = 0
    
    private var addItems: [ProtoConciergeParseItem] {
        items.filter { (itemActions[$0.id] ?? .add) == .add }
    }
    
    private var updateItems: [ProtoConciergeParseItem] {
        items.filter { (itemActions[$0.id] ?? .add) == .update }
    }
    
    private var skipItems: [ProtoConciergeParseItem] {
        items.filter { (itemActions[$0.id] ?? .add) == .skip }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            // WILL ADD section
            if !addItems.isEmpty {
                ImportSectionHeader(section: .willAdd, count: addItems.count)
                
                ForEach(addItems) { item in
                    ImportConfirmCard(
                        item: item,
                        selectedCandidate: selectedByItemId[item.id],
                        isAutoSelected: autoSelectedIds.contains(item.id),
                        section: .willAdd,
                        scrollOffset: scrollOffset,
                        onSelect: { candidate in
                            onSelect(item, candidate)
                        },
                        onToggleExclude: {
                            onToggleExclude(item.id)
                        }
                    )
                }
            }
            
            // WILL UPDATE section
            if !updateItems.isEmpty {
                ImportSectionHeader(section: .willUpdate, count: updateItems.count)
                    .padding(.top, KuroDesignSpacing.sm)
                
                ForEach(updateItems) { item in
                    ImportConfirmCard(
                        item: item,
                        selectedCandidate: selectedByItemId[item.id],
                        isAutoSelected: autoSelectedIds.contains(item.id),
                        section: .willUpdate,
                        scrollOffset: scrollOffset,
                        onSelect: { candidate in
                            onSelect(item, candidate)
                        },
                        onToggleExclude: {
                            onToggleExclude(item.id)
                        }
                    )
                }
            }
            
            // WILL SKIP section
            if !skipItems.isEmpty {
                ImportSectionHeader(section: .willSkip, count: skipItems.count)
                    .padding(.top, KuroDesignSpacing.sm)
                
                ForEach(skipItems) { item in
                    ImportConfirmCard(
                        item: item,
                        selectedCandidate: selectedByItemId[item.id],
                        isAutoSelected: false,
                        section: .willSkip,
                        scrollOffset: scrollOffset,
                        onSelect: { candidate in
                            onSelect(item, candidate)
                        },
                        onToggleExclude: nil
                    )
                }
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onChange(of: geo.frame(in: .global).minY) { _, newValue in
                        scrollOffset = -newValue
                    }
            }
        )
    }
}

// MARK: - Preview Helpers
extension ProtoConciergeCandidate {
    static func mock(
        title: String = "Attack on Titan",
        score: Double = 0.98,
        year: Int? = 2013,
        format: String? = "TV",
        mediaType: String = "anime",
        mediaId: Int = 1
    ) -> ProtoConciergeCandidate {
        ProtoConciergeCandidate(
            media_type: mediaType,
            media_id: mediaId,
            variant_type: "main",
            title_raw: title,
            score: score,
            year: year,
            format: format,
            cover_image_medium: "https://cdn.myanimelist.net/images/anime/10/47347.jpg"
        )
    }
}

extension ProtoConciergeParseItem {
    static func mock(
        raw: String = "Attack on Titan",
        normalized: String = "Attack on Titan",
        candidates: [ProtoConciergeCandidate] = [
            .mock(title: "Attack on Titan", score: 0.98, year: 2013),
            .mock(title: "Attack on Titan: Junior High", score: 0.82, year: 2015, mediaId: 2),
            .mock(title: "Attack on Titan: The Final Season", score: 0.75, year: 2020, mediaId: 3)
        ],
        existingEntry: ProtoConciergeExistingEntry? = nil
    ) -> ProtoConciergeParseItem {
        ProtoConciergeParseItem(
            raw: raw,
            normalized: normalized,
            parsed: ProtoConciergeParseItemParsed(
                mediaTypeHint: nil,
                status: nil,
                progressEpisodes: nil,
                progressChapters: nil,
                progressVolumes: nil,
                seasonNumber: nil,
                episodeInSeason: nil,
                caughtUp: nil,
                lastEpisode: nil,
                completed: nil,
                yearMention: nil
            ),
            candidates: candidates,
            candidateError: nil,
            existing_entry: existingEntry
        )
    }
}

extension ProtoConciergeExistingEntry {
    static func mock() -> ProtoConciergeExistingEntry {
        ProtoConciergeExistingEntry(
            media_type: "anime",
            media_id: 1,
            status: "WATCHING",
            progress_episodes: 12,
            progress_chapters: nil,
            progress_volumes: nil,
            rating: nil,
            updated_at: "2026-02-10T00:00:00Z"
        )
    }
}

#Preview("Import Confirm Card - High Match") {
    ScrollView {
        VStack(spacing: 16) {
            ImportConfirmCard(
                item: .mock(),
                selectedCandidate: .mock(score: 0.98),
                isAutoSelected: true,
                section: .willAdd,
                scrollOffset: 0,
                onSelect: { _ in },
                onToggleExclude: {}
            )
            
            ImportConfirmCard(
                item: .mock(
                    raw: "Hunter x Hunter",
                    normalized: "Hunter x Hunter",
                    candidates: [
                        .mock(title: "Hunter x Hunter (2011)", score: 0.95, year: 2011, mediaId: 1),
                        .mock(title: "Hunter x Hunter (1999)", score: 0.88, year: 1999, mediaId: 2),
                        .mock(title: "Hunter x Hunter: Greed Island", score: 0.72, year: 2003, mediaId: 3)
                    ]
                ),
                selectedCandidate: .mock(title: "Hunter x Hunter (2011)", score: 0.95, year: 2011),
                isAutoSelected: false,
                section: .willAdd,
                scrollOffset: 0,
                onSelect: { _ in },
                onToggleExclude: {}
            )
            
            ImportConfirmCard(
                item: .mock(
                    raw: "Jujutsu Kaisen",
                    normalized: "Jujutsu Kaisen",
                    candidates: [.mock(title: "Jujutsu Kaisen", score: 0.85, year: 2020)]
                ),
                selectedCandidate: .mock(title: "Jujutsu Kaisen", score: 0.85, year: 2020),
                isAutoSelected: false,
                section: .willUpdate,
                scrollOffset: 0,
                onSelect: { _ in },
                onToggleExclude: {}
            )
            
            ImportConfirmCard(
                item: .mock(existingEntry: .mock()),
                selectedCandidate: .mock(score: 1.0),
                isAutoSelected: false,
                section: .willSkip,
                scrollOffset: 0,
                onSelect: { _ in },
                onToggleExclude: nil
            )
        }
        .padding()
    }
    .background(Color.kuroBackground)
}

#Preview("Match Ring Variants") {
    HStack(spacing: 20) {
        VStack(spacing: 8) {
            MatchRing(percentage: 0.98, isSelected: true, isAutoSelected: true)
            Text("98% Auto")
                .font(.kuroCaption())
        }
        
        VStack(spacing: 8) {
            MatchRing(percentage: 0.85, isSelected: true, isAutoSelected: false)
            Text("85%")
                .font(.kuroCaption())
        }
        
        VStack(spacing: 8) {
            MatchRing(percentage: 0.72, isSelected: false, isAutoSelected: false)
            Text("72%")
                .font(.kuroCaption())
        }
    }
    .padding()
    .background(Color.kuroBackground)
}

#Preview("Full Container") {
    struct PreviewContainer: View {
        @State private var selectedByItemId: [String: ProtoConciergeCandidate] = [:]
        @State private var autoSelectedIds: Set<String> = ["mock1"]
        @State private var excludedItemIds: Set<String> = []
        
        let items: [ProtoConciergeParseItem] = [
            .mock(raw: "mock1"),
            .mock(
                raw: "mock2",
                normalized: "Hunter x Hunter",
                candidates: [
                    .mock(title: "Hunter x Hunter (2011)", score: 0.95, year: 2011, mediaId: 1),
                    .mock(title: "Hunter x Hunter (1999)", score: 0.88, year: 1999, mediaId: 2)
                ]
            ),
            .mock(raw: "mock3", existingEntry: .mock()),
            .mock(
                raw: "mock4",
                normalized: "Demon Slayer",
                candidates: [
                    .mock(title: "Demon Slayer: Kimetsu no Yaiba", score: 0.99, year: 2019, mediaId: 4)
                ]
            )
        ]
        
        var body: some View {
            ScrollView {
                ImportCardContainer(
                    items: items,
                    selectedByItemId: selectedByItemId,
                    autoSelectedIds: autoSelectedIds,
                    itemActions: [
                        "mock1": .add,
                        "mock2": .add,
                        "mock3": .skip,
                        "mock4": .update
                    ],
                    excludedItemIds: excludedItemIds,
                    onSelect: { item, candidate in
                        selectedByItemId[item.id] = candidate
                    },
                    onToggleExclude: { id in
                        if excludedItemIds.contains(id) {
                            excludedItemIds.remove(id)
                        } else {
                            excludedItemIds.insert(id)
                        }
                    }
                )
                .padding()
            }
            .background(Color.kuroBackground)
            .onAppear {
                // Pre-select first candidate for each item
                var selections: [String: ProtoConciergeCandidate] = [:]
                for item in items {
                    if let first = item.candidates.first {
                        selections[item.id] = first
                    }
                }
                selectedByItemId = selections
            }
        }
    }
    
    return PreviewContainer()
}
#endif
