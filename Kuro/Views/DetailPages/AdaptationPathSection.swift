import SwiftUI

struct AdaptationPathSection: View {
    let ladder: MediaLadderResponse

    private var featuredItems: [MediaLadderItem] {
        var result: [MediaLadderItem] = []
        if let entryPoint = ladder.entryPoint {
            result.append(entryPoint)
        }
        if let nextStep = ladder.nextStep,
           !result.contains(where: { $0.id == nextStep.id }) {
            result.append(nextStep)
        }
        return Array(result.prefix(2))
    }

    private var featuredIDs: Set<String> {
        Set(featuredItems.map(\.id))
    }

    private var rows: [AdaptationPathRowModel] {
        var result: [AdaptationPathRowModel] = []

        let sourceItems = ladder.sourceMaterial.filter { !featuredIDs.contains($0.id) }
        if !sourceItems.isEmpty {
            result.append(
                AdaptationPathRowModel(
                    label: "READ THE SOURCE",
                    subtitle: "Original material in the Kuro catalog",
                    items: Array(sourceItems.prefix(3))
                )
            )
        }

        let adaptationItems = ladder.adaptations.filter { !featuredIDs.contains($0.id) }
        if !adaptationItems.isEmpty {
            result.append(
                AdaptationPathRowModel(
                    label: "WATCH THE ADAPTATION",
                    subtitle: "Best-known adaptation paths",
                    items: Array(adaptationItems.prefix(3))
                )
            )
        }

        if result.count < 3 {
            let sideStoryItems = ladder.sideStories.filter { !featuredIDs.contains($0.id) }
            if !sideStoryItems.isEmpty {
                result.append(
                    AdaptationPathRowModel(
                        label: "SIDE STORY",
                        subtitle: "Optional companion works",
                        items: Array(sideStoryItems.prefix(3))
                    )
                )
            }
        }

        if result.count < 3 {
            let spinOffItems = ladder.spinOffs.filter { !featuredIDs.contains($0.id) }
            if !spinOffItems.isEmpty {
                result.append(
                    AdaptationPathRowModel(
                        label: "SPIN OFF",
                        subtitle: "Adjacent entries worth knowing",
                        items: Array(spinOffItems.prefix(3))
                    )
                )
            }
        }

        return Array(result.prefix(3))
    }

    private var introText: String {
        if let note = ladder.franchiseNote, !note.isEmpty {
            return note
        }
        switch ladder.coverageStatus {
        case .strong:
            return "Start with the source, then follow the main adaptation path."
        case .partial, .minimal, .none:
            return "Kuro found a partial path through this franchise."
        }
    }

    var body: some View {
        if ladder.hasContent {
            VStack(alignment: .leading, spacing: KuroSpacing.md) {
                Text("ADAPTATION PATH")
                    .font(.kuroCaption(weight: .semibold))
                    .tracking(1.6)
                    .foregroundColor(.kuroBlack80)

                Text(introText)
                    .font(.kuroCaption(weight: .light))
                    .foregroundColor(.kuroTextSecondary)

                if !featuredItems.isEmpty {
                    VStack(alignment: .leading, spacing: KuroSpacing.md) {
                        ForEach(featuredItems) { item in
                            EditorialLadderCard(item: item)
                        }
                    }
                }

                if !rows.isEmpty {
                    VStack(alignment: .leading, spacing: KuroSpacing.md) {
                        ForEach(rows) { row in
                            AdaptationPathRow(row: row)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct AdaptationPathRowModel: Identifiable {
    let id = UUID()
    let label: String
    let subtitle: String
    let items: [MediaLadderItem]
}

private struct EditorialLadderCard: View {
    let item: MediaLadderItem

    var body: some View {
        VStack(alignment: .leading, spacing: KuroSpacing.sm) {
            if let reason = item.reasonLabel, !reason.isEmpty {
                Text(reason.uppercased())
                    .font(.kuroMicro(weight: .medium))
                    .tracking(1.3)
                    .foregroundColor(.kuroBlack80)
            }
            KuroCompactCard(media: item.toMedia(), width: 110)
        }
    }
}

private struct AdaptationPathRow: View {
    let row: AdaptationPathRowModel

    private var cardWidth: CGFloat {
        row.items.count == 1 ? 110 : 102
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KuroSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.label)
                    .font(.kuroMicro(weight: .medium))
                    .tracking(1.3)
                    .foregroundColor(.kuroBlack80)

                Text(row.subtitle)
                    .font(.kuroCaption(weight: .light))
                    .foregroundColor(.kuroTextTertiary)
            }

            if row.items.count == 1, let first = row.items.first {
                KuroCompactCard(media: first.toMedia(), width: cardWidth)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(row.items) { item in
                            KuroCompactCard(media: item.toMedia(), width: cardWidth)
                        }
                    }
                }
            }
        }
    }
}
