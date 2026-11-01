import KuroCore
import KuroLibrary
import SwiftUI

/// Public catalog search only. Choosing a result stages a job-local mapping; it never saves tracking.
struct ImportCatalogMatchPicker: View {
    let imports: ImportsService
    let item: ImportReviewItem
    let onSelect: (Int) -> Void
    @Environment(SearchStore.self) private var search
    @Environment(\.dismiss) private var dismiss
    @State private var scope = AccountActionScope()
    @State private var query = ""
    @State private var results: [Candidate] = []
    @State private var busy = false
    @State private var error: String?

    private struct Candidate: Identifiable {
        let id: Int
        let title: String
        let detail: String
    }

    private var german: Bool { KuroLocale.isGerman }
    private var mediumWord: String { ImportCopy.medium(item.medium, german: german) }

    var body: some View {
        let g = german
        NavigationStack {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
                Text(g ? "„\(item.title)“ zuordnen" : "Match “\(item.title)”")
                    .kuroRoleText(.headline)
                    .foregroundStyle(Color.kuroInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(g ? "Wähle den richtigen \(mediumWord)-Titel. Vor dem Speichern siehst du seine aktuellen Werte. Die Zuordnung gilt nur für diesen Import."
                       : "Choose the right \(mediumWord) title. You'll see its current values before saving. This match applies to this import only.")
                    .font(.kuroBody()).foregroundStyle(Color.kuroInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: KuroDesignSpacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .font(.kuroCustom(14, relativeTo: .body, maxSize: 22))
                        .foregroundStyle(Color.kuroInkQuiet)
                        .accessibilityHidden(true)
                    TextField(g ? "\(mediumWord)-Katalog durchsuchen" : "Search the \(mediumWord) catalogue", text: $query)
                        .font(.kuroBody())
                        .foregroundStyle(Color.kuroInk)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .accessibilityIdentifier("import.match.query")
                }
                .padding(.horizontal, KuroDesignSpacing.md)
                .frame(minHeight: 44)
                .background(Color.kuroCanvasQuiet, in: RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous))
                if busy {
                    KuroStateView(.loading, title: g ? "Katalog wird durchsucht." : "Searching the catalogue.", layout: .inline)
                }
                if let error {
                    KuroStateView(.failed(hasCachedContent: !results.isEmpty), message: error, layout: .inline) {
                        Task { await find() }
                    }
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(results) { candidate in candidateRow(candidate) }
                        if results.isEmpty, !busy, !query.isEmpty, error == nil {
                            KuroStateView(.empty,
                                          title: g ? "Kein passender Katalogtitel." : "No matching catalogue title.",
                                          message: g ? "Versuch einen anderen Titel oder prüf diesen Eintrag später."
                                                     : "Try another title, or leave this one for later review.",
                                          layout: .inline)
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .padding(.horizontal, KuroDesignSpacing.padding)
            .padding(.vertical, KuroDesignSpacing.lg)
            .background(Color.kuroCanvasPage.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(g ? "Abbrechen" : "Cancel") { dismiss() }
                        .foregroundStyle(Color.kuroInk)
                }
            }
        }
        .tint(Color.kuroInk)
        .onAppear { scope.activate(session: imports.accountSession); query = item.title }
        .onDisappear { scope.deactivate() }
        .onChange(of: imports.accountSession.current) { _, _ in scope.deactivate(); dismiss() }
        .task(id: query) { await find() }
    }

    private func candidateRow(_ candidate: Candidate) -> some View {
        let origin = scope.capture(session: imports.accountSession)
        return Button {
            guard scope.isCurrent(origin, session: imports.accountSession) else { return }
            onSelect(candidate.id); dismiss()
        } label: {
            HStack(alignment: .center, spacing: KuroDesignSpacing.sm) {
                VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
                    Text(candidate.title)
                        .font(.kuroCustom(15, weight: .medium, relativeTo: .headline, maxSize: 30)).tracking(-0.2)
                        .foregroundStyle(Color.kuroInk)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(candidate.detail).font(.kuroMeta()).foregroundStyle(Color.kuroInkSecondary)
                }
                Spacer(minLength: KuroDesignSpacing.sm)
                Image(systemName: "arrow.right")
                    .font(.kuroCustom(13, weight: .medium, relativeTo: .footnote, maxSize: 20))
                    .foregroundStyle(Color.kuroInk)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.vertical, KuroDesignSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(KuroPressStyle(pressedScale: 0.99))
        .overlay(alignment: .bottom) { Rectangle().fill(Color.kuroHairline).frame(height: 0.5) }
        .accessibilityHint(german ? "Diesen Titel zuordnen" : "Matches this title")
    }

    private func find() async {
        let requested = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let origin = scope.capture(session: imports.accountSession) else { return }
        guard !requested.isEmpty else { results = []; error = nil; busy = false; return }
        busy = true; error = nil
        defer { if scope.isCurrent(origin, session: imports.accountSession), requested == query.trimmingCharacters(in: .whitespacesAndNewlines) { busy = false } }
        do {
            try await Task.sleep(for: .milliseconds(250))
            guard scope.isCurrent(origin, session: imports.accountSession) else { return }
            let candidates: [Candidate]
            if item.medium.lowercased() == "manga" {
                candidates = try await search.fetchSearchMangaPage(query: requested, filters: nil,
                    cursorRank: nil, cursorPopularity: nil, cursorId: nil, limit: 20).map {
                        Candidate(id: $0.id, title: $0.title, detail: ["Manga", $0.format].compactMap { $0 }.joined(separator: " · "))
                    }
            } else {
                candidates = try await search.fetchSearchAnimePage(query: requested, filters: nil,
                    cursorRank: nil, cursorPopularity: nil, cursorId: nil, limit: 20).map {
                        Candidate(id: $0.id, title: $0.title, detail: ["Anime", $0.format].compactMap { $0 }.joined(separator: " · "))
                    }
            }
            guard scope.isCurrent(origin, session: imports.accountSession), requested == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            results = candidates
        } catch is CancellationError { return }
        catch {
            guard scope.isCurrent(origin, session: imports.accountSession), requested == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            self.error = german ? "Die Katalogsuche konnte nicht geladen werden." : "Catalogue search couldn't load."
        }
    }
}
