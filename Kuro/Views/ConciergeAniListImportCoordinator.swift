import Foundation
import Observation

@MainActor
@Observable
final class ConciergeAniListImportCoordinator {
    struct Request: Sendable {
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
    var preview: SupabaseService.ConciergeAniListPreviewResponse? = nil
    var errorMessage: String? = nil
    var retryAfterSeconds: Int? = nil

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
    }

    func loadPreview(
        using service: SupabaseService,
        isGermanLocale: Bool,
        username: String,
        types: [String],
        statuses: [String],
        maxItems: Int = 200
    ) async {
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
            fail(localizedErrorMessage(error, isGermanLocale: isGermanLocale))
        }
    }

    func confirmImport(
        using service: SupabaseService,
        isGermanLocale: Bool
    ) async -> SupabaseService.ConciergeAniListImportResponse? {
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
