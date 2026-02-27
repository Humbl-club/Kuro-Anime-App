import SwiftUI

// MARK: - Friends Activity Section for Media Detail Views
// Shows friend-level social activity for a title: who's tracking it, comments,
// and thumbs up/down reactions. "Friends" = users sharing at least one non-archived club.
// Privacy is enforced server-side via the shares_club_with() helper.

struct FriendsActivitySection: View {
    let mediaId: Int
    let mediaType: String

    @Environment(SupabaseService.self) private var supabaseService
    @State private var activity: SupabaseService.FriendActivityResponse?
    @State private var isLoading = true
    @State private var commentText = ""
    @State private var isSubmitting = false
    @State private var isEditing = false
    @State private var errorText: String?

    private var hasClubs: Bool {
        !supabaseService.myClubs.isEmpty
    }

    var body: some View {
        if hasClubs {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
                EditorialLayout.divider()

                Text("FRIENDS")
                    .font(.kuroCaption(weight: .medium))
                    .tracking(1.6)
                    .foregroundColor(.kuroBlack80)
                    .accessibilityAddTraits(.isHeader)

                if isLoading && activity == nil {
                    HStack(spacing: 10) {
                        ProgressView().scaleEffect(0.8).tint(.black.opacity(0.45))
                        Text("Loading...")
                            .font(.kuroCaption(weight: .light))
                            .foregroundColor(.black.opacity(0.45))
                    }
                } else if let activity {
                    // Friend tracking pills
                    if !activity.friends_tracking.isEmpty {
                        friendTrackingPills(activity.friends_tracking)
                    }

                    // Comments list
                    if !activity.comments.isEmpty {
                        commentsSection(activity.comments)
                    }

                    // Comment input (own comment)
                    commentInput(existing: activity.comments.first(where: { $0.is_own }))

                    if let errorText {
                        Text(errorText)
                            .font(.kuroCaption())
                            .foregroundColor(.red.opacity(0.85))
                    }
                } else {
                    Text("No friends tracking this yet")
                        .font(.kuroCaption(weight: .light))
                        .foregroundColor(.black.opacity(0.45))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .task(id: mediaId) {
                await loadActivity()
            }
        }
    }

    // MARK: - Friend Tracking Pills

    @ViewBuilder
    private func friendTrackingPills(_ friends: [SupabaseService.FriendTitleActivity]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(friends, id: \.user_id) { friend in
                    let name = friend.display_name ?? String(friend.user_id.prefix(6))
                    let detail = friendDetail(friend)

                    HStack(spacing: 4) {
                        Text(name)
                            .font(.kuroCaption(weight: .medium))
                            .foregroundColor(.black.opacity(0.65))
                            .lineLimit(1)

                        if !detail.isEmpty {
                            Text("\u{00B7}")
                                .foregroundColor(.black.opacity(0.35))
                            Text(detail)
                                .font(.kuroCaption(weight: .light))
                                .foregroundColor(.black.opacity(0.45))
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(Color.black.opacity(0.05))
                    )
                }
            }
        }
    }

    private func friendDetail(_ friend: SupabaseService.FriendTitleActivity) -> String {
        let prefix = mediaType.uppercased() == "ANIME" ? "EP" : "CH"
        if let status = friend.status?.uppercased() {
            if status == "COMPLETED" { return "Completed" }
            if let progress = friend.progress, progress > 0 {
                return "\(prefix) \(progress)"
            }
            return statusLabel(status)
        }
        return ""
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "CURRENT", "WATCHING": return "Watching"
        case "READING": return "Reading"
        case "PLANNING", "PLANNED": return "Planning"
        case "PAUSED", "ON_HOLD": return "Paused"
        case "DROPPED": return "Dropped"
        default: return status.capitalized
        }
    }

    // MARK: - Comments

    @ViewBuilder
    private func commentsSection(_ comments: [SupabaseService.TitleComment]) -> some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            ForEach(comments) { comment in
                commentRow(comment)
            }
        }
    }

    @ViewBuilder
    private func commentRow(_ comment: SupabaseService.TitleComment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                // Avatar initial
                Text(String((comment.display_name ?? "?").prefix(1)).uppercased())
                    .font(.kuroMicro(weight: .semibold))
                    .foregroundColor(.black.opacity(0.50))
                    .frame(width: 20, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: KuroRadius.xs)
                            .fill(Color.black.opacity(0.06))
                    )

                Text(comment.display_name ?? String(comment.user_id.prefix(6)))
                    .font(.kuroCaption(weight: .medium))
                    .foregroundColor(.black.opacity(0.65))

                Text(relativeTime(comment.created_at))
                    .font(.kuroMicro())
                    .foregroundColor(.black.opacity(0.30))

                Spacer(minLength: 0)

                if comment.is_own {
                    Button {
                        isEditing = true
                        commentText = comment.text
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(.black.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(comment.text)
                .font(.kuroBody(weight: .light))
                .foregroundColor(.black.opacity(0.75))
                .lineSpacing(4)

            // Reaction buttons
            if !comment.is_own {
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
                                    .font(.system(size: 10))
                                Text("\(comment.up_count)")
                                    .font(.kuroMicro())
                            }
                            .foregroundColor(.black.opacity(0.35))
                        }
                        if comment.down_count > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "hand.thumbsdown.fill")
                                    .font(.system(size: 10))
                                Text("\(comment.down_count)")
                                    .font(.kuroMicro())
                            }
                            .foregroundColor(.black.opacity(0.35))
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func reactionButton(
        comment: SupabaseService.TitleComment,
        type: String,
        icon: String,
        count: Int,
        isActive: Bool
    ) -> some View {
        Button {
            KuroAccessibility.impactHaptic(.light)
            Task { await toggleReaction(commentId: comment.id, type: type) }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: isActive ? "\(icon).fill" : icon)
                    .font(.system(size: 10, weight: .regular))
                if count > 0 {
                    Text("\(count)")
                        .font(.kuroMicro())
                }
            }
            .foregroundColor(.black.opacity(isActive ? 0.65 : 0.35))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Comment Input

    @ViewBuilder
    private func commentInput(existing: SupabaseService.TitleComment?) -> some View {
        let hasExisting = existing != nil && !isEditing

        if !hasExisting {
            HStack(spacing: KuroDesignSpacing.sm) {
                TextField(
                    isEditing ? "Edit your comment..." : "Leave a comment...",
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
                    ProgressView().scaleEffect(0.75).tint(.black.opacity(0.45))
                } else {
                    Button {
                        Task { await submitComment() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundColor(
                                canSubmit ? .black.opacity(0.70) : .black.opacity(0.20)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)
                }

                if isEditing {
                    Button {
                        isEditing = false
                        commentText = ""
                    } label: {
                        Text("Cancel")
                            .font(.kuroCaption(weight: .light))
                            .foregroundColor(.black.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 0.8)
            )
        }
    }

    private var canSubmit: Bool {
        !commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmitting
    }

    // MARK: - Actions

    private func loadActivity() async {
        isLoading = true
        defer { isLoading = false }
        do {
            activity = try await supabaseService.fetchFriendActivityForTitle(
                mediaType: mediaType,
                mediaId: mediaId
            )
        } catch {
            #if DEBUG
            print("[FriendsActivity] loadActivity error: \(error.localizedDescription)")
            #endif
        }
    }

    private func submitComment() async {
        let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSubmitting = true
        errorText = nil
        do {
            _ = try await supabaseService.upsertTitleComment(
                mediaType: mediaType,
                mediaId: mediaId,
                text: text
            )
            commentText = ""
            isEditing = false
        } catch {
            errorText = "Could not save comment."
            KuroAccessibility.errorHaptic()
            isSubmitting = false
            return
        }
        await loadActivity()
        isSubmitting = false
    }

    private func toggleReaction(commentId: String, type: String) async {
        errorText = nil
        do {
            _ = try await supabaseService.toggleCommentReaction(
                commentId: commentId,
                reactionType: type
            )
            await loadActivity()
        } catch {
            #if DEBUG
            print("[FriendsActivity] toggleReaction error: \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: - Helpers

    private func relativeTime(_ isoString: String) -> String {
        guard let date = SupabaseService.parseISO8601(isoString) else { return "" }
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h" }
        return "\(Int(seconds / 86400))d"
    }
}
