import KuroCore
import SwiftUI

// MARK: - Home "Coming up." calendar card (PROTOTYPE_SPEC.md §4 "Calendar", "Dates to come")
// The prototype's calendar: an SF sans "Coming up." heading with its summary ("6 releases · 7 days"),
// then one rounded card of day groups. Each group has a date chip ("2 / OCT"), "Today / Tomorrow /
// Fri 9 Oct", a release count, up to three stacked covers and a disclosure; the first dated group
// starts open and lists its rows (poster, title, "S2 · Episode 9", and the row's own time or
// certainty on the right). With no dated group the card opens with "No confirmed dates yet." above a
// closed Dates to come.
// Past four groups a "Next N dates" row reveals the rest; an open day with more than three rows
// offers "Show N more releases". "Dates to come" closes the card and exists only when undated rows do.
//
// Two measured variants:
//   anime  card #fafcf9, radius 18, 1 pt #d8ddd9; chips white with a #d4dbd4 rule; open rows white
//   manga  card #fafbf7, radius 14/14/5/5, no rule; chips filled #eceee4 with corners 4/10/4/4;
//          open rows #f0f2ea80 with bottom corners 8; posters and day art radius 1
// Display only: rows open the title's detail through `kuroRoutes`; nothing here writes.
// Open/closed state is kept per medium ("manga|2026-11-01"), so closing Today on one medium never
// closes it on the other when Home keeps one card across a medium switch.
// While the schedule is still being asked (`coverage == .pending`, no groups yet), the card shows
// its branded loading shape in place (`HomeCalendarLoading`) instead of popping in later.
// Embedded by `HomeView.calendarSection` (Task 10) with `HomeCalendarPresentation.groups(...)` for the
// selected medium, its cover/title lookups and `medium:` (so the loading shape and an empty card know
// their medium); the glance scrolls to it (`upcoming-calendar`) and moves VoiceOver focus to it.

struct HomeCalendarCard: View {
    let groups: [HomeCalendarDay]
    let coverage: ReleaseScheduleCoverage
    /// The row's cover when the schedule row carries none (Home passes its card lookup).
    var coverFor: (ReleaseScheduleItem) -> String?
    /// The row's title when the schedule row carries none.
    var titleFor: (ReleaseScheduleItem) -> String
    /// The row's season prefix ("S2"), when Home knows the title's season number (anime).
    var seasonFor: (ReleaseScheduleItem) -> String?
    /// The reference time for "today" (fixtures pin it).
    var now: Date
    /// The medium when Home knows it (the groups may be empty while loading).
    var medium: MediaKind?

    @Environment(\.kuroRoutes) private var routes
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Per-group open state, keyed `medium|day id`; a group never touched follows "the first group
    /// starts open".
    @State private var openGroups: [String: Bool] = [:]
    @State private var allRowsGroups: Set<String> = []
    /// Media whose "Next N dates" has been opened.
    @State private var allDatesMedia: Set<String> = []
    /// The card's measured width: ≤ `KuroMediumSwitch.smallPhoneContainer` uses the prototype's
    /// small-phone heading (22 pt, summary 9 pt).
    @State private var cardWidth: CGFloat = 0

    init(groups: [HomeCalendarDay], coverage: ReleaseScheduleCoverage,
         coverFor: @escaping (ReleaseScheduleItem) -> String? = { $0.coverImage },
         titleFor: @escaping (ReleaseScheduleItem) -> String = { $0.title },
         seasonFor: @escaping (ReleaseScheduleItem) -> String? = { _ in nil },
         now: Date = Date(), medium: MediaKind? = nil) {
        self.groups = groups
        self.coverage = coverage
        self.coverFor = coverFor
        self.titleFor = titleFor
        self.seasonFor = seasonFor
        self.now = now
        self.medium = medium
    }

    private var isManga: Bool { (medium ?? groups.first?.items.first?.medium) == .manga }
    private var mediumKey: String { isManga ? "manga" : "anime" }
    private var showsAllDates: Bool { allDatesMedia.contains(mediumKey) }
    /// The state key of one day group (pure, so the per-medium rule is pinned by tests).
    static func stateKey(manga: Bool, dayId: String) -> String { (manga ? "manga" : "anime") + "|" + dayId }
    private func key(_ day: HomeCalendarDay) -> String { Self.stateKey(manga: isManga, dayId: day.id) }
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
        } else if Self.showsLoading(groups: groups, coverage: coverage) {
            HomeCalendarLoading(manga: isManga)
        }
    }

    /// The in-place skeleton shows only while the schedule has not answered yet.
    static func showsLoading(groups: [HomeCalendarDay], coverage: ReleaseScheduleCoverage) -> Bool {
        groups.isEmpty && coverage == .pending
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
        // "The first group starts open" applies to dated groups only: Dates to come starts closed.
        let first = HomeCalendarPresentation.initiallyOpenGroup(groups)
        let noDates = paged.visible.isEmpty && paged.hidden.isEmpty
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
            if noDates {
                noDatesBand
            }
            if let undated = paged.undated {
                dayGroup(undated, isFirst: false, initiallyOpen: undated.id == first)
            }
        }
        .background(palette.card)
        .clipShape(shape)
        .overlay(shape.strokeBorder(palette.cardRule, lineWidth: palette.cardRule == .clear ? 0 : 1))
        .background {
            // CSS `0 2px 6px -4px`: a negative spread is the shadow of a smaller shape, so the drop
            // shows under the card only, never at its sides.
            shape.fill(palette.card)
                .padding(palette.cardShadowInset)
                .shadow(color: palette.cardShadow, radius: palette.cardShadowRadius, y: palette.cardShadowY)
        }
    }

    /// No dated release at all: the card opens with "No confirmed dates yet." (§7.1) above the closed
    /// Dates to come group, instead of opening the announcements.
    private var noDatesBand: some View {
        Text(KuroLocale.text("No confirmed dates yet.", "Noch keine bestätigten Termine."))
            .font(.kuroCustom(isManga ? 13 : 12, relativeTo: .footnote, maxSize: 24))
            .foregroundStyle(Color(hex: "68736A"))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .background(palette.card)
    }

    // MARK: Day group

    private func isOpen(_ day: HomeCalendarDay, initiallyOpen: Bool) -> Bool {
        openGroups[key(day)] ?? initiallyOpen
    }

    @ViewBuilder
    private func dayGroup(_ day: HomeCalendarDay, isFirst: Bool, initiallyOpen: Bool) -> some View {
        let open = isOpen(day, initiallyOpen: initiallyOpen)
        let undated = day.kind == .undated
        VStack(spacing: 0) {
            Button {
                openGroups[key(day)] = !open
            } label: {
                dayToggle(day, open: open)
            }
            .buttonStyle(HomeContactStyle())
            .background(open && !undated ? Color.white : Color.clear)
            .accessibilityLabel(dayAccessibilityLabel(day))
            .accessibilityValue(open ? KuroLocale.text("Expanded", "Ausgeklappt")
                                     : KuroLocale.text("Collapsed", "Eingeklappt"))
            .accessibilityHint(open ? KuroLocale.text("Hides the releases", "Blendet die Veröffentlichungen aus")
                                    : KuroLocale.text("Shows the releases", "Zeigt die Veröffentlichungen"))
            if open {
                // An open list sits on the events fill (white on anime), Dates to come included.
                events(day).background(palette.eventsFill,
                                       in: UnevenRoundedRectangle(bottomLeadingRadius: palette.eventsBottomRadius,
                                                                  bottomTrailingRadius: palette.eventsBottomRadius,
                                                                  style: .continuous))
            }
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
            // The prototype's text mark: "⌄" / "⌃", SF 21 w300 (`.disclosure-mark`).
            Text(open ? "⌃" : "⌄")
                .font(.kuroCustom(21, weight: .light, relativeTo: .body, maxSize: 30))
                .foregroundStyle(Color(hex: "727D73"))
                .frame(width: 18, height: 24)
                // The marks sit off-centre as in the prototype: ⌃ level with the day label, ⌄ low.
                .offset(y: open ? -3 : 4)
                .accessibilityHidden(true)
        }
        .padding(12)
        .frame(minHeight: 76)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func dateChip(_ day: HomeCalendarDay) -> some View {
        let shape = palette.chipShape
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
                    .clipShape(RoundedRectangle(cornerRadius: palette.artRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: palette.artRadius, style: .continuous)
                        .strokeBorder(rim, lineWidth: 2))
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
        let all = allRowsGroups.contains(key(day))
        let hidden = day.items.count - HomeCalendarPresentation.visibleRowsPerDay
        VStack(spacing: 0) {
            ForEach(Array(day.items.prefix(all ? day.items.count : HomeCalendarPresentation.visibleRowsPerDay))) { item in
                releaseRow(item)
            }
            if hidden > 0 {
                Button {
                    if all { allRowsGroups.remove(key(day)) } else { allRowsGroups.insert(key(day)) }
                } label: {
                    HStack {
                        Text(all ? KuroLocale.text("Show fewer releases", "Weniger Veröffentlichungen zeigen")
                                 : KuroLocale.text("Show \(hidden) more releases", "\(hidden) weitere Veröffentlichungen zeigen"))
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
                    .background(Color(hex: "F6F8F4"), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(hex: "D9E0D7"), lineWidth: 1))
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
                    .clipShape(RoundedRectangle(cornerRadius: palette.artRadius, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.kuroCustom(12, weight: .medium, relativeTo: .footnote, maxSize: 24))
                        .foregroundStyle(Color.kuroInk)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                        .multilineTextAlignment(.leading)
                    Text(HomeCalendarPresentation.rowUnit(item, season: seasonFor(item), copy: copy))
                        .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20))
                        .foregroundStyle(Color(hex: "68736A"))
                    if dynamicTypeSize.isAccessibilitySize {
                        // A 62 pt column would break words at accessibility sizes: the time joins
                        // the copy column instead.
                        rowWhen(item)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                if !dynamicTypeSize.isAccessibilitySize {
                    rowWhen(item)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 62, alignment: .trailing) // `.release-when` max-width 62
                        .fixedSize(horizontal: false, vertical: true)
                }
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

    private func rowWhen(_ item: ReleaseScheduleItem) -> some View {
        Text(HomeCalendarPresentation.rowWhen(item, copy: copy))
            .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20))
            .foregroundStyle(Color(hex: "58665B"))
    }

    // MARK: Next dates

    private func nextDatesRow(_ hidden: [HomeCalendarDay]) -> some View {
        let releases = hidden.reduce(0) { $0 + $1.items.count }
        let dates = hidden.count
        return Button {
            allDatesMedia.insert(mediumKey)
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
    /// The shadow's negative spread (anime `-4px`): the shadow is cast by a shape this much smaller.
    var cardShadowInset: CGFloat = 0
    let topRadius: CGFloat
    let bottomRadius: CGFloat
    /// The open day's row list (the toggle above it is white in both variants).
    let eventsFill: Color
    let chipFill: Color
    let chipRule: Color
    let closedRule: Color
    let pendingFill: Color
    let pendingRule: Color
    /// The date stamp's corners (CSS order TL, TR, BR, BL): anime 10 all round, manga 4/10/4/4.
    let chipCorners: RectangleCornerRadii
    /// The open day's bottom corners (manga `.day-events` 0 0 8 8).
    let eventsBottomRadius: CGFloat
    /// Row posters and stacked day art (manga 1).
    let artRadius: CGFloat

    var chipShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(cornerRadii: chipCorners, style: .continuous)
    }

    static let anime = HomeCalendarPalette(
        card: Color(hex: "FAFCF9"), cardRule: Color(hex: "D8DDD9"),
        cardShadow: Color(hex: "1D291C", opacity: Double(0x20) / 255), cardShadowRadius: 3, cardShadowY: 2,
        cardShadowInset: 4,
        topRadius: 18, bottomRadius: 18,
        eventsFill: .white, chipFill: .white, chipRule: Color(hex: "D4DBD4"),
        closedRule: Color(hex: "DDE2DD"), pendingFill: Color(hex: "F0F3ED"), pendingRule: Color(hex: "D7DED5"),
        chipCorners: RectangleCornerRadii(topLeading: 10, bottomLeading: 10, bottomTrailing: 10, topTrailing: 10),
        eventsBottomRadius: 0, artRadius: 3)

    static let manga = HomeCalendarPalette(
        card: Color(hex: "FAFBF7"), cardRule: .clear,
        cardShadow: Color(hex: "2D3027", opacity: Double(0x09) / 255), cardShadowRadius: 8, cardShadowY: 5,
        topRadius: 14, bottomRadius: 5,
        eventsFill: Color(hex: "F5F6F0"), chipFill: Color(hex: "ECEEE4"), chipRule: .clear,
        closedRule: Color(hex: "DDE2DD"), pendingFill: Color(hex: "F0F3ED"), pendingRule: Color(hex: "D7DED5"),
        chipCorners: RectangleCornerRadii(topLeading: 4, bottomLeading: 4, bottomTrailing: 4, topTrailing: 10),
        eventsBottomRadius: 8, artRadius: 1)
}

/// The calendar's loading shape (spec §5.4): the "Coming up." heading and two branded calendar-day
/// skeletons inside the card's shape, shown in place while the schedule is asked.
struct HomeCalendarLoading: View {
    let manga: Bool

    var body: some View {
        let palette: HomeCalendarPalette = manga ? .manga : .anime
        let shape = UnevenRoundedRectangle(topLeadingRadius: palette.topRadius,
                                           bottomLeadingRadius: palette.bottomRadius,
                                           bottomTrailingRadius: palette.bottomRadius,
                                           topTrailingRadius: palette.topRadius,
                                           style: .continuous)
        VStack(alignment: .leading, spacing: 17) {
            Text(KuroLocale.text("Coming up.", "Demnächst."))
                .font(.kuroCustom(24, weight: .semibold, relativeTo: .title2, maxSize: 40))
                .tracking(-0.85)
                .foregroundStyle(Color.kuroInk)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(0..<2, id: \.self) { index in
                    KuroSkeleton(kind: .calendarDay)
                        .padding(12)
                        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                        .overlay(alignment: .top) {
                            if index > 0 { Rectangle().fill(palette.closedRule).frame(height: 1) }
                        }
                }
            }
            .background(palette.card, in: shape)
            .overlay(shape.strokeBorder(palette.cardRule, lineWidth: palette.cardRule == .clear ? 0 : 1))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(KuroLocale.text("Loading what's coming up", "Termine werden geladen"))
    }
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
