import AuthenticationServices
import SwiftUI

// Dedicated profile/settings page (moved out of the header to keep the top bar clean).
struct ProfileView: View {
    var onOpenConciergeImportReview: ((String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(SupabaseService.self) private var supabaseService
    @State private var isSyncing: Bool = false
    @State private var isProcessingAniListImport: Bool = false
    @State private var showClubs: Bool = false
    @State private var toast: KuroToastState? = nil
    @State private var showDeleteConfirmation: Bool = false
    @State private var isDeleting: Bool = false
    @State private var showServicePicker: Bool = false
    @State private var showAniListImportSheet: Bool = false
    @State private var importResult: ProfileImportResult? = nil
    @State private var streamingObservability: SupabaseService.StreamingObservabilitySnapshot? = nil
    @State private var isRefreshingStreamingObservability: Bool = false

    var body: some View {
        ZStack {
            ProfileBackdrop()
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: KuroDesignSpacing.lg) {
                    header
                        .padding(.top, KuroDesignSpacing.md)

                    stats
                        .padding(.horizontal, KuroDesignSpacing.padding)

                    clubsPreview
                        .padding(.horizontal, KuroDesignSpacing.padding)

                    if FeatureFlags.shared.isStreamingAvailabilityV1Enabled {
                        streamingFreshnessPreview
                            .padding(.horizontal, KuroDesignSpacing.padding)

                        streamingServicesPreview
                            .padding(.horizontal, KuroDesignSpacing.padding)
                    }

                    Rectangle()
                        .fill(Color.black.opacity(0.08))
                        .frame(height: 0.5)
                        .padding(.horizontal, KuroDesignSpacing.padding)

                    actions
                        .padding(.horizontal, KuroDesignSpacing.padding)

                    if let importResult {
                        importResultPreview(importResult)
                            .padding(.horizontal, KuroDesignSpacing.padding)
                    }

                    footer
                        .padding(.top, 6)

                    Spacer(minLength: 24)
                }
                .padding(.bottom, 48)
            }
            // Ensure the last rows can scroll fully above the home indicator / tab chrome.
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 24)
            }
        }
        .scrollContentBackground(.hidden)
        .transaction { $0.animation = nil }
        .task(id: supabaseService.currentUserEmail) {
            // Keep the profile "club context" warm so Clubs opens instantly.
            await supabaseService.fetchMyClubs()
            if FeatureFlags.shared.isStreamingAvailabilityV1Enabled {
                await refreshStreamingObservability()
            }
        }
        .overlay(alignment: .topTrailing) {
            Button(action: {
                KuroAccessibility.impactHaptic(.light)
                dismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .light))
                    .foregroundColor(.kuroBlack80)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Color.kuroSecondaryBackground.opacity(0.92))
                            .overlay(
                                Circle()
                                    .stroke(Color.black.opacity(0.08), lineWidth: 0.8)
                            )
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            .padding(.trailing, 14)
        }
        .overlay(alignment: .top) {
            if let toast {
                KuroToast(toast: toast)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showClubs) {
            NavigationStack {
                ClubsView()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Text("CLUBS")
                                .font(.kuroNavigation(weight: .regular))
                                .tracking(1.5)
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showClubs = false }
                                .font(.kuroBody(weight: .light))
                        }
                    }
            }
            .environment(supabaseService)
        }
        .sheet(isPresented: $showAniListImportSheet) {
            ConciergeAniListImportSheet(
                supabaseService: supabaseService,
                isGermanLocale: isGermanLocale
            ) { response in
                await handleAniListImportCompleted(response)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 92, height: 92)
                    .overlay(
                        LinearGradient(
                            colors: [Color.white.opacity(0.55), Color.black.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(Circle())
                        .opacity(0.95)
                    )
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.75), lineWidth: 0.8)
                            .blendMode(.overlay)
                    )
                    .overlay(
                        Circle().stroke(Color.black.opacity(0.10), lineWidth: 0.7)
                    )

                Text(supabaseService.currentUserInitial)
                    .font(.kuroFeature(weight: .light))
                    .foregroundColor(.kuroBlack80)
            }

            Text((supabaseService.currentUserEmail == nil ? "GUEST" : "KURO USER").uppercased())
                .font(.kuroCaption(weight: .medium))
                .tracking(2.0)
                .foregroundColor(.kuroBlack80)

            if let email = supabaseService.currentUserEmail, !email.isEmpty {
                Text(email.contains("privaterelay.appleid.com") ? "Signed in with Apple" : email)
                    .font(.kuroBody(weight: .light))
                    .foregroundColor(.kuroBlack60)
            } else {
                Text("Discover, track, enjoy.")
                    .font(.kuroBody(weight: .light))
                    .foregroundColor(.kuroBlack60)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var stats: some View {
        let animeLists = supabaseService.userLists.filter { $0.mediaType == "anime" }
        let mangaLists = supabaseService.userLists.filter { $0.mediaType == "manga" }
        let doneCount = supabaseService.userLists.filter { $0.status == .completed }.count
        let episodesWatched = animeLists.reduce(0) { $0 + $1.progress }
        let chaptersRead = mangaLists.reduce(0) { $0 + $1.progress }
        let scoredEntries = supabaseService.userLists.compactMap(\.score).filter { $0 > 0 }
        let avgRating = scoredEntries.isEmpty ? 0.0 : Double(scoredEntries.reduce(0, +)) / Double(scoredEntries.count)

        return VStack(spacing: 10) {
            HStack(spacing: 14) {
                ProfileStatTile(value: "\(animeLists.count)", label: "ANIME")
                ProfileStatTile(value: "\(mangaLists.count)", label: "MANGA")
                ProfileStatTile(value: "\(doneCount)", label: "DONE")
            }
            HStack(spacing: 14) {
                ProfileStatTile(value: "\(episodesWatched)", label: "EPISODES")
                ProfileStatTile(value: "\(chaptersRead)", label: "CHAPTERS")
                ProfileStatTile(value: scoredEntries.isEmpty ? "—" : String(format: "%.0f", avgRating), label: "AVG SCORE")
            }
        }
    }

    private var clubsPreview: some View {
        let clubs = supabaseService.myClubs

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("CLUBS")
                    .font(.kuroMicro(weight: .medium))
                    .tracking(2.0)
                    .foregroundColor(.kuroBlack60)

                Spacer(minLength: 0)

                Text("\(clubs.count)")
                    .font(.kuroMicro(weight: .medium))
                    .foregroundColor(.kuroBlack30)
                    .monospacedDigit()
            }

            if clubs.isEmpty {
                Text("Private clubs with shared rails. No feeds.")
                    .font(.kuroCaption(weight: .light))
                    .foregroundColor(.kuroBlack60)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(clubs.prefix(3)) { c in
                        Text(c.name)
                            .font(.kuroBody(weight: .light))
                            .foregroundColor(.kuroBlack80)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: KuroRadius.lg, style: .continuous)
                .fill(Color.kuroSecondaryBackground.opacity(0.90))
                .overlay(
                    RoundedRectangle(cornerRadius: KuroRadius.lg, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
                )
        )
    }

    private var streamingServicesPreview: some View {
        let services = supabaseService.userStreamingServices
        let registry = supabaseService.streamingServiceRegistry

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("SERVICES")
                    .font(.kuroMicro(weight: .medium))
                    .tracking(2.0)
                    .foregroundColor(.kuroBlack60)

                Spacer(minLength: 0)

                Text("\(services.count)")
                    .font(.kuroMicro(weight: .medium))
                    .foregroundColor(.kuroBlack30)
                    .monospacedDigit()
            }

            if services.isEmpty {
                Text("Set your streaming services to filter your collection.")
                    .font(.kuroCaption(weight: .light))
                    .foregroundColor(.kuroBlack60)
            } else {
                let displayNames = services.compactMap { slug in
                    registry.first(where: { $0.slug == slug })?.display_name
                }
                FlowLayout(spacing: 6) {
                    ForEach(displayNames, id: \.self) { name in
                        Text(name.uppercased())
                            .font(.kuroMicro(weight: .medium))
                            .tracking(0.8)
                            .foregroundColor(.black.opacity(0.55))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.06))
                            )
                    }
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: KuroRadius.lg, style: .continuous)
                .fill(Color.kuroSecondaryBackground.opacity(0.90))
                .overlay(
                    RoundedRectangle(cornerRadius: KuroRadius.lg, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
                )
        )
        .onTapGesture {
            KuroAccessibility.impactHaptic(.light)
            showServicePicker = true
        }
        .sheet(isPresented: $showServicePicker) {
            StreamingServicePickerSheet()
                .environment(supabaseService)
        }
    }

    private var streamingFreshnessPreview: some View {
        ProfileFreshnessCard(
            snapshot: streamingObservability,
            isRefreshing: isRefreshingStreamingObservability
        ) {
            Task { await refreshStreamingObservability() }
        }
    }

    @MainActor
    private func refreshStreamingObservability() async {
        isRefreshingStreamingObservability = true
        defer { isRefreshingStreamingObservability = false }
        await supabaseService.fetchStreamingServiceRegistry()
        await supabaseService.fetchUserStreamingServices()
        streamingObservability = await supabaseService.streamingObservabilitySnapshot()
    }

    private var actions: some View {
        VStack(spacing: 12) {
            ProfileActionRow(
                icon: "person.2",
                title: "Clubs",
                subtitle: "Shared rails, no feeds",
                trailing: "\(supabaseService.myClubs.count)"
            ) {
                showClubs = true
            }

            ProfileActionRow(
                icon: "arrow.triangle.2.circlepath",
                title: "Sync Data",
                subtitle: "Refresh your lists & rails"
            ) {
                Task {
                    isSyncing = true
                    defer { isSyncing = false }
                    await supabaseService.fetchUserLists()
                    await supabaseService.fetchCollectionItems()
                    await supabaseService.fetchUpcomingForUser(days: 7)
                    KuroAccessibility.successHaptic()
                    showToast(.success, title: "Synced", subtitle: "Lists updated")
                }
            }

            ProfileActionRow(
                icon: "square.and.arrow.down",
                title: isGermanLocale ? "Aus AniList importieren" : "Import from AniList",
                subtitle: isGermanLocale
                    ? "Vorschau und Import fur Anime- oder Manga-Listen"
                    : "Preview and import your anime or manga lists"
            ) {
                showAniListImportSheet = true
            }

            ProfileActionRow(
                icon: "trash",
                title: "Clear Cache",
                subtitle: "Reset image + detail caches",
                isDestructive: true
            ) {
                Task {
                    await KuroDiskDetailCache.clearAll()
                    URLCache.shared.removeAllCachedResponses()
                    KuroAccessibility.successHaptic()
                }
            }

            ProfileActionRow(
                icon: "arrow.right.circle",
                title: "Sign Out",
                subtitle: "Log out of your account",
                isDestructive: true
            ) {
                Task { await supabaseService.signOut() }
            }

            ProfileActionRow(
                icon: "person.crop.circle.badge.minus",
                title: "Delete Account",
                subtitle: "Permanently remove all data",
                isDestructive: true
            ) {
                showDeleteConfirmation = true
            }
            .alert("Delete Account", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete Everything", role: .destructive) {
                    Task {
                        isDeleting = true
                        defer { isDeleting = false }
                        do {
                            // For Apple users, obtain a fresh authorization code for token revocation.
                            var appleCode: String? = nil
                            if await supabaseService.isAppleUser {
                                appleCode = await obtainAppleAuthorizationCode()
                            }
                            try await supabaseService.deleteAccount(appleAuthorizationCode: appleCode)
                            dismiss()
                        } catch {
                            showToast(.error, title: "Deletion failed", subtitle: error.localizedDescription)
                        }
                    }
                }
            } message: {
                Text("This will permanently delete your account, lists, club memberships, and all associated data. This action cannot be undone.")
            }

            if isDeleting {
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.9)
                        .tint(.black.opacity(0.55))
                    Text("Deleting account...")
                        .font(.kuroCaption(weight: .light))
                        .foregroundColor(.black.opacity(0.55))
                    Spacer(minLength: 0)
                }
                .padding(.top, 6)
                .padding(.horizontal, 8)
            }

            if isSyncing {
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.9)
                        .tint(.kuroBlack60)
                    Text("Syncing…")
                        .font(.kuroCaption(weight: .light))
                        .foregroundColor(.kuroBlack60)
                    Spacer(minLength: 0)
                }
                .padding(.top, 6)
                .padding(.horizontal, 8)
            }

            if isProcessingAniListImport {
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.9)
                        .tint(.kuroBlack60)
                    Text(isGermanLocale ? "AniList wird importiert..." : "Importing from AniList...")
                        .font(.kuroCaption(weight: .light))
                        .foregroundColor(.kuroBlack60)
                    Spacer(minLength: 0)
                }
                .padding(.top, 6)
                .padding(.horizontal, 8)
            }
        }
    }

    private var isGermanLocale: Bool {
        let language = Locale.current.language.languageCode?.identifier.lowercased() ?? "en"
        return language.hasPrefix("de")
    }

    @ViewBuilder
    private func importResultPreview(_ result: ProfileImportResult) -> some View {
        ProfileImportResultCard(
            result: result,
            isGermanLocale: isGermanLocale,
            onDismiss: { importResult = nil },
            onContinueToConcierge: {
                guard case .needsReview(_, _, _, let importText) = result else { return }
                importResult = nil
                onOpenConciergeImportReview?(importText)
            }
        )
    }

    @MainActor
    private func handleAniListImportCompleted(_ response: SupabaseService.ConciergeAniListImportResponse) async {
        let importText = response.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard response.success, !importText.isEmpty else {
            showToast(
                .error,
                title: isGermanLocale ? "AniList-Import fehlgeschlagen" : "AniList import failed",
                subtitle: response.error ?? (isGermanLocale ? "Es wurden keine importierbaren Titel geliefert." : "AniList did not return importable titles.")
            )
            return
        }

        isProcessingAniListImport = true
        importResult = nil
        defer { isProcessingAniListImport = false }

        do {
            let parseResponse = try await supabaseService.conciergeParse(text: importText, scope: .both)
            guard parseResponse.success, !parseResponse.items.isEmpty else {
                showToast(
                    .error,
                    title: isGermanLocale ? "AniList-Import fehlgeschlagen" : "AniList import failed",
                    subtitle: isGermanLocale ? "Kuro konnte die importierten Titel nicht zuordnen." : "Kuro could not match the imported titles."
                )
                return
            }

            switch profileImportDecision(for: parseResponse, importText: importText) {
            case .apply(let payload):
                let applyResponse = try await supabaseService.conciergeApply(items: payload)
                guard applyResponse.success else {
                    let detail = applyResponse.errors?.first?.error
                        ?? (isGermanLocale ? "Die Titel konnten nicht ubernommen werden." : "The titles could not be applied.")
                    showToast(
                        .error,
                        title: isGermanLocale ? "Import fehlgeschlagen" : "Import failed",
                        subtitle: detail
                    )
                    return
                }

                await refreshProfileDataAfterImport()
                KuroAccessibility.successHaptic()
                importResult = makeAppliedImportResult(applyResponse: applyResponse, truncated: response.truncated == true)
            case .needsReview(let reviewText):
                KuroAccessibility.impactHaptic(.light)
                importResult = makeNeedsReviewImportResult(importText: reviewText, truncated: response.truncated == true)
            }
        } catch {
            showToast(
                .error,
                title: isGermanLocale ? "AniList-Import fehlgeschlagen" : "AniList import failed",
                subtitle: error.localizedDescription
            )
        }
    }

    private func profileImportDecision(
        for response: SupabaseService.ConciergeParseResponse,
        importText: String
    ) -> ProfileImportDecision {
        var selectedByItemId: [String: SupabaseService.ConciergeCandidate] = [:]
        var itemActions: [String: ImportItemAction] = [:]

        for item in response.items {
            guard item.ambiguity == nil else { return .needsReview(importText: importText) }
            guard item.existing_entry == nil else { return .needsReview(importText: importText) }
            guard let top = item.candidates.first else { return .needsReview(importText: importText) }
            guard top.score >= 0.85 else { return .needsReview(importText: importText) }
            guard !hasAmbiguousAdaptations(candidates: item.candidates, yearMention: item.parsed.yearMention) else {
                return .needsReview(importText: importText)
            }

            selectedByItemId[item.id] = top
            itemActions[item.id] = computeItemAction(item: item)
        }

        let payload = buildApplyPayload(
            from: response,
            selectedByItemId: selectedByItemId,
            itemActions: itemActions
        )

        guard !payload.isEmpty else {
            return .needsReview(importText: importText)
        }
        return .apply(payload: payload)
    }

    private func buildApplyPayload(
        from response: SupabaseService.ConciergeParseResponse,
        selectedByItemId: [String: SupabaseService.ConciergeCandidate],
        itemActions: [String: ImportItemAction]
    ) -> [[String: Any]] {
        response.items.compactMap { item -> [String: Any]? in
            guard let candidate = selectedByItemId[item.id] else { return nil }

            let action = itemActions[item.id] ?? .add
            guard action != .skip else { return nil }

            let mediaType = candidate.media_type
            let status = normalizedStatus(for: item.parsed.status, mediaType: mediaType)

            var payload: [String: Any] = [
                "raw": item.raw,
                "mediaType": mediaType.uppercased(),
                "mediaId": candidate.media_id,
                "status": status,
                "confidence": candidate.score,
                "action": action.rawValue,
            ]

            let parsed = item.parsed
            if let value = parsed.progressEpisodes { payload["progressEpisodes"] = value }
            if let value = parsed.progressChapters { payload["progressChapters"] = value }
            if let value = parsed.progressVolumes { payload["progressVolumes"] = value }
            if let value = parsed.seasonNumber { payload["seasonNumber"] = value }
            if let value = parsed.episodeInSeason { payload["episodeInSeason"] = value }
            if let value = parsed.caughtUp { payload["caughtUp"] = value }
            if let value = parsed.lastEpisode { payload["lastEpisode"] = value }
            if let value = parsed.completed { payload["completed"] = value }
            if let value = parsed.rating { payload["rating"] = value }

            if action == .update, let existing = item.existing_entry {
                var expected: [String: Any] = ["status": existing.status]
                if let episodes = existing.progress_episodes { expected["progress_episodes"] = episodes }
                if let chapters = existing.progress_chapters { expected["progress_chapters"] = chapters }
                if let volumes = existing.progress_volumes { expected["progress_volumes"] = volumes }
                payload["expectedExisting"] = expected
            }

            return payload
        }
    }

    private func computeItemAction(item: SupabaseService.ConciergeParseItem) -> ImportItemAction {
        guard let existing = item.existing_entry else { return .add }
        let diff = computeDiff(existing: existing, parsed: item.parsed)
        if let diff, !diff.isEmpty { return .update }
        return .skip
    }

    private func computeDiff(
        existing: SupabaseService.ConciergeExistingEntry,
        parsed: SupabaseService.ConciergeParseItemParsed
    ) -> ImportDiff? {
        var diff = ImportDiff()

        if let parsedStatus = parsed.status,
           parsedStatus.uppercased() != existing.status.uppercased() {
            diff.status = ImportDiff.FieldDiff(from: existing.status, to: parsedStatus.uppercased())
        }
        if let episodes = parsed.progressEpisodes,
           episodes != (existing.progress_episodes ?? 0) {
            diff.progressEpisodes = ImportDiff.FieldDiff(from: existing.progress_episodes ?? 0, to: episodes)
        }
        if let chapters = parsed.progressChapters,
           chapters != (existing.progress_chapters ?? 0) {
            diff.progressChapters = ImportDiff.FieldDiff(from: existing.progress_chapters ?? 0, to: chapters)
        }
        if let volumes = parsed.progressVolumes,
           volumes != (existing.progress_volumes ?? 0) {
            diff.progressVolumes = ImportDiff.FieldDiff(from: existing.progress_volumes ?? 0, to: volumes)
        }

        return diff.isEmpty ? nil : diff
    }

    private func normalizedStatus(for raw: String?, mediaType: String?) -> String {
        let status = (raw ?? "").uppercased()
        if mediaType == "manga", status == "WATCHING" { return "READING" }
        if mediaType == "anime", status == "READING" { return "WATCHING" }
        if status.isEmpty { return "PLANNING" }
        return status
    }

    private func strippedBaseTitle(_ raw: String) -> String {
        var title = raw
        if let range = title.range(of: #"\s*\([^)]*\)\s*$"#, options: .regularExpression) {
            title.removeSubrange(range)
        }
        if let range = title.range(of: ": ") {
            title = String(title[title.startIndex..<range.lowerBound])
        }
        return title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func hasAmbiguousAdaptations(
        candidates: [SupabaseService.ConciergeCandidate],
        yearMention: Int?
    ) -> Bool {
        guard candidates.count >= 2 else { return false }

        let top = candidates[0]
        let second = candidates[1]

        guard top.media_id != second.media_id else { return false }

        let baseTop = strippedBaseTitle(top.title_raw)
        let baseSecond = strippedBaseTitle(second.title_raw)
        guard baseTop == baseSecond else { return false }

        if let mentionedYear = yearMention, let topYear = top.year, topYear == mentionedYear {
            return false
        }

        return true
    }

    @MainActor
    private func refreshProfileDataAfterImport() async {
        await supabaseService.fetchUserLists()
        await supabaseService.fetchCollectionItems()
        await supabaseService.fetchUpcomingForUser(days: 7)
    }

    private func makeAppliedImportResult(
        applyResponse: SupabaseService.ConciergeApplyResponse,
        truncated: Bool
    ) -> ProfileImportResult {
        let appliedItems = applyResponse.applied ?? []
        let addCount = appliedItems.filter { $0.action == "add" }.count
        let updateCount = appliedItems.filter { $0.action == "update" }.count
        let conflictCount = applyResponse.conflicts?.count ?? 0

        var summaryParts: [String] = []
        if addCount > 0 {
            summaryParts.append(isGermanLocale ? "\(addCount) hinzugefugt" : "\(addCount) added")
        }
        if updateCount > 0 {
            summaryParts.append(isGermanLocale ? "\(updateCount) aktualisiert" : "\(updateCount) updated")
        }
        if summaryParts.isEmpty {
            summaryParts.append(
                isGermanLocale
                    ? "\(appliedItems.count) Titel ubernommen"
                    : "\(appliedItems.count) items applied"
            )
        }

        var detailParts: [String] = []
        if conflictCount > 0 {
            detailParts.append(
                isGermanLocale
                    ? "\(conflictCount) Konflikt\(conflictCount == 1 ? "" : "e") erfordern Prufung."
                    : "\(conflictCount) conflict\(conflictCount == 1 ? "" : "s") still need review."
            )
        }
        if truncated {
            detailParts.append(
                isGermanLocale
                    ? "AniList hat nur die ersten 200 Titel geliefert."
                    : "AniList only supplied the first 200 items."
            )
        }

        return .applied(
            title: isGermanLocale ? "Import abgeschlossen" : "Import completed",
            summary: summaryParts.joined(separator: ", "),
            detail: detailParts.isEmpty ? nil : detailParts.joined(separator: " ")
        )
    }

    private func makeNeedsReviewImportResult(importText: String, truncated: Bool) -> ProfileImportResult {
        let detail = truncated
            ? (isGermanLocale
                ? "AniList hat nur die ersten 200 Titel geliefert. Offne Concierge, um den Import zu prufen."
                : "AniList only supplied the first 200 items. Open Concierge to review this import.")
            : (isGermanLocale
                ? "Mindestens ein Titel braucht Bestatigung, bevor Kuro ihn ubernehmen kann."
                : "At least one title needs confirmation before Kuro can apply it.")

        return .needsReview(
            title: isGermanLocale ? "Prufung in Concierge erforderlich" : "Review needed in Concierge",
            summary: isGermanLocale
                ? "Dieser AniList-Import braucht noch eine kurze Prufung."
                : "This AniList import still needs a quick review.",
            detail: detail,
            importText: importText
        )
    }

    private func obtainAppleAuthorizationCode() async -> String? {
        await withCheckedContinuation { continuation in
            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = []
            let delegate = AppleAuthCodeDelegate { code in
                continuation.resume(returning: code)
            }
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = delegate
            // Keep delegate alive until callback fires.
            objc_setAssociatedObject(controller, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
            controller.performRequests()
        }
    }

    private func showToast(_ kind: KuroToastState.Kind, title: String, subtitle: String?) {
        withAnimation(.easeInOut(duration: 0.18)) {
            toast = KuroToastState(kind: kind, title: title, subtitle: subtitle, actionTitle: nil, onAction: nil)
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation(.easeInOut(duration: 0.18)) {
                toast = nil
            }
        }
    }

    private var footer: some View {
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
        let build = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "?"

        return VStack(spacing: 10) {
            if let url = URL(string: "https://kuro.app/privacy") {
                Link(destination: url) {
                    Text("Privacy Policy")
                        .font(.kuroCaption(weight: .light))
                        .foregroundColor(.kuroBlack60)
                        .underline(color: .kuroBlack30)
                }
                .buttonStyle(.plain)
            }

            Text("KURO  •  v\(version) (\(build))")
                .font(.kuroMicro(weight: .light))
                .tracking(1.6)
                .foregroundColor(.kuroBlack30)
        }
    }
}

private struct ProfileBackdrop: View {
    var body: some View {
        ZStack {
            Color.kuroBackground

            // Subtle "editorial" atmosphere so glass surfaces read as intentional, not flat.
            Circle()
                .fill(Color.black.opacity(0.035))
                .frame(width: 420, height: 420)
                .blur(radius: 70)
                .offset(x: -180, y: -260)

            Circle()
                .fill(Color.black.opacity(0.025))
                .frame(width: 520, height: 520)
                .blur(radius: 90)
                .offset(x: 220, y: -180)
        }
    }
}

private struct ProfileStatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 10) {
            Text(value)
                .font(.kuroHeadline(weight: .light))
                .foregroundColor(.kuroBlack80)

            Text(label)
                .font(.kuroMicro(weight: .medium))
                .tracking(2.2)
                .foregroundColor(.kuroTextTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.kuroSecondaryBackground.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

private struct ProfileActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var trailing: String? = nil
    var isDestructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: {
            KuroAccessibility.impactHaptic(.light)
            action()
        }) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(isDestructive ? .red.opacity(0.85) : .kuroBlack60)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.kuroBody(weight: .regular))
                        .foregroundColor(isDestructive ? .red.opacity(0.92) : .kuroBlack80)
                    Text(subtitle)
                        .font(.kuroCaption(weight: .light))
                        .foregroundColor(.kuroBlack60)
                }

                Spacer()

                if let trailing, !trailing.isEmpty {
                    Text(trailing)
                        .font(.kuroMicro(weight: .medium))
                        .foregroundColor(.kuroBlack30)
                        .monospacedDigit()
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.kuroTextTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.75), lineWidth: 0.8)
                            .blendMode(.overlay)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 0.8)
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 10)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Streaming Service Picker Sheet

private struct StreamingServicePickerSheet: View {
    @Environment(SupabaseService.self) private var supabaseService
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSlugs: Set<String> = []
    @State private var isSaving: Bool = false

    private var animeServices: [SupabaseService.StreamingServiceRecord] {
        supabaseService.streamingServiceRegistry.filter { $0.media_types.contains("ANIME") }
    }

    private var mangaServices: [SupabaseService.StreamingServiceRecord] {
        supabaseService.streamingServiceRegistry.filter { $0.media_types.contains("MANGA") }
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: KuroDesignSpacing.lg) {
                    Text("Select the services you use. This filters your collection and enables shared availability in clubs.")
                        .font(.kuroCaption(weight: .light))
                        .foregroundColor(.kuroBlack60)
                        .padding(.horizontal, 20)

                    if !animeServices.isEmpty {
                        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                            Text("ANIME")
                                .font(.kuroMicro(weight: .medium))
                                .tracking(2.0)
                                .foregroundColor(.kuroBlack60)
                                .padding(.horizontal, 20)

                            ForEach(animeServices) { svc in
                                ServiceToggleRow(
                                    name: svc.display_name,
                                    isSelected: selectedSlugs.contains(svc.slug)
                                ) {
                                    if selectedSlugs.contains(svc.slug) {
                                        selectedSlugs.remove(svc.slug)
                                    } else {
                                        selectedSlugs.insert(svc.slug)
                                    }
                                }
                            }
                        }
                    }

                    if !mangaServices.isEmpty {
                        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                            Text("MANGA")
                                .font(.kuroMicro(weight: .medium))
                                .tracking(2.0)
                                .foregroundColor(.kuroBlack60)
                                .padding(.horizontal, 20)

                            ForEach(mangaServices) { svc in
                                ServiceToggleRow(
                                    name: svc.display_name,
                                    isSelected: selectedSlugs.contains(svc.slug)
                                ) {
                                    if selectedSlugs.contains(svc.slug) {
                                        selectedSlugs.remove(svc.slug)
                                    } else {
                                        selectedSlugs.insert(svc.slug)
                                    }
                                }
                            }
                        }
                    }

                    Spacer(minLength: 24)
                }
                .padding(.top, KuroDesignSpacing.md)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("SERVICES")
                        .font(.kuroNavigation(weight: .regular))
                        .tracking(1.5)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            isSaving = true
                            await supabaseService.saveUserStreamingServices(Array(selectedSlugs))
                            isSaving = false
                            dismiss()
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.kuroBlack60)
                        } else {
                            Text("Save")
                                .font(.kuroBody(weight: .light))
                        }
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.kuroBody(weight: .light))
                }
            }
        }
        .onAppear {
            selectedSlugs = Set(supabaseService.userStreamingServices)
        }
    }
}

private struct ServiceToggleRow: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            KuroAccessibility.impactHaptic(.light)
            action()
        }) {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .light))
                    .foregroundColor(isSelected ? .kuroBlack80 : .kuroBlack30)

                Text(name)
                    .font(.kuroBody(weight: .regular))
                    .foregroundColor(.kuroBlack80)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

private enum ProfileImportDecision {
    case apply(payload: [[String: Any]])
    case needsReview(importText: String)
}

private enum ProfileImportResult: Identifiable {
    case applied(title: String, summary: String, detail: String?)
    case needsReview(title: String, summary: String, detail: String?, importText: String)

    var id: String {
        switch self {
        case let .applied(title, summary, _):
            return "applied-\(title)-\(summary)"
        case let .needsReview(title, summary, _, _):
            return "review-\(title)-\(summary)"
        }
    }

    var titleText: String {
        switch self {
        case let .applied(title, _, _), let .needsReview(title, _, _, _):
            return title
        }
    }

    var summaryText: String {
        switch self {
        case let .applied(_, summary, _), let .needsReview(_, summary, _, _):
            return summary
        }
    }

    var detailText: String? {
        switch self {
        case let .applied(_, _, detail), let .needsReview(_, _, detail, _):
            return detail
        }
    }
}

private struct ProfileImportResultCard: View {
    let result: ProfileImportResult
    let isGermanLocale: Bool
    let onDismiss: () -> Void
    let onContinueToConcierge: () -> Void

    private var eyebrow: String {
        switch result {
        case .applied:
            return isGermanLocale ? "IMPORT" : "IMPORT"
        case .needsReview:
            return isGermanLocale ? "PRUFUNG" : "REVIEW"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(eyebrow)
                        .font(.kuroMicro(weight: .medium))
                        .tracking(2.0)
                        .foregroundColor(.kuroBlack60)

                    Text(result.titleText)
                        .font(.kuroBody(weight: .regular))
                        .foregroundColor(.kuroBlack80)

                    Text(result.summaryText)
                        .font(.kuroCaption(weight: .light))
                        .foregroundColor(.kuroBlack60)
                        .fixedSize(horizontal: false, vertical: true)

                    if let detail = result.detailText {
                        Text(detail)
                            .font(.kuroCaption(weight: .light))
                            .foregroundColor(.kuroTextTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.kuroBlack60)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(Color.kuroBlack05)
                        )
                }
                .buttonStyle(.plain)
            }

            if case .needsReview = result {
                Button(action: onContinueToConcierge) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles.rectangle.stack")
                            .font(.system(size: 12, weight: .semibold))
                        Text(isGermanLocale ? "IN CONCIERGE PRUFEN" : "REVIEW IN CONCIERGE")
                            .font(.kuroMicro(weight: .medium))
                            .tracking(1.2)
                    }
                    .foregroundColor(.kuroWhite)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                            .fill(Color.kuroBlack80)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: KuroRadius.lg, style: .continuous)
                .fill(Color.kuroSecondaryBackground.opacity(0.90))
                .overlay(
                    RoundedRectangle(cornerRadius: KuroRadius.lg, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
                )
        )
    }
}

// MARK: - Apple Auth Code Delegate (for token revocation on account deletion)

private final class AppleAuthCodeDelegate: NSObject, ASAuthorizationControllerDelegate {
    private let completion: (String?) -> Void
    private var didComplete = false

    init(completion: @escaping (String?) -> Void) {
        self.completion = completion
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard !didComplete else { return }
        didComplete = true
        if let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
           let codeData = credential.authorizationCode,
           let code = String(data: codeData, encoding: .utf8) {
            completion(code)
        } else {
            completion(nil)
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        guard !didComplete else { return }
        didComplete = true
        completion(nil)
    }
}
