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

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
                Text("Match \(item.title)").font(.kuroHeadline())
                Text("Choose the correct \(item.medium.capitalized) title. Kuro will show its current values for review before saving. This match affects only this import.")
                    .font(.kuroBody()).foregroundStyle(Color.kuroTextSecondary)
                TextField("Search \(item.medium.capitalized) catalog", text: $query)
                    .textFieldStyle(.roundedBorder).font(.kuroBody())
                    .accessibilityIdentifier("import.match.query")
                if busy { ProgressView("Searching catalog") }
                if let error { Text(error).font(.kuroBody()) }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
                        ForEach(results) { candidate in candidateRow(candidate) }
                        if results.isEmpty, !busy, !query.isEmpty, error == nil {
                            Text("No matching catalog title. Try another title or leave this item for later review.").font(.kuroBody())
                        }
                    }
                }
            }
            .padding(KuroDesignSpacing.lg)
            .background(Color.kuroBackground.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
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
            VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
                Text(candidate.title).font(.kuroTitle()).fixedSize(horizontal: false, vertical: true)
                Text(candidate.detail).font(.kuroCaption()).foregroundStyle(Color.kuroTextSecondary)
                Text("Select this \(item.medium.capitalized)").font(.kuroCaption())
            }.foregroundStyle(Color.kuroBlack80)
        }
        .padding(KuroDesignSpacing.md).background(Color.kuroBlack04, in: RoundedRectangle(cornerRadius: KuroRadius.md))
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
                        Candidate(id: $0.id, title: $0.title, detail: "Manga · \($0.format ?? "Unknown format")")
                    }
            } else {
                candidates = try await search.fetchSearchAnimePage(query: requested, filters: nil,
                    cursorRank: nil, cursorPopularity: nil, cursorId: nil, limit: 20).map {
                        Candidate(id: $0.id, title: $0.title, detail: "Anime · \($0.format ?? "Unknown format")")
                    }
            }
            guard scope.isCurrent(origin, session: imports.accountSession), requested == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            results = candidates
        } catch is CancellationError { return }
        catch {
            guard scope.isCurrent(origin, session: imports.accountSession), requested == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            self.error = "Catalog search could not be loaded. Try again."
        }
    }
}
