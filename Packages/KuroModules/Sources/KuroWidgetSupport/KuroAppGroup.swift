import Foundation

// MARK: - App Group (shared by the app and the KuroWidgets extension)
// The only place the App Group identifier and the shared file layout are named. Both processes link
// this module; neither builds a path by hand. Everything written here is account-scoped (tagged with
// an opaque `WidgetAccountHash`) and is wiped by the app on sign-out / account switch.

/// Identity and file layout of the `group.com.Kuro.app` container.
public enum KuroAppGroup {
    /// The App Group both targets declare in their entitlements (`com.apple.security.application-groups`).
    public static let identifier = "group.com.Kuro.app"

    /// The subdirectory inside the container that holds every widget file.
    public static let directoryName = "Widgets"

    /// `Widgets/` inside the App Group container, created on demand. nil when the process has no App
    /// Group entitlement (e.g. an unsigned `CODE_SIGNING_ALLOWED=NO` build): callers then do nothing.
    public static func widgetDirectory(fileManager: FileManager = .default) -> URL? {
        guard let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            return nil
        }
        return ensureDirectory(container.appendingPathComponent(directoryName, isDirectory: true), fileManager: fileManager)
    }

    /// Creates `url` (and parents) when missing; nil when that fails.
    public static func ensureDirectory(_ url: URL, fileManager: FileManager = .default) -> URL? {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue { return url }
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        } catch {
            return nil
        }
    }

    /// The widget kinds the extension registers (`WidgetConfiguration.kind`); the app reloads exactly these.
    public enum WidgetKind {
        public static let nextRelease = "com.Kuro.app.widgets.next-release"
        public static let nowWatching = "com.Kuro.app.widgets.now-watching"
        public static let all = [nextRelease, nowWatching]
    }

    /// Darwin notification the extension posts after it queued a +1, so a running app drains at once.
    /// It carries no payload: the app re-reads the queue and validates every entry itself.
    public static let advanceQueuedNotification = "com.Kuro.app.widgets.advance-queued"
}
