import SwiftUI

// MARK: - Studio Section (anime only)

struct StudioSection: View {
    let studios: [Studio]

    @State private var selectedStudio: Studio?

    var body: some View {
        if !studios.isEmpty {
            VStack(alignment: .leading, spacing: KuroSpacing.sm) {
                Text("STUDIO")
                    .font(.kuroCaption(weight: .semibold))
                    .tracking(1.6)
                    .foregroundColor(.kuroBlack80)

                ForEach(studios, id: \.id) { studio in
                    Button {
                        selectedStudio = studio
                    } label: {
                        HStack(spacing: 8) {
                            Text((studio.name ?? "Unknown").uppercased())
                                .font(.kuroTitle())
                                .foregroundColor(.kuroBlack80)

                            Spacer(minLength: 0)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.kuroTextTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Studio: \(studio.name ?? "Unknown")")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .sheet(item: $selectedStudio) { studio in
                StudioDetailSheet(studio: studio)
            }
        }
    }
}

// MARK: - Credits Section (anime only — curated roles)

struct CreditsSection: View {
    let staffItems: [(staff: Staff, role: String)]

    @State private var showAllCredits = false
    @State private var selectedStaff: Staff?

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
        if !curated.isEmpty {
            VStack(alignment: .leading, spacing: KuroSpacing.md) {
                Text("CREDITS")
                    .font(.kuroCaption(weight: .semibold))
                    .tracking(1.6)
                    .foregroundColor(.kuroBlack80)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(curated.prefix(5), id: \.staff.id) { item in
                        Button {
                            selectedStaff = item.staff
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.rawRole.uppercased())
                                    .font(.kuroMicro(weight: .regular))
                                    .tracking(1.2)
                                    .foregroundColor(.kuroTextSecondary)

                                Text((item.staff.nameFull ?? "Unknown"))
                                    .font(.kuroBody())
                                    .foregroundColor(.kuroBlack80)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if staffItems.count > curated.count || curated.count > 5 {
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
            .sheet(isPresented: $showAllCredits) {
                AllCreditsSheet(staffItems: staffItems)
            }
            .sheet(item: $selectedStaff) { staff in
                StaffDetailSheet(staff: staff)
            }
        }
    }
}

// MARK: - Authors Section (manga only — "CREATED BY")

struct AuthorsSection: View {
    let authorItems: [(author: Author, role: String)]

    @State private var selectedAuthor: Author?

    var body: some View {
        if !authorItems.isEmpty {
            VStack(alignment: .leading, spacing: KuroSpacing.sm) {
                Text("CREATED BY")
                    .font(.kuroCaption(weight: .semibold))
                    .tracking(1.6)
                    .foregroundColor(.kuroBlack80)

                ForEach(authorItems, id: \.author.id) { item in
                    Button {
                        selectedAuthor = item.author
                    } label: {
                        HStack(spacing: 8) {
                            HStack(spacing: 6) {
                                Text((item.author.nameFull ?? "Unknown").uppercased())
                                    .font(.kuroTitle())
                                    .foregroundColor(.kuroBlack80)

                                if !item.role.isEmpty {
                                    Text("— \(item.role.uppercased())")
                                        .font(.kuroMicro(weight: .light))
                                        .tracking(0.8)
                                        .foregroundColor(.kuroTextSecondary)
                                }
                            }

                            Spacer(minLength: 0)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.kuroTextTertiary)
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
