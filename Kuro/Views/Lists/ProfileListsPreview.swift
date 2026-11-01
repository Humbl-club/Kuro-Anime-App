import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - Profile "Your lists" (rulebook §14.3, spec D9)
// One row per main status: the word and its real count, then up to six equal covers (56 pt wide).
// A row is one target: it opens Collection filtered to that status (and the medium of its newest
// title). Counts come from the whole Library; covers from Collection's bounded preview read.

/// Pure rules of the preview (tested in `KuroTests/ProfileLaneTests.swift`).
enum ProfileListsPolicy {
    /// The previewed statuses and their Library statuses.
    static let rows: [(status: ListStatus, covers: Set<ListStatus>)] = [
        (.current, [.current, .repeating]),
        (.planning, [.planning]),
        (.completed, [.completed])
    ]

    /// Titles per previewed status, both media.
    static func count(_ entries: [LibraryEntry], status: ListStatus) -> Int {
        let covered = rows.first { $0.status == status }?.covers ?? [status]
        return entries.filter { covered.contains($0.status) }.count
    }

    /// "42 anime · 86 manga · 51 completed" (real counts; never lifetime history).
    static func summary(_ entries: [LibraryEntry], german: Bool) -> String {
        let anime = entries.filter { $0.key.kind == .anime }.count
        let manga = entries.filter { $0.key.kind == .manga }.count
        let done = entries.filter { $0.status == .completed }.count
        return german
            ? "\(anime) Anime · \(manga) Manga · \(done) abgeschlossen"
            : "\(anime) anime · \(manga) manga · \(done) completed"
    }

    /// The row word for both media together.
    static func title(_ status: ListStatus, german: Bool) -> String {
        switch (status, german) {
        case (.current, false), (.repeating, false): return "Watching & reading"
        case (.current, true), (.repeating, true): return "Schaue & lese ich"
        case (.planning, false): return "Planned"
        case (.planning, true): return "Geplant"
        case (.completed, false): return "Completed"
        case (.completed, true): return "Abgeschlossen"
        case (.paused, false): return "Paused"
        case (.paused, true): return "Pausiert"
        case (.dropped, false): return "Dropped"
        case (.dropped, true): return "Abgebrochen"
        }
    }

    /// The Collection request a row opens: its status, in the medium of its newest cover.
    static func request(for status: ListStatus, covers: [Media]) -> CollectionListRequest {
        CollectionListRequest(medium: covers.first?.kind, status: status)
    }
}

struct ProfileListsPreview: View {
    let entries: [LibraryEntry]
    let previews: [ListStatus: [Media]]
    let previewFailed: Bool
    let onOpen: (CollectionListRequest) -> Void
    let onOpenCollection: () -> Void

    var body: some View {
        let german = KuroLocale.isGerman
        VStack(alignment: .leading, spacing: 0) {
            ForEach(ProfileListsPolicy.rows, id: \.status) { row in
                let count = ProfileListsPolicy.count(entries, status: row.status)
                if count > 0 {
                    ProfileListRow(
                        title: ProfileListsPolicy.title(row.status, german: german),
                        count: count,
                        covers: Array((previews[row.status] ?? []).prefix(CollectionStore.previewLimit))
                    ) {
                        onOpen(ProfileListsPolicy.request(for: row.status, covers: previews[row.status] ?? []))
                    }
                    Rectangle().fill(Color.kuroHairline).frame(height: 0.5)
                }
            }
            if previewFailed && previews.isEmpty {
                Text(german ? "Cover konnten nicht geladen werden. Die Zahlen sind aktuell."
                            : "Covers couldn't load. The counts are current.")
                    .font(.kuroMeta())
                    .foregroundStyle(Color.kuroInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, KuroDesignSpacing.sm)
            }
            KuroInkButton(german ? "Sammlung öffnen" : "Open Collection", role: .secondary, action: onOpenCollection)
                .padding(.top, KuroDesignSpacing.sm)
        }
    }
}

private struct ProfileListRow: View {
    let title: String
    let count: Int
    let covers: [Media]
    let action: () -> Void

    var body: some View {
        let german = KuroLocale.isGerman
        Button(action: {
            KuroAccessibility.impactHaptic(.light)
            action()
        }) {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: KuroDesignSpacing.sm) {
                    Text(title)
                        .font(.kuroTitle())
                        .foregroundStyle(Color.kuroInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(count)")
                        .font(.kuroMeta())
                        .foregroundStyle(Color.kuroInkSecondary)
                        .monospacedDigit()
                    Spacer(minLength: 0)
                }
                if !covers.isEmpty {
                    // Up to six equal covers; a narrow width shows fewer instead of shrinking them.
                    ViewThatFits(in: .horizontal) {
                        coverRow(covers)
                        coverRow(Array(covers.prefix(5)))
                        coverRow(Array(covers.prefix(4)))
                        coverRow(Array(covers.prefix(3)))
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.vertical, KuroDesignSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(KuroPressStyle(pressedScale: 0.99))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(german ? "\(title), \(count) Titel" : "\(title), \(count) \(count == 1 ? "title" : "titles")")
        .accessibilityHint(german ? "Öffnet diese Liste in der Sammlung" : "Opens this list in Collection")
    }

    private func coverRow(_ items: [Media]) -> some View {
        HStack(spacing: KuroDesignSpacing.sm) {
            ForEach(items, id: \.stableKey) { media in
                FolioArtwork(url: media.imageURL, width: 56, height: 80, cornerRadius: 2, maxPixelSize: 180, topBiased: true)
            }
        }
    }
}
