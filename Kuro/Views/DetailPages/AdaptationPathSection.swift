import SwiftUI

struct AdaptationPathSection: View {
    let ladder: MediaLadderResponse

    private var rows: [AdaptationPathRowModel] {
        var result: [AdaptationPathRowModel] = []

        if !ladder.sourceMaterial.isEmpty {
            result.append(
                AdaptationPathRowModel(
                    label: "READ THE SOURCE",
                    subtitle: "Original material in the Kuro catalog",
                    items: Array(ladder.sourceMaterial.prefix(3))
                )
            )
        }

        if !ladder.adaptations.isEmpty {
            result.append(
                AdaptationPathRowModel(
                    label: "WATCH THE ADAPTATION",
                    subtitle: "Best-known adaptation paths",
                    items: Array(ladder.adaptations.prefix(3))
                )
            )
        }

        if !ladder.prequels.isEmpty {
            result.append(
                AdaptationPathRowModel(
                    label: "START WITH",
                    subtitle: "Earlier franchise entry points",
                    items: Array(ladder.prequels.prefix(3))
                )
            )
        }

        if !ladder.sequels.isEmpty {
            result.append(
                AdaptationPathRowModel(
                    label: "CONTINUE TO",
                    subtitle: "Direct follow-up entries",
                    items: Array(ladder.sequels.prefix(3))
                )
            )
        }

        if result.count < 4, !ladder.sideStories.isEmpty {
            result.append(
                AdaptationPathRowModel(
                    label: "SIDE STORY",
                    subtitle: "Optional companion works",
                    items: Array(ladder.sideStories.prefix(3))
                )
            )
        }

        if result.count < 4, !ladder.spinOffs.isEmpty {
            result.append(
                AdaptationPathRowModel(
                    label: "SPIN OFF",
                    subtitle: "Adjacent entries worth knowing",
                    items: Array(ladder.spinOffs.prefix(3))
                )
            )
        }

        return Array(result.prefix(4))
    }

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: KuroSpacing.md) {
                Text("ADAPTATION PATH")
                    .font(.kuroCaption(weight: .semibold))
                    .tracking(1.6)
                    .foregroundColor(.kuroBlack80)

                Text("A compact path through source material, adaptations, and chronology.")
                    .font(.kuroCaption(weight: .light))
                    .foregroundColor(.kuroTextSecondary)

                VStack(alignment: .leading, spacing: KuroSpacing.md) {
                    ForEach(rows) { row in
                        AdaptationPathRow(row: row)
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
