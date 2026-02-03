import SwiftUI

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

struct SearchView: View {
    @Environment(SupabaseService.self) private var supabaseService
    @State private var searchText: String = ""
    @State private var selectedCategories: Set<String> = []
    @State private var searchTask: Task<Void, Never>? = nil

    // Filter results based on search and categories (local composition over service results)
    private var filteredResults: [Anime] {
        var results = supabaseService.animeItems
        let tokens = searchText.tokens()
        if !tokens.isEmpty {
            results = results.filter { media in
                let haystack = (
                    (media.title) + " " +
                    (media.displayDescription) + " " +
                    ((media.genres ?? []).joined(separator: " "))
                ).normalized()
                return tokens.allSatisfy { haystack.contains($0) }
            }
        }
        if !selectedCategories.isEmpty {
            results = results.filter { media in
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
        return results
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.black.opacity(0.3))
                    .font(.system(size: 16, weight: .light))

                TextField("SEARCH ANIME", text: $searchText)
                    .font(.system(size: 14, weight: .light))
                    .tracking(0.5)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.black.opacity(0.05))
            .cornerRadius(0)
            .padding(.horizontal, 24)
            .padding(.top, 24)

            // Category pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(["TRENDING", "NEW SEASON", "CLASSICS", "HIDDEN GEMS"], id: \.self) { category in
                        CategoryPillSelectable(
                            title: category,
                            isSelected: selectedCategories.contains(category)
                        ) {
                            toggleCategory(category)
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.vertical, 20)

            // Results or hints
            Group {
                if !searchText.isEmpty || !selectedCategories.isEmpty {
                    if supabaseService.isLoading {
                        ProgressView("Searching...")
                            .padding(.top, 40)
                    } else if filteredResults.isEmpty {
                        VStack(spacing: 8) {
                            Text("NO RESULTS FOUND")
                                .font(.system(size: 11, weight: .regular))
                                .tracking(1.5)
                                .foregroundColor(.black.opacity(0.3))

                            Text("Try adjusting your search or filters")
                                .font(.system(size: 10, weight: .light))
                                .tracking(1.0)
                                .foregroundColor(.black.opacity(0.2))
                        }
                        .padding(.top, 60)
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 0) {
                                ForEach(filteredResults) { anime in
                                    SearchResultRowReal(media: anime)
                                    Rectangle()
                                        .fill(Color.black.opacity(0.08))
                                        .frame(height: 0.5)
                                }
                            }
                            .padding(.horizontal, 24)
                        }
                        // Disable implicit animations on list updates
                        .transaction { $0.animation = nil }
                    }
                } else {
                    Spacer()
                    VStack(spacing: 8) {
                        Text("BEGIN TYPING TO SEARCH")
                            .font(.system(size: 11, weight: .regular))
                            .tracking(1.5)
                            .foregroundColor(.black.opacity(0.3))

                        Text("DISCOVER YOUR NEXT OBSESSION")
                            .font(.system(size: 10, weight: .light))
                            .tracking(1.0)
                            .foregroundColor(.black.opacity(0.2))
                    }
                    .padding(.top, 80)
                    Spacer()
                }
            }
            // Ensure the Group switching doesn’t animate
            .transaction { $0.animation = nil }
        }
        .onChange(of: searchText) { _, _ in
            debounceSearch()
        }
        .onAppear {
            Task {
                if supabaseService.animeItems.isEmpty {
                    await supabaseService.fetchAnime()
                }
            }
        }
    }

    private func toggleCategory(_ category: String) {
        if selectedCategories.contains(category) {
            selectedCategories.remove(category)
        } else {
            selectedCategories.insert(category)
        }
        debounceSearch()
    }

    private func debounceSearch() {
        searchTask?.cancel()
        searchTask = Task {
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
                await performSearch()
            } catch { /* cancelled */ }
        }
    }

    private func performSearch() async { /* local filtering only */ }
}

#Preview {
    SearchView()
        .environment(SupabaseService.shared)
}
