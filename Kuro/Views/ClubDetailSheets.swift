import KuroCore
import SwiftUI
import UIKit

// MARK: - Add Item to Rail Sheet

struct AddItemToRailSheet: View {
    let railId: String
    let clubId: String
    let onAdded: () -> Void

    @Environment(ClubsStore.self) private var clubs
    @State private var actionScope = AccountActionScope()
    @Environment(SearchStore.self) private var search
    @Environment(\.dismiss) private var dismiss

    @State private var selectedMedia: MediaKind = .anime
    @State private var searchText = ""
    @State private var animeResults: [AnimeCard] = []
    @State private var mangaResults: [MangaCard] = []
    @State private var isSearching = false
    @State private var isAdding = false
    @State private var errorMessage: String? = nil
    @State private var searchTask: Task<Void, Never>? = nil
    @FocusState private var searchFocused: Bool

    private var trimmedQuery: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        let origin = actionScope.capture(session: clubs.accountSession)
        return NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
                    KuroMediumSwitch(selection: $selectedMedia, size: .compact)

                    HStack(spacing: KuroDesignSpacing.sm) {
                        Image(systemName: "magnifyingglass")
                            .font(.kuroMeta())
                            .foregroundStyle(Color.kuroInkQuiet)
                            .accessibilityHidden(true)
                        TextField("", text: $searchText,
                                  prompt: Text(selectedMedia == .manga
                                               ? KuroLocale.text("Search manga", "Manga suchen")
                                               : KuroLocale.text("Search anime", "Anime suchen"))
                                    .foregroundStyle(Color.kuroInkQuiet))
                            .font(.kuroBody(weight: .regular))
                            .foregroundStyle(Color.kuroInk)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .submitLabel(.search)
                            .focused($searchFocused)
                            .accessibilityLabel(KuroLocale.text("Search titles", "Titel suchen"))
                    }
                    .padding(.horizontal, KuroDesignSpacing.md)
                    .frame(minHeight: 48)
                    .background(
                        RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                            .fill(Color.kuroCanvasQuiet)
                    )

                    if let errorMessage {
                        ClubInlineError(text: errorMessage)
                    }
                }
                .padding(.horizontal, KuroDesignSpacing.padding)
                .padding(.top, KuroDesignSpacing.sm)
                .padding(.bottom, KuroDesignSpacing.md)

                Rectangle().fill(Color.kuroHairline).frame(height: 1)

                results(origin: origin)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .kuroReadableWidth()
            .background(Color.kuroCanvasPage)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(KuroLocale.text("Add a title", "Titel hinzufügen"))
                        .font(.kuroTitleName(weight: .medium))
                        .foregroundStyle(Color.kuroInk)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(KuroLocale.text("Cancel", "Abbrechen")) { dismiss() }
                        .font(.kuroBody(weight: .regular))
                        .tint(Color.kuroInk)
                }
            }
            .onChange(of: searchText) { _, _ in
                debouncedSearch()
            }
            .onChange(of: selectedMedia) { _, _ in
                debouncedSearch()
            }
            .onAppear {
                actionScope.activate(session: clubs.accountSession)
                searchFocused = true
            }
            .onDisappear {
                actionScope.deactivate()
                isAdding = false
                isSearching = false
                searchTask?.cancel()
                searchTask = nil
            }
        }
        // A tool over the club page (N7/N8): visible grabber and Cancel; an add in flight is not
        // swiped away.
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isAdding)
    }

    @ViewBuilder
    private func results(origin: AccountActionScope.Ticket?) -> some View {
        let german = KuroLocale.isGerman
        if isAdding {
            KuroStateView(.loading, title: KuroLocale.text("Adding.", "Wird hinzugefügt."), layout: .page)
        } else if trimmedQuery.count < 2 {
            KuroStateView(.empty,
                          title: KuroLocale.text("Find a title.", "Finde einen Titel."),
                          message: KuroLocale.text("Type at least two letters.", "Gib mindestens zwei Buchstaben ein."),
                          layout: .page)
        } else if isSearching && animeResults.isEmpty && mangaResults.isEmpty {
            KuroStateView(.loading, title: KuroLocale.text("Searching.", "Suche läuft."), layout: .page)
        } else if errorMessage == nil,
                  (selectedMedia == .anime ? animeResults.isEmpty : mangaResults.isEmpty), !isSearching {
            KuroStateView(.empty,
                          title: german ? "Keine Titel passen zu „\(trimmedQuery)“." : "No titles match \u{201C}\(trimmedQuery)\u{201D}.",
                          layout: .page)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    if selectedMedia == .anime {
                        ForEach(animeResults) { card in
                            RailSearchResultRow(title: card.title, imageURL: card.coverImageMedium,
                                                year: card.year, format: card.format) {
                                addItem(mediaType: "ANIME", mediaId: card.id, origin: origin)
                            }
                        }
                    } else {
                        ForEach(mangaResults) { card in
                            RailSearchResultRow(title: card.title, imageURL: card.coverImageMedium,
                                                year: card.year, format: card.format) {
                                addItem(mediaType: "MANGA", mediaId: card.id, origin: origin)
                            }
                        }
                    }
                }
                .padding(.bottom, KuroDesignSpacing.xxl)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func debouncedSearch() {
        guard let origin = actionScope.capture(session: clubs.accountSession) else { return }
        searchTask?.cancel()
        errorMessage = nil
        let query = trimmedQuery
        guard query.count >= 2 else {
            animeResults = []
            mangaResults = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
            await performSearch(query: query, origin: origin)
        }
    }

    private func performSearch(query: String, origin: AccountActionScope.Ticket) async {
        guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
        let medium = selectedMedia
        do {
            if medium == .anime {
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
            if actionScope.isCurrent(origin, session: clubs.accountSession), !(error is CancellationError) {
                // Clear stale results so old rows aren't actionable
                if medium == .anime { animeResults = [] } else { mangaResults = [] }
                errorMessage = KuroLocale.text("Search didn't work. Check your connection and try again.",
                                               "Die Suche hat nicht geklappt. Prüf deine Verbindung und versuch es noch einmal.")
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
        searchFocused = false
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
                isAdding = false
                guard !(error is CancellationError) else { return }
                // The store's typed `ClubError` (structured add_club_rail_item codes, else the SQLSTATE
                // fallback); a transport failure (not a `ClubError`) gets the generic copy.
                let message = ClubCopy.addRailItemError(error as? ClubError, german: KuroLocale.isGerman)
                errorMessage = message
                AccessibilityNotification.Announcement(message).post()
                KuroAccessibility.errorHaptic()
            }
        }
    }
}

struct RailSearchResultRow: View {
    let title: String
    let imageURL: String?
    let year: String
    let format: String?
    let onTap: () -> Void

    private var meta: String {
        [year, format?.replacingOccurrences(of: "_", with: " ").capitalized]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: KuroDesignSpacing.md) {
                Color.kuroMissingArt
                    .frame(width: 40, height: 57)
                    .overlay {
                        KuroCachedAsyncImage(url: URL(string: imageURL ?? ""), maxPixelSize: 120) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            default:
                                Color.kuroMissingArt
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: KuroRadius.xs, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.kuroBody(weight: .medium))
                        .foregroundStyle(Color.kuroInk)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if !meta.isEmpty {
                        Text(meta)
                            .font(.kuroMeta())
                            .foregroundStyle(Color.kuroInkQuiet)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "plus")
                    .font(.kuroMeta(weight: .medium))
                    .foregroundStyle(Color.kuroInk)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.kuroCanvasQuiet))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, KuroDesignSpacing.padding)
            .padding(.vertical, KuroDesignSpacing.sm)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(KuroPressStyle(pressedScale: 0.99))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.kuroHairline).frame(height: 1).padding(.leading, KuroDesignSpacing.padding)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(KuroLocale.text("Add \(title)", "\(title) hinzufügen"))
        .accessibilityValue(meta)
        .accessibilityAddTraits(.isButton)
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
    @State private var didCopyCode = false

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

    var body: some View {
        let origin = actionScope.capture(session: clubs.accountSession)
        let german = KuroLocale.isGerman
        return NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: KuroDesignSpacing.lg) {
                    // Club
                    VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                        ClubSheetTitle(kicker: ClubsListCardRules.audienceLabel(sharingLevel: bundle.club.sharing_level, german: german),
                                       title: bundle.club.name)

                        if let desc = bundle.club.description?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
                            Text(desc)
                                .font(.kuroBody(weight: .light))
                                .foregroundStyle(Color.kuroInkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Text(ClubCopy.sharingDescription(bundle.club.sharing_level, german: german))
                            .font(.kuroMeta())
                            .foregroundStyle(Color.kuroInkQuiet)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    hairline

                    // Invite code (owner/admin only: the server sends it only to them)
                    if let code = bundle.club.invite_code {
                        VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
                            KuroSectionHeader(KuroLocale.text("Invite", "Einladen"), size: .title)

                            HStack(alignment: .center, spacing: KuroDesignSpacing.md) {
                                Text(verbatim: code)
                                    .font(.kuroCustom(24, weight: .medium, design: .monospaced, relativeTo: .title2, maxSize: 44))
                                    .tracking(3)
                                    .foregroundStyle(Color.kuroInk)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .accessibilityLabel(KuroLocale.text("Invite code", "Einladungscode"))
                                    .accessibilityValue(code.map(String.init).joined(separator: " "))

                                Button {
                                    guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
                                    UIPasteboard.general.string = code
                                    KuroAccessibility.successHaptic()
                                    withAnimation(KuroMotion.resolve(KuroMotion.settle)) { didCopyCode = true }
                                    AccessibilityNotification.Announcement(KuroLocale.text("Code copied", "Code kopiert")).post()
                                } label: {
                                    Label(didCopyCode ? KuroLocale.text("Copied", "Kopiert") : KuroLocale.text("Copy", "Kopieren"),
                                          systemImage: didCopyCode ? "checkmark" : "doc.on.doc")
                                        .font(.kuroMeta(weight: .medium))
                                        .foregroundStyle(Color.kuroInk)
                                        .padding(.horizontal, KuroDesignSpacing.md)
                                        .frame(minHeight: 44)
                                        .background(Capsule().fill(Color.kuroCanvasQuiet))
                                        .contentShape(Capsule())
                                }
                                .buttonStyle(KuroPressStyle())
                            }

                            ShareLink(
                                item: KuroLocale.text(
                                    "Join my club \u{201C}\(bundle.club.name)\u{201D} in Kuro: kuro://join/\(code). Or enter the code \(code) in the app.",
                                    "Tritt meinem Club „\(bundle.club.name)“ in Kuro bei: kuro://join/\(code). Oder gib den Code \(code) in der App ein."
                                ),
                                subject: Text(KuroLocale.text("Join \(bundle.club.name) on Kuro", "Tritt \(bundle.club.name) in Kuro bei")),
                                message: Text(KuroLocale.text("Invite code: \(code)", "Einladungscode: \(code)"))
                            ) {
                                VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                                    HStack(spacing: KuroDesignSpacing.md) {
                                        Text(KuroLocale.text("Share the invite", "Einladung teilen"))
                                            .font(.kuroButtonLabel(weight: .medium))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Image(systemName: "square.and.arrow.up")
                                            .font(.kuroMeta())
                                            .accessibilityHidden(true)
                                    }
                                    Rectangle().frame(height: 1).accessibilityHidden(true)
                                }
                                .foregroundStyle(Color.kuroInk)
                                .frame(minHeight: 52, alignment: .bottom)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(KuroPressStyle())
                        }

                        hairline
                    } else {
                        // Members get no code from the server: say who can invite instead of a dead end.
                        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                            KuroSectionHeader(KuroLocale.text("Invite", "Einladen"), size: .title)
                            Text(KuroLocale.text("Ask an owner or admin for the invite code.",
                                                 "Frag Inhaber:in oder Admin nach dem Einladungscode."))
                                .font(.kuroBody(weight: .light))
                                .foregroundStyle(Color.kuroInkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        hairline
                    }

                    // Members
                    VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                        KuroSectionHeader(
                            ClubsListCardRules.memberCountText(bundle.member_count, german: german)
                                ?? KuroLocale.text("Members", "Mitglieder"),
                            size: .title
                        )

                        ForEach(Array(bundle.members.enumerated()), id: \.element.user_id) { _, member in
                            memberRow(member)
                        }
                    }

                    hairline

                    // Leave
                    VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                        if let leaveErrorText {
                            ClubInlineError(text: leaveErrorText)
                        }

                        KuroInkButton(KuroLocale.text("Leave club", "Club verlassen"), role: .destructive, isLoading: isLeaving) {
                            leaveConfirmMessage = computeLeaveMessage()
                            showLeaveConfirm = true
                        }
                        .disabled(isLeaving)
                        .alert(KuroLocale.text("Leave this club?", "Club verlassen?"), isPresented: $showLeaveConfirm) {
                            Button(KuroLocale.text("Leave", "Verlassen"), role: .destructive) { leaveClub(origin: origin) }
                            Button(KuroLocale.text("Cancel", "Abbrechen"), role: .cancel) { }
                        } message: {
                            Text(leaveConfirmMessage)
                        }
                    }
                }
                .padding(.horizontal, KuroDesignSpacing.padding)
                .padding(.top, KuroDesignSpacing.md)
                .padding(.bottom, KuroDesignSpacing.xxl)
                .kuroReadableWidth()
            }
            .background(Color.kuroCanvasPage)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(KuroLocale.text("Done", "Fertig")) {
                        onDismiss()
                        dismiss()
                    }
                    .font(.kuroBody(weight: .semibold))
                    .tint(Color.kuroInk)
                }
            }
        }
        // A tool over the club page (N7/N8): visible grabber and Done; a leave in flight is not swiped away.
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isLeaving)
        .onAppear { actionScope.activate(session: clubs.accountSession) }
        .onDisappear { actionScope.deactivate(); isLeaving = false }
    }

    private var hairline: some View {
        Rectangle().fill(Color.kuroHairline).frame(height: 1)
    }

    private func memberRow(_ member: ClubMember) -> some View {
        let label = memberDisplayName(member)
        let isYou = member.user_id == identity.currentUserId
        let role = roleLabel(member.role)
        return HStack(spacing: KuroDesignSpacing.md) {
            Text(String(label.prefix(1)).uppercased())
                .font(.kuroCustom(13, weight: .semibold, relativeTo: .footnote, maxSize: 22))
                .foregroundStyle(Color.kuroInk)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.kuroCanvasQuiet))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(isYou ? KuroLocale.text("\(label) (you)", "\(label) (du)") : label)
                    .font(.kuroBody(weight: .medium))
                    .foregroundStyle(Color.kuroInk)
                if let joined = joinedLabel(member.joined_at) {
                    Text(joined)
                        .font(.kuroMeta())
                        .foregroundStyle(Color.kuroInkQuiet)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let role {
                Text(role)
                    .font(.kuroMeta(weight: member.role == "owner" ? .semibold : .regular))
                    .foregroundStyle(member.role == "owner" ? Color.kuroInk : Color.kuroInkSecondary)
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    private func roleLabel(_ role: String) -> String? {
        switch role {
        case "owner": return KuroLocale.text("Owner", "Inhaber")
        case "admin": return KuroLocale.text("Admin", "Admin")
        default: return nil
        }
    }

    private func computeLeaveMessage() -> String {
        ClubLeaveCopy.message(clubName: bundle.club.name, myRole: bundle.my_role,
                              memberCount: bundle.member_count, members: bundle.members,
                              german: KuroLocale.isGerman)
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
                    leaveErrorText = KuroLocale.text("You're no longer a member of this club.", "Du bist nicht mehr Mitglied dieses Clubs.")
                } else {
                    leaveErrorText = KuroLocale.text("Couldn't leave the club. Try again.", "Der Club konnte nicht verlassen werden. Versuch es noch einmal.")
                }
                KuroAccessibility.errorHaptic()
            }
            if actionScope.isCurrent(ticket, session: clubs.accountSession) { isLeaving = false }
        }
    }

    private func memberDisplayName(_ member: ClubMember) -> String {
        let trimmed = member.display_name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? KuroLocale.text("Member", "Mitglied") : trimmed
    }

    private func joinedLabel(_ raw: String) -> String? {
        guard let date = Self.isoWithFractional.date(from: raw) ?? Self.iso.date(from: raw) else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.locale = KuroLocale.locale
        let relative = formatter.localizedString(for: date, relativeTo: Date())
        return KuroLocale.text("Joined \(relative)", "Beigetreten \(relative)")
    }
}
