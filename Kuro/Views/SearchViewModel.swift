import Foundation

@MainActor
@Observable
final class SearchViewModel {
    var query: String = ""
    var selectedCategories: Set<String> = []
    var results: [Anime] = []

    private var debounceTask: Task<Void, Never>?

    func updateQuery(_ text: String, allItems: [Anime]) {
        query = text
        debounce(allItems)
    }

    func toggleCategory(_ category: String, allItems: [Anime]) {
        if selectedCategories.contains(category) {
            selectedCategories.remove(category)
        } else {
            selectedCategories.insert(category)
        }
        debounce(allItems)
    }

    private func debounce(_ allItems: [Anime]) {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
                await self?.search(in: allItems)
            } catch { /* cancelled */ }
        }
    }

    func search(in allItems: [Anime]) async {
        let tokens = query.tokens()
        var filtered = allItems
        if !tokens.isEmpty {
            filtered = filtered.filter { media in
                let haystack = (
                    (media.title) + " " +
                    (media.displayDescription) + " " +
                    ((media.genres ?? []).joined(separator: " "))
                ).normalized()
                return tokens.allSatisfy { haystack.contains($0) }
            }
        }
        if !selectedCategories.isEmpty {
            filtered = filtered.filter { media in
                selectedCategories.contains { category in
                    switch category {
                    case "TRENDING":
                        return (media.averageScore ?? 0) > 80
                    case "NEW SEASON":
                        return (media.seasonYear ?? 0) >= 2024
                    case "CLASSICS":
                        return Int(media.year) ?? 0 < 2010
                    case "HIDDEN GEMS":
                        return (media.averageScore ?? 0) > 85 && Int(media.year) ?? 0 < 2015
                    default:
                        return false
                    }
                }
            }
        }
        results = filtered
    }
}

private extension String {
    func normalized() -> String {
        self.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
    func tokens() -> [String] {
        self.normalized()
            .split{ $0.isWhitespace || $0.isNewline }
            .map(String.init)
    }
}
