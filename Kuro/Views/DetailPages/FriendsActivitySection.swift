import SwiftUI
import KuroCore

// MARK: - Friends Activity Section for Media Detail Views
// Shows friend-level social activity for a title: who's tracking it, comments,
// and thumbs up/down reactions. "Friends" = users sharing at least one non-archived club.
// Privacy is enforced server-side via the shares_club_with() helper.
//
// Permission lifecycle (F03/F04): the section's activity belongs to the friend scope it was read under
// (`SocialActivityStore.friendScopeGeneration`). When that changes (a club revocation, also while
// another club keeps `hasClubs` true) the section drops what it shows and re-reads. A completion the
// store dropped (`CancellationError`: account or friend scope changed while in flight) never touches the
// section: no error, no cleared draft, no stale activity. Only the newest load publishes, and a saved
// comment clears the draft only if the draft is still the text that was saved.

struct FriendsActivitySection: View {
    let mediaId: Int
    let mediaType: String
    var editorial = false
    /// The divider and "Between us." heading; the prototype detail draws its own card heading.
    var showsHeading = true
    /// Reports the club members tracking this title whenever the shown activity changes ([] when it
    /// is cleared by a title or friend-scope change), so the page's club presence follows the same
    /// read and the same permission lifecycle.
    var onRoster: (([SocialActivityStore.FriendTitleActivity]) -> Void)? = nil
    /// Fixture renders only (KuroTests): shown instead of reading the activity.
    var preview: SocialActivityStore.FriendActivityResponse? = nil

    @Environment(ClubsStore.self) private var clubs
    @Environment(SocialActivityStore.self) private var social
    @State private var activity: SocialActivityStore.FriendActivityResponse?
    @State private var isLoading = true
    @State private var commentText = ""
    @State private var isSubmitting = false
    @State private var isEditing = false
    @State private var errorText: String?
    @State private var showDeleteConfirm = false
    /// The newest activity load; an older one never publishes (or ends the loading state).
    @State private var loadToken = 0
    @State private var containsSpoilers = false
    @State private var revealed: Set<String> = []
    @State private var loadingMore = false
    @State private var actionScope = AccountActionScope()
    /// Prototype card only: the "Who's watching" roster and the compose field start folded.
    @State private var showsRoster = false
    @State private var composing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The prototype detail card's presentation (`DetailBetweenUs`): presentation only, same reads/writes.
    private var prototypeStyle: Bool { !showsHeading }

    /// What the activity read depends on: the title and the friend scope (F03).
    private struct ActivityKey: Equatable {
        let mediaType: String
        let mediaId: Int
        let friendScope: Int
    }

    /// "Spoiler · Story" / "Spoiler · Ending" (prototype "Spoiler · Season N"). The stored scope is only
    /// `none`/`story`/`ending` (the `title_comments` check), so no season number is ever shown.
    static func spoilerLabel(_ scope: String?, german: Bool) -> String {
        switch scope?.lowercased() {
        case "story": return german ? "Spoiler · Handlung" : "Spoiler · Story"
        case "ending": return german ? "Spoiler · Ende" : "Spoiler · Ending"
        default: return "Spoiler"
        }
    }

    private var hasClubs: Bool {
        !clubs.myClubs.isEmpty
    }

    var body: some View {
        let origin = actionScope.capture(session: social.accountSession)
        let permission = social.friendScopeGeneration
        if hasClubs {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
                if showsHeading {
                    EditorialLayout.divider()

                    Text(editorial ? KuroLocale.text("Between us.", "Unter uns.") : KuroLocale.text("FRIENDS", "FREUNDE"))
                        .font(.kuroCaption(weight: .medium))
                        .tracking(1.6)
                        .foregroundColor(.kuroBlack80)
                        .accessibilityAddTraits(.isHeader)
                }

                if isLoading && activity == nil {
                    HStack(spacing: 10) {
                        KuroBusyMark(width: 24)
                        Text(KuroLocale.text("Loading…", "Wird geladen …"))
                            .font(.kuroCaption(weight: .light))
                            .foregroundColor(.kuroInkQuiet)
                    }
                } else if let activity {
                    // Friend tracking pills
                    if !activity.friends_tracking.isEmpty {
                        if prototypeStyle {
                            rosterDisclosure(activity.friends_tracking)
                        } else {
                            friendTrackingPills(activity.friends_tracking)
                        }
                    }

                    // Comments list
                    if !activity.comments.isEmpty {
                        commentsSection(activity.comments)
                    }
                    if activity.comments_next != nil || activity.friends_next != nil {
                        Button(loadingMore
                               ? KuroLocale.text("Loading…", "Wird geladen …")
                               : KuroLocale.text("More from your clubs", "Mehr aus deinen Clubs")) { Task { await loadMoreActivity() } }
                            .font(.kuroCaption()).frame(minHeight: 44).disabled(loadingMore)
                    }

                    // Comment input (own comment)
                    if let own = activity.own_comment, !activity.comments.contains(where: { $0.id == own.id }) { commentRow(own) }
                    commentInput(existing: activity.own_comment ?? activity.comments.first(where: { $0.is_own }))

                    if let errorText {
                        Text(errorText)
                            .font(.kuroCaption())
                            .foregroundColor(.red.opacity(0.85))
                    }
                } else {
                    Text(editorial
                         ? KuroLocale.text("A quiet room. Leave the first thought.", "Noch ist es still. Hinterlass den ersten Gedanken.")
                         : KuroLocale.text("No friends are following this yet.", "Noch verfolgt kein Freund diesen Titel."))
                        .font(.kuroCaption(weight: .light))
                        .foregroundColor(.kuroInkQuiet)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .alert(KuroLocale.text("Delete your comment?", "Deinen Kommentar löschen?"), isPresented: $showDeleteConfirm) {
                Button(KuroLocale.text("Delete", "Löschen"), role: .destructive) {
                    launchAction(origin: origin, permission: permission) { ticket in
                        do {
                            try await social.deleteTitleComment(
                                mediaType: mediaType,
                                mediaId: mediaId
                            )
                            guard mayPublish(ticket, permission: permission) else { return }
                            errorText = nil
                        } catch is CancellationError {
                            // Dropped by the store (the account changed): nothing of it is shown.
                            return
                        } catch {
                            guard mayPublish(ticket, permission: permission) else { return }
                            errorText = KuroLocale.text("Couldn't delete your comment. Try again.", "Kommentar konnte nicht gelöscht werden. Versuch es noch einmal.")
                        }
                        guard mayPublish(ticket, permission: permission) else { return }
                        await loadActivity()
                    }
                }
                Button(KuroLocale.text("Cancel", "Abbrechen"), role: .cancel) {}
            }
            .onAppear { actionScope.activate(session: social.accountSession) }
            .onDisappear {
                actionScope.deactivate()
                resetTitleState()
            }
            .task(id: ActivityKey(mediaType: mediaType, mediaId: mediaId, friendScope: social.friendScopeGeneration)) {
                resetTitleState()
                if let preview {
                    // Fixture renders only: the given activity, no read.
                    activity = preview
                    isLoading = false
                    return
                }
                await loadActivity()
            }
            .onChange(of: activity?.friends_tracking.map(\.user_id) ?? [], initial: true) { _, _ in
                onRoster?(activity?.friends_tracking ?? [])
            }
        }
    }

    // MARK: - Friend Tracking Pills

    /// "Who's watching ⌄ · N people" (prototype `.circle-members`), opening the pills.
    @ViewBuilder
    private func rosterDisclosure(_ friends: [SocialActivityStore.FriendTitleActivity]) -> some View {
        let manga = mediaType.uppercased() == "MANGA"
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(KuroMotion.detail(KuroMotion.settle, reduceMotion: reduceMotion)) { showsRoster.toggle() }
            } label: {
                HStack {
                    Text(manga ? KuroLocale.text("Who's reading", "Wer liest mit") : KuroLocale.text("Who's watching", "Wer schaut mit"))
                        .font(.kuroCustom(10, relativeTo: .footnote, maxSize: 22))
                        .foregroundStyle(Color.kuroInk)
                    Spacer()
                    Text(friends.count == 1 ? KuroLocale.text("1 person", "1 Person")
                                            : KuroLocale.text("\(friends.count) people", "\(friends.count) Personen"))
                        .font(.kuroCustom(9, relativeTo: .caption2, maxSize: 20))
                        .foregroundStyle(Color(hex: "61725D"))
                    Image(systemName: "chevron.down")
                        .font(.kuroCustom(8, relativeTo: .caption2, maxSize: 16))
                        .rotationEffect(.degrees(showsRoster ? 180 : 0))
                        .foregroundStyle(Color(hex: "61725D"))
                }
                .frame(minHeight: 47)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(showsRoster ? .isSelected : [])
            if showsRoster { friendTrackingPills(friends).padding(.bottom, 8) }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: "647C64", opacity: Double(0x26) / 255)).frame(height: 1) }
    }

    @ViewBuilder
    private func friendTrackingPills(_ friends: [SocialActivityStore.FriendTitleActivity]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(friends, id: \.user_id) { friend in
                    let name = friend.display_name ?? String(friend.user_id.prefix(6))
                    let detail = friendDetail(friend)

                    HStack(spacing: 4) {
                        Text(name)
                            .font(.kuroCaption(weight: .medium))
                            .foregroundColor(.kuroBlack65)
                            .lineLimit(1)

                        if !detail.isEmpty {
                            Text("\u{00B7}")
                                .foregroundColor(.kuroInkQuiet)
                            Text(detail)
                                .font(.kuroCaption(weight: .light))
                                .foregroundColor(.kuroInkQuiet)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(Color.kuroBlack05)
                    )
                }
            }
        }
    }

    private func friendDetail(_ friend: SocialActivityStore.FriendTitleActivity) -> String {
        let prefix = mediaType.uppercased() == "ANIME"
            ? KuroLocale.text("Ep.", "F.")
            : KuroLocale.text("Ch.", "Kap.")
        if let status = friend.status?.uppercased() {
            if status == "COMPLETED" { return statusLabel(status) }
            if let progress = friend.progress, progress > 0 {
                return "\(prefix) \(progress)"
            }
            return statusLabel(status)
        }
        return ""
    }

    /// A friend's status word for the medium (EN/DE, third person in German: "Schaut" / "Liest");
    /// an unknown value keeps its own text.
    private func statusLabel(_ status: String) -> String {
        let kind: MediaKind = mediaType.uppercased() == "MANGA" ? .manga : .anime
        return DetailCopy.listStatus(status, medium: kind, german: KuroLocale.isGerman, perspective: .other)
            ?? status.capitalized
    }

    // MARK: - Comments

    @ViewBuilder
    private func commentsSection(_ comments: [SocialActivityStore.TitleComment]) -> some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            ForEach(comments) { comment in
                commentRow(comment)
            }
        }
    }

    @ViewBuilder
    private func commentRow(_ comment: SocialActivityStore.TitleComment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                // Avatar initial (the prototype card shows the name alone)
                if !prototypeStyle {
                Text(String((comment.display_name ?? "?").prefix(1)).uppercased())
                    .font(.kuroMicro(weight: .semibold))
                    .foregroundColor(.kuroInkQuiet)
                    .frame(width: 20, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: KuroRadius.xs)
                            .fill(Color.kuroBlack06)
                    )
                }

                Text(comment.display_name ?? String(comment.user_id.prefix(6)))
                    .font(prototypeStyle ? .kuroCustom(11, weight: .semibold, relativeTo: .footnote, maxSize: 24) : .kuroCaption(weight: .medium))
                    .foregroundColor(prototypeStyle ? .kuroInk : .kuroBlack65)

                Text(relativeTime(comment.created_at))
                    .font(prototypeStyle ? .kuroCustom(8, relativeTo: .caption2, maxSize: 18) : .kuroMicro())
                    .foregroundColor(prototypeStyle ? Color(hex: "6B7B6D") : .kuroInkQuiet)

                Spacer(minLength: 0)

                // The prototype card keeps the reactions on the byline row (same buttons, same writes).
                if prototypeStyle && !comment.is_own {
                    reactionButton(comment: comment, type: "up", icon: "hand.thumbsup", count: comment.up_count,
                                   isActive: comment.my_reaction == "up")
                    reactionButton(comment: comment, type: "down", icon: "hand.thumbsdown", count: comment.down_count,
                                   isActive: comment.my_reaction == "down")
                }

                if comment.is_own {
                    Button {
                        isEditing = true
                        commentText = comment.text
                        containsSpoilers = comment.spoiler_scope != nil && comment.spoiler_scope != "none"
                    } label: {
                        Image(systemName: "pencil")
                            .font(.kuroCustom(10, weight: .regular, maxSize: 16))
                            .foregroundColor(.kuroInkQuiet)
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel(KuroLocale.text("Edit thought", "Gedanken bearbeiten"))

                    Button {
                        KuroAccessibility.impactHaptic(.light)
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.kuroCustom(10, weight: .regular, maxSize: 16))
                            .foregroundColor(.red.opacity(0.65))
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel(KuroLocale.text("Delete comment", "Kommentar löschen"))
                }
            }

            if comment.spoiler_scope != nil && comment.spoiler_scope != "none" && !comment.is_own && !revealed.contains(comment.id) {
                if prototypeStyle {
                    Button { revealed.insert(comment.id) } label: {
                        HStack {
                            Text(Self.spoilerLabel(comment.spoiler_scope, german: KuroLocale.isGerman))
                            Spacer()
                            Text(KuroLocale.text("Reveal", "Anzeigen"))
                                .font(.kuroCustom(9, relativeTo: .caption2, maxSize: 20))
                                .underline(color: Color(hex: "647C63", opacity: Double(0x40) / 255))
                        }
                        .font(.kuroCustom(10, relativeTo: .footnote, maxSize: 22))
                        .foregroundStyle(Color(hex: "526C56"))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(KuroLocale.text("Reveals a club member's spoiler", "Zeigt den Spoiler eines Clubmitglieds"))
                } else {
                Button(KuroLocale.text("Spoiler · Reveal", "Spoiler · Anzeigen")) { revealed.insert(comment.id) }
                    .font(.kuroCaption()).frame(minHeight: 44)
                    .accessibilityHint(KuroLocale.text("Reveals a club member's spoiler", "Zeigt den Spoiler eines Clubmitglieds"))
                }
            } else {
                Text(comment.text)
                    .font(prototypeStyle ? .kuroCustom(13, relativeTo: .callout, maxSize: 28) : .kuroBody(weight: .light))
                    .foregroundColor(prototypeStyle ? Color(hex: "405646") : .kuroBlack80).lineSpacing(prototypeStyle ? 5 : 4)
                if revealed.contains(comment.id) {
                    Button(KuroLocale.text("Hide spoiler", "Spoiler ausblenden")) { revealed.remove(comment.id) }.frame(minHeight: 44)
                }
            }

            // Reaction buttons
            if prototypeStyle && !comment.is_own {
                EmptyView()
            } else if !comment.is_own {
                HStack(spacing: 12) {
                    reactionButton(
                        comment: comment,
                        type: "up",
                        icon: "hand.thumbsup",
                        count: comment.up_count,
                        isActive: comment.my_reaction == "up"
                    )

                    reactionButton(
                        comment: comment,
                        type: "down",
                        icon: "hand.thumbsdown",
                        count: comment.down_count,
                        isActive: comment.my_reaction == "down"
                    )
                }
                .padding(.top, 2)
            } else {
                // Show counts for own comment (no toggle buttons)
                if comment.up_count > 0 || comment.down_count > 0 {
                    HStack(spacing: 12) {
                        if comment.up_count > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "hand.thumbsup.fill")
                                    .font(.kuroCustom(10, maxSize: 16))
                                Text("\(comment.up_count)")
                                    .font(.kuroMicro())
                            }
                            .foregroundColor(.kuroInkQuiet)
                        }
                        if comment.down_count > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "hand.thumbsdown.fill")
                                    .font(.kuroCustom(10, maxSize: 16))
                                Text("\(comment.down_count)")
                                    .font(.kuroMicro())
                            }
                            .foregroundColor(.kuroInkQuiet)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(.top, prototypeStyle ? 13 : 6)
        .padding(.bottom, prototypeStyle ? 14 : 6)
        .overlay(alignment: .bottom) {
            if prototypeStyle { Rectangle().fill(Color(hex: "6F8671", opacity: Double(0x20) / 255)).frame(height: 1) }
        }
    }

    @ViewBuilder
    private func reactionButton(
        comment: SocialActivityStore.TitleComment,
        type: String,
        icon: String,
        count: Int,
        isActive: Bool
    ) -> some View {
        let origin = actionScope.capture(session: social.accountSession)
        let permission = social.friendScopeGeneration
        return Button {
            KuroAccessibility.impactHaptic(.light)
            launchAction(origin: origin, permission: permission) { ticket in
                await toggleReaction(commentId: comment.id, type: type, origin: ticket, permission: permission)
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: isActive ? "\(icon).fill" : icon)
                    .font(.kuroCustom(10, weight: .regular, maxSize: 16))
                if count > 0 {
                    Text("\(count)")
                        .font(.kuroMicro())
                }
            }
            .foregroundColor(isActive ? .kuroBlack80 : .kuroInkQuiet)
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel(type == "up"
                            ? KuroLocale.text("Like thought", "Gedanken mögen")
                            : KuroLocale.text("Dislike thought", "Gedanken nicht mögen"))
    }

    // MARK: - Comment Input

    @ViewBuilder
    private func commentInput(existing: SocialActivityStore.TitleComment?) -> some View {
        let hasExisting = existing != nil && !isEditing
        let origin = actionScope.capture(session: social.accountSession)
        let permission = social.friendScopeGeneration

        if !hasExisting, prototypeStyle, !composing, !isEditing, commentText.isEmpty {
            leaveThoughtCard
        } else if !hasExisting {
            HStack(spacing: KuroDesignSpacing.sm) {
                TextField(
                    isEditing
                        ? KuroLocale.text("Edit your thought…", "Deinen Gedanken bearbeiten …")
                        : (editorial
                           ? KuroLocale.text("Leave a thought…", "Hinterlass einen Gedanken …")
                           : KuroLocale.text("Leave a comment…", "Hinterlass einen Kommentar …")),
                    text: $commentText,
                    axis: .vertical
                )
                .font(.kuroBody(weight: .light))
                .lineLimit(1...4)
                .onChange(of: commentText) { _, newValue in
                    if newValue.count > 500 {
                        commentText = String(newValue.prefix(500))
                    }
                }

                if isSubmitting {
                    KuroBusyMark(width: 24)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(KuroLocale.text("Posting", "Wird gesendet"))
                } else {
                    Button {
                        let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
                        let spoiler = editorial ? (containsSpoilers ? "story" : "none") : nil
                        launchAction(origin: origin, permission: permission) { ticket in
                            await submitComment(text: text, spoilerScope: spoiler, origin: ticket, permission: permission)
                        }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.kuroCustom(24, weight: .regular, maxSize: 38))
                            .foregroundColor(
                                canSubmit ? .kuroBlack70 : .kuroBlack20
                            )
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel(isEditing
                                        ? KuroLocale.text("Save thought", "Gedanken speichern")
                                        : KuroLocale.text("Post thought", "Gedanken teilen"))
                    .disabled(!canSubmit)
                }

                if isEditing {
                    Button {
                        isEditing = false
                        commentText = ""
                    } label: {
                        Text(KuroLocale.text("Cancel", "Abbrechen"))
                            .font(.kuroCaption(weight: .light))
                            .foregroundColor(.kuroInkQuiet)
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
                }
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.kuroBlack08, lineWidth: 0.8))
            if editorial { Toggle(KuroLocale.text("Contains spoilers", "Enthält Spoiler"), isOn: $containsSpoilers).font(.kuroCaption()).frame(minHeight: 44) }
        }
    }

    /// "Leave a thought · Shared with your clubs" (prototype `.circle-compose`), opening the field.
    private var leaveThoughtCard: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button {
            withAnimation(KuroMotion.detail(KuroMotion.settle, reduceMotion: reduceMotion)) { composing = true }
        } label: {
            HStack(spacing: 12) {
                Text("＋")
                    .font(.kuroCustom(20, weight: .light, relativeTo: .title3, maxSize: 32))
                    .foregroundStyle(Color(hex: "4E6849"))
                    .frame(width: 28, height: 28)
                    .overlay(Circle().strokeBorder(Color(hex: "ADC0A9"), lineWidth: 1))
                VStack(alignment: .leading, spacing: 5) {
                    Text(KuroLocale.text("Leave a thought", "Gedanken teilen"))
                        .font(.kuroCustom(12, weight: .medium, relativeTo: .subheadline, maxSize: 26))
                        .foregroundStyle(Color.kuroInk)
                    Text(KuroLocale.text("Shared with your clubs", "Mit deinen Clubs geteilt"))
                        .font(.kuroCustom(9, relativeTo: .caption2, maxSize: 20))
                        .foregroundStyle(Color(hex: "697E64"))
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.kuroCustom(13, weight: .medium, relativeTo: .body, maxSize: 24))
                    .foregroundStyle(Color.kuroInk)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(minHeight: 62)
            .background(Color(hex: "F6F8F1"), in: shape)
            .overlay(shape.strokeBorder(Color(hex: "CBD7C5"), lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(KuroPressStyle())
        .padding(.top, 11)
    }

    private var canSubmit: Bool {
        !commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmitting
    }

    // MARK: - Actions

    private func mayPublish(_ ticket: AccountActionScope.Ticket, permission: Int) -> Bool {
        actionScope.isCurrent(ticket, session: social.accountSession)
            && permission == social.friendScopeGeneration
    }

    private func launchAction(origin: AccountActionScope.Ticket?, permission: Int,
                              operation: @escaping @MainActor (AccountActionScope.Ticket) async -> Void) {
        guard permission == social.friendScopeGeneration else { return }
        actionScope.launch(origin: origin, session: social.accountSession) { ticket in
            guard mayPublish(ticket, permission: permission) else { return }
            await operation(ticket)
        }
    }

    private func resetTitleState() {
        composing = false
        showsRoster = false
        activity = nil
        errorText = nil
        loadToken += 1
        loadingMore = false
        isSubmitting = false
        commentText = ""
        containsSpoilers = false
        isEditing = false
        revealed = []
    }

    private func loadActivity() async {
        loadToken += 1
        let token = loadToken
        isLoading = true
        loadingMore = false
        defer {
            if token == loadToken { isLoading = false }
        }
        do {
            let loaded = try await social.fetchFriendActivityForTitle(
                mediaType: mediaType,
                mediaId: mediaId, paged: editorial
            )
            // A newer load (or a friend-scope reset) superseded this one.
            guard !Task.isCancelled, token == loadToken else { return }
            activity = loaded
            errorText = nil
        } catch is CancellationError { return
        } catch {
            if token == loadToken { errorText = KuroLocale.text("Couldn't load your club's thoughts. Try again.", "Die Gedanken deines Clubs konnten nicht geladen werden. Versuch es noch einmal.") }
            #if DEBUG
            print("[FriendsActivity] loadActivity error: \(error.localizedDescription)")
            #endif
        }
    }

    private func loadMoreActivity() async {
        guard !loadingMore, let previous = activity else { return }
        loadingMore = true
        let token = loadToken
        defer { if token == loadToken { loadingMore = false } }
        do {
            let page = try await social.fetchFriendActivityForTitle(mediaType: mediaType, mediaId: mediaId,
                paged: true, commentCursor: previous.comments_next, friendCursor: previous.friends_next)
            guard token == loadToken else { return }
            activity = .init(friends_tracking: previous.friends_tracking + page.friends_tracking.filter { item in
                !previous.friends_tracking.contains(where: { $0.user_id == item.user_id })
            }, comments: previous.comments + page.comments.filter { item in
                !previous.comments.contains(where: { $0.id == item.id })
            }, own_comment: page.own_comment ?? previous.own_comment,
            comments_next: previous.comments_next == nil ? nil : page.comments_next,
            friends_next: previous.friends_next == nil ? nil : page.friends_next)
        } catch is CancellationError { return }
        catch { if token == loadToken { errorText = KuroLocale.text("Couldn't load more thoughts. Try again.", "Weitere Gedanken konnten nicht geladen werden. Versuch es noch einmal.") } }
    }

    private func submitComment(text: String, spoilerScope: String?, origin: AccountActionScope.Ticket,
                               permission: Int) async {
        guard !text.isEmpty, mayPublish(origin, permission: permission) else { return }
        isSubmitting = true
        errorText = nil
        do {
            _ = try await social.upsertTitleComment(
                mediaType: mediaType,
                mediaId: mediaId,
                text: text,
                spoilerScope: spoilerScope
            )
            guard mayPublish(origin, permission: permission) else { return }
            // Clear the draft only if it is still the text that was saved (never a newer draft).
            if commentText.trimmingCharacters(in: .whitespacesAndNewlines) == text {
                commentText = ""
                isEditing = false
            }
        } catch is CancellationError {
            // Dropped by the store (the account changed while saving): no error over a newer state.
            if mayPublish(origin, permission: permission) { isSubmitting = false }
            return
        } catch {
            guard mayPublish(origin, permission: permission) else { return }
            errorText = KuroLocale.text("Couldn't save your comment. Try again.", "Kommentar konnte nicht gespeichert werden. Versuch es noch einmal.")
            KuroAccessibility.errorHaptic()
            isSubmitting = false
            return
        }
        guard mayPublish(origin, permission: permission) else { return }
        await loadActivity()
        guard mayPublish(origin, permission: permission) else { return }
        isSubmitting = false
    }

    private func toggleReaction(commentId: String, type: String, origin: AccountActionScope.Ticket,
                                permission: Int) async {
        guard mayPublish(origin, permission: permission) else { return }
        errorText = nil
        do {
            _ = try await social.toggleCommentReaction(
                commentId: commentId,
                reactionType: type
            )
            guard mayPublish(origin, permission: permission) else { return }
            await loadActivity()
        } catch {
            // Includes `CancellationError` (the friend scope or account changed): nothing is shown.
            #if DEBUG
            print("[FriendsActivity] toggleReaction error: \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: - Helpers

    private func relativeTime(_ isoString: String) -> String {
        guard let date = ClubsStore.parseISO8601(isoString) else { return "" }
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return KuroLocale.text("now", "jetzt") }
        if seconds < 3600 { return KuroLocale.text("\(Int(seconds / 60))m", "\(Int(seconds / 60)) Min.") }
        if seconds < 86400 { return KuroLocale.text("\(Int(seconds / 3600))h", "\(Int(seconds / 3600)) Std.") }
        return KuroLocale.text("\(Int(seconds / 86400))d", "\(Int(seconds / 86400)) T.")
    }
}
