import SwiftUI

// Shared Concierge UI components used by `ConciergeView`:
// message model, assistant orb/panel, and chat bubble subviews.

enum ConciergeMascotState: Equatable {
    case idle
    case listening
    case thinking
    case celebrating
    case concerned
}

struct KuroConciergeMascot: View {
    @Binding var expanded: Bool
    @Binding var offset: CGSize
    @Binding var dragStart: CGSize
    let baseBottomPadding: CGFloat
    let containerSize: CGSize
    let state: ConciergeMascotState
    let onTapMascot: () -> Void

    @Namespace private var mascotNS
    @State private var pulse: Bool = false
    @State private var ringPhase: Bool = false

    private let panelWidth: CGFloat = 316
    private let panelHeight: CGFloat = 148
    private let orbSize: CGFloat = 56

    var body: some View {
        let clamped = clamp(offset: offset)

        VStack(spacing: 0) {
            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        KuroConciergeMark(size: 34)
                            .matchedGeometryEffect(id: "kurochan", in: mascotNS)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("CONCIERGE")
                                .font(.kuroCaption(weight: .medium))
                                .tracking(2.4)
                                .foregroundStyle(.primary.opacity(0.82))
                            Text(statusLine)
                                .font(.kuroCaption())
                                .foregroundStyle(.secondary.opacity(0.65))
                        }
                        Spacer(minLength: 0)

                        Button(action: { withAnimation(KuroAnimation.fast) { expanded = false } }) {
                            Image(systemName: "chevron.down")
                                .font(.kuroBody(weight: .semibold))
                                .foregroundStyle(.primary.opacity(0.45))
                                .frame(width: 34, height: 34)
                                .background(
                                    Circle().fill(Color.black.opacity(0.04))
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    Text(isGerman
                        ? "Nutze deine Kuro-Bibliothek oder schildere kurz die Stimmung.\nSauber gefiltert."
                        : "Use your Kuro library directly, or describe the mood.\nCleanly filtered."
                    )
                        .font(.kuroCaption())
                        .foregroundStyle(.secondary.opacity(0.75))

                    Button(action: {
                        KuroAccessibility.impactHaptic(.light)
                        onTapMascot()
                    }) {
                        HStack(spacing: 10) {
                            Text("START CHAT")
                                .font(.kuroCaption(weight: .medium))
                                .tracking(1.8)
                                .foregroundStyle(.primary.opacity(0.82))
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.right")
                                .font(.kuroCaption(weight: .semibold))
                                .foregroundStyle(.primary.opacity(0.45))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.black.opacity(0.04))
                                .overlay(Capsule().stroke(Color.black.opacity(0.08), lineWidth: 0.8))
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(KuroDesignSpacing.md)
                .frame(width: panelWidth, height: panelHeight, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: KuroRadius.lg, style: .continuous)
                        .fill(Color.kuroSecondaryBackground.opacity(0.96))
                        .overlay(
                            RoundedRectangle(cornerRadius: KuroRadius.lg, style: .continuous)
                                .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
                        )
                        .shadow(color: Color.black.opacity(0.10), radius: 18, x: 0, y: 10)
                )
                .clipShape(RoundedRectangle(cornerRadius: KuroRadius.lg, style: .continuous))
                .gesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { value in
                            offset = CGSize(
                                width: dragStart.width + value.translation.width,
                                height: dragStart.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            let next = clamp(offset: offset)
                            withAnimation(KuroAnimation.editorial) {
                                offset = next
                            }
                            dragStart = next
                        }
                )
            } else {
                Button(action: {
                    withAnimation(KuroAnimation.editorial) { expanded = true }
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.kuroSecondaryBackground.opacity(0.96))
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.9)
                            )
                            .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
                            .frame(width: 56, height: 56)

                        Circle()
                            .strokeBorder(Color.black.opacity(pulse ? 0.12 : 0.04), lineWidth: 1.1)
                            .frame(width: 56, height: 56)
                            .scaleEffect(pulse ? 1.08 : 0.96)
                            .opacity(pulse ? 1.0 : 0.0)
                            .allowsHitTesting(false)

                        ZStack {
                            // State ring (subtle, monochrome).
                            if state == .thinking {
                                Circle()
                                    .trim(from: 0.0, to: 0.72)
                                    .stroke(Color.primary.opacity(0.35), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                                    .rotationEffect(.degrees(ringPhase ? 360 : 0))
                                    .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: ringPhase)
                                    .frame(width: 42, height: 42)
                                    .allowsHitTesting(false)
                            }

                            KuroConciergeMark(size: 24)
                                .matchedGeometryEffect(id: "kurochan", in: mascotNS)

                            if state == .concerned {
                                Image(systemName: "exclamationmark")
                                    .font(.kuroMicro(weight: .bold))
                                    .foregroundStyle(.primary.opacity(0.55))
                                    .offset(x: 14, y: -14)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { value in
                            offset = CGSize(
                                width: dragStart.width + value.translation.width,
                                height: dragStart.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            let next = clamp(offset: offset)
                            withAnimation(KuroAnimation.editorial) {
                                offset = next
                            }
                            dragStart = next
                        }
                )
            }
        }
        .padding(.leading, KuroDesignSpacing.md)
        .padding(.bottom, baseBottomPadding)
        .offset(clamped)
        .onAppear {
            if dragStart == .zero, offset == .zero {
                dragStart = .zero
                offset = .zero
            }

            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                pulse = true
            }

            ringPhase = true
        }
        .onChange(of: expanded) { _, _ in
            let next = clamp(offset: offset)
            if next != offset {
                offset = next
                dragStart = next
            }
        }
    }

    private var statusLine: String {
        switch state {
        case .idle: return "Imports + recommendations"
        case .listening: return "Listening"
        case .thinking: return "Thinking"
        case .celebrating: return "Saved"
        case .concerned: return "Needs clarification"
        }
    }

    private func clamp(offset: CGSize) -> CGSize {
        let activeWidth = expanded ? panelWidth : orbSize
        let maxRight = max(0, containerSize.width - (activeWidth + 32))
        let minX: CGFloat = 0
        let maxX: CGFloat = maxRight

        // Keep the collapsed orb close to the input bar so it never drifts into header content.
        let minY: CGFloat = expanded
            ? -max(120, containerSize.height * 0.70)
            : -max(28, containerSize.height * 0.18)
        let maxY: CGFloat = 0

        return CGSize(
            width: min(maxX, max(minX, offset.width)),
            height: min(maxY, max(minY, offset.height))
        )
    }
}

// MARK: - Message Model

struct ConciergeMessage: Identifiable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    let text: String
    let showClarifyActions: Bool
    /// If this message was produced from a specific user input (e.g. an import parse),
    /// keep the originating text so actions like "Re-parse" target the correct input.
    let sourceUserText: String?
    let items: [SupabaseService.ConciergeParseItem]?
    let recommendations: [SupabaseService.ConciergeRecommendResponse.Item]?
    let recommendationSets: [SupabaseService.ConciergeRecommendResponse.Set]?
    let recommendationCategories: [String]?
    let parseResponse: SupabaseService.ConciergeParseResponse?
    /// Ambiguity from the parser requiring user clarification before re-parse.
    let ambiguity: SupabaseService.ConciergeAmbiguity?

    init(
        role: Role,
        text: String,
        showClarifyActions: Bool = false,
        sourceUserText: String? = nil,
        items: [SupabaseService.ConciergeParseItem]? = nil,
        recommendations: [SupabaseService.ConciergeRecommendResponse.Item]? = nil,
        recommendationSets: [SupabaseService.ConciergeRecommendResponse.Set]? = nil,
        recommendationCategories: [String]? = nil,
        parseResponse: SupabaseService.ConciergeParseResponse? = nil,
        ambiguity: SupabaseService.ConciergeAmbiguity? = nil
    ) {
        self.role = role
        self.text = text
        self.showClarifyActions = showClarifyActions
        self.sourceUserText = sourceUserText
        self.items = items
        self.recommendations = recommendations
        self.recommendationSets = recommendationSets
        self.recommendationCategories = recommendationCategories
        self.parseResponse = parseResponse
        self.ambiguity = ambiguity
    }
}

extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        switch self {
        case .none: return true
        case .some(let s): return s.isEmpty
        }
    }
}

private enum ConciergeCuratedCopy {
    private static let en: [String: (String, String?)] = [
        "premium_picks": ("The Cut", "High-confidence picks, new to you"),
        "gateway_start_here": ("Start Here", "A clean entry point"),
        "premium_action": ("Action With Craft", "Clean choreography, real momentum"),
        "premium_comedy_grownup": ("Comedy With Bite", "Smart, dry, character-led"),
        "cozy_comfort": ("Soft Evenings", "Gentle, restorative stories"),
        "dark_serious": ("Dark, Not Empty", "Serious tone, strong craft"),
        "hidden_gems": ("Underseen", "Quiet classics, overlooked hits"),
        "classics_expanded": ("The Canon", "Anchors worth knowing"),
        "short_one_season": ("Short, Complete", "One season, clean finish"),
        "movie_night": ("One Perfect Film", "Stand-alone nights"),
        "romance_serious": ("Romance That Lands", "Earned, not fluffy"),
        "romcom": ("Light, Sharp Romance", "Warmth with timing"),
        "fantasy_non_isekai": ("Fantasy With Texture", "Myth, wonder, discipline"),
        "isekai": ("Other Worlds, Cleanly", "Escapism with craft"),
        "sports": ("Competition, Pure", "Training arcs that work"),
        "scifi": ("Ideas With Heat", "Speculation, not noise"),
        "horror_supernatural": ("Unease, Done Right", "Atmosphere over gore"),
        "mecha": ("Steel and Stakes", "Big machines, real themes"),
        "mystery_detective": ("Cases With Discipline", "Puzzles that hold"),
        "music_performance": ("Sound and Feeling", "Performance that moves"),
        "historical": ("Period Weight", "History with texture"),
        "school_coming_of_age": ("Coming-of-Age, Quietly", "Youth, rendered cleanly"),
        "shoujo_josei": ("Emotion, With Clarity", "Character-first, precise"),
        "similar_to_seed": ("In the Same Orbit", "Close to your anchor"),
    ]

    private static let de: [String: (String, String?)] = [
        "premium_picks": ("Die Auswahl", "Sichere Picks, neu für dich"),
        "gateway_start_here": ("Hier anfangen", "Ein sauberer Einstieg"),
        "premium_action": ("Action mit Handwerk", "Choreo, Tempo, Klarheit"),
        "premium_comedy_grownup": ("Komödie mit Biss", "Trocken, klug, figurengetrieben"),
        "cozy_comfort": ("Sanfte Abende", "Ruhig, warm, erholsam"),
        "dark_serious": ("Dunkel, nicht leer", "Ernst, aber mit Substanz"),
        "hidden_gems": ("Unterschätzt", "Übersehenes, das sitzt"),
        "classics_expanded": ("Der Kanon", "Anker, die man kennt"),
        "short_one_season": ("Kurz, abgeschlossen", "Eine Staffel, sauberer Abschluss"),
        "movie_night": ("Ein perfekter Film", "Standalone-Abende"),
        "romance_serious": ("Romantik, die trifft", "Verdient, nicht fluffig"),
        "romcom": ("Leicht, aber scharf", "Wärme mit Timing"),
        "fantasy_non_isekai": ("Fantasy mit Textur", "Mythos, Staunen, Disziplin"),
        "isekai": ("Andere Welten, sauber", "Eskapismus mit Handwerk"),
        "sports": ("Wettkampf, pur", "Training, das funktioniert"),
        "scifi": ("Ideen mit Hitze", "Spekulation, nicht Lärm"),
        "horror_supernatural": ("Unbehagen, richtig", "Atmosphäre statt Gore"),
        "mecha": ("Stahl und Einsatz", "Große Maschinen, echte Themen"),
        "mystery_detective": ("Fälle mit Disziplin", "Rätsel, die halten"),
        "music_performance": ("Klang und Gefühl", "Performance, die bewegt"),
        "historical": ("Zeitgewicht", "Geschichte mit Textur"),
        "school_coming_of_age": ("Coming-of-Age, leise", "Jugend, klar gezeichnet"),
        "shoujo_josei": ("Gefühl, mit Klarheit", "Figuren zuerst, präzise"),
        "similar_to_seed": ("In derselben Umlaufbahn", "Nahe an deinem Anker"),
    ]

    static func titleAndSubtitle(for modeId: String?) -> (String, String?)? {
        guard let modeId, !modeId.isEmpty else { return nil }
        let language = Locale.current.language.languageCode?.identifier.lowercased() ?? "en"
        if language.hasPrefix("de") { return de[modeId] }
        return en[modeId]
    }

    static func titleAndSubtitle(for modeId: String?, fallbackTitle: String?) -> (String, String?)? {
        if let direct = titleAndSubtitle(for: modeId) { return direct }

        let raw = (fallbackTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let l = raw.lowercased()

        // Heuristic mapping so older server payloads don't surface internal "Premium / Cozy" labels.
        if l.contains("premium comedy") || l.contains("grown") {
            return titleAndSubtitle(for: "premium_comedy_grownup")
        }
        if l.contains("cozy") || l.contains("comfort") {
            return titleAndSubtitle(for: "cozy_comfort")
        }
        if l.contains("premium picks") || l.contains("picks") {
            return titleAndSubtitle(for: "premium_picks")
        }
        if l.contains("hidden") && l.contains("gem") {
            return titleAndSubtitle(for: "hidden_gems")
        }
        if l.contains("classic") || l.contains("canon") {
            return titleAndSubtitle(for: "classics_expanded")
        }
        if l.contains("dark") || l.contains("serious") {
            return titleAndSubtitle(for: "dark_serious")
        }
        if l.contains("action") {
            return titleAndSubtitle(for: "premium_action")
        }
        if l.contains("movie") {
            return titleAndSubtitle(for: "movie_night")
        }
        if l.contains("one season") || l.contains("short") {
            return titleAndSubtitle(for: "short_one_season")
        }

        // As a final fallback, soften the raw label so it doesn't read like a mode/debug tag.
        let softened = raw
            .replacingOccurrences(of: "premium", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "cozy", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "comfort", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "grown-up", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "grownup", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "/", with: " · ")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if softened.isEmpty { return nil }
        return (softened, nil)
    }
}

// MARK: - Action Bar

struct ConciergeActionBar: View {
    let selectedCount: Int
    let hasAnySelection: Bool
    let canUndo: Bool
    let onApply: () -> Void
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onUndo) {
                Text("UNDO")
                    .font(.kuroCaption(weight: .medium))
                    .tracking(1.6)
                    .foregroundColor(canUndo ? .black : .black.opacity(0.25))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous)
                            .fill(Color.black.opacity(canUndo ? 0.04 : 0.02))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canUndo)

            Spacer()

            Button(action: onApply) {
                HStack(spacing: KuroDesignSpacing.sm) {
                    Text("APPLY")
                        .font(.kuroCaption(weight: .medium))
                        .tracking(1.6)
                    Text("\(selectedCount)")
                        .font(.kuroCaption(weight: .medium))
                        .tracking(1.0)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 999, style: .continuous)
                                .fill(Color.white.opacity(0.12))
                        )
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous)
                        .fill(hasAnySelection ? Color.black : Color.black.opacity(0.2))
                )
            }
            .buttonStyle(.plain)
            .disabled(!hasAnySelection)
        }
    }
}

// MARK: - Typing Indicator (500ms cycle)

struct ConciergeTypingIndicator: View {
    @State private var phase: Int = 0

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Circle().fill(Color.black.opacity(0.25)).frame(width: 6, height: 6).opacity(phase == 0 ? 1 : 0.35)
                    .scaleEffect(phase == 0 ? 1.15 : 0.95)
                Circle().fill(Color.black.opacity(0.25)).frame(width: 6, height: 6).opacity(phase == 1 ? 1 : 0.35)
                    .scaleEffect(phase == 1 ? 1.15 : 0.95)
                Circle().fill(Color.black.opacity(0.25)).frame(width: 6, height: 6).opacity(phase == 2 ? 1 : 0.35)
                    .scaleEffect(phase == 2 ? 1.15 : 0.95)
            }
            Text("Thinking")
                .font(.kuroCaption())
                .foregroundColor(.black.opacity(0.55))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                // Avoid full-screen materials in a frequently-updating view.
                .fill(Color.kuroSecondaryBackground.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous))
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                phase = (phase + 1) % 3
            }
        }
    }
}

// MARK: - Intro Card

struct ConciergeIntroCard: View {
    var body: some View {
        KuroGlassCard(cornerRadius: KuroRadius.lg) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    KuroConciergeMark(size: 34)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("CONCIERGE")
                            .font(.kuroCaption(weight: .medium))
                            .tracking(2.4)
                            .foregroundColor(.black.opacity(0.80))
                        Text("Imports + recommendations")
                            .font(.kuroCaption())
                            .foregroundColor(.black.opacity(0.55))
                    }

                    Spacer(minLength: 0)
                }

                Rectangle()
                    .fill(Color.black.opacity(0.06))
                    .frame(height: 0.5)

                Text(isGerman
                    ? "Importe deine Liste — oder beschreibe kurz die Stimmung.\nSauber gefiltert."
                    : "Import your library, or describe the mood.\nCleanly filtered."
                )
                    .font(.kuroBody(weight: .light))
                    .foregroundColor(.black.opacity(0.62))
                    .lineSpacing(3)
            }
            .padding(KuroDesignSpacing.md)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isGerman
            ? "Concierge. Bibliothek importieren oder Stimmung beschreiben."
            : "Concierge. Import from your list or describe a mood."
        )
    }
}

// MARK: - Starter Actions

struct ConciergeStarterActions: View {
    let onPaste: () -> Void
    let onImportLibrary: () -> Void
    let onExampleImport: () -> Void
    let onExampleVibe: () -> Void

    @State private var appeared: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            KuroGlassPill(
                title: isGerman ? "Aus deiner Bibliothek" : "From your library",
                subtitle: isGerman ? "Direkter Kuro-Import" : "Direct Kuro import",
                systemImage: "doc.text.image",
                action: onImportLibrary
            )
            .offset(y: appeared ? 0 : 3)
            .opacity(appeared ? 1 : 0)

            KuroGlassPill(
                title: isGerman ? "Aus der Zwischenablage" : "From clipboard",
                subtitle: isGerman ? "Manuelle Eingabe" : "Manual list",
                systemImage: "doc.on.clipboard",
                action: onPaste
            )
            .offset(y: appeared ? 0 : 6)
            .opacity(appeared ? 1 : 0)

            KuroGlassPill(
                title: isGerman ? "Kurzes Beispiel" : "Sample format",
                subtitle: isGerman ? "Import-Vorlage in einem Schritt" : "One-shot format example",
                systemImage: "text.append",
                action: onExampleImport
            )
            .offset(y: appeared ? 0 : 10)
            .opacity(appeared ? 1 : 0)

            KuroGlassPill(
                title: "Curate for me",
                subtitle: "Recommendations",
                systemImage: "sparkles",
                action: onExampleVibe
            )
            .offset(y: appeared ? 0 : 14)
            .opacity(appeared ? 1 : 0)
        }
        .padding(.horizontal, KuroDesignSpacing.padding)
        .onAppear {
            withAnimation(KuroAnimation.fast) {
                appeared = true
            }
        }
    }
}

// MARK: - Locale Helper

private var isGerman: Bool {
    let language = Locale.current.language.languageCode?.identifier.lowercased() ?? "en"
    return language.hasPrefix("de")
}

// MARK: - Clarify Card (Two-Path Intent Picker, Locale-Aware)

struct ConciergeClarifyCard: View {
    let onPaste: () -> Void
    let onImportLibrary: () -> Void
    let onExampleImport: () -> Void
    let onExampleVibe: () -> Void

    @State private var appeared: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Import path
            VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.kuroCaption(weight: .semibold))
                        .foregroundColor(.black.opacity(0.45))
                    Text(isGerman ? "IMPORTIEREN" : "IMPORT")
                        .font(.kuroCaption(weight: .medium))
                        .tracking(1.8)
                        .foregroundColor(.black.opacity(0.55))
                }

                KuroGlassPill(
                    title: isGerman ? "Aus deiner Bibliothek" : "From your library",
                    subtitle: isGerman ? "Nutze deine Kuro-Liste direkt" : "Use your Kuro list directly",
                    systemImage: "doc.text.image",
                    action: onImportLibrary
                )

                KuroGlassPill(
                    title: isGerman ? "Aus Zwischenablage einfügen" : "From clipboard",
                    subtitle: isGerman ? "Titel, Fortschritt, Bewertungen" : "Titles, progress, ratings",
                    systemImage: "doc.on.clipboard",
                    action: onPaste
                )

                KuroGlassPill(
                    title: isGerman ? "Beispiel ausprobieren" : "Try an example",
                    subtitle: isGerman ? "Attack on Titan (fertig), JJK Folge 12..." : "Attack on Titan (completed), JJK ep 12...",
                    systemImage: "text.append",
                    action: onExampleImport
                )
            }
            .offset(y: appeared ? 0 : 6)
            .opacity(appeared ? 1 : 0)

            // Divider
            HStack(spacing: KuroDesignSpacing.sm) {
                Rectangle()
                    .fill(Color.black.opacity(0.06))
                    .frame(height: 0.5)
                Text(isGerman ? "ODER" : "OR")
                    .font(.kuroMicro(weight: .medium))
                    .tracking(1.4)
                    .foregroundColor(.black.opacity(0.30))
                Rectangle()
                    .fill(Color.black.opacity(0.06))
                    .frame(height: 0.5)
            }
            .padding(.vertical, 14)
            .offset(y: appeared ? 0 : 8)
            .opacity(appeared ? 1 : 0)

            // Vibe path
            VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.kuroCaption(weight: .semibold))
                        .foregroundColor(.black.opacity(0.45))
                    Text(isGerman ? "EMPFEHLEN" : "RECOMMEND")
                        .font(.kuroCaption(weight: .medium))
                        .tracking(1.8)
                        .foregroundColor(.black.opacity(0.55))
                }

                KuroGlassPill(
                    title: isGerman ? "Stimmung beschreiben" : "Describe a mood",
                    subtitle: isGerman ? "Lustig, sanft, düster, kurz..." : "Funny, soft, dark, short...",
                    systemImage: "text.bubble",
                    action: onExampleVibe
                )
            }
            .offset(y: appeared ? 0 : 10)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(KuroAnimation.editorial) {
                appeared = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isGerman ? "Wahlen: Titel importieren oder Empfehlungen erhalten" : "Choose: import titles or get recommendations")
    }
}

// MARK: - Status Clarify Card (Finished vs Still Watching)

struct ConciergeStatusClarifyCard: View {
    let titleContext: String?
    let onChoose: (_ status: String) -> Void

    @State private var appeared: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
            // Header
            Text(isGerman ? "Fertig geschaut?" : "Did you finish it?")
                .font(.kuroBody(weight: .regular))
                .foregroundColor(.black.opacity(0.82))
                .offset(y: appeared ? 0 : 4)
                .opacity(appeared ? 1 : 0)

            // Title context
            if let title = titleContext, !title.isEmpty {
                Text(isGerman ? "Für: \(title)" : "For: \(title)")
                    .font(.kuroCaption())
                    .foregroundColor(.black.opacity(0.55))
                    .lineLimit(2)
                    .offset(y: appeared ? 0 : 6)
                    .opacity(appeared ? 1 : 0)
            }

            // One-tap pills
            HStack(spacing: KuroDesignSpacing.sm) {
                ClarifyChoicePill(
                    label: isGerman ? "Fertig" : "Finished",
                    systemImage: "checkmark.circle"
                ) {
                    KuroAccessibility.impactHaptic(.light)
                    onChoose("COMPLETED")
                }

                ClarifyChoicePill(
                    label: isGerman ? "Noch dabei" : "Still watching",
                    systemImage: "play.circle"
                ) {
                    KuroAccessibility.impactHaptic(.light)
                    onChoose("CURRENT")
                }
            }
            .offset(y: appeared ? 0 : 8)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(KuroAnimation.editorial) {
                appeared = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isGerman ? "Klarung: Fertig geschaut?" : "Clarification: Did you finish it?")
    }
}

// MARK: - Unit Clarify Card (Episode / Season / Chapter / Volume)

struct ConciergeUnitClarifyCard: View {
    let numberContext: String?
    let onChoose: (_ unit: String) -> Void

    @State private var appeared: Bool = false

    private var headerText: String {
        let num = numberContext ?? "?"
        return isGerman
            ? "Was bedeutet '\(num)'?"
            : "What does '\(num)' refer to?"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
            // Header
            Text(headerText)
                .font(.kuroBody(weight: .regular))
                .foregroundColor(.black.opacity(0.82))
                .offset(y: appeared ? 0 : 4)
                .opacity(appeared ? 1 : 0)

            // Four one-tap pills in a 2x2 grid
            VStack(spacing: KuroDesignSpacing.sm) {
                HStack(spacing: KuroDesignSpacing.sm) {
                    ClarifyChoicePill(
                        label: isGerman ? "Folge" : "Episode",
                        systemImage: "play.rectangle"
                    ) {
                        KuroAccessibility.impactHaptic(.light)
                        onChoose("episode")
                    }

                    ClarifyChoicePill(
                        label: isGerman ? "Staffel" : "Season",
                        systemImage: "rectangle.stack"
                    ) {
                        KuroAccessibility.impactHaptic(.light)
                        onChoose("season")
                    }
                }
                .offset(y: appeared ? 0 : 6)
                .opacity(appeared ? 1 : 0)

                HStack(spacing: KuroDesignSpacing.sm) {
                    ClarifyChoicePill(
                        label: isGerman ? "Kapitel" : "Chapter",
                        systemImage: "book"
                    ) {
                        KuroAccessibility.impactHaptic(.light)
                        onChoose("chapter")
                    }

                    ClarifyChoicePill(
                        label: isGerman ? "Band" : "Volume",
                        systemImage: "books.vertical"
                    ) {
                        KuroAccessibility.impactHaptic(.light)
                        onChoose("volume")
                    }
                }
                .offset(y: appeared ? 0 : 10)
                .opacity(appeared ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(KuroAnimation.editorial) {
                appeared = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isGerman ? "Klarung: Einheit wahlen" : "Clarification: Choose a unit")
    }
}

// MARK: - Intent Clarify Card (Import vs Recommend)

struct ConciergeIntentClarifyCard: View {
    let titleContext: String?
    let onChoose: (_ intent: String) -> Void

    @State private var appeared: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
            Text(isGerman ? "Was möchtest du tun?" : "What do you want to do?")
                .font(.kuroBody(weight: .regular))
                .foregroundColor(.black.opacity(0.82))
                .offset(y: appeared ? 0 : 4)
                .opacity(appeared ? 1 : 0)

            if let title = titleContext, !title.isEmpty {
                Text(isGerman ? "Für: \(title)" : "For: \(title)")
                    .font(.kuroCaption())
                    .foregroundColor(.black.opacity(0.55))
                    .lineLimit(2)
                    .offset(y: appeared ? 0 : 6)
                    .opacity(appeared ? 1 : 0)
            }

            HStack(spacing: KuroDesignSpacing.sm) {
                ClarifyChoicePill(
                    label: isGerman ? "Zur Liste" : "Add to list",
                    systemImage: "square.and.arrow.down"
                ) {
                    KuroAccessibility.impactHaptic(.light)
                    onChoose("import")
                }

                ClarifyChoicePill(
                    label: isGerman ? "Als Vorlage" : "Use as seed",
                    systemImage: "sparkles"
                ) {
                    KuroAccessibility.impactHaptic(.light)
                    onChoose("recommend_seed")
                }
            }
            .offset(y: appeared ? 0 : 8)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(KuroAnimation.editorial) {
                appeared = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isGerman ? "Klarung: Import oder Empfehlung" : "Clarification: import or recommendation")
    }
}

// MARK: - Clarify Choice Pill (Shared one-tap button)

private struct ClarifyChoicePill: View {
    let label: String
    let systemImage: String
    let action: () -> Void

    @State private var isPressed: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.kuroCaption(weight: .semibold))
                    .foregroundColor(.black.opacity(0.55))

                Text(label)
                    .font(.kuroCaption(weight: .medium))
                    .foregroundColor(.black.opacity(0.82))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.85), value: isPressed)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.01)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.04))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.7)
                )
        )
    }
}

// MARK: - Chat Bubble

struct ConciergeBubble: View {
    let message: ConciergeMessage
    let selected: (SupabaseService.ConciergeParseItem) -> SupabaseService.ConciergeCandidate?
    let onSelect: (SupabaseService.ConciergeParseItem, SupabaseService.ConciergeCandidate) -> Void
    let onOpenRecommendation: (SupabaseService.ConciergeRecommendResponse.Item) -> Void
    let onQuickSave: (SupabaseService.ConciergeRecommendResponse.Item) -> Void
    let onClarifyPaste: () -> Void
    let onClarifyImportLibrary: () -> Void
    let onClarifyExampleImport: () -> Void
    let onClarifyExampleVibe: () -> Void
    var onClarifyAmbiguity: ((_ kind: String, _ value: String, _ sourceText: String) -> Void)? = nil
    var onConfirmItems: ((SupabaseService.ConciergeParseResponse) -> Void)? = nil
    var onReparse: (() -> Void)? = nil
    var isImportApplied: Bool = false
    var autoReasonByItemId: [String: String] = [:]
    var itemActions: [String: ImportItemAction] = [:]
    @Binding var excludedItemIds: Set<String>
    @Environment(\.colorScheme) private var colorScheme

    private func glassBubble<Content: View>(cornerRadius: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.kuroSecondaryBackground.opacity(colorScheme == .dark ? 0.92 : 0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.06), lineWidth: 0.8)
                    )
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.30 : 0.06), radius: 14, x: 0, y: 8)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

	    var body: some View {
	        HStack(alignment: .bottom) {
	            if message.role == .assistant {
	                VStack(alignment: .leading, spacing: 10) {
	                    let isRecommendationMessage = (message.recommendationSets?.isEmpty == false) || (message.recommendations?.isEmpty == false)
	                    if !message.text.isEmpty {
	                        if isRecommendationMessage {
	                            Text(message.text)
	                                .font(.system(size: 13, weight: .light, design: .serif))
	                                .italic()
	                                .foregroundStyle(.black.opacity(0.64))
	                                .lineSpacing(3)
	                                .padding(.horizontal, 2)
	                                .frame(maxWidth: 520, alignment: .leading)
	                        } else {
	                            glassBubble(cornerRadius: KuroRadius.md) {
	                                Text(message.text)
	                                    .font(.kuroBody())
	                                    .foregroundStyle(.primary.opacity(0.82))
	                                    .padding(.horizontal, 14)
	                                    .padding(.vertical, 12)
	                            }
	                            .frame(maxWidth: 360, alignment: .leading)
	                        }
	                    }

                    if message.showClarifyActions {
                        ConciergeClarifyCard(
                            onPaste: onClarifyPaste,
                            onImportLibrary: onClarifyImportLibrary,
                            onExampleImport: onClarifyExampleImport,
                            onExampleVibe: onClarifyExampleVibe
                        )
                        .frame(maxWidth: 420, alignment: .leading)
                    }

                    // Ambiguity clarification cards
                    if let ambiguity = message.ambiguity, let sourceText = message.sourceUserText {
                        ambiguityCard(ambiguity: ambiguity, sourceText: sourceText)
                            .frame(maxWidth: 420, alignment: .leading)
                    }

                    // Inline confirm bubble for import items
                    if let items = message.items, !items.isEmpty, let parseResponse = message.parseResponse {
                        ConciergeConfirmBubble(
                            items: items,
                            selected: selected,
                            onSelect: onSelect,
                            onConfirm: { onConfirmItems?(parseResponse) },
                            onReparse: onReparse,
                            isApplied: isImportApplied,
                            autoReasonByItemId: autoReasonByItemId,
                            itemActions: itemActions,
                            excludedItemIds: $excludedItemIds
                        )
                        .frame(maxWidth: 420, alignment: .leading)
                    } else if let items = message.items, !items.isEmpty {
                        glassBubble(cornerRadius: KuroRadius.md) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("MATCHES")
                                        .font(.kuroCaption(weight: .medium))
                                        .tracking(1.6)
                                        .foregroundColor(.black.opacity(0.55))
                                    Spacer()
                                    Text("\(items.count)")
                                        .font(.kuroCaption(weight: .medium))
                                        .foregroundColor(.black.opacity(0.45))
                                }

                                VStack(spacing: 10) {
                                    ForEach(items) { item in
                                        ConciergeMatchRow(
                                            item: item,
                                            chosen: selected(item),
                                            onSelect: { cand in onSelect(item, cand) }
                                        )
                                    }
                                }
                            }
                            .padding(14)
                        }
                        .frame(maxWidth: 420, alignment: .leading)
                    }

	                    if let sets = message.recommendationSets, !sets.isEmpty {
	                        VStack(alignment: .leading, spacing: 18) {
	                            ForEach(sets, id: \.id) { set in
	                                let items = (set.items ?? [])
	                                if !items.isEmpty {
	                                    let curated = ConciergeCuratedCopy.titleAndSubtitle(for: set.modeId, fallbackTitle: set.title)
	                                    let title = (set.displayTitle ?? curated?.0 ?? set.title).trimmingCharacters(in: .whitespacesAndNewlines)
	                                    RecommendationRail(
	                                        title: title.isEmpty ? "Selections" : title,
	                                        subtitle: set.displaySubtitle ?? curated?.1,
	                                        items: items,
	                                        onOpen: { onOpenRecommendation($0) },
	                                        onSave: { onQuickSave($0) },
	                                        onHide: nil
	                                    )
	                                }
	                            }
	                        }
	                        .frame(maxWidth: 520, alignment: .leading)
	                    } else if let recs = message.recommendations, !recs.isEmpty {
	                        VStack(alignment: .leading, spacing: 14) {
	                            RecommendationRail(
	                                title: "Selections",
	                                subtitle: nil,
	                                items: recs,
	                                onOpen: { onOpenRecommendation($0) },
	                                onSave: { onQuickSave($0) },
	                                onHide: nil
	                            )
	                        }
	                        .frame(maxWidth: 520, alignment: .leading)
	                    }
                }
                Spacer(minLength: 40)
            } else {
                // User bubble — direct black fill, no glass wrapper
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.kuroBody())
                    .foregroundColor(.white.opacity(0.92))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black)
                            .overlay(
                                RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.0), lineWidth: 0.6)
                            )
                    )
                    .frame(maxWidth: 360, alignment: .trailing)
            }
        }
    }

    @ViewBuilder
    private func ambiguityCard(ambiguity: SupabaseService.ConciergeAmbiguity, sourceText: String) -> some View {
        switch ambiguity.kind {
        case "status_unclear":
            glassBubble(cornerRadius: KuroRadius.md) {
                ConciergeStatusClarifyCard(
                    titleContext: ambiguity.title_context
                ) { status in
                    onClarifyAmbiguity?(ambiguity.kind, status, sourceText)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }

        case "unit_unclear":
            glassBubble(cornerRadius: KuroRadius.md) {
                ConciergeUnitClarifyCard(
                    numberContext: ambiguity.number_context
                ) { unit in
                    onClarifyAmbiguity?(ambiguity.kind, unit, sourceText)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }

        case "intent_unclear":
            glassBubble(cornerRadius: KuroRadius.md) {
                ConciergeIntentClarifyCard(
                    titleContext: ambiguity.title_context
                ) { intent in
                    onClarifyAmbiguity?(ambiguity.kind, intent, sourceText)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }

        default:
            EmptyView()
        }
    }
}

// MARK: - Inline Confirm Bubble (with Import Reconciliation)

struct ConciergeConfirmBubble: View {
    let items: [SupabaseService.ConciergeParseItem]
    let selected: (SupabaseService.ConciergeParseItem) -> SupabaseService.ConciergeCandidate?
    let onSelect: (SupabaseService.ConciergeParseItem, SupabaseService.ConciergeCandidate) -> Void
    let onConfirm: () -> Void
    var onReparse: (() -> Void)? = nil
    var isApplied: Bool = false
    var autoReasonByItemId: [String: String] = [:]
    var itemActions: [String: ImportItemAction] = [:]
    @Binding var excludedItemIds: Set<String>

    private func actionFor(_ item: SupabaseService.ConciergeParseItem) -> ImportItemAction {
        itemActions[item.id] ?? .add
    }

    private var addItems: [SupabaseService.ConciergeParseItem] {
        items.filter { actionFor($0) == .add }
    }
    private var updateItems: [SupabaseService.ConciergeParseItem] {
        items.filter { actionFor($0) == .update }
    }
    private var skipItems: [SupabaseService.ConciergeParseItem] {
        items.filter { actionFor($0) == .skip }
    }

    private var confirmableCount: Int {
        items.reduce(0) { acc, item in
            let action = actionFor(item)
            if action == .skip { return acc }
            if excludedItemIds.contains(item.id) { return acc }
            if selected(item) == nil { return acc }
            return acc + 1
        }
    }

    private var selectedByItemId: [String: SupabaseService.ConciergeCandidate] {
        Dictionary(
            uniqueKeysWithValues: items.compactMap { item in
                guard let c = selected(item) else { return nil }
                return (item.id, c)
            }
        )
    }

    private var autoSelectedIds: Set<String> {
        Set(items.compactMap { item in
            guard let c = selected(item) else { return nil }
            if excludedItemIds.contains(item.id) { return nil }
            if actionFor(item) == .skip { return nil }
            return (c.score >= 0.85 || autoReasonByItemId[item.id] != nil) ? item.id : nil
        })
    }

    private var actionableCount: Int {
        addItems.count + updateItems.count
    }

    private func glassBubble<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                    .fill(Color.kuroSecondaryBackground.opacity(0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                            .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 8)
            )
            .clipShape(RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous))
    }

    var body: some View {
        glassBubble {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    Rectangle()
                        .fill(Color.black.opacity(0.44))
                        .frame(width: 1.5, height: 18)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("IMPORT REVIEW")
                            .font(.kuroMicro(weight: .medium))
                            .tracking(2.0)
                            .foregroundStyle(.secondary.opacity(0.88))
                        Text("Review matches and confirm changes.")
                            .font(.kuroCaption(weight: .light))
                            .foregroundColor(.black.opacity(0.52))
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(items.count)")
                            .font(.kuroMicro(weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary.opacity(0.75))
                        Text("items")
                            .font(.kuroMicro(weight: .medium))
                            .foregroundStyle(.secondary.opacity(0.42))
                    }
                }
                .padding(.bottom, 12)

                HStack(spacing: 8) {
                    if !addItems.isEmpty {
                        summaryPill("NEW", count: addItems.count)
                    }
                    if !updateItems.isEmpty {
                        summaryPill("UPDATE", count: updateItems.count)
                    }
                    if !skipItems.isEmpty {
                        summaryPill("UNCHANGED", count: skipItems.count)
                    }
                }
                .padding(.bottom, 10)

                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 0.5)
                    .padding(.bottom, 12)

                ImportCardContainer(
                    items: items,
                    selectedByItemId: selectedByItemId,
                    autoSelectedIds: autoSelectedIds,
                    autoReasonByItemId: autoReasonByItemId,
                    itemActions: itemActions,
                    excludedItemIds: excludedItemIds,
                    onSelect: { item, candidate in onSelect(item, candidate) },
                    onToggleExclude: { toggleExclude($0) }
                )

                if isApplied {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.kuroCaption(weight: .medium))
                        Text("APPLIED TO LIBRARY")
                            .font(.kuroCaption(weight: .medium))
                            .tracking(1.6)
                    }
                    .foregroundColor(.black.opacity(0.58))
                    .padding(.top, 16)
                } else {
                    HStack(spacing: 10) {
                        // Re-parse: show when many items have low confidence
                        if showReparse, let reparse = onReparse {
                            Button(action: {
                                KuroAccessibility.impactHaptic(.light)
                                reparse()
                            }) {
                                Text("RE-PARSE")
                                    .font(.kuroCaption(weight: .medium))
                                    .tracking(1.6)
                                    .foregroundColor(.black.opacity(0.62))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 11)
                                    .background(
                                        RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous)
                                            .fill(Color.black.opacity(0.04))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous)
                                                    .stroke(Color.black.opacity(0.08), lineWidth: 0.8)
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Re-parse import text")
                        }

                        Button(action: {
                            KuroAccessibility.impactHaptic(.medium)
                            onConfirm()
                        }) {
                            HStack(spacing: 8) {
                                Text("CONFIRM")
                                    .font(.kuroCaption(weight: .medium))
                                    .tracking(2.0)

                                Text("\(confirmableCount)")
                                    .font(.kuroMicro(weight: .semibold))
                                    .monospacedDigit()
                            }
                            .foregroundColor(confirmableCount > 0 ? .white : .white.opacity(0.40))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(confirmableCount > 0 ? Color.black.opacity(0.88) : Color.black.opacity(0.10))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(confirmableCount == 0)
                    }
                    .padding(.top, 16)

                    Text("\(confirmableCount) of \(actionableCount) ready to apply")
                        .font(.kuroCaption(weight: .light))
                        .foregroundColor(.black.opacity(0.46))
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
    }

    /// Show re-parse when 2+ actionable items have low confidence (< 0.70).
    private var showReparse: Bool {
        let lowConfidenceCount = items.filter { item in
            let action = actionFor(item)
            guard action != .skip else { return false }
            guard let c = selected(item) else { return true }
            return c.score < 0.70
        }.count
        return lowConfidenceCount >= 2
    }

    private func toggleExclude(_ id: String) {
        KuroAccessibility.impactHaptic(.light)
        if excludedItemIds.contains(id) {
            excludedItemIds.remove(id)
        } else {
            excludedItemIds.insert(id)
        }
    }

    private func summaryPill(_ title: String, count: Int) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.kuroMicro(weight: .medium))
                .tracking(1.1)
            Text("\(count)")
                .font(.kuroMicro(weight: .medium))
                .monospacedDigit()
        }
        .foregroundColor(.black.opacity(0.48))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.04))
        )
    }
}

// MARK: - Match Row

private struct ConciergeMatchRow: View {
    let item: SupabaseService.ConciergeParseItem
    let chosen: SupabaseService.ConciergeCandidate?
    let onSelect: (SupabaseService.ConciergeCandidate) -> Void

    @State private var expanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.normalized.isEmpty ? item.raw : item.normalized)
                        .font(.kuroBody(weight: .regular))
                        .foregroundColor(.black.opacity(0.90))
                        .lineLimit(2)

                    if let c = chosen {
                        Text(c.title_raw)
                            .font(.kuroCaption())
                            .foregroundColor(.black.opacity(0.55))
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)

                if item.candidates.count > 1 {
                    Button(action: { withAnimation(KuroAnimation.fast) { expanded.toggle() } }) {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.kuroCaption(weight: .semibold))
                            .foregroundColor(.black.opacity(0.4))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.black.opacity(0.04)))
                    }
                    .buttonStyle(.plain)
                }
            }

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(item.candidates.prefix(4), id: \.media_id) { cand in
                        Button(action: { onSelect(cand) }) {
                            HStack(spacing: 10) {
                                // Radio dot
                                Circle()
                                    .fill(chosen?.media_id == cand.media_id ? Color.black : Color.clear)
                                    .frame(width: 8, height: 8)
                                    .overlay(
                                        Circle().strokeBorder(Color.black.opacity(0.3), lineWidth: 1)
                                    )

                                Text(cand.title_raw)
                                    .font(.kuroCaption())
                                    .foregroundColor(.black.opacity(0.82))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                if let year = cand.year {
                                    Text(String(year))
                                        .font(.kuroCaption())
                                        .foregroundColor(.black.opacity(0.45))
                                }
                                Text("\(Int(cand.score * 100))%")
                                    .font(.kuroCaption(weight: .medium))
                                    .foregroundColor(.black.opacity(0.45))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous)
                                    .fill(Color.black.opacity(chosen?.media_id == cand.media_id ? 0.06 : 0.03))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
