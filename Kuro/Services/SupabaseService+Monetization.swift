import Foundation

#if canImport(Supabase)
import Supabase

extension SupabaseService {
// MARK: - Monetization (Outbound Link Ledger)

    /// Fire-and-forget: records a tap on an outbound link (WATCH/READ CTA, provider
    /// sheet pick, external reference). Never blocks or delays navigation — errors
    /// are swallowed and only printed in DEBUG builds.
    func recordOutboundLink(mediaType: String, mediaId: Int, linkKind: String, provider: String) {
        let params = RPCRecordOutboundLinkParams(
            p_media_type: mediaType,
            p_media_id: mediaId,
            p_link_kind: linkKind,
            p_provider: provider
        )
        Task { [weak self] in
            guard let self, let client = self.client else { return }
            do {
                try await client
                    .rpc("record_outbound_link", params: params)
                    .execute()
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
