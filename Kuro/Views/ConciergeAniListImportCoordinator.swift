import Foundation
import Observation
import KuroCore
import KuroLibrary

@MainActor
@Observable
final class ConciergeAniListImportCoordinator {
    struct Request: Equatable, Sendable {
        let username: String
        let types: [String]
        let statuses: [String]
        let maxItems: Int
    }

    enum Phase: Equatable {
        case form
        case previewing
        case ready
        case importing
        case error
    }

    var phase: Phase = .form
    var preview: ConciergeAniListPreviewResponse? = nil
    var errorMessage: String? = nil
    var retryAfterSeconds: Int? = nil
    var preparedImport: ImportOutcome?
    private let scope = AccountActionScope()
    @ObservationIgnored private var preparedActionId: String?
    @ObservationIgnored private var preparationTask: Task<ImportOutcome?, Never>?

    func activate(using service: ImportsService) { scope.activate(session: service.accountSession) }
    func stop() { scope.deactivate(); preparationTask?.cancel(); preparationTask = nil; reset() }

    /// Foundation path reads complete structured source pages; approval happens in the shared review.
    func prepare(using service: ImportsService, username: String, types: [String], statuses: [String]) async -> ImportOutcome? {
        guard let origin = scope.capture(session: service.accountSession), !isPreviewing else { return nil }
        let selected = Request(username: username.trimmingCharacters(in: .whitespacesAndNewlines), types: types.sorted(), statuses: statuses.sorted(), maxItems: 0)
        let retryingOriginal = phase == .error && request == selected
        if !retryingOriginal { preparedActionId = nil }
        request = selected
        phase = .previewing; errorMessage = nil
        let task = Task { @MainActor () -> ImportOutcome? in
            guard self.scope.isCurrent(origin, session: service.accountSession), !Task.isCancelled else { return nil }
            do {
                let result: ImportOutcome
                if retryingOriginal {
                    guard let actionId = self.preparedActionId else {
                        throw ImportFailure.invalidInput("No saved input is available for this action. Edit the form to start a new review.")
                    }
                    result = try await service.resumeImport(actionId: actionId)
                } else {
                    result = try await service.prepareAniListImport(username: selected.username, types: types, statuses: statuses,
                        onActionId: { [weak self] actionId in
                            guard let self, self.scope.isCurrent(origin, session: service.accountSession) else { return }
                            self.preparedActionId = actionId
                        })
                }
                guard self.scope.isCurrent(origin, session: service.accountSession), !Task.isCancelled else { return nil }
                self.preparedImport = result; self.phase = .ready
                return result
            } catch is CancellationError { return nil }
            catch {
                guard self.scope.isCurrent(origin, session: service.accountSession), !Task.isCancelled else { return nil }
                self.fail((error as? ImportFailure)?.localizedDescription ?? error.localizedDescription)
                return nil
            }
        }
        preparationTask = task
        let result = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        if scope.isCurrent(origin, session: service.accountSession) { preparationTask = nil }
        return result
    }

    func pauseForDisabledFoundation() {
        phase = .error
        errorMessage = "Library synchronization is unavailable. Resume this same import when it is enabled again."
    }

    private var request: Request? = nil
    private var previewText: String? = nil

    var isPreviewing: Bool {
        phase == .previewing
    }

    var isImporting: Bool {
        phase == .importing
    }

    func reset() {
        phase = .form
        preview = nil
        errorMessage = nil
        retryAfterSeconds = nil
        request = nil
        previewText = nil
        preparedImport = nil; preparedActionId = nil
    }

    func loadPreview(
        using service: ImportsService,
        isGermanLocale: Bool,
        username: String,
        types: [String],
        statuses: [String],
        maxItems: Int = 200
    ) async {
        guard let origin = scope.capture(session: service.accountSession) else { return }
        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = Request(username: normalizedUsername, types: types, statuses: statuses, maxItems: maxItems)

        self.request = request
        phase = .previewing
        errorMessage = nil
        retryAfterSeconds = nil
        preview = nil
        previewText = nil

        do {
            let response = try await service.conciergePreviewAniListImport(
                username: normalizedUsername,
                types: types,
                statuses: statuses,
                maxItems: maxItems
            )
            guard scope.isCurrent(origin, session: service.accountSession) else { return }

            guard response.success else {
                fail(
                    response.error ?? localizedFallbackMessage(isGermanLocale: isGermanLocale),
                    retryAfterSeconds: response.retry_after_s
                )
                return
            }

            self.preview = response
            self.previewText = response.text?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            phase = .ready
        } catch {
            guard scope.isCurrent(origin, session: service.accountSession) else { return }
            fail(localizedErrorMessage(error, isGermanLocale: isGermanLocale))
        }
    }

    func confirmImport(
        using service: ImportsService,
        isGermanLocale: Bool
    ) async -> ConciergeAniListImportResponse? {
        guard let origin = scope.capture(session: service.accountSession) else { return nil }
        guard let request else {
            fail(localizedMissingPreviewRequest(isGermanLocale: isGermanLocale))
            return nil
        }

        phase = .importing
        errorMessage = nil
        retryAfterSeconds = nil

        do {
            let response = try await service.conciergeImportAniList(
                username: request.username,
                types: request.types,
                statuses: request.statuses,
                maxItems: request.maxItems,
                cachedText: previewText
            )
            guard scope.isCurrent(origin, session: service.accountSession) else { return nil }

            guard response.success else {
                fail(
                    response.error ?? localizedFallbackMessage(isGermanLocale: isGermanLocale),
                    retryAfterSeconds: response.retry_after_s
                )
                return nil
            }

            guard let importText = response.text?.trimmingCharacters(in: .whitespacesAndNewlines), !importText.isEmpty else {
                fail(localizedEmptyImportMessage(isGermanLocale: isGermanLocale))
                return nil
            }

            phase = .ready
            previewText = importText
            return response
        } catch {
            guard scope.isCurrent(origin, session: service.accountSession) else { return nil }
            fail(localizedErrorMessage(error, isGermanLocale: isGermanLocale))
            return nil
        }
    }

    private func fail(_ message: String, retryAfterSeconds: Int? = nil) {
        errorMessage = message
        self.retryAfterSeconds = retryAfterSeconds
        phase = .error
    }

    private func localizedFallbackMessage(isGermanLocale: Bool) -> String {
        isGermanLocale ? "Die Vorschau ist fehlgeschlagen." : "The preview failed."
    }

    private func localizedMissingPreviewRequest(isGermanLocale: Bool) -> String {
        isGermanLocale ? "Erstelle zuerst eine Vorschau." : "Create a preview first."
    }

    private func localizedEmptyImportMessage(isGermanLocale: Bool) -> String {
        isGermanLocale
            ? "AniList hat keine passenden Einträge für diesen Import geliefert."
            : "AniList returned no matching entries for this import."
    }

    private func localizedErrorMessage(_ error: Error, isGermanLocale: Bool) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return isGermanLocale ? "Die AniList-Abfrage hat zu lange gedauert." : "The AniList request timed out."
            case .notConnectedToInternet:
                return isGermanLocale ? "Du bist offline. Bitte versuche es erneut." : "You're offline. Please try again."
            case .networkConnectionLost:
                return isGermanLocale ? "Die Verbindung wurde unterbrochen." : "The connection was lost."
            default:
                break
            }
        }

        if let localized = (error as NSError).localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            return localized
        }

        return isGermanLocale ? "Die AniList-Vorschau ist fehlgeschlagen." : "The AniList preview failed."
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
