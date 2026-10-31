import KuroCore
import SwiftUI

// MARK: - Add Item to Rail Sheet

struct AddItemToRailSheet: View {
    let railId: String
    let clubId: String
    let onAdded: () -> Void

    @Environment(ClubsStore.self) private var clubs
    @State private var actionScope = AccountActionScope()
    @Environment(SearchStore.self) private var search
    @Environment(\.dismiss) private var dismiss

    enum MediaTab: String, CaseIterable {
        case anime = "ANIME"
        case manga = "MANGA"
    }

    @State private var selectedMedia: MediaTab = .anime
    @State private var searchText = ""
    @State private var animeResults: [AnimeCard] = []
    @State private var mangaResults: [MangaCard] = []
    @State private var isSearching = false
    @State private var isAdding = false
    @State private var errorMessage: String? = nil
    @State private var searchTask: Task<Void, Never>? = nil

    var body: some View {
        let origin = actionScope.capture(session: clubs.accountSession)
        return NavigationStack {
            VStack(spacing: 0) {
                // Media type toggle
                Picker("Type", selection: $selectedMedia) {
                    ForEach(MediaTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.vertical, KuroDesignSpacing.sm)

                // Search field
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.kuroCustom(14, weight: .regular, relativeTo: .body))
                        .foregroundColor(.kuroBlack35)
                    TextField("Search titles...", text: $searchText)
                        .font(.kuroBody(weight: .light))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous)
                        .fill(Color.kuroBlack04)
                )
                .padding(.horizontal, 20)

                EditorialLayout.divider()
                    .padding(.top, KuroDesignSpacing.sm)

                // Error message
                if let errorMessage {
                    Text(errorMessage)
                        .font(.kuroCaption(weight: .light))
                        .foregroundColor(.red.opacity(0.85))
                        .padding(.horizontal, 20)
                        .padding(.top, KuroDesignSpacing.sm)
                }

                // Results
                if isAdding {
                    VStack(spacing: KuroDesignSpacing.md) {
                        ProgressView()
                            .scaleEffect(0.9)
                            .tint(.kuroBlack60)
                        Text("Adding...")
                            .font(.kuroCaption(weight: .light))
                            .foregroundColor(.kuroBlack60)
                    }
                    .padding(.top, KuroDesignSpacing.xxl)
                    Spacer()
                } else if isSearching && animeResults.isEmpty && mangaResults.isEmpty {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.kuroTextTertiary)
                        .padding(.top, KuroDesignSpacing.xxl)
                    Spacer()
                } else if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(spacing: KuroDesignSpacing.sm) {
                        Image(systemName: "text.magnifyingglass")
                            .font(.kuroCustom(20, weight: .light, relativeTo: .title3))
                            .foregroundColor(.kuroBlack30)
                        Text("Type to search")
                            .font(.kuroCaption(weight: .light))
                            .foregroundColor(.kuroBlack30)
                    }
                    .padding(.top, KuroDesignSpacing.xxl)
                    Spacer()
                } else if selectedMedia == .anime && animeResults.isEmpty && !isSearching {
                    Text("No anime found")
                        .font(.kuroCaption(weight: .light))
                        .foregroundColor(.kuroBlack30)
                        .padding(.top, KuroDesignSpacing.xxl)
                    Spacer()
                } else if selectedMedia == .manga && mangaResults.isEmpty && !isSearching {
                    Text("No manga found")
                        .font(.kuroCaption(weight: .light))
                        .foregroundColor(.kuroBlack30)
                        .padding(.top, KuroDesignSpacing.xxl)
                    Spacer()
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            if selectedMedia == .anime {
                                ForEach(animeResults) { card in
                                    RailSearchResultRow(
                                        title: card.title,
                                        imageURL: card.coverImageMedium,
                                        year: card.year,
                                        format: card.format
                                    ) {
                                        addItem(mediaType: "ANIME", mediaId: card.id, origin: origin)
                                    }
                                }
                            } else {
                                ForEach(mangaResults) { card in
                                    RailSearchResultRow(
                                        title: card.title,
                                        imageURL: card.coverImageMedium,
                                        year: card.year,
                                        format: card.format
                                    ) {
                                        addItem(mediaType: "MANGA", mediaId: card.id, origin: origin)
                                    }
                                }
                            }
                        }
                        .padding(.bottom, KuroDesignSpacing.xxl)
                    }
                }
            }
            .background(Color.kuroBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("ADD ITEM")
                        .font(.kuroNavigation(weight: .regular))
                        .tracking(1.5)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.kuroBody(weight: .light))
                }
            }
            .onChange(of: searchText) { _, _ in
                debouncedSearch()
            }
            .onChange(of: selectedMedia) { _, _ in
                debouncedSearch()
            }
            .onAppear { actionScope.activate(session: clubs.accountSession) }
            .onDisappear {
                actionScope.deactivate()
                isAdding = false
                isSearching = false
                searchTask?.cancel()
                searchTask = nil
            }
        }
    }

    private func debouncedSearch() {
        guard let origin = actionScope.capture(session: clubs.accountSession) else { return }
        searchTask?.cancel()
        errorMessage = nil
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            animeResults = []
            mangaResults = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
            await performSearch(query: query, origin: origin)
        }
    }

    private func performSearch(query: String, origin: AccountActionScope.Ticket) async {
        guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
        do {
            if selectedMedia == .anime {
                let results = try await search.fetchSearchAnimePage(
                    query: query, filters: nil, cursorRank: nil,
                    cursorPopularity: nil, cursorId: nil, limit: 20
                )
                guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
                animeResults = results
            } else {
                let results = try await search.fetchSearchMangaPage(
                    query: query, filters: nil, cursorRank: nil,
                    cursorPopularity: nil, cursorId: nil, limit: 20
                )
                guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
                mangaResults = results
            }
        } catch {
            if actionScope.isCurrent(origin, session: clubs.accountSession) {
                // Clear stale results so old rows aren't actionable
                if selectedMedia == .anime { animeResults = [] } else { mangaResults = [] }
                errorMessage = "Search failed. Check your connection and try again."
                #if DEBUG
                print("[ClubDetail] AddItemToRailSheet search: \(error)")
                #endif
            }
        }
        if actionScope.isCurrent(origin, session: clubs.accountSession) {
            isSearching = false
        }
    }

    private func addItem(mediaType: String, mediaId: Int, origin: AccountActionScope.Ticket?) {
        guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
        guard !isAdding else { return }
        isAdding = true
        errorMessage = nil
        actionScope.launch(origin: origin, session: clubs.accountSession) { ticket in
            do {
                _ = try await clubs.addRailItem(
                    railId: railId, mediaType: mediaType, mediaId: mediaId
                )
                guard actionScope.isCurrent(ticket, session: clubs.accountSession) else { return }
                KuroAccessibility.successHaptic()
                onAdded()
                dismiss()
            } catch {
                guard actionScope.isCurrent(ticket, session: clubs.accountSession) else { return }
                // The store's typed `ClubError` (structured add_club_rail_item codes, else the SQLSTATE
                // fallback); a transport failure or cancellation (not a `ClubError`) gets the generic copy.
                errorMessage = Self.mapRailItemError(error as? ClubError)
                KuroAccessibility.errorHaptic()
                isAdding = false
            }
        }
    }

    /// Maps an add_club_rail_item failure to a user-facing string.
    private static func mapRailItemError(_ error: ClubError?) -> String {
        switch error {
        case .duplicateItem?, .uniqueViolation?:
            // `uniqueViolation`: SQLSTATE 23505 without its DETAIL code (the SDK drops `details`).
            return "This title is already in this rail."
        case .notAMember?:
            return "You're no longer a member of this club."
        case .railLocked?:
            return "This rail is locked. Only admins can add items."
        case .mediaNotFound?:
            return "This title was not found in the catalog."
        case .invalidMediaType?:
            return "Invalid media type."
        case .unauthenticated?:
            return "Please sign in again to continue."
        case .noteTooLong?:
            return "Note is too long. Keep it under 280 characters."
        case .railNotFound?:
            return "This rail is no longer available."
        default:
            return "Could not add item. Please try again."
        }
    }
}

struct RailSearchResultRow: View {
    let title: String
    let imageURL: String?
    let year: String
    let format: String?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                KuroCachedAsyncImage(url: URL(string: imageURL ?? ""), maxPixelSize: 120) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 40, height: 56)
                            .clipped()
                    default:
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.kuroBlack06)
                            .frame(width: 40, height: 56)
                    }
                }
                .frame(width: 40, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.kuroBody(weight: .regular))
                        .foregroundColor(.kuroBlack85)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Text(year)
                            .font(.kuroCaption(weight: .light))
                            .foregroundColor(.kuroTextTertiary)
                        if let format, !format.isEmpty {
                            Text(format.lowercased())
                                .font(.kuroCaption(weight: .light))
                                .foregroundColor(.kuroTextTertiary)
                        }
                    }
                }

                Spacer()

                Image(systemName: "plus.circle")
                    .font(.kuroCustom(20, weight: .light, relativeTo: .title3))
                    .foregroundColor(.kuroBlack35)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Club Settings Sheet

struct ClubSettingsSheet: View {
    let bundle: ClubBundle
    let clubId: String
    let onDismiss: () -> Void
    /// Told `true` before the leave request and `false` when it fails (the parent tells a voluntary
    /// leave from a removal).
    var onLeaving: ((Bool) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(IdentityStore.self) private var identity
    @Environment(ClubsStore.self) private var clubs
    @State private var actionScope = AccountActionScope()

    @State private var isLeaving = false
    @State private var showLeaveConfirm = false
    @State private var leaveConfirmMessage = ""
    @State private var leaveErrorText: String? = nil

    private static let isoWithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let relFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    var body: some View {
        let origin = actionScope.capture(session: clubs.accountSession)
        return NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: KuroDesignSpacing.lg) {
                    // Club Info
                    VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                        Text("CLUB INFO")
                            .font(.kuroCaption(weight: .medium))
                            .tracking(1.6)
                            .foregroundColor(.kuroBlack30)
                            .accessibilityAddTraits(.isHeader)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(bundle.club.name)
                                .font(.kuroHeadline(weight: .light))
                                .foregroundColor(.kuroBlack80)

                            if let desc = bundle.club.description, !desc.isEmpty {
                                Text(desc)
                                    .font(.kuroBody(weight: .light))
                                    .foregroundColor(.kuroBlack60)
                            }

                            HStack(spacing: 12) {
                                Label("\(bundle.member_count) members", systemImage: "person.2")
                                    .font(.kuroCaption(weight: .light))
                                    .foregroundColor(.kuroBlack60)

                                Text(bundle.club.sharing_level.uppercased())
                                    .font(.kuroMicro(weight: .medium))
                                    .tracking(1.0)
                                    .foregroundColor(.kuroBlack60)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule().stroke(Color.kuroBlack12, lineWidth: 0.6)
                                    )
                            }

                            Text(sharingLevelDescription)
                                .font(.kuroCaption(weight: .light))
                                .foregroundColor(.kuroBlack30)
                        }
                    }

                    EditorialLayout.divider()

                    // Invite Code (owner/admin only)
                    if let code = bundle.club.invite_code {
                        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                            Text("INVITE CODE")
                                .font(.kuroCaption(weight: .medium))
                                .tracking(1.6)
                                .foregroundColor(.kuroBlack30)
                                .accessibilityAddTraits(.isHeader)

                            HStack(spacing: 12) {
                                Text(code)
                                    .font(.kuroCustom(20, weight: .medium, design: .monospaced, relativeTo: .title3))
                                    .tracking(2.0)
                                    .foregroundColor(.kuroBlack80)

                                Button {
                                    guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
                                    UIPasteboard.general.string = code
                                    KuroAccessibility.successHaptic()
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.kuroCustom(14, weight: .regular, relativeTo: .body))
                                        .foregroundColor(.kuroBlack60)
                                }
                                .buttonStyle(.plain)
                            }

                            ShareLink(
                                item: "Join my club \"\(bundle.club.name)\" in Kuro: kuro://join/\(code) — or enter code \(code) in the app.",
                                subject: Text("Join \(bundle.club.name) on Kuro"),
                                message: Text("Use this invite code to join: \(code)")
                            ) {
                                HStack(spacing: 8) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.kuroCustom(13, weight: .regular, relativeTo: .caption1))
                                    Text("SHARE INVITE")
                                        .font(.kuroCaption(weight: .medium))
                                        .tracking(1.6)
                                }
                                .foregroundColor(.kuroBlack80)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous)
                                        .stroke(Color.kuroBlack15, lineWidth: 0.8)
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        EditorialLayout.divider()
                    }

                    // Members
                    VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                        Text("MEMBERS")
                            .font(.kuroCaption(weight: .medium))
                            .tracking(1.6)
                            .foregroundColor(.kuroBlack30)
                            .accessibilityAddTraits(.isHeader)

                        ForEach(Array(bundle.members.enumerated()), id: \.element.user_id) { index, member in
                            let label = memberDisplayName(member, index: index)
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(Color.kuroBlack06)
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Text(String(label.prefix(1)).uppercased())
                                            .font(.kuroMicro(weight: .medium))
                                            .foregroundColor(.kuroBlack60)
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(label)
                                            .font(.kuroCaption(weight: .medium))
                                            .foregroundColor(.kuroBlack80)

                                        if member.user_id == identity.currentUserId {
                                            Text("YOU")
                                                .font(.kuroMicro(weight: .medium))
                                                .tracking(1.0)
                                                .foregroundColor(.kuroBlack45)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(
                                                    Capsule().stroke(Color.kuroBlack10, lineWidth: 0.6)
                                                )
                                        }
                                    }

                                    Text(joinedLabel(member.joined_at))
                                        .font(.kuroMicro())
                                        .foregroundColor(.kuroBlack30)
                                }

                                Spacer()

                                Text(member.role.uppercased())
                                    .font(.kuroMicro(weight: .medium))
                                    .tracking(1.0)
                                    .foregroundColor(member.role == "owner" ? .kuroBlack80 : .kuroTextTertiary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule().stroke(
                                            member.role == "owner" ? Color.kuroBlack20 : Color.kuroBlack08,
                                            lineWidth: 0.6
                                        )
                                    )
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    EditorialLayout.divider()

                    // Leave Club
                    if let leaveErrorText {
                        Text(leaveErrorText)
                            .font(.kuroCaption())
                            .foregroundColor(.red.opacity(0.85))
                    }

                    Button {
                        leaveConfirmMessage = computeLeaveMessage()
                        showLeaveConfirm = true
                    } label: {
                        HStack(spacing: 10) {
                            if isLeaving {
                                ProgressView().scaleEffect(0.8).tint(.red.opacity(0.85))
                            }
                            Text("LEAVE CLUB")
                                .font(.kuroCaption(weight: .medium))
                                .tracking(1.6)
                        }
                        .foregroundColor(.red.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous)
                                .stroke(Color.red.opacity(0.25), lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isLeaving)
                    .alert("Leave Club?", isPresented: $showLeaveConfirm) {
                        Button("Leave", role: .destructive) { leaveClub(origin: origin) }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text(leaveConfirmMessage)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, KuroDesignSpacing.md)
                .padding(.bottom, KuroDesignSpacing.xxl)
            }
            .background(Color.kuroBackground)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("SETTINGS")
                        .font(.kuroNavigation(weight: .regular))
                        .tracking(1.5)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDismiss()
                        dismiss()
                    }
                    .font(.kuroBody(weight: .light))
                }
            }
        }
        .onAppear { actionScope.activate(session: clubs.accountSession) }
        .onDisappear { actionScope.deactivate(); isLeaving = false }
    }

    private var sharingLevelDescription: String {
        switch bundle.club.sharing_level {
        case "private": return "Only aggregates. Members can't see each other's data."
        case "status": return "Members can see watch/read status but not progress numbers."
        case "progress": return "Members can see full progress, status, and ratings."
        default: return ""
        }
    }

    private func computeLeaveMessage() -> String {
        guard bundle.my_role == "owner" else {
            return "Leave \(bundle.club.name)? You'll need a new invite code to rejoin."
        }
        // Owner leaving: check for successor
        let others = bundle.members.filter { $0.role != "owner" }
        if others.isEmpty {
            return "You're the only member. This club will be deleted."
        }
        // Promote oldest admin, else oldest member
        let admins = others.filter { $0.role == "admin" }.sorted { $0.joined_at < $1.joined_at }
        if let successor = admins.first {
            return "Ownership will transfer to member \(String(successor.user_id.prefix(8)))... You'll need a new invite code to rejoin."
        }
        let sorted = others.sorted { $0.joined_at < $1.joined_at }
        if let successor = sorted.first {
            return "Ownership will transfer to member \(String(successor.user_id.prefix(8)))... You'll need a new invite code to rejoin."
        }
        return "You'll need a new invite code to rejoin."
    }

    private func leaveClub(origin: AccountActionScope.Ticket?) {
        guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
        isLeaving = true
        leaveErrorText = nil
        onLeaving?(true)
        actionScope.launch(origin: origin, session: clubs.accountSession) { ticket in
            do {
                try await clubs.leaveClub(clubId: clubId)
                guard actionScope.isCurrent(ticket, session: clubs.accountSession) else { return }
                KuroAccessibility.successHaptic()
                dismiss()
            } catch {
                guard actionScope.isCurrent(ticket, session: clubs.accountSession) else { return }
                onLeaving?(false)
                if (error as? ClubError) == .notAMember {
                    leaveErrorText = "You're no longer a member of this club."
                } else {
                    leaveErrorText = "Could not leave club. Please try again."
                }
                KuroAccessibility.errorHaptic()
            }
            if actionScope.isCurrent(ticket, session: clubs.accountSession) { isLeaving = false }
        }
    }

    private func memberDisplayName(_ member: ClubMember, index: Int) -> String {
        let trimmed = member.display_name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        // Stable short identifier from UUID (consistent across sessions)
        let compact = member.user_id.replacingOccurrences(of: "-", with: "")
        let short = String(compact.prefix(6))
        return short.isEmpty ? "Unknown" : short
    }

    private func joinedLabel(_ raw: String) -> String {
        guard let date = Self.isoWithFractional.date(from: raw) ?? Self.iso.date(from: raw) else {
            return "Joined recently"
        }
        return "Joined \(Self.relFormatter.localizedString(for: date, relativeTo: Date()))"
    }
}
