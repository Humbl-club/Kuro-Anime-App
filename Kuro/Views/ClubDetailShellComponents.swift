import KuroCore
import SwiftUI

// MARK: - Club detail shell
// Discover + Clubs redesign (spec §7.3): the club's identity surface is the same dark room as Home's
// and the Clubs list (`ClubRoomBackground`), full-bleed with a rounded foot: seal and kicker, the club
// name in serif, the description, a "You" ring and the other members' positional fills, and the one
// member note (D11) on Home's warm note card, spoiler-gated. Under it, on Home's warm paper, the
// labelled keys (D9, D10) and the tabs. No blur, glass, parallax or decorative motion.

// MARK: - Status bar (journey chrome)

/// The club page's rules for its chrome (navigation contract N1–N3, H1–H3). Pure (NavclubsTests).
nonisolated enum ClubChromeRules {
    /// How far the collapse runs once it starts (pt of scroll).
    static let collapseDistance: CGFloat = 60

    /// The scroll offset at which the paper bar starts to fade in: shortly before the room's bottom
    /// edge reaches the bar, so the bar is complete just after the room has gone.
    static func collapseStart(heroHeight: CGFloat) -> CGFloat {
        max(0, heroHeight - 140)
    }

    /// Back is drawn only on a pushed club page (the first page of a journey shows ✕ only).
    static func showsBack(isPushed: Bool) -> Bool { isPushed }

    /// The controls sit on the room (white circles) until the bar is half drawn, then on the paper bar
    /// (plain ink glyphs).
    static func controlsOnRoom(_ shownProgress: CGFloat) -> Bool { shownProgress < 0.5 }
}

/// Back (pushed pages only), then the club name, settings and ✕ over the room; once the room has
/// scrolled away the prototype's paper bar with a hairline fades in with the club name. The progress
/// is the foundation's `KuroCollapse` (tied to the scroll offset; Reduce Motion snaps half way with a
/// short cross-fade). Every control is 44 pt and stays put at every offset (H2). ✕ closes the whole
/// journey (N3); outside a journey it dismisses the sheet.
struct JournalStatusBar: View {
    let clubName: String
    /// Raw collapse progress 0...1 (`kuroCollapseTracking`); 0 while the club is loading.
    let progress: CGFloat
    /// nil while the club is loading (no settings to show yet).
    let onSettings: (() -> Void)?

    @Environment(\.kuroJourney) private var journey
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shown = KuroCollapse.displayProgress(progress, reduceMotion: reduceMotion)
        let onRoom = ClubChromeRules.controlsOnRoom(shown)
        let showsBack = ClubChromeRules.showsBack(isPushed: journey?.isPushed == true)
        HStack(spacing: KuroDesignSpacing.sm) {
            if showsBack {
                ClubCircleButton(systemImage: "chevron.left",
                                 label: KuroLocale.text("Back", "Zurück"),
                                 onRoom: onRoom,
                                 plainOnPage: true) { journey?.pop() }
            }
            Text(clubName)
                .font(.kuroTitleName(weight: .medium))
                .foregroundStyle(Color.kuroInk)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, showsBack ? 0 : KuroDesignSpacing.sm)
                .opacity(Double(shown))
                .accessibilityAddTraits(.isHeader)
                .accessibilityHidden(shown < 0.5)
            if let onSettings {
                ClubCircleButton(systemImage: "ellipsis",
                                 label: KuroLocale.text("Club settings", "Clubeinstellungen"),
                                 onRoom: onRoom,
                                 plainOnPage: true,
                                 action: onSettings)
            }
            ClubCircleButton(systemImage: "xmark",
                             label: KuroLocale.text("Close", "Schließen"),
                             onRoom: onRoom,
                             plainOnPage: true) {
                if let journey { journey.closeOrDismiss { dismiss() } } else { dismiss() }
            }
        }
        .padding(.horizontal, KuroDesignSpacing.md)
        .frame(height: KuroJourneyChrome.barHeight)
        .background(alignment: .bottom) {
            Color.kuroPaper
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.kuroLine).frame(height: 0.5)
                }
                .ignoresSafeArea(edges: .top)
                .opacity(Double(shown))
                .allowsHitTesting(false)
        }
        // Back (or the club name once shown) first after a push or pop, before the club's content.
        .accessibilityElement(children: .contain)
        .accessibilitySortPriority(1)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : nil, value: shown)
        .kuroAnimation(KuroMotion.settle, value: onRoom)
    }
}

/// A 44 pt circular control: white on the room, ink on the page (a quiet disc, or a plain ink glyph
/// in the journey's compact bar with `plainOnPage`).
struct ClubCircleButton: View {
    let systemImage: String
    let label: String
    let onRoom: Bool
    var plainOnPage: Bool = false
    let action: () -> Void

    private var fill: Color {
        if onRoom { return Color.kuroWhite15 }
        return plainOnPage ? Color.clear : Color.kuroCanvasQuiet
    }

    var body: some View {
        Button {
            KuroAccessibility.impactHaptic(.light)
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.kuroCustom(16, weight: .medium, relativeTo: .body, maxSize: 22))
                .foregroundStyle(onRoom ? Color.kuroRoomText : Color.kuroInk)
                .frame(width: 44, height: 44)
                .background(Circle().fill(fill))
                .contentShape(Circle())
        }
        .buttonStyle(KuroPressStyle())
        .accessibilityLabel(label)
    }
}

// MARK: - Room hero (spec §7.3)

struct JournalHeroSection: View {
    let bundle: ClubBundle
    /// The viewer's user id (the "You" ring; D13).
    let viewerId: String?
    /// Space above the content (status bar plus the controls row).
    let topInset: CGFloat
    let compact: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The note card's scroll anchor ("{name}'s note ↑" scrolls here).
    static let noteAnchor = "club.hero.note"

    private var german: Bool { KuroLocale.isGerman }
    private var openPollCount: Int { bundle.polls.filter { !$0.is_closed }.count }

    /// The other members' initials (never for a private club: `ClubsListCardRules.memberInitials`).
    private var others: [String] {
        let names = ClubRoomRules.otherMembers(bundle.members, viewerId: viewerId)
            .compactMap { $0.display_name?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return ClubsListCardRules.memberInitials(sharingLevel: bundle.club.sharing_level, memberNames: names)
    }

    private var summary: String {
        ClubRoomCopy.summary(memberCount: bundle.member_count, railCount: bundle.rails.count,
                             openPolls: openPollCount, german: german)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: compact ? 8 : 10) {
                ClubSeal(ring: ClubSeal.ring(compact: compact))
                    .accessibilityHidden(true)
                Text(ClubRoomCopy.heroKicker(sharingLevel: bundle.club.sharing_level, german: german))
                    .font(.kuroCustom(7, relativeTo: .caption2, maxSize: 14))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(ClubRoomPalette.kicker)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            Text(bundle.club.name)
                .font(.kuroEditorial(size: compact ? 26 : 30))
                .tracking(-0.9)
                .foregroundStyle(ClubRoomPalette.text)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 14)

            if let desc = bundle.club.description?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
                Text(desc)
                    .font(.kuroCustom(12, relativeTo: .footnote, maxSize: 24))
                    .foregroundStyle(ClubRoomPalette.rowSecondary)
                    .lineSpacing(2)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }

            memberRow
                .padding(.top, 13)

            if let note = ClubRoomCopy.firstNote(in: bundle) {
                ClubHeroNoteCard(note: note, item: item(note.itemId), rail: rail(of: note.itemId), compact: compact)
                    // A different (or edited) note is a new card: it starts hidden again.
                    .id(note.itemId + "\u{1F}" + note.text)
                    .padding(.top, 16)
                    .id(Self.noteAnchor)
            }
        }
        .padding(.top, topInset)
        .padding(.horizontal, ClubRoomLayout.heroPadding(compact: compact).leading)
        .padding(.bottom, ClubRoomLayout.heroPadding(compact: compact).bottom)
        // iPad: the room stays full-bleed; its text keeps the readable column.
        .kuroReadableWidth()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ClubRoomBackground(cornerRadius: 24, topCornerRadius: 0).ignoresSafeArea(edges: .top))
    }

    private func item(_ id: String) -> ClubRailItem? {
        bundle.rails.lazy.flatMap(\.items).first { $0.id == id }
    }

    private func rail(of itemId: String) -> ClubRail? {
        bundle.rails.first { $0.items.contains { $0.id == itemId } }
    }

    // MARK: Members

    private var memberRow: some View {
        let shown = Array(others.prefix(4))
        let overflow = max(0, bundle.member_count - 1 - shown.count)
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        return layout {
            HStack(spacing: -6) {
                Text(ClubRoomCopy.you(german: german))
                    .font(.kuroCustom(6.5, weight: .semibold, relativeTo: .caption2, maxSize: 12))
                    .foregroundStyle(ClubRoomPalette.text)
                    .frame(width: 24, height: 24)
                    .overlay(Circle().strokeBorder(ClubRoomPalette.text.opacity(0.6), lineWidth: 1))
                    .background(Circle().fill(ClubRoomPalette.room))
                ClubMemberFills(initials: shown, size: 22, overflow: shown.isEmpty ? 0 : overflow)
                    .padding(.leading, 9)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ClubRoomCopy.youAndMembers(memberCount: bundle.member_count, german: german))
            Text(summary)
                .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20))
                .foregroundStyle(ClubRoomPalette.rowSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Hero note card (Home's warm note card; D11)

/// The club's one note: Home's light card (cover, author, the rail, "A note on {title}"), then the
/// existing spoiler gate; opened, the quote in serif. "{title} ›" pushes the title. Rail notes carry
/// no spoiler scope and no time, so the gate stays and no time is shown.
struct ClubHeroNoteCard: View {
    let note: ClubRoomCopy.Note
    let item: ClubRailItem?
    let rail: ClubRail?
    let compact: Bool

    @Environment(\.kuroRoutes) private var routes
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isRevealed = false

    private var german: Bool { KuroLocale.isGerman }
    private var narrow: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        HStack(alignment: .top, spacing: compact ? 11 : 13) {
            HomeCalendarArt(raw: item?.cover_image_medium)
                .frame(width: narrow ? 40 : (compact ? 48 : 60), height: narrow ? 60 : (compact ? 72 : 90))
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .shadow(color: ClubRoomPalette.noteArtShadow, radius: 3, y: 3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(note.author ?? KuroLocale.text("A club member", "Ein Clubmitglied"))
                        .font(.kuroCustom(compact ? 10 : 11, weight: .semibold, relativeTo: .caption1, maxSize: 22))
                        .foregroundStyle(ClubRoomPalette.noteInk)
                    Spacer(minLength: 6)
                    if let rail {
                        Text(rail.title)
                            .font(.kuroCustom(compact ? 9 : 10, relativeTo: .caption2, maxSize: 20))
                            .foregroundStyle(ClubRoomPalette.noteMeta)
                            .lineLimit(1)
                    }
                }
                Text(ClubRoomCopy.noteOn(note.title, german: german))
                    .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20))
                    .foregroundStyle(ClubRoomPalette.noteMeta)
                    .padding(.top, 3)
                    .fixedSize(horizontal: false, vertical: true)

                if isRevealed {
                    Text(KuroLocale.text("“\(note.text)”", "„\(note.text)“"))
                        .font(.kuroEditorial(size: compact ? 16 : 18))
                        .tracking(-0.3)
                        .lineSpacing(3)
                        .foregroundStyle(ClubRoomPalette.noteInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                        .transition(.opacity)
                        .accessibilityLabel(KuroLocale.text("Note by \(note.author ?? "a member"): \(note.text)",
                                                            "Notiz von \(note.author ?? "einem Mitglied"): \(note.text)"))
                } else {
                    spoilerGate
                        .padding(.top, 10)
                }

                if let item {
                    Button {
                        routes.openMedia(MediaRoute(ClubActivityTarget.key(mediaType: item.media_type, mediaId: item.media_id)))
                    } label: {
                        Text("\(note.title) ›")
                            .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20))
                            .foregroundStyle(ClubRoomPalette.noteLink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .padding(.top, 8)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(HomeContactStyle())
                    .accessibilityHint(KuroLocale.text("Opens this title", "Öffnet diesen Titel"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(compact ? 14 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            shape.fill(ClubRoomPalette.note)
                .shadow(color: ClubRoomPalette.noteShadow, radius: 3.5, y: 3)
        }
        .overlay(shape.strokeBorder(ClubRoomPalette.noteBorder, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    /// The existing gate copy ("May contain spoilers. Tap to read.") on Home's spoiler-line face.
    private var spoilerGate: some View {
        Button {
            KuroAccessibility.impactHaptic(.light)
            withAnimation(KuroMotion.resolve(KuroMotion.settle)) { isRevealed = true }
        } label: {
            HStack(spacing: 10) {
                Text(KuroLocale.text("May contain spoilers. Tap to read.", "Kann spoilern. Tippen zum Lesen."))
                    .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20))
                    .foregroundStyle(ClubRoomPalette.quietInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.kuroCustom(12, weight: .regular, relativeTo: .footnote, maxSize: 20))
                    .foregroundStyle(ClubRoomPalette.quietInk)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .frame(minHeight: 46)
            .background(ClubRoomPalette.quiet, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(ClubRoomPalette.quietBorder, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(KuroLocale.text("Note by \(note.author ?? "a member"), may contain spoilers. Double tap to read.",
                                            "Notiz von \(note.author ?? "einem Mitglied"), kann spoilern. Zum Lesen doppeltippen."))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Key row (replaces the floating bottom bar; D9, D10)

/// The club's actions as labelled keys on paper: equal cells 8 apart, each a 44 pt raised light key
/// (`KuroKeyFace(.light)` recipe: radius 7, the light key gradient, #20282326 border, inset highlight,
/// a tight drop), a 15 pt glyph and a 12 pt medium label. Which keys show is `ClubRoomRules.keys`.
/// Offline: drawn at .45 and disabled, VoiceOver value "Offline". Accessibility sizes stack them.
struct ClubKeyRow: View {
    let keys: [ClubRoomRules.Key]
    let compact: Bool
    let isConnected: Bool
    let onKey: (ClubRoomRules.Key) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static func glyph(_ key: ClubRoomRules.Key) -> String {
        switch key {
        case .addTitle, .startRail: return "plus"
        case .invite: return "arrow.up.right"
        case .ask: return "questionmark"
        }
    }

    var body: some View {
        let german = KuroLocale.isGerman
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
        layout {
            ForEach(keys, id: \.self) { key in
                let title = ClubRoomCopy.keyTitle(key, german: german)
                Button {
                    KuroAccessibility.impactHaptic(.light)
                    onKey(key)
                } label: {
                    keyFace(title: title, glyph: Self.glyph(key), iconOver: compact && !stacked && keys.count > 2)
                }
                .buttonStyle(ClubKeyStyle())
                .accessibilityLabel(title)
                .accessibilityValue(isConnected ? "" : KuroLocale.text("Offline", "Offline"))
            }
        }
        .opacity(isConnected ? 1 : 0.45)
        .disabled(!isConnected)
        .accessibilityElement(children: .contain)
    }

    private func keyFace(title: String, glyph: String, iconOver: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        let content = Group {
            Image(systemName: glyph)
                .font(.kuroCustom(iconOver ? 13 : 15, weight: .regular, relativeTo: .subheadline, maxSize: 24))
                .accessibilityHidden(true)
            Text(title)
                .font(.kuroCustom(12, weight: .medium, relativeTo: .footnote, maxSize: 24))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(iconOver ? .center : .leading)
        }
        return Group {
            if iconOver {
                VStack(spacing: 2) { content }
            } else {
                HStack(spacing: 8) { content }
            }
        }
        .foregroundStyle(Color(hex: "29352C"))
        .padding(.horizontal, iconOver ? 4 : 10)
        .padding(.vertical, iconOver ? 5 : 0)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: iconOver ? .center : .leading)
        .background(
            shape.fill(LinearGradient(colors: [.kuroKeyLightTop, .kuroKeyLightBottom], startPoint: .top, endPoint: .bottom))
                .shadow(color: Color(hex: "142319", opacity: Double(0x12) / 255), radius: 0.5, y: 1)
        )
        .overlay(shape.strokeBorder(Color(hex: "202823", opacity: Double(0x26) / 255), lineWidth: 1))
        .overlay(alignment: .top) {
            shape.stroke(Color.white.opacity(Double(0x90) / 255), lineWidth: 1)
                .mask(Rectangle().frame(height: 2).frame(maxHeight: .infinity, alignment: .top))
        }
        .contentShape(shape)
    }
}

/// The key press: Home's pressed key (scale .95, darkened), still under Reduce Motion.
private struct ClubKeyStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.06 : 0)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : KuroMotion.contact, value: configuration.isPressed)
    }
}
