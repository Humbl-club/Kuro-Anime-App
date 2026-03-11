import SwiftUI

// MARK: - Production Section (anime — merged studios + credits)

struct ProductionSection: View {
    let studios: [Studio]
    let staffItems: [(staff: Staff, role: String)]

    @State private var selectedStudio: Studio?
    @State private var selectedStaff: Staff?
    @State private var showAllCredits = false

    private var curatedCredits: [(staff: Staff, role: CreditRole, rawRole: String)] {
        var seen = Set<Int>()
        var result: [(staff: Staff, role: CreditRole, rawRole: String)] = []
        for item in staffItems {
            guard let normalized = CreditRole.from(raw: item.role) else { continue }
            let key = normalized.rawValue * 100_000 + item.staff.id
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append((staff: item.staff, role: normalized, rawRole: item.role))
        }
        return result.sorted { $0.role.rawValue < $1.role.rawValue }
    }

    var body: some View {
        let curated = curatedCredits
        let hasContent = !studios.isEmpty || !curated.isEmpty
        if hasContent {
            VStack(alignment: .leading, spacing: KuroSpacing.md) {
                Text("PRODUCTION")
                    .font(.kuroCaption(weight: .semibold))
                    .tracking(1.6)
                    .foregroundColor(.kuroBlack80)
                    .accessibilityAddTraits(.isHeader)

                // Studios as inline tappable text with interpuncts
                if !studios.isEmpty {
                    ProductionStudiosLine(studios: studios, selectedStudio: $selectedStudio)
                }

                // Credits as editorial bylines (show top 2)
                ForEach(curated.prefix(2), id: \.staff.id) { item in
                    Button {
                        selectedStaff = item.staff
                    } label: {
                        HStack(spacing: 0) {
                            Text("\(item.role.editorialPrefix) ")
                                .font(.kuroCaption(weight: .regular))
                                .tracking(0.4)
                                .foregroundColor(.kuroTextSecondary)

                            Text((item.staff.nameFull ?? "Unknown").uppercased())
                                .font(.kuroBody(weight: .medium))
                                .tracking(0.3)
                                .foregroundColor(.kuroBlack80)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.role.editorialPrefix) \(item.staff.nameFull ?? "Unknown")")
                }

                // ALL CREDITS capsule
                if staffItems.count > curated.count || curated.count > 2 {
                    Button {
                        showAllCredits = true
                    } label: {
                        Text("ALL CREDITS")
                            .font(.kuroMicro(weight: .medium))
                            .tracking(1.2)
                            .foregroundColor(.kuroBlack80)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().stroke(Color.black.opacity(0.12), lineWidth: 0.7)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .sheet(item: $selectedStudio) { studio in
                StudioDetailSheet(studio: studio)
            }
            .sheet(item: $selectedStaff) { staff in
                StaffDetailSheet(staff: staff)
            }
            .sheet(isPresented: $showAllCredits) {
                AllCreditsSheet(staffItems: staffItems)
            }
        }
    }
}

// MARK: - Inline Studio Names with Interpuncts

private struct ProductionStudiosLine: View {
    let studios: [Studio]
    @Binding var selectedStudio: Studio?

    var body: some View {
        FlowLayout(spacing: 0) {
            ForEach(Array(studios.enumerated()), id: \.element.id) { index, studio in
                HStack(spacing: 0) {
                    if index > 0 {
                        Text(" \u{00B7} ")
                            .font(.kuroBody(weight: .regular))
                            .foregroundColor(.kuroTextTertiary)
                    }
                    Button {
                        selectedStudio = studio
                    } label: {
                        Text((studio.name ?? "Unknown").uppercased())
                            .font(.kuroBody(weight: .light))
                            .foregroundColor(.kuroBlack80)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Manga Production Section (authors as editorial bylines)

struct MangaProductionSection: View {
    let authorItems: [(author: Author, role: String)]

    @State private var selectedAuthor: Author?

    var body: some View {
        if !authorItems.isEmpty {
            VStack(alignment: .leading, spacing: KuroSpacing.md) {
                Text("PRODUCTION")
                    .font(.kuroCaption(weight: .semibold))
                    .tracking(1.6)
                    .foregroundColor(.kuroBlack80)
                    .accessibilityAddTraits(.isHeader)

                ForEach(authorItems, id: \.author.id) { item in
                    Button {
                        selectedAuthor = item.author
                    } label: {
                        HStack(spacing: 0) {
                            if !item.role.isEmpty {
                                Text("\(item.role.capitalized) by ")
                                    .font(.kuroCaption(weight: .regular))
                                    .tracking(0.4)
                                    .foregroundColor(.kuroTextSecondary)
                            }

                            Text((item.author.nameFull ?? "Unknown").uppercased())
                                .font(.kuroBody(weight: .medium))
                                .tracking(0.3)
                                .foregroundColor(.kuroBlack80)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Author: \(item.author.nameFull ?? "Unknown"), \(item.role)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .sheet(item: $selectedAuthor) { author in
                AuthorDetailSheet(author: author)
            }
        }
    }
}

// MARK: - All Credits Sheet

struct AllCreditsSheet: View {
    let staffItems: [(staff: Staff, role: String)]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedStaff: Staff?

    private var grouped: [(role: String, staff: [Staff])] {
        var dict: [String: [Staff]] = [:]
        var order: [String] = []
        for item in staffItems {
            let role = item.role.isEmpty ? "Other" : item.role
            if dict[role] == nil { order.append(role) }
            dict[role, default: []].append(item.staff)
        }
        return order.map { (role: $0, staff: dict[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KuroSpacing.lg) {
                    ForEach(grouped, id: \.role) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.role.uppercased())
                                .font(.kuroMicro(weight: .medium))
                                .tracking(1.4)
                                .foregroundColor(.kuroTextSecondary)

                            ForEach(group.staff, id: \.id) { person in
                                Button {
                                    selectedStaff = person
                                } label: {
                                    Text(person.nameFull ?? "Unknown")
                                        .font(.kuroBody())
                                        .foregroundColor(.kuroBlack80)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, ResponsiveLayout.padding())
                .padding(.vertical, KuroSpacing.lg)
            }
            .background(Color.kuroBackground)
            .navigationTitle("ALL CREDITS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.kuroBlack80)
                }
            }
        }
        .sheet(item: $selectedStaff) { staff in
            StaffDetailSheet(staff: staff)
        }
    }
}

// MARK: - Conformances for sheet presentation

extension Studio: Hashable {
    static func == (lhs: Studio, rhs: Studio) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension Staff: Hashable {
    static func == (lhs: Staff, rhs: Staff) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension Author: Hashable {
    static func == (lhs: Author, rhs: Author) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
