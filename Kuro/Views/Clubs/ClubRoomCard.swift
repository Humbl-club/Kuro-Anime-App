import SwiftUI

// MARK: - Club room card (Clubs list; spec §7.1)
// One compact room per club, the same dark surface as Home's room and the club page's hero:
// masthead (seal, audience kicker, serif name, unread dot, a fan of the club's real covers), the meta
// line on its own (member fills where the sharing level allows them, then members · rails · polls), and
// Home's dark activity row when the server sent a readable preview. The whole room is one button.
//
// Data honesty (lane decisions, recorded in the lane report):
// - The fan draws only real covers (no empty slots, P11).
// - The activity row carries no cover: the newest cover can belong to another rail item than the
//   preview's title (Home's room makes the same call, `HomeClubRoom` header).
// - `poll_count` counts open and closed polls, so the meta says "polls", not "open polls".
// - Private clubs keep "never list member initials" (`ClubsListCardRules.memberInitials`).

struct ClubRoomCard: View {
    let club: ClubListRow
    let hasUnseen: Bool
    let now: Date

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var roomWidth: CGFloat = 0

    private var compact: Bool { HomeClubRoom.isCompact(width: roomWidth) }
    private var german: Bool { KuroLocale.isGerman }

    private var covers: [URL] {
        (club.cover_images ?? []).compactMap(URL.init(string:)).prefix(compact ? 2 : 3).map { $0 }
    }

    private var initials: [String] {
        Array(ClubsListCardRules.memberInitials(sharingLevel: club.sharing_level, memberNames: club.member_names).prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            masthead
            metaLine
                .padding(.top, 12)
            if let line = ClubsListCardRules.recentLine(club.activity_preview, german: german) {
                activityRow(line)
                    .padding(.top, 10)
            }
        }
        .padding(.top, 18)
        .padding(.horizontal, compact ? 12 : 16)
        .padding(.bottom, ClubsListCardRules.recentLine(club.activity_preview, german: german) == nil ? 16 : 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { ClubRoomBackground(cornerRadius: 24) }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { roomWidth = $0 }
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: Masthead

    @ViewBuilder
    private var masthead: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        HStack(alignment: .center, spacing: compact ? 8 : 10) {
            ClubSeal(ring: ClubSeal.ring(compact: compact))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(ClubsListCardRules.audienceLabel(sharingLevel: club.sharing_level, german: german))
                    .font(.kuroCustom(7, relativeTo: .caption2, maxSize: 14))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(ClubRoomPalette.kicker)
                name
                if stacked && !covers.isEmpty { fan.padding(.top, 6) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !stacked && !covers.isEmpty { fan }
        }
    }

    private var name: some View {
        Text(nameText)
            .font(.kuroEditorial(size: compact ? 19 : 22))
            .tracking(-0.6)
            .foregroundStyle(ClubRoomPalette.text)
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The name, then (unread) a small monochrome dot after its last word.
    private var nameText: AttributedString {
        var text = AttributedString(club.name)
        guard hasUnseen else { return text }
        var dot = AttributedString("\u{2009}\u{25CF}")
        dot.font = .kuroCustom(7, relativeTo: .caption2, maxSize: 12)
        dot.baselineOffset = 5
        text.append(dot)
        return text
    }

    private var fan: some View {
        HStack(spacing: ClubRoomLayout.fanOverlap) {
            ForEach(Array(covers.enumerated()), id: \.offset) { _, url in
                KuroCachedAsyncImage(url: url, maxPixelSize: 120) { phase in
                    if case .success(let image) = phase { image.resizable().scaledToFill() }
                    else { HomeInk.posterFill }
                }
                .frame(width: ClubRoomLayout.fanCover.width, height: ClubRoomLayout.fanCover.height)
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous).strokeBorder(ClubRoomPalette.memberRim, lineWidth: 1.5))
                .shadow(color: Color.black.opacity(Double(0x2A) / 255), radius: 1.5, x: -2, y: 0)
            }
        }
        .padding(.leading, 8)
        .accessibilityHidden(true)
    }

    // MARK: Meta

    private var metaLine: some View {
        let meta = ClubRoomCopy.listMeta(memberCount: club.member_count, railCount: club.rail_count,
                                         pollCount: club.poll_count, german: german)
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        return layout {
            if !initials.isEmpty {
                ClubMemberFills(initials: initials, size: 22)
            }
            if !meta.isEmpty {
                Text(meta)
                    .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20))
                    .foregroundStyle(ClubRoomPalette.rowSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Activity row (Home's dark row)

    private func activityRow(_ line: String) -> some View {
        let ago = club.last_activity_at.flatMap(ClubDates.parse).flatMap { HomeClubRoom.timeAgo($0, now: now, german: german) }
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(line)
                    .font(.kuroCustom(11, weight: .medium, relativeTo: .caption1, maxSize: 22))
                    .foregroundStyle(ClubRoomPalette.rowInk)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let ago {
                    Text(ago)
                        .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20))
                        .foregroundStyle(ClubRoomPalette.rowSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.kuroCustom(13, weight: .medium, relativeTo: .footnote, maxSize: 20))
                .foregroundStyle(ClubRoomPalette.rowInk)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 2)
        .frame(minHeight: 56)
        .overlay(alignment: .top) { Rectangle().fill(ClubRoomPalette.footerRule).frame(height: 1) }
        .accessibilityHidden(true)
    }
}

// MARK: - Skeleton (spec §7.5)

/// Two rooms drawn with skeleton blocks (`ClubRoomPalette.text` @ .08 / .13 on the room), then the
/// branded scrub line. Replaces the white card skeleton.
struct ClubRoomSkeleton: View {
    var rooms: Int = 2

    private var block: Color { ClubRoomPalette.text.opacity(KuroSkeleton.blockInkOpacity) }
    private var deep: Color { ClubRoomPalette.text.opacity(KuroSkeleton.deepBlockInkOpacity) }

    var body: some View {
        VStack(alignment: .leading, spacing: ClubRoomLayout.roomGap) {
            ForEach(0..<rooms, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Circle().fill(deep).frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 6) {
                            Capsule().fill(block).frame(width: 72, height: 7)
                            Capsule().fill(deep).frame(width: 150, height: 16)
                        }
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 2).fill(block).frame(width: 30, height: 44)
                    }
                    HStack(spacing: 8) {
                        Circle().fill(block).frame(width: 22, height: 22)
                        Capsule().fill(block).frame(width: 140, height: 9)
                    }
                }
                .padding(EdgeInsets(top: 18, leading: 16, bottom: 16, trailing: 16))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background { ClubRoomBackground(cornerRadius: 24) }
            }
            KuroScrubLine().frame(maxWidth: 96)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(KuroLocale.text("Loading your clubs", "Deine Clubs werden geladen"))
    }
}
