import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - The progress hook on Essentials (usability spec §5.9)
// Under the purpose line, a glance-card-face row (radius 8, 1 pt border, padding 10 / 12): "{k}/{n}" at
// 21 pt mono, then "You've seen {k} of {n}." over "{title} is under way." (one essential Watching /
// Reading) or "{r} to go.", then segments (n ≤ 12; 1 pt gaps, 3 pt tall: Completed and Seen-it in ink, a
// Watching title half, the rest `HomeInk.tileTrack`), a single 3 pt bar above 12. Shown only once k ≥ 1.

/// The hook's numbers (pure).
struct DiscoverProgressModel: Equatable {
    enum Segment: Equatable { case done, half, open }

    let seen: Int
    let total: Int
    /// The first essential under way (Watching / Reading), if any.
    let underWay: String?
    let segments: [Segment]

    var remaining: Int { max(0, total - seen) }
    var shows: Bool { seen >= 1 && total >= 1 }

    /// k = curated items Completed in the Library plus those hidden as Seen it; n = the list minus the
    /// titles hidden as Not interested; half for a title under way.
    static func make(items: [(key: MediaKey, title: String)], status: (MediaKey) -> ListStatus?,
                     hidden: (MediaKey) -> DiscoverFeedback?) -> DiscoverProgressModel {
        var seen = 0
        var underWay: String?
        var segments: [Segment] = []
        for item in items {
            let answer = hidden(item.key)
            if answer == .notInterested { continue }
            let state = status(item.key)
            if state == .completed || answer == .seenIt {
                seen += 1
                segments.append(.done)
            } else if state == .current || state == .repeating {
                if underWay == nil { underWay = item.title }
                segments.append(.half)
            } else {
                segments.append(.open)
            }
        }
        return DiscoverProgressModel(seen: seen, total: segments.count, underWay: underWay, segments: segments)
    }

    /// Segments draw for up to 12 titles; above that one bar.
    static let segmentLimit = 12
}

struct DiscoverProgressHook: View {
    let model: DiscoverProgressModel
    let manga: Bool

    private var german: Bool { KuroLocale.isGerman }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("\(model.seen)/\(model.total)")
                .font(.kuroCustom(21, weight: .medium, relativeTo: .title3, maxSize: 34))
                .monospacedDigit()
                .foregroundStyle(HomeInk.glanceInk)
                .fixedSize()
            VStack(alignment: .leading, spacing: 4) {
                Text(DiscoverIssueCopy.progressHead(seen: model.seen, of: model.total, manga: manga, german: german))
                    .font(.kuroCustom(12, weight: .medium, relativeTo: .footnote, maxSize: 24))
                    .foregroundStyle(HomeInk.glanceInk)
                Text(model.underWay.map { DiscoverIssueCopy.progressUnderWay($0, german: german) }
                     ?? DiscoverIssueCopy.progressToGo(model.remaining, german: german))
                    .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20))
                    .foregroundStyle(HomeInk.glanceMuted)
                    .lineLimit(2)
                segments
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(HomeInk.glanceFill, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(HomeInk.glanceBorder, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DiscoverIssueCopy.progressSpoken(seen: model.seen, of: model.total, manga: manga, german: german))
    }

    @ViewBuilder
    private var segments: some View {
        if model.segments.count <= DiscoverProgressModel.segmentLimit {
            HStack(spacing: 1) {
                ForEach(Array(model.segments.enumerated()), id: \.offset) { _, segment in
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(HomeInk.tileTrack)
                            Rectangle().fill(Color.kuroInk)
                                .frame(width: segment == .done ? geo.size.width : (segment == .half ? geo.size.width / 2 : 0))
                        }
                    }
                    .frame(height: 3)
                }
            }
        } else {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(HomeInk.tileTrack)
                    Rectangle().fill(Color.kuroInk)
                        .frame(width: geo.size.width * CGFloat(model.seen) / CGFloat(max(1, model.total)))
                }
            }
            .frame(height: 3)
        }
    }
}
