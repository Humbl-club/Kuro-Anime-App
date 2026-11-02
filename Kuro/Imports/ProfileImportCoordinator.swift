import AuthenticationServices
import Foundation
import KuroCore
import KuroLibrary
import Observation

/// One mounted account's Profile import policy: action identity, retries, file access and Undo.
/// Writes remain authoritative in ImportsService; rendering never starts a second tracking owner.
@MainActor
@Observable
final class ProfileImportCoordinator {
    private let imports: ImportsService
    private let library: LibraryStore
    private let collection: CollectionStore
    private let releases: ReleasesStore
    private let flags: FeatureFlags
    private let isGermanLocale: Bool
    private let accountContext: AccountContext?
    @ObservationIgnored private let applyAttempt = ImportApplyAttempt()
    @ObservationIgnored private let cardLifetime = ProfileImportCardLifetime()
    @ObservationIgnored private var operationTask: Task<Void, Never>?
    @ObservationIgnored private var undoTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var malImportAccount: AccountContext?
    @ObservationIgnored private var malRetryPending = false
    @ObservationIgnored private var preparedActionId: String?
    @ObservationIgnored private var structuredRetrySelection: ConciergeAniListImportResponse?
    private var closed = false
    private var preparedWorkflow: ImportOutcome?
    private(set) var workflowJob: ImportOutcome? {
        get { isCurrentAccount ? preparedWorkflow : nil }
        set { preparedWorkflow = newValue }
    }
    private(set) var isProcessingAniListImport = false
    private var retryOffered = false
    private var result: ProfileImportResult?
    private var notice: KuroToastState?
    private(set) var profileRetryOffered: Bool {
        get { isCurrentAccount && retryOffered }
        set { retryOffered = newValue }
    }
    private(set) var importResult: ProfileImportResult? {
        get { isCurrentAccount ? result : nil }
        set { result = newValue }
    }
    private(set) var toast: KuroToastState? {
        get { isCurrentAccount ? notice : nil }
        set { notice = newValue }
    }

    init(imports: ImportsService, library: LibraryStore, collection: CollectionStore,
         releases: ReleasesStore, flags: FeatureFlags, isGermanLocale: Bool) {
        self.imports = imports; self.library = library; self.collection = collection
        self.releases = releases; self.flags = flags; self.isGermanLocale = isGermanLocale
        self.accountContext = imports.accountSession.current
    }
    private var isCurrentAccount: Bool {
        !closed && accountContext != nil && imports.accountSession.isCurrent(accountContext)
    }
    private var mayPublish: Bool { isCurrentAccount && !Task.isCancelled }
    func dismissWorkflow() { workflowJob = nil }

    func refreshMALIdentity() async {
        guard mayPublish, flags.seriesFoundationV1Enabled else { return }
        do { _ = try await imports.refreshMALAccountIdentity() }
        catch is CancellationError { return }
        catch { /* A missing connection is shown by the source controls, not a success toast. */ }
    }

    @discardableResult
    func prepareConnectedMAL() -> Task<Void, Never>? {
        guard mayPublish, operationTask == nil, flags.seriesFoundationV1Enabled else { return nil }
        operationTask = Task { @MainActor in
            defer { self.operationTask = nil }
            await self.performMALAccountImport()
        }
        return operationTask
    }
    func beginAniListSelection() -> Bool {
        guard mayPublish, operationTask == nil else { return false }
        applyAttempt.abandon(); profileRetryOffered = false
        structuredRetrySelection = nil
        malRetryPending = false; preparedActionId = nil
        return true
    }
    func beginMALFileSelection() -> Bool {
        guard mayPublish, operationTask == nil else { return false }
        applyAttempt.abandon()
        structuredRetrySelection = nil
        malRetryPending = false
        profileRetryOffered = false; preparedActionId = nil
        malImportAccount = accountContext
        return true
    }
    func receiveMALFile(_ result: Result<URL, Error>) {
        guard mayPublish, operationTask == nil, malImportAccount == accountContext else { return }
        operationTask = Task { @MainActor in
            await self.handleMALExport(result)
            self.operationTask = nil
        }
    }
    func receiveAniList(_ response: ConciergeAniListImportResponse) async {
        guard mayPublish, operationTask == nil else { return }
        let task = Task { @MainActor in await self.handleAniListImportCompleted(response) }
        operationTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        operationTask = nil
    }
    @discardableResult
    func retry() -> Task<Void, Never>? {
        guard mayPublish, operationTask == nil else { return nil }
        operationTask = Task { @MainActor in
            if self.malRetryPending || self.structuredRetrySelection != nil {
                await self.resumePreparedSource()
            } else {
                await self.retryUnresolvedProfileImport()
            }
            self.operationTask = nil
        }
        return operationTask
    }
    /// A retry continues recorded input and action identity, never a second source gesture.
    private func resumePreparedSource() async {
        guard mayPublish, flags.seriesFoundationV1Enabled else { return }
        isProcessingAniListImport = true
        defer { isProcessingAniListImport = false }
        do {
            guard let actionId = preparedActionId else {
                profileRetryOffered = false
                showToast(.info, title: "Choose your source again", subtitle: "This action has no saved input to resume. Starting again creates a new review.")
                return
            }
            let job = try await imports.resumeImport(actionId: actionId)
            guard mayPublish else { return }
            malRetryPending = false; structuredRetrySelection = nil; profileRetryOffered = false
            workflowJob = job
        } catch is CancellationError { return }
        catch {
            guard mayPublish else { return }
            profileRetryOffered = true
            showToast(.error, title: "Import paused", subtitle: error.localizedDescription)
        }
    }

    @discardableResult
    func connectAndImportMAL(presentationAnchor: ASPresentationAnchor) -> Task<Void, Never>? {
        guard mayPublish, operationTask == nil, imports.malAccountAvailable else { return nil }
        applyAttempt.abandon(); structuredRetrySelection = nil; malRetryPending = false; preparedActionId = nil
        profileRetryOffered = false
        dismissImportResult()
        operationTask = Task { @MainActor in
            defer { self.operationTask = nil }
            guard self.mayPublish else { return }
            guard self.flags.seriesFoundationV1Enabled else {
                self.showToast(.info, title: "MAL account", subtitle: "Library synchronization is not enabled yet.")
                return
            }
            do {
                try await self.imports.connectMALAccount(presentationAnchor: presentationAnchor)
                guard self.mayPublish else { return }
                await self.performMALAccountImport()
            } catch is CancellationError { return }
            catch {
                guard self.mayPublish else { return }
                self.showToast(.error, title: "MAL account", subtitle: "The account could not be connected. Nothing was imported.")
            }
        }
        return operationTask
    }

    func disconnectMALAccount() {
        guard mayPublish, operationTask == nil else { return }
        do {
            try imports.disconnectMALAccount()
            malRetryPending = false; profileRetryOffered = false
            showToast(.info, title: "MAL account", subtitle: "Disconnected. Your Kuro library was kept.")
        } catch { showToast(.error, title: "MAL account", subtitle: "Credentials could not be removed.") }
    }

    private func performMALAccountImport() async {
        guard mayPublish else { return }
        malRetryPending = true; preparedActionId = nil
        guard flags.seriesFoundationV1Enabled, imports.malAccountAvailable else {
            profileRetryOffered = true
            showToast(.info, title: "Import paused", subtitle: "Retry when MAL synchronization is available again.")
            return
        }
        dismissImportResult()
        profileRetryOffered = false; isProcessingAniListImport = true
        defer { isProcessingAniListImport = false }
        do {
            let job = try await imports.prepareMALAccountImport(onActionId: { [weak self] actionId in
                guard let self, self.mayPublish else { return }
                self.preparedActionId = actionId
            })
            guard mayPublish else { return }
            malRetryPending = false
            workflowJob = job
        } catch is CancellationError { return }
        catch {
            guard mayPublish else { return }
            profileRetryOffered = true
            showToast(.error, title: "Import paused", subtitle: "Source reading did not finish. Retry resumes the saved input; nothing is saved before review.")
        }
    }

    @discardableResult
    func undo() -> Task<Void, Never>? {
        guard mayPublish, undoTask == nil else { return nil }
        undoTask = Task { @MainActor in
            await self.undoProfileImport()
            self.undoTask = nil
        }
        return undoTask
    }
    func stop() {
        closed = true
        operationTask?.cancel(); operationTask = nil
        undoTask?.cancel(); undoTask = nil
        toastTask?.cancel(); toastTask = nil
        applyAttempt.abandon(); cardLifetime.invalidate()
        malImportAccount = nil; importResult = nil; toast = nil
        structuredRetrySelection = nil
        malRetryPending = false; preparedActionId = nil
        workflowJob = nil
        profileRetryOffered = false; isProcessingAniListImport = false
    }
    private func showToast(_ kind: KuroToastState.Kind, title: String, subtitle: String?) {
        guard mayPublish else { return }
        toastTask?.cancel()
        let notice = KuroToastState(kind: kind, title: title, subtitle: subtitle, actionTitle: nil, onAction: nil)
        toast = notice
        toastTask = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 2_500_000_000) } catch { return }
            guard self.mayPublish, self.toast?.id == notice.id else { return }
            self.toast = nil
        }
    }

    @MainActor
    private func handleMALExport(_ result: Result<URL, Error>) async {
        guard malImportAccount == accountContext, mayPublish else { return }
        guard flags.seriesFoundationV1Enabled else {
            showToast(.error, title: "MAL export", subtitle: "The library update is not enabled yet. Nothing was sent.")
            return
        }
        isProcessingAniListImport = true
        defer { isProcessingAniListImport = false }
        do {
            let url = try result.get()
            dismissImportResult()
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            guard let size, size <= MALExportParser.maxBytes else { throw MALExportError.tooLarge }
            let read = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                return try Data(contentsOf: url, options: .mappedIfSafe)
            }
            let data = try await withTaskCancellationHandler { try await read.value } onCancel: { read.cancel() }
            guard mayPublish else { return }
            let job = try await imports.prepareMALFileImport(data: data, label: url.lastPathComponent)
            guard mayPublish else { return }
            workflowJob = job
        } catch is CancellationError {
            return
        } catch {
            guard mayPublish else { return }
            if (error as NSError).domain == NSCocoaErrorDomain, (error as NSError).code == NSUserCancelledError { return }
            showToast(.error, title: "MAL source reading paused", subtitle: ((error as? ImportFailure) ?? imports.importError)?.localizedDescription ?? error.localizedDescription)
        }
    }

    private func importCountLine(_ counts: LibraryImportCounts, partial: Bool) -> String {
        var line = "\(counts.added) added, \(counts.updated) updated, \(counts.conflict) conflicts, \(counts.unmatched) unmatched"
        if partial { line += ". The provider stopped before the last page." }
        return line
    }

    /// Retry is pinned to the structured job even when rollout changes. Disabled execution
    /// retains its recovery choice; it never reparses provider text into a new legacy Apply.
    private func performStructuredAniListImport(_ response: ConciergeAniListImportResponse) async {
        guard mayPublish else { return }
        guard flags.seriesFoundationV1Enabled else {
            profileRetryOffered = true
            showToast(.info, title: "Import paused",
                subtitle: "Library synchronization is unavailable. Retry when it is enabled again.")
            return
        }
        applyAttempt.abandon()
        dismissImportResult()
        structuredRetrySelection = response; preparedActionId = nil
        profileRetryOffered = false
        isProcessingAniListImport=true
        defer { isProcessingAniListImport=false }
        do {
            guard let username = response.username, !username.isEmpty else { throw ImportFailure.invalidInput("Choose an AniList username again.") }
            let job = try await imports.prepareAniListImport(username: username,
                types: response.types ?? ["ANIME", "MANGA"], statuses: response.statuses ?? ["CURRENT", "COMPLETED", "PLANNING", "PAUSED", "DROPPED", "REPEATING"],
                onActionId: { [weak self] actionId in
                    guard let self, self.mayPublish else { return }
                    self.preparedActionId = actionId
                })
            guard mayPublish else { return }
            structuredRetrySelection = nil
            malRetryPending = false
            profileRetryOffered = false
            workflowJob = job
        } catch is CancellationError {
            structuredRetrySelection = nil
            malRetryPending = false
            profileRetryOffered = false
        } catch {
            guard mayPublish else { return }
            let translated = ConciergeFunctionErrors.translateConciergeFunctionError(error)
            profileRetryOffered = ImportApplyDelivery.of(translated) == .uncertain
            if !profileRetryOffered { structuredRetrySelection = nil }
            showToast(.error, title: profileRetryOffered ? "Import paused" : "Import failed",
                subtitle: profileRetryOffered ? "Your imported titles are safe. Retry to continue." : translated.localizedDescription)
        }
    }

    @MainActor
    private func handleAniListImportCompleted(_ response: ConciergeAniListImportResponse) async {
        guard mayPublish else { return }
        if flags.seriesFoundationV1Enabled, response.libraryItems != nil {
            await performStructuredAniListImport(response)
            return
        }
        let importText = response.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard response.success, !importText.isEmpty else {
            showToast(
                .error,
                title: isGermanLocale ? "AniList-Import fehlgeschlagen" : "AniList import failed",
                subtitle: response.error ?? (isGermanLocale ? "Es wurden keine importierbaren Titel geliefert." : "AniList did not return importable titles.")
            )
            return
        }

        // Completing the AniList sheet is a new import, not a replay of a lost response.
        applyAttempt.abandon()
        profileRetryOffered = false
        isProcessingAniListImport = true
        dismissImportResult()
        defer { isProcessingAniListImport = false }

        do {
            // Repeated lines collapse; existing entries come from the Library, not the parse response.
            let parsed = try await imports.conciergeParse(text: importText, scope: .both)
            guard mayPublish else { return }
            let parseResponse = ImportReconciler.prepared(parsed, existing: ImportReconciler.libraryLookup(library))
            guard parseResponse.success, !parseResponse.items.isEmpty else {
                showToast(
                    .error,
                    title: isGermanLocale ? "AniList-Import fehlgeschlagen" : "AniList import failed",
                    subtitle: isGermanLocale ? "Kuro konnte die importierten Titel nicht zuordnen." : "Kuro could not match the imported titles."
                )
                return
            }

            switch profileImportDecision(for: parseResponse, importText: importText) {
            case .apply(let payload, let omittedBeyondLimit):
                let started = applyAttempt.begin(
                    anchor: ProfileImportRecovery.anchor,
                    stamp: ProfileImportRecovery.stamp
                ) { payload }
                let applyResponse = try await imports.conciergeApply(items: started.items, idempotencyKey: started.key)
                guard mayPublish else { return }
                let presented = applyResponse.presentation
                if presented.tone == .failed {
                    applyAttempt.complete()
                    showToast(
                        .error,
                        title: isGermanLocale ? "Import fehlgeschlagen" : "Import failed",
                        subtitle: presented.firstError
                            ?? (isGermanLocale ? "Die Titel konnten nicht ubernommen werden." : "The titles could not be applied.")
                    )
                    return
                }
                applyAttempt.complete()
                profileRetryOffered = false
                if presented.tone == .empty {
                    showToast(
                        .info,
                        title: isGermanLocale ? "Nichts zu ubernhemen" : "Nothing to add",
                        subtitle: nil
                    )
                    return
                }

                await refreshProfileDataAfterImport()
                guard mayPublish else { return }
                KuroAccessibility.successHaptic()
                importResult = makeAppliedImportResult(
                    applyResponse: applyResponse,
                    truncated: response.truncated == true,
                    omittedBeyondLimit: omittedBeyondLimit
                )
            case .needsReview(let reviewText):
                KuroAccessibility.impactHaptic(.light)
                importResult = makeNeedsReviewImportResult(importText: reviewText, truncated: response.truncated == true)
            }
        } catch is CancellationError {
            applyAttempt.observe(CancellationError())
            profileRetryOffered = false
            return
        } catch {
            applyAttempt.observe(error)
            profileRetryOffered = ImportApplyDelivery.of(error) == .uncertain
            showToast(
                .error,
                title: isGermanLocale ? "AniList-Import fehlgeschlagen" : "AniList import failed",
                subtitle: error.localizedDescription
            )
        }
    }

    /// Applies at once only when the parse needs no review: no parser ambiguity and every item passes
    /// the shared auto-apply rule (top candidate >= 0.85, no ambiguous adaptations, not in the library),
    /// gated on the Library's load state (`ImportReconciler.canApply`: never applied while the Library
    /// is not loaded for this account; an unknown tracking state always goes to review). The decision is
    /// `ImportReconciler.profileImportPlan` (one implementation with the Concierge auto-apply); nothing to
    /// apply = review.
    private func profileImportDecision(
        for response: ConciergeParseResponse,
        importText: String
    ) -> ProfileImportDecision {
        switch ImportReconciler.profileImportPlan(
            for: response.items,
            loadState: library.loadState,
            existing: ImportReconciler.libraryLookup(library)
        ) {
        case .apply(let applyItems, let omitted):
            return .apply(payload: applyItems.map(\.payload), omittedBeyondLimit: omitted)
        case .nothingToApply, .review:
            return .needsReview(importText: importText)
        }
    }

    @MainActor
    private func refreshProfileDataAfterImport() async {
        // `conciergeApply` already re-reads the Library projection; the Collection feed and
        // upcoming airings are refreshed here.
        await collection.fetchCollectionFeed()
        guard mayPublish else { return }
        await releases.fetchUpcomingForUser(days: 7)
    }

    private func makeAppliedImportResult(
        applyResponse: ConciergeApplyResponse,
        truncated: Bool,
        omittedBeyondLimit: Int = 0
    ) -> ProfileImportResult {
        let presented = applyResponse.presentation
        let addCount = presented.addCount
        let updateCount = presented.updateCount

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
                    ? "\(presented.acceptedCount) Titel ubernommen"
                    : "\(presented.acceptedCount) items applied"
            )
        }

        var detailParts: [String] = []
        let rejected = presented.conflictCount + presented.errorCount
        if rejected > 0 {
            detailParts.append(
                isGermanLocale
                    ? "\(rejected) Titel brauchen noch eine Prufung."
                    : "\(rejected) still need review."
            )
        }
        if truncated {
            detailParts.append(
                isGermanLocale
                    ? "AniList hat nur die ersten 200 Titel geliefert."
                    : "AniList only supplied the first 200 items."
            )
        }
        if let omitted = ImportReconciler.omittedApplyCopy(omitted: omittedBeyondLimit, german: isGermanLocale) {
            detailParts.append(omitted)
        }

        let partial = presented.tone == .partial
        return .applied(
            title: partial
                ? (isGermanLocale ? "Import teilweise ubernommen" : "Import partially applied")
                : (isGermanLocale ? "Import abgeschlossen" : "Import completed"),
            summary: summaryParts.joined(separator: ", "),
            detail: detailParts.isEmpty ? nil : detailParts.joined(separator: " "),
            undoSessionId: presented.undoSessionId
        )
    }

    /// Replay of the unresolved Profile import. Fresh reconciliation is not consulted.
    private func retryUnresolvedProfileImport() async {
        guard mayPublish else { return }
        guard let replay = ProfileImportRecovery.replayIfRetrying(intent: .retryUnresolved, attempt: applyAttempt) else {
            profileRetryOffered = false
            return
        }
        isProcessingAniListImport = true
        defer { isProcessingAniListImport = false }
        do {
            let applyResponse = try await imports.conciergeApply(items: replay.items, idempotencyKey: replay.key)
            guard mayPublish else { return }
            let presented = applyResponse.presentation
            if presented.tone == .failed {
                applyAttempt.complete()
                profileRetryOffered = false
                showToast(
                    .error,
                    title: isGermanLocale ? "Import fehlgeschlagen" : "Import failed",
                    subtitle: presented.firstError
                        ?? (isGermanLocale ? "Die Titel konnten nicht ubernommen werden." : "The titles could not be applied.")
                )
                return
            }
            applyAttempt.complete()
            profileRetryOffered = false
            guard presented.tone != .empty, presented.undoSessionId != nil || presented.acceptedCount > 0 else {
                showToast(.info, title: isGermanLocale ? "Nichts zu ubernhemen" : "Nothing to add", subtitle: nil)
                return
            }
            await refreshProfileDataAfterImport()
            guard mayPublish else { return }
            cardLifetime.invalidate()
            importResult = makeAppliedImportResult(applyResponse: applyResponse, truncated: false)
        } catch is CancellationError {
            applyAttempt.observe(CancellationError())
            profileRetryOffered = false
        } catch {
            applyAttempt.observe(error)
            profileRetryOffered = ImportApplyDelivery.of(error) == .uncertain
            showToast(
                .error,
                title: isGermanLocale ? "AniList-Import fehlgeschlagen" : "AniList import failed",
                subtitle: error.localizedDescription
            )
        }
    }

    func dismissImportResult() {
        cardLifetime.invalidate()
        undoTask?.cancel()
        importResult = nil
    }

    private func undoProfileImport() async {
        guard mayPublish else { return }
        guard case let .applied(_, summary, detail, sessionId) = importResult, let sessionId else { return }
        let startedGeneration = cardLifetime.generation
        do {
            let response = try await imports.conciergeUndo(sessionId: sessionId)
            guard mayPublish else { return }
            guard ProfileUndoPublication.mayApply(
                startedGeneration: startedGeneration,
                generation: cardLifetime.generation,
                visibleSession: importResult?.undoSessionId,
                startedSession: sessionId
            ) else { return }
            guard response.success else {
                showToast(
                    .error,
                    title: isGermanLocale ? "Ruckgangig fehlgeschlagen" : "Undo failed",
                    subtitle: isGermanLocale ? "Versuch es noch einmal." : "Try again."
                )
                return
            }
            await refreshProfileDataAfterImport()
            guard mayPublish else { return }
            guard ProfileUndoPublication.mayApply(
                startedGeneration: startedGeneration,
                generation: cardLifetime.generation,
                visibleSession: importResult?.undoSessionId,
                startedSession: sessionId
            ) else { return }
            let kept = response.keptCount
            importResult = .applied(
                title: isGermanLocale ? "Import ruckgangig gemacht" : "Import undone",
                summary: summary,
                detail: kept > 0
                    ? (isGermanLocale ? "\(kept) spatere Anderungen bleiben." : "\(kept) later edits were kept.")
                    : detail,
                undoSessionId: nil
            )
        } catch is CancellationError {
            return
        } catch {
            guard mayPublish else { return }
            guard ProfileUndoPublication.mayApply(
                startedGeneration: startedGeneration,
                generation: cardLifetime.generation,
                visibleSession: importResult?.undoSessionId,
                startedSession: sessionId
            ) else { return }
            showToast(
                .error,
                title: isGermanLocale ? "Ruckgangig fehlgeschlagen" : "Undo failed",
                subtitle: error.localizedDescription
            )
        }
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

}

private enum ProfileImportDecision {
    case apply(payload: [[String: Any]], omittedBeyondLimit: Int)
    case needsReview(importText: String)
}

enum ProfileImportResult: Identifiable {
    case applied(title: String, summary: String, detail: String?, undoSessionId: String?)
    case needsReview(title: String, summary: String, detail: String?, importText: String)

    var id: String {
        switch self {
        case let .applied(title, summary, _, sessionId):
            return "applied-\(title)-\(summary)-\(sessionId ?? "")"
        case let .needsReview(title, summary, _, _):
            return "review-\(title)-\(summary)"
        }
    }

    var titleText: String {
        switch self {
        case let .applied(title, _, _, _), let .needsReview(title, _, _, _):
            return title
        }
    }

    var summaryText: String {
        switch self {
        case let .applied(_, summary, _, _), let .needsReview(_, summary, _, _):
            return summary
        }
    }

    var detailText: String? {
        switch self {
        case let .applied(_, _, detail, _), let .needsReview(_, _, detail, _):
            return detail
        }
    }

    var undoSessionId: String? {
        if case let .applied(_, _, _, sessionId) = self { return sessionId }
        return nil
    }
}
