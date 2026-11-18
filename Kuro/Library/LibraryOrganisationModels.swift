import Foundation
import KuroCore
import Supabase

// MARK: - W9 organisation models (tags and custom lists)
// Wire rows, the tag rules shared with the database, the delta a tags-and-lists sheet sends, the error
// vocabulary and the EN/DE copy. The two owners are `LibraryTagsStore` and `CustomListsStore`.

/// Tag rules identical to the database's (`library_tags` checks): trim, NFC, at most 24 Unicode scalars,
/// at most 10 per entry, case-insensitive unique. Swift `Character` counting would accept a tag the
/// database rejects, so lengths always count scalars.
nonisolated enum LibraryTagRules {
    static let maxTags = 10
    static let maxLength = 24

    /// The tag trimmed of whitespace and newlines and in NFC; nil when nothing is left.
    static func normalised(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The case-insensitive identity of a tag.
    static func key(_ tag: String) -> String {
        (normalised(tag) ?? tag).lowercased()
    }

    /// Scalars of the normalised tag (what the database counts with `char_length`).
    static func length(_ tag: String) -> Int { tag.unicodeScalars.count }

    /// The tags after normalisation and dedupe by key (first spelling wins), or the first rule broken.
    static func validate(_ raw: [String]) -> Result<[String], LibraryTagError> {
        var seen = Set<String>()
        var result: [String] = []
        for item in raw {
            guard let tag = normalised(item) else { return .failure(.empty) }
            guard length(tag) <= maxLength else { return .failure(.tooLong(tag)) }
            if seen.insert(tag.lowercased()).inserted { result.append(tag) }
        }
        return result.count > maxTags ? .failure(.tooMany) : .success(result)
    }
}

nonisolated enum LibraryTagError: Error, Equatable { case empty, tooLong(String), tooMany }

/// The sheet's edit as the changes against what the sheet showed when it opened: never a whole set.
nonisolated struct TitleOrganisationDelta: Equatable, Sendable {
    let key: MediaKey
    var addTags: [String]
    var removeTags: [String]
    var addListIds: [UUID]
    var removeListIds: [UUID]

    var isEmpty: Bool { addTags.isEmpty && removeTags.isEmpty && addListIds.isEmpty && removeListIds.isEmpty }

    /// Tags compare by `LibraryTagRules.key` (adds keep the edited spelling, removes send the original
    /// spelling), so a case-only respelling is no change and no key or list id is in both an add and a remove.
    static func between(key: MediaKey, originalTags: [String], editedTags: [String],
                        originalListIds: Set<UUID>, editedListIds: Set<UUID>) -> TitleOrganisationDelta {
        let originalKeys = Set(originalTags.map(LibraryTagRules.key))
        var editedKeys = Set<String>()
        var adds: [String] = []
        for tag in editedTags {
            guard let normalised = LibraryTagRules.normalised(tag) else { continue }
            let tagKey = normalised.lowercased()
            guard editedKeys.insert(tagKey).inserted else { continue }
            if !originalKeys.contains(tagKey) { adds.append(normalised) }
        }
        var seenRemoved = Set<String>()
        let removes = originalTags.filter {
            let tagKey = LibraryTagRules.key($0)
            return !editedKeys.contains(tagKey) && seenRemoved.insert(tagKey).inserted
        }
        return TitleOrganisationDelta(
            key: key, addTags: adds, removeTags: removes,
            addListIds: editedListIds.subtracting(originalListIds).sorted { $0.uuidString < $1.uuidString },
            removeListIds: originalListIds.subtracting(editedListIds).sorted { $0.uuidString < $1.uuidString })
    }
}

nonisolated struct OrganisationItemRow: Equatable, Sendable, Decodable {
    let listId: UUID
    let itemId: UUID
    let position: Double
    enum CodingKeys: String, CodingKey { case listId = "list_id", itemId = "item_id", position }
}

nonisolated struct OrganisationListRevision: Equatable, Sendable, Decodable {
    let listId: UUID
    let revisionBefore: Int64
    let revision: Int64
    enum CodingKeys: String, CodingKey { case listId = "list_id", revisionBefore = "revision_before", revision }
}

/// The server state a delta save returns (other devices' changes included).
nonisolated struct TitleOrganisation: Equatable, Sendable {
    let tags: [String]
    let items: [OrganisationItemRow]
    let changedLists: [OrganisationListRevision]
}

/// Wire shape of `apply_title_organisation_delta_v1`.
nonisolated struct OrganisationDeltaResult: Decodable, Sendable {
    let tags: [String]
    let items: [OrganisationItemRow]
    let lists: [OrganisationListRevision]
}

/// Wire shape of one `library_tag_index_v1` row.
nonisolated struct TagIndexRow: Decodable, Sendable {
    let medium: String
    let mediaId: Int
    let tags: [String]
    enum CodingKeys: String, CodingKey { case medium, mediaId = "media_id", tags }
    var key: MediaKey? { MediaKind(rawValue: medium).map { MediaKey(kind: $0, id: mediaId) } }
}

nonisolated struct RPCOrganisationDeltaParams: Encodable, Sendable {
    let p_medium: String
    let p_media_id: Int
    let p_add_tags: [String]
    let p_remove_tags: [String]
    let p_add_list_ids: [UUID]
    let p_remove_list_ids: [UUID]
}

/// `unavailable` = the switch is off, or the RPC is not deployed (PGRST202).
nonisolated enum OrganiseLoadState: Equatable { case notLoaded, loading, loaded, failed, unavailable }

nonisolated enum OrganiseError: Error, Equatable {
    case offline, notTracked, tagLimit, tagTooLong, listFull, listLimit, nameTaken, nameInvalid, notFound
    case staleList, unavailable, failed

    /// Maps what the SDK or the database raised to the vocabulary above; nil for a cancellation.
    static func from(_ error: any Error) -> OrganiseError? {
        if error is CancellationError { return nil }
        if let urlError = error as? URLError {
            return urlError.code == .cancelled ? nil : .offline
        }
        if let postgrest = error as? PostgrestError {
            if let code = postgrest.code, ["PGRST202", "PGRST203", "PGRST205", "42883", "42P01"].contains(code) {
                return .unavailable
            }
            let table: [(String, OrganiseError)] = [
                ("ENTRY_NOT_FOUND", .notTracked), ("TAG_LIMIT", .tagLimit), ("TAG_TOO_LONG", .tagTooLong),
                ("LIST_ITEMS_LIMIT", .listFull), ("LIST_FULL", .listFull), ("LIST_LIMIT", .listLimit),
                ("LIST_NAME_TAKEN", .nameTaken), ("LIST_NAME_INVALID", .nameInvalid),
                ("LIST_NOT_FOUND", .notFound), ("ITEM_NOT_FOUND", .notFound), ("STALE_LIST", .staleList),
            ]
            for (token, mapped) in table where postgrest.message.contains(token) { return mapped }
            return .failed
        }
        if let http = error as? HTTPError, http.response.statusCode == 404 { return .unavailable }
        return .failed
    }
}

nonisolated enum CollectionSelectionSource: Equatable { case imported, tag(String) }

/// EN/DE copy for every W9 label, notice and error. One table, so a render test can prove both
/// languages are complete and different.
enum OrganiseCopy {
    enum Key: CaseIterable {
        case tagsAndLists, yourLists, newList, rename, deleteList, deleteListConfirm, arrange, done, tryAgain
        case notInLibrary, staleMove, removeFromList, removed, undo, tags, lists, addTag, save, cancel
        case allLists, noLists, noListsHint, seedOffer, createTheseLists, notNow, listName, empty, loadFailed, offline
        case errTagLimit, errTagTooLong, errListFull, errListLimit, errNameTaken, errNameInvalid
        case errNotTracked, errNotFound, errStale, errUnavailable, errFailed, errOffline
    }

    static func pair(_ key: Key) -> (en: String, de: String) {
        switch key {
        case .tagsAndLists: return ("Tags & lists…", "Schlagwörter & Listen…")
        case .yourLists: return ("Your lists", "Deine Listen")
        case .newList: return ("New list", "Neue Liste")
        case .rename: return ("Rename", "Umbenennen")
        case .deleteList: return ("Delete list", "Liste löschen")
        case .deleteListConfirm: return ("Delete this list? The titles stay in your library.", "Diese Liste löschen? Die Titel bleiben in deiner Bibliothek.")
        case .arrange: return ("Arrange", "Ordnen")
        case .done: return ("Done", "Fertig")
        case .tryAgain: return ("Try again", "Erneut versuchen")
        case .notInLibrary: return ("No longer in your library", "Nicht mehr in deiner Bibliothek")
        case .staleMove: return ("This list changed on another device. Your move was not saved.",
                                 "Diese Liste wurde auf einem anderen Gerät geändert. Deine Verschiebung wurde nicht gespeichert.")
        case .removeFromList: return ("Remove from list", "Aus Liste entfernen")
        case .removed: return ("Removed from the list", "Aus der Liste entfernt")
        case .undo: return ("Undo", "Rückgängig")
        case .tags: return ("Tags", "Schlagwörter")
        case .lists: return ("Lists", "Listen")
        case .addTag: return ("Add a tag", "Schlagwort hinzufügen")
        case .save: return ("Save", "Sichern")
        case .cancel: return ("Cancel", "Abbrechen")
        case .allLists: return ("All lists", "Alle Listen")
        case .noLists: return ("No lists yet", "Noch keine Listen")
        case .noListsHint: return ("Make a list for anything: a mixed shelf of anime and manga.", "Lege eine Liste für alles an: ein gemischtes Regal aus Anime und Manga.")
        case .seedOffer: return ("Your import had lists.", "Dein Import enthielt Listen.")
        case .createTheseLists: return ("Create these lists", "Diese Listen anlegen")
        case .notNow: return ("Not now", "Nicht jetzt")
        case .listName: return ("List name", "Listenname")
        case .empty: return ("Nothing in this list yet.", "In dieser Liste ist noch nichts.")
        case .loadFailed: return ("Your lists could not be loaded.", "Deine Listen konnten nicht geladen werden.")
        case .offline: return ("Offline. Connect to load your lists.", "Offline. Verbinde dich, um deine Listen zu laden.")
        case .errTagLimit: return ("A title can have 10 tags.", "Ein Titel kann 10 Schlagwörter haben.")
        case .errTagTooLong: return ("Tags can have 24 characters.", "Schlagwörter können 24 Zeichen lang sein.")
        case .errListFull: return ("This list is full.", "Diese Liste ist voll.")
        case .errListLimit: return ("You can have 50 lists.", "Du kannst 50 Listen haben.")
        case .errNameTaken: return ("You already have a list with that name.", "Du hast schon eine Liste mit diesem Namen.")
        case .errNameInvalid: return ("A list name needs 1 to 60 characters.", "Ein Listenname braucht 1 bis 60 Zeichen.")
        case .errNotTracked: return ("Add this title to your library first.", "Füge diesen Titel zuerst deiner Bibliothek hinzu.")
        case .errNotFound: return ("That list or title is no longer there.", "Diese Liste oder dieser Titel ist nicht mehr da.")
        case .errStale: return ("This list changed on another device.", "Diese Liste wurde auf einem anderen Gerät geändert.")
        case .errUnavailable: return ("Lists are not available yet.", "Listen sind noch nicht verfügbar.")
        case .errFailed: return ("That did not work. Try again.", "Das hat nicht geklappt. Versuche es erneut.")
        case .errOffline: return ("You are offline.", "Du bist offline.")
        }
    }

    static func string(_ key: Key, german: Bool) -> String {
        let pair = pair(key)
        return german ? pair.de : pair.en
    }

    static func text(_ key: Key) -> String { KuroLocale.text(pair(key).en, pair(key).de) }

    /// "Your lists · 3"
    static func yourListsCount(_ count: Int) -> String { "\(text(.yourLists)) · \(count)" }

    /// "Tagged “comfy”" / "Markiert „comfy“"
    static func tagged(_ tag: String) -> String {
        KuroLocale.text("Tagged “\(tag)”", "Markiert „\(tag)“")
    }

    /// "Your import had 3 lists."
    static func seedOffer(count: Int) -> String {
        KuroLocale.text("Your import had \(count) list\(count == 1 ? "" : "s").",
                        "Dein Import enthielt \(count) Liste\(count == 1 ? "" : "n").")
    }

    static func error(_ error: OrganiseError, german: Bool) -> String {
        let key: Key
        switch error {
        case .offline: key = .errOffline
        case .notTracked: key = .errNotTracked
        case .tagLimit: key = .errTagLimit
        case .tagTooLong: key = .errTagTooLong
        case .listFull: key = .errListFull
        case .listLimit: key = .errListLimit
        case .nameTaken: key = .errNameTaken
        case .nameInvalid: key = .errNameInvalid
        case .notFound: key = .errNotFound
        case .staleList: key = .errStale
        case .unavailable: key = .errUnavailable
        case .failed: key = .errFailed
        }
        return string(key, german: german)
    }

    /// Every string, same order in both languages (render test).
    static func allStrings(german: Bool) -> [String] { Key.allCases.map { string($0, german: german) } }
}
