import Foundation

#if canImport(Supabase)
import Supabase

extension SupabaseService {
    // MARK: - Streaming Availability

    struct ProviderInfo: Decodable, Sendable {
        let slug: String
        let display_name: String
        let language: String?
    }

    struct BatchProviderResult: Decodable, Sendable {
        let media_type: String
        let media_id: Int
        let providers: [ProviderInfo]
    }

    struct StreamingServiceRecord: Decodable, Sendable, Identifiable {
        let slug: String
        let display_name: String
        let media_types: [String]
        let priority: Int
        let is_active: Bool
        var id: String { slug }
    }

    struct ClubSharedProvidersResponse: Decodable, Sendable {
        let shared_services: [SharedService]
        let member_count_total: Int
        let member_count_with_services: Int
        let coverage_pct: Int

        struct SharedService: Decodable, Sendable {
            let slug: String
            let display_name: String
        }
    }

    func providers(mediaId: Int, mediaType: String) -> [ProviderInfo] {
        let key = "\(mediaType.uppercased())-\(mediaId)"
        if let cached = providerCache[key], !cached.isEmpty {
            return cached
        }
        if let availability = providerAvailabilityCache[key], !availability.isEmpty {
            return availability.map { provider in
                ProviderInfo(
                    slug: provider.slug,
                    display_name: provider.displayName,
                    language: provider.languages.first
                )
            }
        }
        return []
    }

    func providerAvailability(mediaId: Int, mediaType: String) -> [ProviderAvailabilityProvider] {
        providerAvailabilityCache["\(mediaType.uppercased())-\(mediaId)"] ?? []
    }

    func bestProviderDisplayName(mediaId: Int, mediaType: String) -> String? {
        let key = "\(mediaType.uppercased())-\(mediaId)"
        if let provider = providerAvailabilityCache[key]?.first {
            return provider.displayName
        }
        return providers(mediaId: mediaId, mediaType: mediaType).first?.display_name
    }

    func bestProviderAvailabilityNote(
        mediaId: Int,
        mediaType: String,
        preferredAudioLang: String?,
        preferredSubtitleLang: String? = nil,
        originalLanguage: String? = nil
    ) -> ProviderAvailabilityNote? {
        guard mediaType.uppercased() == "ANIME" else { return nil }
        let key = "\(mediaType.uppercased())-\(mediaId)"
        guard let providers = providerAvailabilityCache[key], !providers.isEmpty else { return nil }
        return ProviderAvailabilityNoteBuilder.bestNote(
            from: providers,
            preferredAudioLang: preferredAudioLang,
            preferredSubtitleLang: preferredSubtitleLang,
            originalLanguage: originalLanguage
        )
    }

    func collectionItemsAvailableOn(slug: String) -> Set<String> {
        var result = Set<String>()
        for (key, providers) in providerCache {
            if providers.contains(where: { $0.slug == slug }) {
                result.insert(key)
            }
        }
        for (key, providers) in providerAvailabilityCache {
            if providers.contains(where: { $0.slug == slug }) {
                result.insert(key)
            }
        }
        return result
    }

    func collectionItemsWithLanguage(lang: String, includeUnknown: Bool) -> Set<String> {
        var result = Set<String>()
        for (key, providers) in providerCache {
            if providers.contains(where: {
                let normalized = normalizedExternalLanguage($0.language)
                return normalized == lang || (includeUnknown && normalized == "unknown")
            }) {
                result.insert(key)
            }
        }
        for (key, providers) in providerAvailabilityCache {
            if providers.contains(where: { provider in
                if provider.languages.contains(lang) { return true }
                if includeUnknown && provider.languages.contains("unknown") { return true }
                return false
            }) {
                result.insert(key)
            }
        }
        return result
    }

    func fetchProviderAvailabilityV2(
        items: [(mediaType: String, mediaId: Int)],
        preferredAudioLang: String? = nil,
        preferredSubLang: String? = nil,
        includeUnknown: Bool = true
    ) async {
        guard !items.isEmpty else { return }
        let payload = items.map { ["media_type": $0.mediaType.uppercased(), "media_id": "\($0.mediaId)"] }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        do {
            let params = RPCBatchProviderAvailabilityV2Params(
                p_items: jsonString,
                p_audio_lang: preferredAudioLang,
                p_sub_lang: preferredSubLang,
                p_include_unknown: includeUnknown
            )
            let raw: [ProviderAvailabilityBatchItem] = try await client
                .rpc("batch_provider_availability_for_media_v2", params: params)
                .execute()
                .value
            for item in raw {
                let key = "\(item.mediaType)-\(item.mediaId)"
                providerAvailabilityCache[key] = item.providers
                providerCache[key] = item.providers.map {
                    ProviderInfo(slug: $0.slug, display_name: $0.displayName, language: $0.languages.first)
                }
            }
        } catch {
            #if DEBUG
            print("[Streaming] fetchProviderAvailabilityV2 error: \(error.localizedDescription)")
            #endif
        }
    }

    func prefetchProviderAvailabilityV2(
        items: [(mediaType: String, mediaId: Int)],
        preferredAudioLang: String? = nil,
        preferredSubLang: String? = nil,
        includeUnknown: Bool = true
    ) {
        providerAvailabilityPrefetchTask?.cancel()
        providerAvailabilityPrefetchTask = Task { [weak self] in
            guard let self else { return }
            await self.fetchProviderAvailabilityV2(
                items: items,
                preferredAudioLang: preferredAudioLang,
                preferredSubLang: preferredSubLang,
                includeUnknown: includeUnknown
            )
        }
    }

    func prefetchProviders(items: [(mediaType: String, mediaId: Int)]) {
        providerPrefetchTask?.cancel()
        providerPrefetchTask = Task { [weak self] in
            guard let self, !items.isEmpty else { return }
            let payload = items.map { ["media_type": $0.mediaType, "media_id": "\($0.mediaId)"] }
            guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
                  let jsonString = String(data: jsonData, encoding: .utf8) else { return }
            do {
                let params = RPCBatchProvidersParams(p_items: jsonString)
                let raw: [BatchProviderResult] = try await client
                    .rpc("batch_providers_for_media", params: params)
                    .execute()
                    .value
                guard !Task.isCancelled else { return }
                for item in raw {
                    self.providerCache["\(item.media_type)-\(item.media_id)"] = item.providers
                }
            } catch {
                #if DEBUG
                print("[Streaming] prefetchProviders error: \(error.localizedDescription)")
                #endif
            }
        }
    }

    func enqueueAvailabilityRefreshIfStale(
        mediaType: String,
        mediaId: Int,
        reason: String = "on_demand_open"
    ) async -> Bool {
        let key = "\(mediaType.uppercased())-\(mediaId)"
        if let last = availabilityRefreshEnqueueCooldown[key],
           Date().timeIntervalSince(last) < 10 * 60 {
            return false
        }
        do {
            let rows = try await fetchMediaAvailabilityStatusRows(
                mediaType: mediaType,
                mediaId: mediaId
            )
            let shouldQueue: Bool
            if let status = rows.first {
                shouldQueue = (!status.hasRows) || ((status.staleDays ?? 999) >= 30)
            } else {
                shouldQueue = true
            }

            guard shouldQueue else { return false }
            let enqueueParams = RPCEnqueueMediaAvailabilityRefreshParams(
                p_media_type: mediaType.uppercased(),
                p_media_id: mediaId,
                p_reason: reason
            )
            let _: AnyJSON = try await client
                .rpc("enqueue_media_availability_refresh", params: enqueueParams)
                .execute()
                .value
            availabilityRefreshEnqueueCooldown[key] = Date()
            return true
        } catch {
            #if DEBUG
            print("[Streaming] enqueueAvailabilityRefreshIfStale error: \(error.localizedDescription)")
            #endif
            return false
        }
    }

    func mediaAvailabilityStatus(
        mediaId: Int,
        mediaType: String
    ) async -> MediaAvailabilityStatus? {
        do {
            return try await fetchMediaAvailabilityStatusRows(
                mediaType: mediaType,
                mediaId: mediaId
            ).first
        } catch {
            #if DEBUG
            print("[Streaming] mediaAvailabilityStatus error: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    private func fetchMediaAvailabilityStatusRows(
        mediaType: String,
        mediaId: Int
    ) async throws -> [MediaAvailabilityStatus] {
        let params = RPCGetMediaAvailabilityStatusParams(
            p_media_type: mediaType.uppercased(),
            p_media_id: mediaId
        )
        return try await client
            .rpc("get_media_availability_status", params: params)
            .execute()
            .value
    }

    func fetchStreamingServiceRegistry() async {
        do {
            let records: [StreamingServiceRecord] = try await client
                .from("streaming_services")
                .select()
                .eq("is_active", value: true)
                .order("priority", ascending: true)
                .execute()
                .value
            streamingServiceRegistry = records
        } catch {
            #if DEBUG
            print("[Streaming] fetchStreamingServiceRegistry error: \(error.localizedDescription)")
            #endif
        }
    }

    func fetchUserStreamingServices() async {
        do {
            struct Row: Decodable { let service: String }
            let rows: [Row] = try await client
                .from("user_streaming_services")
                .select("service")
                .execute()
                .value
            userStreamingServices = rows.map(\.service)
        } catch {
            #if DEBUG
            print("[Streaming] fetchUserStreamingServices error: \(error.localizedDescription)")
            #endif
        }
    }

    func saveUserStreamingServices(_ slugs: [String]) async {
        do {
            let params = RPCSaveStreamingServicesParams(p_services: slugs)
            let _: AnyJSON = try await client
                .rpc("save_user_streaming_services", params: params)
                .execute()
                .value
            userStreamingServices = slugs
        } catch {
            #if DEBUG
            print("[Streaming] saveUserStreamingServices error: \(error.localizedDescription)")
            #endif
        }
    }

    func fetchClubSharedProviders(clubId: String) async -> ClubSharedProvidersResponse? {
        do {
            struct Params: Encodable, Sendable {
                let p_club_id: String
                enum CodingKeys: String, CodingKey { case p_club_id }
                nonisolated func encode(to encoder: Encoder) throws {
                    var c = encoder.container(keyedBy: CodingKeys.self)
                    try c.encode(p_club_id, forKey: .p_club_id)
                }
            }
            let response: ClubSharedProvidersResponse = try await client
                .rpc("club_shared_providers", params: Params(p_club_id: clubId))
                .execute()
                .value
            clubSharedProvidersCache[clubId] = response
            return response
        } catch {
            #if DEBUG
            print("[Streaming] fetchClubSharedProviders error: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    func cachedClubSharedProviders(clubId: String) -> ClubSharedProvidersResponse? {
        clubSharedProvidersCache[clubId]
    }
}
#endif
