import SwiftUI

// MARK: - Character Section (compact, importance-first preview)
//
// Navigation contract (docs/superpowers/specs/2026-11-02-navigation-contract-design.md): a character
// opens its page by PUSHING it inside the journey (`routes.openCharacter`), and "See all" pushes the
// character directory (`JourneyPage.seeAll`, `CastDirectory.journeyID`), whose characters push in turn.
// Nothing here presents a sheet.

/// The character directory's journey identity (pure, tested in NaventityTests).
enum CastDirectory {
    /// `characters:<ids>`: stable for one title's cast (the same characters in the same order), so a
    /// second "See all" on the same title pops back to the open directory (N5) instead of a copy.
    static func journeyID(characterIDs: [Int]) -> String {
        "characters:" + characterIDs.map(String.init).joined(separator: "-")
    }
}

struct CastSection: View {
    let characters: [(character: Character, role: String)]

    @Environment(\.kuroRoutes) private var routes

    private let previewLimit = 8
    private let displayLimit = 10
    private var sectionTitle: String { KuroLocale.text("Characters", "Figuren") }

    private var filtered: [(character: Character, role: String)] {
        characters
            .filter { $0.role.lowercased() != "background" }
            .sorted { lhs, rhs in
                let lhsMain = lhs.role.uppercased() == "MAIN"
                let rhsMain = rhs.role.uppercased() == "MAIN"
                if lhsMain != rhsMain { return lhsMain }
                let lhsSupp = lhs.role.uppercased() == "SUPPORTING"
                let rhsSupp = rhs.role.uppercased() == "SUPPORTING"
                if lhsSupp != rhsSupp { return lhsSupp }
                return (lhs.character.nameFull ?? "") < (rhs.character.nameFull ?? "")
            }
    }

    private var displayedCharacters: [(character: Character, role: String)] {
        Array(filtered.prefix(displayLimit))
    }

    private func openDirectory() {
        let title = sectionTitle
        let items = displayedCharacters
        let id = CastDirectory.journeyID(characterIDs: items.map(\.character.id))
        routes.openPage(.seeAll(AnyJourneyPage(id: id, title: title) {
            CharacterDirectoryPage(title: title, characters: items)
        }))
    }

    var body: some View {
        if !displayedCharacters.isEmpty {
            VStack(alignment: .leading, spacing: KuroSpacing.md) {
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Text(sectionTitle)
                        .font(.kuroCaption(weight: .semibold))
                        .tracking(1.6)
                        .textCase(.uppercase)
                        .foregroundColor(.kuroBlack80)
                        .accessibilityAddTraits(.isHeader)

                    Spacer()

                    if displayedCharacters.count > previewLimit {
                        Button {
                            openDirectory()
                        } label: {
                            Text(KuroLocale.text("See all", "Alle ansehen"))
                                .font(.kuroMeta(weight: .medium))
                                .foregroundColor(.kuroBlack80)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(KuroPressStyle())
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(displayedCharacters.prefix(previewLimit), id: \.character.id) { item in
                            Button {
                                routes.openCharacter(item.character)
                            } label: {
                                CastCircleItem(character: item.character, role: item.role)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(KuroPressStyle())
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Cast Circle Item

private struct CastCircleItem: View {
    let character: Character
    let role: String

    private var isMain: Bool { role.uppercased() == "MAIN" }
    private var isSupporting: Bool { role.uppercased() == "SUPPORTING" }
    private var displayName: String { (character.nameFull ?? DetailCopy.unknown(german: KuroLocale.isGerman)).uppercased() }
    private var roleLabel: String? {
        DetailCopy.characterRole(role, german: KuroLocale.isGerman)?.uppercased()
    }

    private var resolvedImageURL: URL? {
        guard let raw = character.imageLarge?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }

        let lowered = raw.lowercased()
        let blockedTokens = ["no_image", "no-image", "noimage", "placeholder", "default", "fallback"]
        guard !blockedTokens.contains(where: lowered.contains) else {
            return nil
        }

        return URL(string: raw)
    }

    var body: some View {
        Group {
            if let resolvedImageURL {
                imageItem(url: resolvedImageURL)
            } else {
                nameOnlyItem
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(character.nameFull ?? DetailCopy.unknown(german: KuroLocale.isGerman)), \(DetailCopy.characterRole(role, german: KuroLocale.isGerman) ?? KuroLocale.text("Character", "Figur"))")
    }

    private func imageItem(url: URL) -> some View {
        VStack(spacing: 6) {
            KuroCachedAsyncImage(
                url: url,
                maxPixelSize: 64
            ) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    nameOnlyFallback
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color.kuroBlack08, lineWidth: 0.5)
            )

            Text(displayName)
                .font(.kuroMicro(weight: .regular))
                .tracking(0.6)
                .foregroundColor(.kuroBlack80)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 72)

            if let roleLabel {
                roleBadge(roleLabel)
            }
        }
    }

    private var nameOnlyItem: some View {
        VStack(spacing: 8) {
            Text(displayName)
                .font(.kuroMicro(weight: .semibold))
                .tracking(0.8)
                .foregroundColor(.kuroBlack80)
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .frame(width: 80, alignment: .center)
                .fixedSize(horizontal: false, vertical: true)

            if let roleLabel {
                roleBadge(roleLabel)
            }
        }
        .frame(width: 80, alignment: .top)
    }

    private var nameOnlyFallback: some View {
        VStack {
            Spacer(minLength: 0)
            Text(displayName)
                .font(.kuroMicro(weight: .semibold))
                .tracking(0.6)
                .foregroundColor(.kuroBlack80)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 56)
            Spacer(minLength: 0)
        }
        .frame(width: 64, height: 64)
    }

    private func roleBadge(_ label: String) -> some View {
        Text(label)
            .font(.kuroCustom(8, weight: .semibold, maxSize: 13))
            .tracking(1.0)
            .foregroundColor(.kuroTextSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(Color.kuroBlack06)
            )
    }
}

/// The full character list as a journey page ("See all"): pushed by `CastSection`, each character
/// pushes its page. No stack and no Close of its own (the journey chrome draws back and ✕).
private struct CharacterDirectoryPage: View {
    let title: String
    let characters: [(character: Character, role: String)]

    @Environment(\.kuroRoutes) private var routes

    private let columns = [
        GridItem(.adaptive(minimum: 76, maximum: 88), spacing: 16)
    ]

    private var mainCount: Int {
        characters.filter { $0.role.uppercased() == "MAIN" }.count
    }

    private var supportingCount: Int {
        characters.filter { $0.role.uppercased() == "SUPPORTING" }.count
    }

    var body: some View {
        KuroJourneyAwareStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KuroSpacing.lg) {
                    EntitySectionLead(
                        text: characters.count >= 10
                            ? KuroLocale.text("The ten most important characters, main roles first.", "Die zehn wichtigsten Figuren, Hauptrollen zuerst.")
                            : KuroLocale.text("The characters by importance, main roles first.", "Die Figuren nach Bedeutung, Hauptrollen zuerst.")
                    )

                    HStack(spacing: 8) {
                        CharacterDirectoryStatPill(
                            title: KuroLocale.text("TOTAL", "GESAMT"),
                            value: "\(characters.count)"
                        )
                        if mainCount > 0 {
                            CharacterDirectoryStatPill(
                                title: KuroLocale.text("MAIN", "HAUPTROLLEN"),
                                value: "\(mainCount)"
                            )
                        }
                        if supportingCount > 0 {
                            CharacterDirectoryStatPill(
                                title: KuroLocale.text("SUPPORTING", "NEBENROLLEN"),
                                value: "\(supportingCount)"
                            )
                        }
                    }

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                        ForEach(characters, id: \.character.id) { item in
                            Button {
                                routes.openCharacter(item.character)
                            } label: {
                                CastCircleItem(character: item.character, role: item.role)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(KuroPressStyle())
                        }
                    }
                }
                .padding(.horizontal, KuroDesignSpacing.padding)
                .padding(.top, KuroJourneyChrome.barHeight + KuroSpacing.md)
                .padding(.bottom, KuroSpacing.lg)
            }
            .background(Color.kuroBackground)
            // No artwork: the compact bar (with the title) from the start.
            .kuroJourneyChrome(title: title, collapseProgress: 1)
        }
        .routePresenter()
    }
}

private struct CharacterDirectoryStatPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.kuroCustom(9, weight: .semibold, maxSize: 14))
                .tracking(1.0)
                .foregroundColor(.kuroTextTertiary)

            Text(value)
                .font(.kuroMicro(weight: .semibold))
                .tracking(0.6)
                .foregroundColor(.kuroBlack80)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.kuroBlack04)
        )
    }
}

extension Character: Hashable {
    static func == (lhs: Character, rhs: Character) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
