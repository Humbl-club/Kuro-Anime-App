import Foundation
import KuroCore
import Observation

#if canImport(Supabase)
import Supabase

// MARK: - Outbound link telemetry (E6c2)
// The monetization ledger of outbound taps, moved verbatim from `SupabaseService+Monetization.swift`.
// The RPC derives the user from the JWT (never a client-sent user id), so the tap must be SENT with the
// credential of the account that tapped (F33/F70): with the account coordinator, the send is a
// credential lease of the account current at the tap (or of the signed-out state), never dispatched
// once that ended and never with another account's token. Without it (composition not yet wired), the
// send goes out as before.

@MainActor
@Observable
final class OutboundLinkTelemetry {
    /// The app's single SDK client; nil when the configuration is missing (nothing is recorded).
    @ObservationIgnored private let client: SupabaseClient?
    /// The shared account coordinator (attribution of the tap); nil keeps the pre-F33 behavior.
    @ObservationIgnored private let accountSession: AccountSessionCoordinator?

    init(client: SupabaseClient?, accountSession: AccountSessionCoordinator? = nil) {
        self.client = client
        self.accountSession = accountSession
    }

    /// Fire-and-forget: records a tap on an outbound link (WATCH/READ CTA, provider
    /// sheet pick, external reference). Never blocks or delays navigation — errors
    /// are swallowed and only printed in DEBUG builds. Returns the send (tests await it).
    @discardableResult
    func recordOutboundLink(mediaType: String, mediaId: Int, linkKind: String, provider: String) -> Task<Void, Never> {
        let params = RPCRecordOutboundLinkParams(
            p_media_type: mediaType,
            p_media_id: mediaId,
            p_link_kind: linkKind,
            p_provider: provider
        )
        let context = accountSession?.current
        return Task { [weak self] in
            guard let self, let client = self.client else { return }
            do {
                let send: @MainActor () async throws -> Void = {
                    _ = try await client
                        .rpc("record_outbound_link", params: params)
                        .execute()
                }
                if let accountSession = self.accountSession {
                    try await accountSession.withCredentialLease(for: context, send)
                } else {
                    try await send()
                }
            } catch {
                #if DEBUG
                print("[Monetization] recordOutboundLink error: \(error.localizedDescription)")
                #endif
            }
        }
    }
}

struct RPCRecordOutboundLinkParams: Encodable, Sendable {
    let p_media_type: String
    let p_media_id: Int
    let p_link_kind: String
    let p_provider: String

    enum CodingKeys: String, CodingKey { case p_media_type, p_media_id, p_link_kind, p_provider }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_media_type, forKey: .p_media_type)
        try c.encode(p_media_id, forKey: .p_media_id)
        try c.encode(p_link_kind, forKey: .p_link_kind)
        try c.encode(p_provider, forKey: .p_provider)
    }
}
#endif
