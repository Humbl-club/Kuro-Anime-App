import SwiftUI

// MARK: - Cast Section (horizontal circular portrait rail)

struct CastSection: View {
    let characters: [(character: Character, role: String)]
    let containerWidth: CGFloat

    @State private var selectedCharacter: Character?

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

    var body: some View {
        if !filtered.isEmpty {
            VStack(alignment: .leading, spacing: KuroSpacing.md) {
                Text("CAST")
                    .font(.kuroCaption(weight: .semibold))
                    .tracking(1.6)
                    .foregroundColor(.kuroBlack80)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(filtered.prefix(20), id: \.character.id) { item in
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

    var body: some View {
        VStack(spacing: 6) {
            KuroCachedAsyncImage(
                url: character.imageLarge.flatMap(URL.init),
                maxPixelSize: 64
            ) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    placeholderCircle
                default:
                    placeholderCircle
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
            )

            Text((character.nameFull ?? "Unknown").uppercased())
                .font(.kuroMicro(weight: .regular))
                .tracking(0.6)
                .foregroundColor(.kuroBlack80)
                .lineLimit(1)
                .frame(width: 64)

            if isMain {
                Text("MAIN")
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(character.nameFull ?? "Unknown"), \(isMain ? "main" : "supporting") character")
    }

    private var placeholderCircle: some View {
        Circle()
            .fill(Color.black.opacity(0.06))
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 22, weight: .light))
                    .foregroundColor(.black.opacity(0.2))
            )
    }
}

extension Character: Hashable {
    static func == (lhs: Character, rhs: Character) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
