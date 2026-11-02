import KuroCore
import SwiftUI

// MARK: - Opening line (prototype Poster Home, PROTOTYPE_SPEC.md §4 "Opening line"; LANE_AMENDMENTS 3)
// A kicker left ("NOW WATCHING", SF 9/12.6, tracking 1.05, #666c68) and a right-aligned headline
// (SF 14/18.2 w550, tracking −0.3, ink): "2 new episodes", "Keep watching.", "Begin here.".
// Caught up (amendment 3): the headline is "Keep watching." / "Keep reading." and "Nothing new today.
// Stay at your own pace." is a separate bordered quiet card at the top of the feed
// (SF 11/15.4 muted, #ffffff80 fill, 1 pt #dce1dc border, radius 8, padding 10/12).
// At 320 pt the kicker is 8 pt and the headline 13 pt (§5).

/// The opening line's copy (pure; EN/DE).
enum HomeOpeningLine {
    /// The right-aligned headline. `available` counts released units (episodes / chapters) the reader
    /// has not reached, over every title in progress (`HomeShelfPolicy.opening`); caught up and
    /// nothing new read "Keep watching." / "Keep reading.".
    static func headline(available: Int, caughtUp: Bool, newAccount: Bool, medium: MediaKind,
                         german: Bool = KuroLocale.isGerman) -> String {
        if newAccount { return german ? "Fang hier an." : "Begin here." }
        if caughtUp || available <= 0 {
            switch (medium, german) {
            case (.anime, false): return "Keep watching."
            case (.anime, true): return "Weiterschauen."
            case (.manga, false): return "Keep reading."
            case (.manga, true): return "Weiterlesen."
            }
        }
        switch (medium, german) {
        case (.anime, false): return available == 1 ? "1 new episode" : "\(available) new episodes"
        case (.anime, true): return available == 1 ? "1 neue Folge" : "\(available) neue Folgen"
        case (.manga, false): return available == 1 ? "1 new chapter" : "\(available) new chapters"
        case (.manga, true): return available == 1 ? "1 neues Kapitel" : "\(available) neue Kapitel"
        }
    }

    /// The kicker: "NOW WATCHING" / "NOW READING" / "YOUR COLLECTION" (uppercased by the view).
    static func kicker(newAccount: Bool, medium: MediaKind, german: Bool = KuroLocale.isGerman) -> String {
        if newAccount { return german ? "Deine Sammlung" : "Your collection" }
        switch (medium, german) {
        case (.anime, false): return "Now watching"
        case (.anime, true): return "Du schaust gerade"
        case (.manga, false): return "Now reading"
        case (.manga, true): return "Du liest gerade"
        }
    }

    /// The caught-up quiet card's line (amendment 3).
    static func quietLine(german: Bool = KuroLocale.isGerman) -> String {
        german ? "Heute nichts Neues. Bleib in deinem Tempo." : "Nothing new today. Stay at your own pace."
    }

    /// The quiet card shows only when nothing is new and nothing is unknown (`caughtUp` is
    /// `HomeShelfPolicy.opening(...).nothingNew`, over every title in progress).
    static func showsQuietLine(available: Int, caughtUp: Bool, newAccount: Bool) -> Bool {
        caughtUp && available == 0 && !newAccount
    }
}

/// The opening row: kicker left, headline right. Wraps under accessibility sizes instead of truncating.
struct HomeOpeningLineView: View {
    let kicker: String
    let headline: String
    /// 320 pt phones (≤ `KuroMediumSwitch.smallPhoneContainer` column): the prototype's smaller sizes.
    let compact: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        layout {
            Text(kicker)
                .font(.kuroCustom(compact ? 8 : 9, relativeTo: .caption2, maxSize: 18))
                .tracking(1.05)
                .textCase(.uppercase)
                .foregroundStyle(HomeInk.kicker)
                .lineLimit(1)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            Text(headline)
                .font(.kuroCustom(compact ? 13 : 14, weight: .semibold, relativeTo: .subheadline, maxSize: 28))
                .tracking(-0.3)
                .foregroundStyle(Color.kuroInk)
                .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The caught-up quiet card (amendment 3).
struct HomeQuietCard: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.kuroCustom(11, relativeTo: .footnote, maxSize: 24))
            .foregroundStyle(Color.kuroMuted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 10 pt padding around the prototype's 15.4 pt line.
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(HomeInk.quietBorder, lineWidth: 1))
    }
}
