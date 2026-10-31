import Foundation
import KuroCore
import Observation

#if canImport(Supabase)
import Supabase

// MARK: - Concierge
// Owner of the Concierge recommendation transport: `concierge-recommend` (+ its cache and in-flight
// loads), the parse warmup and the RAG retrieval feedback. Routing and picks are deterministic on the
// server; the optional Groq narration is copy only. The conversation itself is NOT here: it stays
// view-local and session-local (project rule).
//
// Account scope: recommendations leave out the caller's tracked titles, so the cache and its
// in-flight loads are keyed by user id and cleared on every account transition
// (`AccountScopedState`). A completion of an account that is no longer current is never cached or
// handed out: it ends in `CancellationError` (success and failure alike).

@MainActor
@Observable
final class ConciergeStore: AccountScopedState, MemoryPressureTrimmable {
    /// The app's single SDK client (shared by every owner); nil when the configuration is
    /// missing, and then every call fails with `MissingSupabaseConfiguration`.
    private let client: SupabaseClient?
    /// The shared account coordinator (every completion is checked against it).
    let accountSession: AccountSessionCoordinator

    init(client: SupabaseClient?, accountSession: AccountSessionCoordinator) {
        self.client = client
        self.accountSession = accountSession
    }

    // MARK: State

    /// Per-user recommendations, keyed "concierge_recommend|<user>|<scope>|<limit>|<narrate>|<text>".
    var conciergeRecommendCache: [String: TimedCache<ConciergeRecommendResponse>] = [:]
    /// In-flight recommendations: joined only by the same key and account context.
    @ObservationIgnored let conciergeRecommendLoads = AccountScopedLoads<String, ConciergeRecommendResponse>()

    // MARK: AccountScopedState

    func cancelAccountWork() {
        conciergeRecommendLoads.cancelAll()
    }

    func clearPrivateState() {
        conciergeRecommendCache.removeAll()
    }

    /// Sheds the recommendation cache under memory pressure.
    func trimCachesForMemoryPressure() {
        conciergeRecommendCache.removeAll()
    }

    // MARK: - Warmup

    /// Fire-and-forget edge function warmup — warms the Deno isolate. Dispatched as a credential lease
    /// of the account that asked (or of signed-out, when nobody is current) so it cannot be sent
    /// after that account ends. Runs at `priority` (the app: `.background`; KuroTests pass a higher
    /// one so a loaded test host cannot starve it).
    func conciergeWarmup(priority: TaskPriority = .background) async {
        let context = accountSession.current
        let client = self.client
        let accountSession = self.accountSession
        do {
            _ = try await Task(priority: priority) { @MainActor in
                try await accountSession.withCredentialLease(for: context) {
                    guard let client else { throw MissingSupabaseConfiguration() }
                    let data = try JSONSerialization.data(withJSONObject: ["text": ""], options: [])
                    let options = FunctionInvokeOptions(
                        method: .post,
                        query: [URLQueryItem(name: "warmup", value: "true")],
                        body: data
                    )
                    let _: [String: Bool] = try await client.functions.invoke("concierge-parse", options: options)
                }
            }.value
        } catch {
            // Best-effort warmup — silently ignore failures, including an account that ended first.
        }
    }

    // MARK: - Recommend

    func conciergeRecommend(text: String, scope: ConciergeScope = .both, limit: Int = 8, narrate: Bool = true) async throws -> ConciergeRecommendResponse {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let lim = max(3, min(20, limit))
        let context = accountSession.current
        let user = context?.userId ?? "anon"
        let key = "concierge_recommend|\(user)|\(scope.rawValue)|\(lim)|\(narrate ? 1 : 0)|\(normalized)"

        let now = Date()
        if let cached = conciergeRecommendCache[key], now.timeIntervalSince(cached.storedAt) < 3600 {
            return cached.value
        }

        // Keep the request in a shared load so callers can share in-flight work (same account only).
        // This runs on the main actor; the network call is async and should not block the UI thread.
        let client = self.client
        let accountSession = self.accountSession
        let work: @MainActor () async throws -> ConciergeRecommendResponse = {
            guard let client else { throw MissingSupabaseConfiguration() }
            let payload: [String: Any] = [
                "text": text,
                "scope": scope.rawValue,
                "limit": lim,
                "narrate": narrate,
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [])
            let options = FunctionInvokeOptions(method: .post, body: data)
            let resp: ConciergeRecommendResponse = try await accountSession.withCredentialLease(for: context) {
                try await withRetry { [client] in
                    try await client.functions.invoke("concierge-recommend", options: options)
                }
            }
            return resp
        }
        do {
            let resp = try await conciergeRecommendLoads.run(key: key, context: context, priority: .userInitiated, work: work)
            guard accountSession.isCurrent(context) else { throw CancellationError() }
            conciergeRecommendCache[key] = TimedCache(value: resp, storedAt: now)
            trimTimedCache(&conciergeRecommendCache, maxEntries: 60)
            return resp
        } catch {
            // A failure of an account that is no longer current is not reported to the next one.
            guard accountSession.isCurrent(context) else { throw CancellationError() }
            throw ConciergeFunctionErrors.translateConciergeFunctionError(error)
        }
    }

    // MARK: - Retrieval feedback

    /// Best-effort feedback for server-side RAG retrieval.
    /// Never throws to callers by design; failures are debug-logged only.
    func conciergeRetrieveFeedback(
        query: String,
        locale: String,
        selectedEntityId: String?,
        accepted: Bool,
        rejectedReason: String? = nil
    ) async {
        let context = accountSession.current
        guard context != nil else { return }
        do {
            guard let client else { throw MissingSupabaseConfiguration() }
            var payload: [String: Any] = [
                "query": query,
                "locale": locale,
                "accepted": accepted,
            ]
            if let selectedEntityId, !selectedEntityId.isEmpty {
                payload["selected_entity_id"] = selectedEntityId
            }
            if let rejectedReason, !rejectedReason.isEmpty {
                payload["rejected_reason"] = rejectedReason
            }
            let data = try JSONSerialization.data(withJSONObject: payload, options: [])
            let options = FunctionInvokeOptions(method: .post, body: data)
            let _: [String: Bool] = try await accountSession.withCredentialLease(for: context) {
                try await client.functions.invoke(
                    "concierge-retrieve-feedback",
                    options: options
                )
            }
        } catch is CancellationError {
            return
        } catch {
            #if DEBUG
            print("[ConciergeStore] conciergeRetrieveFeedback failed: \(error.localizedDescription)")
            #endif
        }
    }
}
#endif
