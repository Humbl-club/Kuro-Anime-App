import SwiftUI

// MARK: - Character Section (compact, importance-first preview)

struct CastSection: View {
    let characters: [(character: Character, role: String)]

    @State private var selectedCharacter: Character?
    @State private var showAllCharacters = false

    private let previewLimit = 8
    private let displayLimit = 10
    private let sectionTitle = "CHARACTERS"

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

    var body: some View {
        if !displayedCharacters.isEmpty {
            VStack(alignment: .leading, spacing: KuroSpacing.md) {
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Text(sectionTitle)
                        .font(.kuroCaption(weight: .semibold))
                        .tracking(1.6)
                        .foregroundColor(.kuroBlack80)

                    Spacer()

                    if displayedCharacters.count > previewLimit {
                        Button("See All") {
                            showAllCharacters = true
                        }
                        .font(.kuroMicro(weight: .medium))
                        .foregroundColor(.kuroBlack80)
                        .buttonStyle(.plain)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(displayedCharacters.prefix(previewLimit), id: \.character.id) { item in
                            CastCircleItem(
                                character: item.character,
                                role: item.role
                            )
                            .onTapGesture {
                                selectedCharacter = item.character
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .sheet(isPresented: $showAllCharacters) {
                CharacterDirectorySheet(
                    title: sectionTitle,
                    characters: displayedCharacters
                )
            }
            .sheet(item: $selectedCharacter) { character in
                CharacterDetailSheet(character: character)
            }
        }
    }
}

// MARK: - Cast Circle Item

private struct CastCircleItem: View {
    let character: Character
    let role: String

    private var isMain: Bool { role.uppercased() == "MAIN" }
    private var isSupporting: Bool { role.uppercased() == "SUPPORTING" }
    private var displayName: String { (character.nameFull ?? "Unknown").uppercased() }
    private var roleLabel: String? {
        if isMain { return "MAIN" }
        if isSupporting { return "SUPPORTING" }
        let trimmed = role.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.uppercased()
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
        .accessibilityLabel("\(character.nameFull ?? "Unknown"), \((roleLabel ?? "character").lowercased())")
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
                    .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
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
            .font(.system(size: 8, weight: .semibold))
            .tracking(1.0)
            .foregroundColor(.black.opacity(0.55))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(Color.black.opacity(0.06))
            )
    }
}

private struct CharacterDirectorySheet: View {
    let title: String
    let characters: [(character: Character, role: String)]

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCharacter: Character?

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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KuroSpacing.lg) {
                    EntitySectionLead(
                        text: characters.count >= 10
                            ? "Showing the top 10 character slice Kuro keeps for this title, ordered by series importance."
                            : "Showing the importance-ordered character slice Kuro keeps for this title."
                    )

                    HStack(spacing: 8) {
                        CharacterDirectoryStatPill(
                            title: "TOTAL",
                            value: "\(characters.count)"
                        )
                        if mainCount > 0 {
                            CharacterDirectoryStatPill(
                                title: "MAIN",
                                value: "\(mainCount)"
                            )
                        }
                        if supportingCount > 0 {
                            CharacterDirectoryStatPill(
                                title: "SUPPORTING",
                                value: "\(supportingCount)"
                            )
                        }
                    }

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                        ForEach(characters, id: \.character.id) { item in
                            CastCircleItem(character: item.character, role: item.role)
                                .onTapGesture {
                                    selectedCharacter = item.character
                                }
                        }
                    }
                }
                .padding(.horizontal, ResponsiveLayout.padding())
                .padding(.vertical, KuroSpacing.lg)
            }
            .background(Color.kuroBackground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.kuroBlack80)
                }
            }
        }
        .sheet(item: $selectedCharacter) { character in
            CharacterDetailSheet(character: character)
        }
    }
}

private struct CharacterDirectoryStatPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
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
                .fill(Color.black.opacity(0.04))
        )
    }
}

extension Character: Hashable {
    static func == (lhs: Character, rhs: Character) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
