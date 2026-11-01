import SwiftUI

// MARK: - Club detail shell
// The club's identity surface is the dark neutral room (`kuroRoom`, rulebook §3.2/§14.7): real rail
// artwork, the club name in serif, the honest audience line, member initials and one member note on
// a light card, hidden until tapped (notes can spoil). Tab content sits on the white page below.
// No blur, glass, parallax or decorative motion.

// MARK: - Status bar

/// Close and settings over the room; once the room has scrolled away the bar turns white with the
/// club name. Both controls are 44 pt circles that keep contrast on either ground.
struct JournalStatusBar: View {
    let clubName: String
    let scrollOffset: CGFloat
    let heroHeight: CGFloat
    let safeTop: CGFloat
    let onBack: () -> Void
    let onSettings: () -> Void

    private var progress: CGFloat {
        min(1, max(0, (-scrollOffset - (heroHeight - 120)) / 40))
    }

    private var isOverPage: Bool { progress > 0.5 }

    var body: some View {
        VStack(spacing: 0) {
            Color.kuroCanvasPage.opacity(Double(progress))
                .frame(height: safeTop)

            HStack(spacing: KuroDesignSpacing.sm) {
                ClubCircleButton(systemImage: "xmark",
                                 label: KuroLocale.text("Close", "Schließen"),
                                 onRoom: !isOverPage,
                                 action: onBack)
                Spacer(minLength: 0)
                if isOverPage {
                    Text(clubName)
                        .font(.kuroTitleName(weight: .medium))
                        .foregroundStyle(Color.kuroInk)
                        .lineLimit(1)
                        .opacity(max(0, Double(progress - 0.5) * 2))
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
                ClubCircleButton(systemImage: "ellipsis",
                                 label: KuroLocale.text("Club settings", "Clubeinstellungen"),
                                 onRoom: !isOverPage,
                                 action: onSettings)
            }
            .padding(.horizontal, KuroDesignSpacing.md)
            .frame(minHeight: 52)
            .background(Color.kuroCanvasPage.opacity(Double(progress)))

            Rectangle()
                .fill(Color.kuroHairline)
                .frame(height: 1)
                .opacity(progress > 0.8 ? 1 : 0)
        }
        .kuroAnimation(KuroMotion.settle, value: isOverPage)
    }
}

/// A 44 pt circular control: white on the room, ink on the page.
struct ClubCircleButton: View {
    let systemImage: String
    let label: String
    let onRoom: Bool
    let action: () -> Void

    var body: some View {
        Button {
            KuroAccessibility.impactHaptic(.light)
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.kuroCustom(16, weight: .medium, relativeTo: .body, maxSize: 22))
                .foregroundStyle(onRoom ? Color.kuroRoomText : Color.kuroInk)
                .frame(width: 44, height: 44)
                .background(
                    Circle().fill(onRoom ? Color.kuroWhite15 : Color.kuroCanvasQuiet)
                )
                .contentShape(Circle())
        }
        .buttonStyle(KuroPressStyle())
        .accessibilityLabel(label)
    }
}

// MARK: - Room hero

struct JournalHeroSection: View {
    let bundle: ClubBundle
    /// Space above the content (status bar plus the controls row).
    let topInset: CGFloat

    private var coverURLs: [URL] {
        bundle.rails
            .flatMap(\.items)
            .compactMap { $0.cover_image_medium.flatMap(URL.init(string:)) }
            .prefix(4)
            .map { $0 }
    }

    private var openPollCount: Int { bundle.polls.filter { !$0.is_closed }.count }

    private var initials: [String] {
        ClubsListCardRules.memberInitials(
            sharingLevel: bundle.club.sharing_level,
            memberNames: bundle.members.map { $0.display_name ?? "" }.filter { !$0.isEmpty }
        )
    }

    private var summary: String {
        ClubRoomCopy.summary(memberCount: bundle.member_count, railCount: bundle.rails.count,
                             openPolls: openPollCount, german: KuroLocale.isGerman)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
            ClubArtStrip(urls: coverURLs, monogram: String(bundle.club.name.prefix(1)), maxPixelSize: 360)
                .clipShape(RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                Text(ClubsListCardRules.audienceLabel(sharingLevel: bundle.club.sharing_level, german: KuroLocale.isGerman))
                    .font(.kuroMicro(weight: .medium))
                    .tracking(2.1)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.kuroRoomTextSecondary)

                Text(bundle.club.name)
                    .font(.kuroFeature(weight: .light))
                    .foregroundStyle(Color.kuroRoomText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                if let desc = bundle.club.description?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
                    Text(desc)
                        .font(.kuroBody(weight: .light))
                        .foregroundStyle(Color.kuroRoomTextSecondary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: KuroDesignSpacing.sm) {
                        if !initials.isEmpty {
                            ClubInitialsRow(initials: initials, total: bundle.member_count, onRoom: true)
                        }
                        summaryText
                    }
                    VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                        if !initials.isEmpty {
                            ClubInitialsRow(initials: initials, total: bundle.member_count, onRoom: true)
                        }
                        summaryText
                    }
                }
            }

            if let note = ClubRoomCopy.firstNote(in: bundle) {
                ClubNoteCard(note: note.text, author: note.author, title: note.title)
                    // A different (or edited) note is a new card: it starts hidden again.
                    .id(note.itemId + "\u{1F}" + note.text)
            }
        }
        .padding(.horizontal, KuroDesignSpacing.padding)
        .padding(.top, topInset)
        .padding(.bottom, KuroDesignSpacing.lg)
        // iPad: the room stays full-bleed; its art and text keep the readable column (spec D3).
        .kuroReadableWidth()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.kuroRoom)
    }

    private var summaryText: some View {
        Text(summary)
            .font(.kuroMeta())
            .foregroundStyle(Color.kuroRoomTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Note card

/// A member's note on a light card. Notes may spoil, so the text stays hidden until tapped.
struct ClubNoteCard: View {
    let note: String
    let author: String?
    let title: String

    @State private var isRevealed = false

    private var byline: String {
        let german = KuroLocale.isGerman
        let who = author ?? (german ? "Ein Mitglied" : "A member")
        return german ? "\(who) zu \(title)" : "\(who) on \(title)"
    }

    var body: some View {
        Button {
            guard !isRevealed else { return }
            KuroAccessibility.impactHaptic(.light)
            withAnimation(KuroMotion.resolve(KuroMotion.settle)) { isRevealed = true }
        } label: {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                Text(byline)
                    .font(.kuroMeta(weight: .medium))
                    .foregroundStyle(Color.kuroInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if isRevealed {
                    Text(note)
                        .font(.kuroTitle(weight: .regular))
                        .foregroundStyle(Color.kuroInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                } else {
                    HStack(spacing: KuroDesignSpacing.sm) {
                        Image(systemName: "eye.slash")
                            .font(.kuroMeta())
                        Text(KuroLocale.text("May contain spoilers. Tap to read.", "Kann spoilern. Tippen zum Lesen."))
                            .font(.kuroMeta())
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(Color.kuroInkQuiet)
                }
            }
            .padding(KuroDesignSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                    .fill(Color.kuroCanvasPage)
            )
            .overlay(
                RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                    .strokeBorder(Color.kuroHairline, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous))
        }
        .buttonStyle(KuroPressStyle(pressedScale: 0.99))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isRevealed ? "\(byline): \(note)" : byline)
        .accessibilityHint(isRevealed ? "" : KuroLocale.text("May contain spoilers. Double-tap to read.", "Kann spoilern. Doppeltippen zum Lesen."))
        .accessibilityAddTraits(isRevealed ? [] : .isButton)
    }
}

// MARK: - Bottom bar

/// The club's actions as a solid white capsule with a hairline (no glass): add to a rail and start
/// a poll for owners/admins, invite for everyone. Every target is 44 pt.
struct JournalBottomBar: View {
    let role: String
    let isConnected: Bool
    let onAdd: () -> Void
    let onInvite: () -> Void
    let onPoll: () -> Void

    private var isAdminOrOwner: Bool {
        ["owner", "admin"].contains(role)
    }

    var body: some View {
        HStack(spacing: KuroDesignSpacing.xs) {
            if isAdminOrOwner {
                bottomBarButton(icon: "plus", label: KuroLocale.text("Add a title", "Titel hinzufügen"), action: onAdd)
                divider
            }

            bottomBarButton(icon: "person.badge.plus", label: KuroLocale.text("Invite members", "Mitglieder einladen"), action: onInvite)

            if isAdminOrOwner {
                divider
                bottomBarButton(icon: "chart.bar", label: KuroLocale.text("Start a poll", "Umfrage starten"), action: onPoll)
            }
        }
        .padding(.horizontal, KuroDesignSpacing.md)
        .padding(.vertical, KuroDesignSpacing.xs)
        .background(
            Capsule(style: .continuous)
                .fill(Color.kuroCanvasPage)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.kuroHairline, lineWidth: 1)
                )
                .shadow(color: Color.kuroBlack08, radius: 12, x: 0, y: 4)
        )
        .opacity(isConnected ? 1.0 : 0.5)
        .disabled(!isConnected)
        .accessibilityElement(children: .contain)
    }

    private func bottomBarButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            KuroAccessibility.impactHaptic(.light)
            action()
        } label: {
            Image(systemName: icon)
                .font(.kuroCustom(18, weight: .regular, relativeTo: .title3, maxSize: 26))
                .foregroundStyle(Color.kuroInk)
                .frame(minWidth: 48, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(KuroPressStyle())
        .accessibilityLabel(label)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.kuroHairline)
            .frame(width: 1, height: 20)
            .accessibilityHidden(true)
    }
}
