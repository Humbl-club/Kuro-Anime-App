import KuroCore
import SwiftUI

// MARK: - Home "Coming up." calendar card (PROTOTYPE_SPEC.md §4 "Calendar", "Dates to come")
// The prototype's calendar: an SF sans "Coming up." heading with its summary ("6 releases · 7 days"),
// then one rounded card of day groups. Each group has a date chip ("2 / OCT"), "Today / Tomorrow /
// Fri 9 Oct", a release count, up to three stacked covers and a disclosure; the first group starts
// open and lists its rows (poster, title, unit, and the row's own time or certainty on the right).
// Past four groups a "Next N dates" row reveals the rest; an open day with more than three rows
// offers "Show N more releases". "Dates to come" closes the card and exists only when undated rows do.
//
// Two measured variants:
//   anime  card #fafcf9, radius 18, 1 pt #d8ddd9; chips white with a #d4dbd4 rule; open rows white
//   manga  card #fafbf7, radius 14/14/5/5, no rule; chips filled #eceee4; open rows #f5f6f0
// Display only: rows open the title's detail through `kuroRoutes`; nothing here writes.
// Integration: Home embeds `HomeCalendarCard(groups:coverage:)` where the calendar goes, with
// `HomeCalendarPresentation.groups(...)` for the selected medium (lane 4 owns `HomeView`).

struct HomeCalendarCard: View {
    let groups: [HomeCalendarDay]
    let coverage: ReleaseScheduleCoverage
    /// The row's cover when the schedule row carries none (Home passes its card lookup).
    var coverFor: (ReleaseScheduleItem) -> String?
    /// The row's title when the schedule row carries none.
    var titleFor: (ReleaseScheduleItem) -> String
    /// The reference time for "today" (fixtures pin it).
    var now: Date

    @Environment(\.kuroRoutes) private var routes
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Per-group open state; a group never touched follows "the first group starts open".
    @State private var openGroups: [String: Bool] = [:]
    @State private var allRowsGroups: Set<String> = []
    @State private var showsAllDates = false
    /// The card's measured width: ≤ `KuroMediumSwitch.smallPhoneContainer` uses the prototype's
    /// small-phone heading (22 pt, summary 9 pt).
    @State private var cardWidth: CGFloat = 0

    init(groups: [HomeCalendarDay], coverage: ReleaseScheduleCoverage,
         coverFor: @escaping (ReleaseScheduleItem) -> String? = { $0.coverImage },
         titleFor: @escaping (ReleaseScheduleItem) -> String = { $0.title },
         now: Date = Date()) {
        self.groups = groups
        self.coverage = coverage
        self.coverFor = coverFor
        self.titleFor = titleFor
        self.now = now
    }

    private var isManga: Bool { groups.first?.items.first?.medium == .manga }
    private var palette: HomeCalendarPalette { isManga ? .manga : .anime }
    private var copy: ReleaseCopy { ReleaseCopy.current(now: now) }

    var body: some View {
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 17) {
                heading
                card
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { cardWidth = $0 }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(KuroLocale.text("Upcoming from your list", "Demnächst aus deiner Liste"))
        }
    }

    // MARK: Heading

    private var heading: some View {
        let small = cardWidth > 0 && cardWidth <= KuroMediumSwitch.smallPhoneContainer
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 9))
        return layout {
            Text(KuroLocale.text("Coming up.", "Demnächst."))
                .font(.kuroCustom(small ? 22 : 24, weight: .semibold, relativeTo: .title2, maxSize: 40))
                .tracking(-0.85)
                .foregroundStyle(Color.kuroInk)
                .accessibilityAddTraits(.isHeader)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            Text(HomeCalendarPresentation.summary(groups, coverage: coverage, copy: copy))
                .font(.kuroCustom(small ? 9 : 10, relativeTo: .caption2, maxSize: 20))
                .foregroundStyle(Color(hex: "656C66"))
        }
    }

    // MARK: Card

    private var card: some View {
        let paged = HomeCalendarPresentation.paged(groups, showAll: showsAllDates)
        let first = groups.first?.id
        let shape = UnevenRoundedRectangle(topLeadingRadius: palette.topRadius,
                                           bottomLeadingRadius: palette.bottomRadius,
                                           bottomTrailingRadius: palette.bottomRadius,
                                           topTrailingRadius: palette.topRadius,
                                           style: .continuous)
        return VStack(spacing: 0) {
            ForEach(Array(paged.visible.enumerated()), id: \.element.id) { index, day in
                dayGroup(day, isFirst: index == 0, initiallyOpen: day.id == first)
            }
            if !paged.hidden.isEmpty {
                nextDatesRow(paged.hidden)
            }
            if let undated = paged.undated {
                dayGroup(undated, isFirst: paged.visible.isEmpty && paged.hidden.isEmpty,
                         initiallyOpen: undated.id == first)
            }
        }
        .background(palette.card)
        .clipShape(shape)
        .overlay(shape.strokeBorder(palette.cardRule, lineWidth: palette.cardRule == .clear ? 0 : 1))
        .background {
            shape.fill(palette.card)
                .shadow(color: palette.cardShadow, radius: palette.cardShadowRadius, y: palette.cardShadowY)
        }
    }

    // MARK: Day group

    private func isOpen(_ day: HomeCalendarDay, initiallyOpen: Bool) -> Bool {
        openGroups[day.id] ?? initiallyOpen
    }

    @ViewBuilder
    private func dayGroup(_ day: HomeCalendarDay, isFirst: Bool, initiallyOpen: Bool) -> some View {
        let open = isOpen(day, initiallyOpen: initiallyOpen)
        let undated = day.kind == .undated
        VStack(spacing: 0) {
            Button {
                openGroups[day.id] = !open
            } label: {
                dayToggle(day, open: open)
            }
            .buttonStyle(HomeContactStyle())
            .background(open && !undated ? Color.white : Color.clear)
            .accessibilityLabel(dayAccessibilityLabel(day))
            .accessibilityValue(open ? KuroLocale.text("Expanded", "Ausgeklappt")
                                     : KuroLocale.text("Collapsed", "Eingeklappt"))
            .accessibilityHint(open ? KuroLocale.text("Hides the releases", "Blendet die Termine aus")
                                    : KuroLocale.text("Shows the releases", "Zeigt die Termine"))
            if open { events(day).background(undated ? palette.pendingFill : palette.eventsFill) }
        }
        .background(undated ? palette.pendingFill : palette.card)
        .overlay(alignment: .top) {
            if !isFirst {
                Rectangle().fill(undated ? palette.pendingRule : palette.closedRule).frame(height: 1)
            }
        }
    }

    private func dayToggle(_ day: HomeCalendarDay, open: Bool) -> some View {
        HStack(alignment: .center, spacing: 11) {
            dateChip(day)
            VStack(alignment: .leading, spacing: 4) {
                Text(day.label)
                    .font(.kuroCustom(12, weight: .semibold, relativeTo: .footnote, maxSize: 24))
                    .foregroundStyle(Color.kuroInk)
                    .fixedSize(horizontal: false, vertical: true)
                Text(day.kind == .undated
                     ? HomeCalendarPresentation.announcementCount(day.items.count, german: copy.german)
                     : HomeCalendarPresentation.releaseCount(day.items.count, german: copy.german))
                    .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20))
                    .foregroundStyle(Color(hex: "68736A"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !dynamicTypeSize.isAccessibilitySize {
                dayArt(day.items, rim: day.kind == .undated ? palette.pendingFill : (open ? Color.white : palette.card))
            }
            Image(systemName: open ? "chevron.up" : "chevron.down")
                .font(.kuroCustom(14, weight: .light, relativeTo: .body, maxSize: 22))
                .foregroundStyle(Color(hex: "727D73"))
                .frame(width: 18, height: 24)
                .accessibilityHidden(true)
        }
        .padding(12)
        .frame(minHeight: 76)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func dateChip(_ day: HomeCalendarDay) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Group {
            if day.kind == .day {
                VStack(spacing: 3) {
                    Text(day.day)
                        .font(.kuroCustom(19, weight: .medium, relativeTo: .title3, maxSize: 30))
                        .tracking(-0.6)
                        .monospacedDigit()
                        .foregroundStyle(Color.kuroInk)
                    Text(HomeCalendarPresentation.chipMonth(day.month, locale: copy.locale))
                        .font(.kuroCustom(9, relativeTo: .caption2, maxSize: 16))
                        .tracking(0.4)
                        .foregroundStyle(Color(hex: "667267"))
                }
            } else {
                Text("…")
                    .font(.kuroCustom(18, relativeTo: .body, maxSize: 28))
                    .foregroundStyle(Color(hex: "737E70"))
            }
        }
        .frame(minWidth: 40, minHeight: 44)
        .background {
            if day.kind == .day {
                shape.fill(palette.chipFill)
            } else if isManga {
                shape.fill(palette.chipFill)
            }
        }
        .overlay {
            if day.kind == .day {
                if palette.chipRule != .clear { shape.strokeBorder(palette.chipRule, lineWidth: 1) }
            } else if !isManga {
                shape.strokeBorder(palette.chipRule, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
        }
        .accessibilityHidden(true)
    }

    private func dayArt(_ items: [ReleaseScheduleItem], rim: Color) -> some View {
        HStack(spacing: -6) {
            ForEach(Array(items.prefix(3))) { item in
                HomeCalendarArt(raw: coverFor(item))
                    .frame(width: 23, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(rim, lineWidth: 2))
                    .shadow(color: Color(hex: "243A21", opacity: Double(0x20) / 255), radius: 1, x: -2)
            }
        }
        .accessibilityHidden(true)
    }

    private func dayAccessibilityLabel(_ day: HomeCalendarDay) -> String {
        let count = day.kind == .undated
            ? HomeCalendarPresentation.announcementCount(day.items.count, german: copy.german)
            : HomeCalendarPresentation.releaseCount(day.items.count, german: copy.german)
        return "\(day.label), \(count)"
    }

    // MARK: Rows

    @ViewBuilder
    private func events(_ day: HomeCalendarDay) -> some View {
        let all = allRowsGroups.contains(day.id)
        let hidden = day.items.count - HomeCalendarPresentation.visibleRowsPerDay
        VStack(spacing: 0) {
            ForEach(Array(day.items.prefix(all ? day.items.count : HomeCalendarPresentation.visibleRowsPerDay))) { item in
                releaseRow(item)
            }
            if hidden > 0 {
                Button {
                    if all { allRowsGroups.remove(day.id) } else { allRowsGroups.insert(day.id) }
                } label: {
                    HStack {
                        Text(all ? KuroLocale.text("Show fewer releases", "Weniger Termine zeigen")
                                 : KuroLocale.text("Show \(hidden) more releases", "\(hidden) weitere Termine zeigen"))
                            .font(.kuroCustom(11, relativeTo: .caption1, maxSize: 22))
                            .foregroundStyle(Color(hex: "4F5A4F"))
                        Spacer(minLength: 8)
                        Image(systemName: all ? "chevron.up" : "chevron.down")
                            .font(.kuroCustom(11, weight: .light, relativeTo: .caption1, maxSize: 20))
                            .foregroundStyle(Color(hex: "727D73"))
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 13)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color(hex: "F6F8F4"), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color(hex: "D9E0D7"), lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(HomeContactStyle())
                .padding(.top, 8)
                .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 9)
    }

    private func releaseRow(_ item: ReleaseScheduleItem) -> some View {
        let title = item.title.isEmpty ? titleFor(item) : item.title
        return Button {
            routes.openMedia(MediaRoute(kind: item.medium, id: item.mediaId))
        } label: {
            HStack(alignment: .center, spacing: 10) {
                HomeCalendarArt(raw: coverFor(item))
                    .frame(width: 32, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.kuroCustom(12, weight: .medium, relativeTo: .footnote, maxSize: 24))
                        .foregroundStyle(Color.kuroInk)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                        .multilineTextAlignment(.leading)
                    Text(copy.unitSpokenLabel(item))
                        .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20))
                        .foregroundStyle(Color(hex: "68736A"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(HomeCalendarPresentation.rowWhen(item, copy: copy))
                    .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20))
                    .foregroundStyle(Color(hex: "58665B"))
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 76, alignment: .trailing)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.right")
                    .font(.kuroCustom(12, weight: .regular, relativeTo: .footnote, maxSize: 20))
                    .foregroundStyle(Color(hex: "798679"))
                    .frame(width: 14)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 13)
            .frame(minHeight: 74)
            .overlay(alignment: .top) { Rectangle().fill(Color(hex: "E3E7E1")).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(copy.accessibilityLine(item))")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Next dates

    private func nextDatesRow(_ hidden: [HomeCalendarDay]) -> some View {
        let releases = hidden.reduce(0) { $0 + $1.items.count }
        let dates = hidden.count
        return Button {
            showsAllDates = true
        } label: {
            HStack {
                Text(KuroLocale.text(dates == 1 ? "Next date" : "Next \(dates) dates",
                                     dates == 1 ? "Ein weiterer Tag" : "\(dates) weitere Tage"))
                    .font(.kuroCustom(11, relativeTo: .caption1, maxSize: 22))
                    .foregroundStyle(Color(hex: "4F5A4F"))
                Spacer(minLength: 8)
                Text(HomeCalendarPresentation.releaseCount(releases, german: copy.german) + " ↓")
                    .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20))
                    .foregroundStyle(Color(hex: "68736A"))
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Color(hex: "F6F8F4"))
            .overlay(alignment: .top) { Rectangle().fill(Color(hex: "D9E0D7")).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
    }
}

/// The measured colours of one calendar variant.
struct HomeCalendarPalette: Equatable {
    let card: Color
    let cardRule: Color
    let cardShadow: Color
    let cardShadowRadius: CGFloat
    let cardShadowY: CGFloat
    let topRadius: CGFloat
    let bottomRadius: CGFloat
    /// The open day's row list (the toggle above it is white in both variants).
    let eventsFill: Color
    let chipFill: Color
    let chipRule: Color
    let closedRule: Color
    let pendingFill: Color
    let pendingRule: Color

    static let anime = HomeCalendarPalette(
        card: Color(hex: "FAFCF9"), cardRule: Color(hex: "D8DDD9"),
        cardShadow: Color(hex: "1D291C", opacity: Double(0x20) / 255), cardShadowRadius: 2, cardShadowY: 2,
        topRadius: 18, bottomRadius: 18,
        eventsFill: .white, chipFill: .white, chipRule: Color(hex: "D4DBD4"),
        closedRule: Color(hex: "DDE2DD"), pendingFill: Color(hex: "F0F3ED"), pendingRule: Color(hex: "D7DED5"))

    static let manga = HomeCalendarPalette(
        card: Color(hex: "FAFBF7"), cardRule: .clear,
        cardShadow: Color(hex: "2D3027", opacity: Double(0x09) / 255), cardShadowRadius: 8, cardShadowY: 5,
        topRadius: 14, bottomRadius: 5,
        eventsFill: Color(hex: "F5F6F0"), chipFill: Color(hex: "ECEEE4"), chipRule: .clear,
        closedRule: Color(hex: "DDE2DD"), pendingFill: Color(hex: "F0F3ED"), pendingRule: Color(hex: "D7DED5"))
}

/// One cover in the calendar (row poster or stacked day art); a missing cover keeps its frame.
struct HomeCalendarArt: View {
    let raw: String?

    var body: some View {
        if let raw, let url = URL(string: raw) {
            KuroCachedAsyncImage(url: url, maxPixelSize: 160) { phase in
                if case .success(let image) = phase { image.resizable().scaledToFill() }
                else { Color.kuroMissingArt }
            }
        } else {
            Color.kuroMissingArt
        }
    }
}
