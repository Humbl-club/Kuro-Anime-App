import Foundation
import KuroLibrary

// MARK: - Import copy (EN/DE)
// The words the import screens show for provider, phase and per-title outcome. Raw enum values are
// internal ("finalizing", "myanimelist") and never reach the UI (rulebook §9).

enum ImportCopy {
    static func provider(_ provider: LibraryProviderReference.Provider) -> String {
        switch provider {
        case .anilist: return "AniList"
        case .myanimelist: return "MyAnimeList"
        }
    }

    /// "AniList · username" / "MyAnimeList · file".
    static func source(_ selection: ImportSelection, german: Bool) -> String {
        let identity = selection.sourceIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = selection.sourceKind == .export ? (german ? "Datei" : "file") : (german ? "Konto" : "account")
        return "\(provider(selection.provider)) · \(identity.isEmpty ? fallback : identity)"
    }

    /// The state of a job in plain words.
    static func phase(_ phase: ImportPhase, german: Bool) -> String {
        switch (phase, german) {
        case (.preparing, false): return "Reading your source"
        case (.preparing, true): return "Quelle wird gelesen"
        case (.reviewing, false): return "Waiting for your review"
        case (.reviewing, true): return "Wartet auf deine Prüfung"
        case (.applying, false): return "Saving"
        case (.applying, true): return "Wird gespeichert"
        case (.finalizing, false): return "Refreshing your Library"
        case (.finalizing, true): return "Bibliothek wird aktualisiert"
        case (.ready, false): return "Done"
        case (.ready, true): return "Fertig"
        case (.cancelled, false): return "Stopped"
        case (.cancelled, true): return "Angehalten"
        case (.failed, false): return "Needs attention"
        case (.failed, true): return "Braucht deine Aufmerksamkeit"
        case (.undoing, false): return "Undoing"
        case (.undoing, true): return "Wird rückgängig gemacht"
        case (.undone, false): return "Undone"
        case (.undone, true): return "Rückgängig gemacht"
        }
    }

    static func disposition(_ disposition: ImportDisposition, german: Bool) -> String {
        switch (disposition, german) {
        case (.new, false): return "New title"
        case (.new, true): return "Neuer Titel"
        case (.existing, false): return "Already in Kuro"
        case (.existing, true): return "Schon in Kuro"
        case (.changes, false): return "Changes available"
        case (.changes, true): return "Änderungen verfügbar"
        case (.added, false): return "Added"
        case (.added, true): return "Hinzugefügt"
        case (.updated, false): return "Updated"
        case (.updated, true): return "Aktualisiert"
        case (.unchanged, false): return "Kept"
        case (.unchanged, true): return "Beibehalten"
        case (.pending, false): return "Pending"
        case (.pending, true): return "Ausstehend"
        case (.unmatched, false), (.conflict, false), (.invalid, false), (.sourceChanged, false): return "Needs review"
        case (.unmatched, true), (.conflict, true), (.invalid, true), (.sourceChanged, true): return "Zu prüfen"
        }
    }

    static func medium(_ raw: String, german: Bool) -> String {
        raw.lowercased() == "manga" ? "Manga" : "Anime"
    }

    /// "12 saved · 3 to review".
    static func savedSummary(applied: Int, needsReview: Int, german: Bool) -> String {
        german ? "\(applied) gespeichert · \(needsReview) zu prüfen" : "\(applied) saved · \(needsReview) to review"
    }

    static func counts(_ counts: ImportCounts, german: Bool) -> String {
        german
            ? "\(counts.added) hinzugefügt · \(counts.updated) aktualisiert · \(counts.unchanged) beibehalten · \(counts.needsReview) zu prüfen · \(counts.pending) ausstehend"
            : "\(counts.added) added · \(counts.updated) updated · \(counts.unchanged) kept · \(counts.needsReview) to review · \(counts.pending) pending"
    }

    static func close(german: Bool) -> String { german ? "Schließen" : "Close" }

    /// A failure in the reader's language. Free text from the server stays as sent.
    static func failure(_ failure: ImportFailure, german: Bool) -> String {
        guard german else { return failure.localizedDescription }
        switch failure {
        case .transient(let text), .invalidInput(let text), .limit(let text): return text
        case .uncertainDelivery: return "Die Antwort ging verloren. Setz den Import fort, um gespeicherte Änderungen zu prüfen."
        case .reconnect: return "Verbinde dein Konto beim Anbieter erneut, um fortzufahren."
        case .denied: return "Der Anbieter hat das Lesen dieser Liste nicht erlaubt. Es wird nichts entfernt."
        case .activeJob: return "Ein Import läuft bereits. Setz ihn fort oder halte ihn zuerst an."
        case .pendingTracking: return "Synchronisiere zuerst deine offenen Änderungen."
        }
    }
}
