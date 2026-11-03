import KuroCore
import SwiftUI

// MARK: - Club week card (spec §7.3.2; Home's `HomeCalendarCard` grammar)
// One rounded card (#FAFCF9, radius 18, 1 pt #D8DDD9, a drop that shows under the bottom edge only)
// holding a row per Berlin day: a 40 × 44 date chip, "Today" / "Yesterday" / the weekday over
// "{n} updates", up to three stacked covers and a ⌃ / ⌄ disclosure. An open day lists its updates as
// white rows inset 63: the cover, "You reached episode 4" (the subject in semibold), the title and the
// 24 h time, ›. A row opens its title (N9). Updates without a date close the card under "Earlier".

struct ClubWeekCard: View {
    let days: [ClubWeekRules.Day]
    let undated: [ClubWeekRules.Entry]
    let now: Date
    /// The first (newest) day starts open; "Earlier" starts closed.
    let openFirst: Bool

    @State private var open: Set<Date> = []
    @State private var seeded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let cardFill = Color(hex: "FAFCF9")
    private static let cardRule = Color(hex: "D8DDD9")
    private static let rowRule = Color(hex: "E3E7E1")
    private static let meta = Color(hex: "68736A")

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        VStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                if index > 0 { Rectangle().fill(Color(hex: "DDE2DD")).frame(height: 1) }
                dayRow(day)
                if open.contains(day.start) {
                    VStack(spacing: 0) {
                        ForEach(day.entries) { entry in entryRow(entry) }
                    }
                    .background(Color.white)
                    .transition(.opacity)
                }
            }
            if !undated.isEmpty {
                if !days.isEmpty { Rectangle().fill(Color(hex: "DDE2DD")).frame(height: 1) }
                VStack(spacing: 0) {
                    ForEach(undated) { entry in entryRow(entry) }
                }
                .background(Color.white)
            }
        }
        .clipShape(shape)
        .background {
            shape.fill(Self.cardFill)
                .background(
                    shape.fill(Color(hex: "1D291C", opacity: Double(0x20) / 255))
                        .padding(4)
                        .offset(y: 2)
                        .blur(radius: 3)
                )
        }
        .overlay(shape.strokeBorder(Self.cardRule, lineWidth: 1))
        .onAppear {
            guard !seeded else { return }
            seeded = true
            if openFirst, let first = days.first { open = [first.start] }
        }
    }

    // MARK: Day row

    private func dayRow(_ day: ClubWeekRules.Day) -> some View {
        let german = KuroLocale.isGerman
        let isOpen = open.contains(day.start)
        let chip = ClubWeekCopy.chip(day.start, german: german)
        let label = ClubWeekCopy.dayLabel(day.start, now: now, german: german)
        let count = ClubWeekCopy.updates(day.entries.count, german: german)
        let covers = Array(day.entries.compactMap(\.coverImage).reduce(into: [String]()) { list, cover in
            if !list.contains(cover) { list.append(cover) }
        }.prefix(3))
        return Button {
            KuroAccessibility.selectionHaptic()
            withAnimation(KuroFold.animation(reduceMotion: reduceMotion)) {
                if isOpen { open.remove(day.start) } else { open.insert(day.start) }
            }
        } label: {
            HStack(spacing: 11) {
                VStack(spacing: 0) {
                    Text(chip.day)
                        .font(.kuroCustom(17, weight: .medium, design: .monospaced, relativeTo: .title3, maxSize: 30))
                        .tracking(-0.6)
                        .foregroundStyle(Color.kuroInk)
                    Text(chip.month)
                        .font(.kuroCustom(8, relativeTo: .caption2, maxSize: 14))
                        .tracking(0.4)
                        .textCase(.uppercase)
                        .foregroundStyle(Color(hex: "667267"))
                }
                .frame(width: 40, height: 44)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(hex: "D4DBD4"), lineWidth: 1))

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.kuroCustom(12, weight: .semibold, relativeTo: .footnote, maxSize: 24))
                        .foregroundStyle(Color.kuroInk)
                    Text(count)
                        .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20))
                        .foregroundStyle(Self.meta)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: -6) {
                    ForEach(covers, id: \.self) { cover in
                        HomeCalendarArt(raw: cover)
                            .frame(width: 23, height: 34)
                            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous).strokeBorder(Color.white, lineWidth: 2))
                            .shadow(color: Color(hex: "243A21", opacity: Double(0x20) / 255), radius: 1.5, x: -2)
                    }
                }
                .accessibilityHidden(true)

                Text(isOpen ? "⌃" : "⌄")
                    .font(.kuroCustom(21, weight: .light, relativeTo: .title3, maxSize: 30))
                    .foregroundStyle(Color(hex: "727D73"))
                    .frame(width: 22)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .frame(minHeight: 76)
            .background(isOpen ? Color.white : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(count)")
        .accessibilityValue(KuroFold.accessibilityValue(expanded: isOpen, german: german))
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Entry row

    private func entryRow(_ entry: ClubWeekRules.Entry) -> some View {
        ClubWeekEntryRow(entry: entry)
            .overlay(alignment: .top) { Rectangle().fill(Self.rowRule).frame(height: 1).padding(.leading, 63) }
    }
}

/// One update: cover, the sentence ("You reached episode 4"), the title, the Berlin time, ›.
private struct ClubWeekEntryRow: View {
    let entry: ClubWeekRules.Entry

    @Environment(\.kuroRoutes) private var routes
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let german = KuroLocale.isGerman
        let line = ClubWeekCopy.line(subject: entry.displayName, isViewer: entry.isViewer, status: entry.status,
                                     progress: entry.progress, isManga: entry.isManga, german: german)
        let time = entry.updatedAt.map { ClubWeekCopy.time($0) }
        return Button {
            guard !suppressCardTaps else { return }
            KuroAccessibility.impactHaptic(.light)
            routes.openMedia(MediaRoute(entry.mediaKey))
        } label: {
            HStack(alignment: .center, spacing: 11) {
                HomeCalendarArt(raw: entry.coverImage)
                    .frame(width: 32, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(sentence(line))
                        .font(.kuroCustom(12, relativeTo: .footnote, maxSize: 24))
                        .foregroundStyle(Color.kuroInk)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(entry.titleDisplay)
                        .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20))
                        .foregroundStyle(Color(hex: "68736A"))
                        .lineLimit(2)
                    if dynamicTypeSize.isAccessibilitySize, let time {
                        Text(time)
                            .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20).monospacedDigit())
                            .foregroundStyle(Color(hex: "58665B"))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !dynamicTypeSize.isAccessibilitySize, let time {
                    Text(time)
                        .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20).monospacedDigit())
                        .foregroundStyle(Color(hex: "58665B"))
                }
                Image(systemName: "chevron.right")
                    .font(.kuroCustom(12, relativeTo: .footnote, maxSize: 20))
                    .foregroundStyle(Color(hex: "798679"))
                    .accessibilityHidden(true)
            }
            .padding(.leading, 63)
            .padding(.trailing, 14)
            .padding(.vertical, 13)
            .frame(minHeight: 74)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(KuroLocale.text("Opens the title.", "Öffnet den Titel."))
    }

    private func sentence(_ line: (subject: String, predicate: String)) -> AttributedString {
        var subject = AttributedString(line.subject)
        subject.font = .kuroCustom(12, weight: .semibold, relativeTo: .footnote, maxSize: 24)
        var rest = AttributedString(" " + line.predicate)
        rest.font = .kuroCustom(12, relativeTo: .footnote, maxSize: 24)
        return subject + rest
    }
}
