import Foundation
import KuroCore
import Observation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Notification tap → title journey
// A release notification carries ONE payload: `kuro_link` = `kuro://anime/<id>` or
// `kuro://manga/<id>`. The tap hands it to `NotificationLinkInbox`; `KuroApp` turns it into the same
// `DeepLink` a `kuro://` URL becomes (`pendingDeepLink`), so the navigation contract's N10 collapse
// rules apply unchanged. Nothing else is accepted from a payload: any other scheme, host or path is
// ignored (an airing reminder scheduled before payloads existed is read from its `airing-<id>-*` id).

nonisolated enum ReleaseNotificationLink {
    static let userInfoKey = "kuro_link"

    static func url(for key: MediaKey) -> URL? {
        URL(string: "kuro://\(key.kind.rawValue)/\(key.id)")
    }

    static func userInfo(for key: MediaKey) -> [String: String] {
        url(for: key).map { [userInfoKey: $0.absoluteString] } ?? [:]
    }

    /// The title link a notification may open, or nil.
    static func validatedURL(userInfo: [AnyHashable: Any], identifier: String) -> URL? {
        if let text = userInfo[userInfoKey] as? String, let url = URL(string: text), let key = mediaKey(url) {
            return Self.url(for: key)
        }
        // Older airing reminders: "airing-<animeId>-start" / "airing-<animeId>-1h".
        let parts = identifier.split(separator: "-")
        if parts.count == 3, parts[0] == "airing", let id = Int(parts[1]), id > 0 {
            return url(for: MediaKey(kind: .anime, id: id))
        }
        return nil
    }

    /// `kuro://anime/<positive int>` or `kuro://manga/<positive int>` only.
    static func mediaKey(_ url: URL) -> MediaKey? {
        guard url.scheme?.lowercased() == "kuro", let host = url.host?.lowercased(),
              let kind = MediaKind(rawValue: host) else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }
        guard path.count == 1, let id = Int(path[0]), id > 0, url.query == nil, url.fragment == nil else { return nil }
        return MediaKey(kind: kind, id: id)
    }
}

/// The tapped notification's link, waiting for `KuroApp` to route it (cold start: until the scene is up).
@MainActor
@Observable
final class NotificationLinkInbox {
    private(set) var pendingURL: URL?

    func receive(_ url: URL) {
        pendingURL = url
    }

    /// The pending link, cleared (one consumer).
    func take() -> URL? {
        defer { pendingURL = nil }
        return pendingURL
    }
}

/// `UNUserNotificationCenter` delegate: banners while Kuro is open, taps routed to the inbox.
final class KuroNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = KuroNotificationDelegate()

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let request = response.notification.request
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let url = ReleaseNotificationLink.validatedURL(userInfo: request.content.userInfo,
                                                             identifier: request.identifier) else { return }
        await MainActor.run { AppComposition.shared.notificationLinks.receive(url) }
    }
}

#if canImport(UIKit)
/// Installs the notification delegate before launch finishes, so a tap that launched the app is seen.
final class KuroAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = KuroNotificationDelegate.shared
        return true
    }
}
#endif
