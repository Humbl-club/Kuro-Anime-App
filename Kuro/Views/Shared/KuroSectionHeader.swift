import SwiftUI

// MARK: - Section header (spec §3.5, rulebook §4)
// A serif section title ("Coming up.", "Seasons", "Between us.") exposed as a header to VoiceOver,
// with an optional kicker above it and one optional text action on the trailing edge.

struct KuroSectionHeader: View {
    /// The serif size: `.headline` (26 pt) for page sections, `.title` (19 pt) inside a section.
    enum Size {
        case headline
        case title
    }

    let title: String
    var kicker: String? = nil
    var size: Size = .headline
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    init(_ title: String, kicker: String? = nil, size: Size = .headline,
         actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.kicker = kicker
        self.size = size
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: KuroDesignSpacing.md) {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
                if let kicker {
                    Text(kicker)
                        .kuroKicker()
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(size == .headline ? .kuroHeadline(weight: .light) : .kuroTitle(weight: .regular))
                    .foregroundStyle(Color.kuroInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.kuroMeta(weight: .medium))
                        .foregroundStyle(Color.kuroInk)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(KuroPressStyle())
            }
        }
    }
}
