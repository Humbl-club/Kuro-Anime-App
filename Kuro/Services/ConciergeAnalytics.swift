import Foundation

#if canImport(Supabase)
import Supabase

// MARK: - Concierge Analytics
// Privacy-safe telemetry for concierge interactions.
// No PII in payload. user_id is the Supabase auth UID only.
// Fire-and-forget: analytics NEVER blocks UI or response.
// Offline batching: queues events when offline, flushes on reconnect.
// Owner: `InteractionTelemetry` (Kuro/Telemetry/), which composition builds over `shared` (the
// instance KuroApp's reconnect flush reaches) and which scopes the queue to the account.

@MainActor
final class ConciergeAnalytics {
    static let shared = ConciergeAnalytics()

    private var client: SupabaseClient?
    /// Whether events can be sent now (production: a `NetworkMonitor` of its own).
    private let isConnected: @MainActor () -> Bool
    private var userId: String?
    private var offlineQueue: [EventRow] = []
    private static let maxQueueSize = 200

    /// Connectivity from a `NetworkMonitor` of its own.
    convenience init() {
        let connectivity = NetworkMonitor()
        self.init(isConnected: { connectivity.isConnected })
    }

    /// `isConnected`: whether events can be sent now (KuroTests script it).
    init(isConnected: @escaping @MainActor () -> Bool) {
        self.isConnected = isConnected
    }

    private struct EventRow: Encodable, Sendable {
        let user_id: String?
        let event_name: String
        let language: String
        let market: String
        let payload: AnyJSON
    }

    // MARK: - Configuration

    func configure(client: SupabaseClient) {
        self.client = client
    }

    func setUserId(_ id: String?) {
        self.userId = id
        if id != nil { flushIfNeeded() }
    }

    // MARK: - Track

    /// Sends the event at once (returns the send) or queues it while offline (returns nil).
    @discardableResult
    func track(_ event: String, payload: [String: Any] = [:]) -> Task<Void, Never>? {
        let lang = Self.detectLanguage()
        let market = Self.detectMarket()
        let uid = userId
        let payloadJson = payload.reduce(into: [String: AnyJSON]()) { acc, entry in
            if let v = Self.toAnyJSON(entry.value) {
                acc[entry.key] = v
            }
        }

        let row = EventRow(
            user_id: uid,
            event_name: event,
            language: lang,
            market: market,
            payload: .object(payloadJson)
        )

        guard isConnected(), client != nil else {
            if offlineQueue.count < Self.maxQueueSize {
                offlineQueue.append(row)
            }
            return nil
        }

        return sendFireAndForget(row)
    }

    // MARK: - Flush (on reconnect)

    /// Sends the queued events (returns the sends; fire-and-forget for callers).
    @discardableResult
    func flushIfNeeded() -> [Task<Void, Never>] {
        guard !offlineQueue.isEmpty else { return [] }
        guard isConnected(), client != nil else { return [] }

        let batch = offlineQueue
        offlineQueue.removeAll()

        return batch.compactMap { sendFireAndForget($0) }
    }

    /// Drops the queued events attributed to an account (its session ended: under another login the
    /// insert policy rejects them, and they must not outlive the account). Anonymous events stay.
    func dropQueuedAccountEvents() {
        offlineQueue.removeAll { $0.user_id != nil }
    }

    // MARK: - Private

    private func sendFireAndForget(_ row: EventRow) -> Task<Void, Never>? {
        guard let client else { return nil }

        return Task(priority: .utility) {
            do {
                try await client
                    .from("concierge_events")
                    .insert(row)
                    .execute()
            } catch {
                #if DEBUG
                print("[ConciergeAnalytics] insert failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    // MARK: - Locale Detection

    nonisolated private static func detectLanguage() -> String {
        Locale.current.language.languageCode?.identifier.lowercased() ?? "en"
    }

    nonisolated private static func detectMarket() -> String {
        let lang = detectLanguage()
        let region = Locale.current.region?.identifier.uppercased() ?? "US"
        return "\(lang)-\(region)"
    }

    nonisolated private static func toAnyJSON(_ value: Any) -> AnyJSON? {
        switch value {
        case let v as String:
            return .string(v)
        case let v as Int:
            return .integer(v)
        case let v as Double:
            return .double(v)
        case let v as Bool:
            return .bool(v)
        case let v as [String]:
            return .array(v.map(AnyJSON.string))
        case let v as [Int]:
            return .array(v.map(AnyJSON.integer))
        case let v as [Double]:
            return .array(v.map(AnyJSON.double))
        case let v as [Bool]:
            return .array(v.map(AnyJSON.bool))
        default:
            return nil
        }
    }
}

#else
// Stub when Supabase SDK is not available (e.g. previews)
@MainActor
final class ConciergeAnalytics {
    static let shared = ConciergeAnalytics()
    func configure(client: Any) {}
    func setUserId(_ id: String?) {}
    func track(_ event: String, payload: [String: Any] = [:]) {}
    func flushIfNeeded() {}
}
#endif
