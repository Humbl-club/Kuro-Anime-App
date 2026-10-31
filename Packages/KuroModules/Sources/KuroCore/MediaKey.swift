import Foundation

/// Medium of a catalog title. Raw values match the app's existing `MediaKind`.
public enum MediaKind: String, Codable, Sendable {
    case anime
    case manga
}

/// Typed identity of a catalog title. Anime and manga ids come from independent
/// sequences, so `anime 42` and `manga 42` are different titles.
public struct MediaKey: Hashable, Sendable {
    public let kind: MediaKind
    public let id: Int

    public init(kind: MediaKind, id: Int) {
        self.kind = kind
        self.id = id
    }
}
