import Foundation
import Observation
import UserNotifications

#if canImport(Supabase)
import Supabase

extension SupabaseService {
    // MARK: - Concierge: AniList import

    struct ConciergeAniListPreviewItem: Decodable, Sendable, Identifiable {
        let mediaId: Int
        let type: String
        let line: String?
        let title: String?
        let status: String
        let progress: Int?
        let year: Int?
        let updatedAt: Int?

        var id: String { "\(type)-\(mediaId)" }

        var titleDisplay: String {
            title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? line?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "AniList \(type) \(mediaId)"
        }
    }

    struct ConciergeAniListPreviewResponse: Decodable, Sendable {
        let success: Bool
        let source: String?
        let username: String?
        let itemCount: Int?
        let truncated: Bool?
        let countsByType: [String: Int]?
        let countsByStatus: [String: Int]?
        let sampleItems: [ConciergeAniListPreviewItem]?
        let text: String?
        let publicListOnly: Bool?
        let retry_after_s: Int?
        let error: String?
    }

    struct ConciergeAniListImportResponse: Decodable, Sendable {
        let success: Bool
        let source: String?
        let username: String?
        let itemCount: Int?
        let truncated: Bool?
        let text: String?
        let publicListOnly: Bool?
        let retry_after_s: Int?
        let error: String?
    }

    func conciergePreviewAniListImport(
        username: String,
        types: [String] = ["ANIME", "MANGA"],
        statuses: [String] = ["CURRENT", "COMPLETED", "PLANNING"],
        maxItems: Int = 200
    ) async throws -> ConciergeAniListPreviewResponse {
        try await invokeAniListImport(
            mode: "preview",
            username: username,
            types: types,
            statuses: statuses,
            maxItems: maxItems,
            cachedText: nil
        )
    }

    func conciergeImportAniList(
        username: String,
        types: [String] = ["ANIME", "MANGA"],
        statuses: [String] = ["CURRENT", "COMPLETED", "PLANNING"],
        maxItems: Int = 200,
        cachedText: String? = nil
    ) async throws -> ConciergeAniListImportResponse {
        try await invokeAniListImport(
            mode: "import",
            username: username,
            types: types,
            statuses: statuses,
            maxItems: maxItems,
            cachedText: cachedText
        )
    }

    private func invokeAniListImport<T: Decodable>(
        mode: String,
        username: String,
        types: [String],
        statuses: [String],
        maxItems: Int,
        cachedText: String?
    ) async throws -> T {
        let u = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty else {
            throw NSError(
                domain: "Concierge",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Missing AniList username"]
            )
        }
        let cap = max(25, min(400, maxItems))

        do {
            var payload: [String: Any] = [
                "mode": mode,
                "username": u,
                "types": types,
                "statuses": statuses,
                "maxItems": cap,
            ]
            if let cachedText, !cachedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                payload["text"] = cachedText
            }
            let client = self.client
            let task = Task<T, Error>(priority: .userInitiated) {
                let data = try JSONSerialization.data(withJSONObject: payload, options: [])
                let options = FunctionInvokeOptions(method: .post, body: data)
                return try await client!.functions.invoke("concierge-import-anilist", options: options)
            }
            return try await task.value
        } catch {
            throw translateConciergeFunctionError(error)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
#endif
