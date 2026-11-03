import Foundation

// MARK: - Snapshot file (app writes, extension reads)
// `Widgets/snapshot.json` plus small cover thumbnails in `Widgets/thumbs/`. Written atomically under
// `NSFileCoordinator` with `completeUntilFirstUserAuthentication` protection; `clear()` removes both
// (sign-out, account switch, deletion), so nothing of an ended account stays readable by the widget.

public struct WidgetSnapshotStore: Sendable {
    /// Largest thumbnail file accepted (the writer stores ~120 px JPEGs, a few KB each).
    public static let maxThumbnailBytes = 96 * 1024

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The store in the App Group, or nil without the entitlement.
    public static func shared(fileManager: FileManager = .default) -> WidgetSnapshotStore? {
        KuroAppGroup.widgetDirectory(fileManager: fileManager).map(WidgetSnapshotStore.init(directory:))
    }

    public var snapshotURL: URL { directory.appendingPathComponent("snapshot.json") }
    public var thumbnailDirectory: URL { directory.appendingPathComponent("thumbs", isDirectory: true) }

    /// The snapshot on disk; nil when absent, unreadable or of another schema.
    public func read() -> WidgetSnapshot? {
        var snapshot: WidgetSnapshot?
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: snapshotURL, options: [], error: &coordinationError) { url in
            guard let data = try? Data(contentsOf: url),
                  let decoded = try? WidgetJSON.decoder.decode(WidgetSnapshot.self, from: data),
                  decoded.schema == WidgetSnapshot.currentSchema else { return }
            snapshot = decoded
        }
        return snapshot
    }

    /// Writes `snapshot` atomically. Returns false when the write failed.
    @discardableResult
    public func write(_ snapshot: WidgetSnapshot) -> Bool {
        guard KuroAppGroup.ensureDirectory(directory) != nil else { return false }
        var success = false
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: snapshotURL, options: [.forReplacing], error: &coordinationError) { url in
            do {
                try WidgetJSON.encoder.encode(snapshot).write(to: url, options: WidgetJSON.writeOptions)
                success = true
            } catch {
                success = false
            }
        }
        return success && coordinationError == nil
    }

    /// Removes the snapshot and every thumbnail.
    public func clear(fileManager: FileManager = .default) {
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: snapshotURL, options: [.forDeleting], error: &coordinationError) { url in
            try? fileManager.removeItem(at: url)
        }
        try? fileManager.removeItem(at: thumbnailDirectory)
    }

    // MARK: Thumbnails

    /// The file name for a title's thumbnail (stable per title and artwork URL).
    public static func thumbnailName(medium: String, mediaId: Int, artwork: URL) -> String {
        var hash: UInt64 = 1469598103934665603 // FNV-1a over the artwork URL: a new cover is a new file.
        for byte in artwork.absoluteString.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return "\(medium)-\(mediaId)-\(String(hash, radix: 16)).jpg"
    }

    public func thumbnailURL(named name: String) -> URL? {
        guard Self.isSafeName(name) else { return nil }
        return thumbnailDirectory.appendingPathComponent(name)
    }

    public func hasThumbnail(named name: String, fileManager: FileManager = .default) -> Bool {
        guard let url = thumbnailURL(named: name) else { return false }
        return fileManager.fileExists(atPath: url.path)
    }

    /// Stores a thumbnail (bounded size, safe name). Returns false when rejected or not written.
    @discardableResult
    public func writeThumbnail(_ data: Data, named name: String) -> Bool {
        guard data.count <= Self.maxThumbnailBytes, !data.isEmpty,
              let url = thumbnailURL(named: name),
              KuroAppGroup.ensureDirectory(thumbnailDirectory) != nil else { return false }
        return (try? data.write(to: url, options: WidgetJSON.writeOptions)) != nil
    }

    /// Removes thumbnails no snapshot row names any more.
    public func pruneThumbnails(keeping names: Set<String>, fileManager: FileManager = .default) {
        guard let files = try? fileManager.contentsOfDirectory(atPath: thumbnailDirectory.path) else { return }
        for file in files where !names.contains(file) {
            try? fileManager.removeItem(at: thumbnailDirectory.appendingPathComponent(file))
        }
    }

    /// Letters, digits, `-` and `.` only, no leading dot: a name from the snapshot file can never
    /// escape `thumbs/`.
    static func isSafeName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 128, !name.hasPrefix(".") else { return false }
        return name.unicodeScalars.allSatisfy { scalar in
            (scalar.isASCII && CharacterSet.alphanumerics.contains(scalar)) || scalar == "-" || scalar == "."
        }
    }
}
