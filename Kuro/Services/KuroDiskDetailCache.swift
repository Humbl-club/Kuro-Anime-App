import Foundation

enum KuroDiskDetailCache {
    nonisolated private static let folderName = "kuro.detail.v1"
    nonisolated private static let maxFiles = 300
    nonisolated private static let enforceLimitInterval: TimeInterval = 60
    private static var lastEnforcedAt: Date?

    nonisolated private static func baseDir() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(folderName, isDirectory: true)
    }

    nonisolated private static func fileURL(kind: MediaKind, id: Int) -> URL? {
        baseDir()?
            .appendingPathComponent(kind.rawValue, isDirectory: true)
            .appendingPathComponent("\(id).json", isDirectory: false)
    }

    static func read<T: Decodable>(kind: MediaKind, id: Int, as type: T.Type) async -> T? {
        await Task.detached(priority: .utility) {
            guard let url = fileURL(kind: kind, id: id) else { return nil }
            guard let data = try? Data(contentsOf: url) else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try? decoder.decode(T.self, from: data)
        }.value
    }

    static func write<T: Encodable>(kind: MediaKind, id: Int, value: T) async {
        await Task.detached(priority: .utility) {
            guard let base = baseDir(), let url = fileURL(kind: kind, id: id) else { return }
            do {
                let fm = FileManager.default
                try fm.createDirectory(at: base, withIntermediateDirectories: true)
                try fm.createDirectory(at: base.appendingPathComponent(kind.rawValue, isDirectory: true), withIntermediateDirectories: true)

                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(value)
                try data.write(to: url, options: [.atomic])

                await enforceLimitIfNeeded()
            } catch {
                // Best-effort cache; ignore failures.
            }
        }.value
    }

    @MainActor private static func enforceLimitIfNeeded() async {
        if let last = lastEnforcedAt, Date().timeIntervalSince(last) < enforceLimitInterval {
            return
        }
        lastEnforcedAt = Date()
        await enforceLimit()
    }

    nonisolated private static func enforceLimit() async {
        guard let base = baseDir() else { return }
        let fm = FileManager.default
        guard let kinds = try? fm.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var files: [URL] = []
        for kindDir in kinds {
            guard (try? kindDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let kindFiles = (try? fm.contentsOfDirectory(
                at: kindDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            files.append(contentsOf: kindFiles)
        }

        guard files.count > maxFiles else { return }

        let sorted = files.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da < db
        }

        for url in sorted.prefix(files.count - maxFiles) {
            try? fm.removeItem(at: url)
        }
    }

    static func clearAll() async {
        await Task.detached(priority: .utility) {
            guard let base = baseDir() else { return }
            try? FileManager.default.removeItem(at: base)
        }.value
    }
}
