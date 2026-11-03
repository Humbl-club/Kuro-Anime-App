import Foundation
import KuroCore

#if canImport(Supabase)
import Supabase

// MARK: - Cast and voice actors (public data, 2026-11-03)
// Readers for the prepared `anime_cast_v1` / `character_voice_actors_v1` / `staff_voice_roles_v1`
// RPCs (20261103100000). Public catalogue data: never account-scoped, kept across sign-out, shed
// under memory pressure. While a contract is not deployed (PGRST202/205, 404, an unreadable
// payload: `ReleaseFailure.classify`), the cast falls back to `fetchCharactersForAnime` (no voice
// actors) and the two person readers answer empty; that answer is cached like a success, and the
// contract is retried after `voiceUndeployedRetryInterval`. A transient failure (offline, 5xx)
// answers the same fallback without caching it.

@MainActor
extension CatalogStore {
    /// Lifetime of a cached cast / voice-actor answer.
    nonisolated static let voiceTTL: TimeInterval = 10 * 60
    /// How long a "not deployed" answer suppresses calls to that contract.
    nonisolated static let voiceUndeployedRetryInterval: TimeInterval = 30 * 60

    /// The cast of one anime: MAIN, SUPPORTING, other, each with its primary voice actor in
    /// `language` (nil when none is stored). Never empty while `anime_characters` has rows: before
    /// the RPC is live it is the characters rail with `voiceActor == nil`.
    func fetchCast(forAnime animeId: Int, language: String = CatalogVoiceContract.defaultLanguage,
                   limit: Int = 25) async -> [CastMember] {
        let key = "\(animeId)|\(language.uppercased())|\(limit)"
        if let cached = animeCastCache[key], Date().timeIntervalSince(cached.storedAt) < Self.voiceTTL {
            return cached.value
        }
        let result = try? await animeCastLoads.run(key: key, context: nil) { [weak self] in
            guard let self else { return [] }
            return await self.loadCast(animeId: animeId, language: language, limit: limit, key: key)
        }
        return result ?? []
    }

    /// The voice actors of one character (primary first), with the anime of each role.
    func fetchVoiceActors(forCharacter characterId: Int,
                          language: String = CatalogVoiceContract.defaultLanguage) async -> [VoiceActorCredit] {
        let key = "\(characterId)|\(language.uppercased())"
        if let cached = characterVoiceActorsCache[key], Date().timeIntervalSince(cached.storedAt) < Self.voiceTTL {
            return cached.value
        }
        guard voiceContractAvailable(.characterVoiceActors) else { return [] }
        do {
            let client = try requiredClient()
            let rows: LenientRows<CharacterVoiceActorRow> = try await client
                .rpc(CatalogVoiceContract.characterVoiceActors.rawValue,
                     params: RPCCharacterVoiceActorsParams(p_character_id: characterId, p_language: language.uppercased()))
                .execute()
                .value
            let credits = rows.rows.map(\.credit)
            storeVoice(&characterVoiceActorsCache, credits, key: key)
            return credits
        } catch {
            if voiceFailureIsUndeployed(.characterVoiceActors, error) { storeVoice(&characterVoiceActorsCache, [], key: key) }
            return []
        }
    }

    /// The characters one person voiced (MAIN first, then the anime's popularity), for the staff page.
    func fetchVoiceRoles(forStaff staffId: Int, limit: Int = 50) async -> [VoiceRole] {
        let key = "\(staffId)|\(limit)"
        if let cached = staffVoiceRolesCache[key], Date().timeIntervalSince(cached.storedAt) < Self.voiceTTL {
            return cached.value
        }
        guard voiceContractAvailable(.staffVoiceRoles) else { return [] }
        do {
            let client = try requiredClient()
            let rows: LenientRows<StaffVoiceRoleRow> = try await client
                .rpc(CatalogVoiceContract.staffVoiceRoles.rawValue,
                     params: RPCStaffVoiceRolesParams(p_staff_id: staffId, p_limit: max(1, min(100, limit))))
                .execute()
                .value
            let roles = rows.rows.map(\.voiceRole)
            storeVoice(&staffVoiceRolesCache, roles, key: key)
            return roles
        } catch {
            if voiceFailureIsUndeployed(.staffVoiceRoles, error) { storeVoice(&staffVoiceRolesCache, [], key: key) }
            return []
        }
    }

    // MARK: Loading

    private func loadCast(animeId: Int, language: String, limit: Int, key: String) async -> [CastMember] {
        if voiceContractAvailable(.animeCast) {
            do {
                let client = try requiredClient()
                let rows: LenientRows<AnimeCastRow> = try await client
                    .rpc(CatalogVoiceContract.animeCast.rawValue,
                         params: RPCAnimeCastParams(p_anime_id: animeId, p_language: language.uppercased(),
                                                    p_limit: max(1, min(50, limit))))
                    .execute()
                    .value
                let members = rows.rows.map(\.member)
                storeVoice(&animeCastCache, members, key: key)
                return members
            } catch {
                let undeployed = voiceFailureIsUndeployed(.animeCast, error)
                let fallback = await castFallback(animeId: animeId, limit: limit)
                if undeployed, !fallback.isEmpty { storeVoice(&animeCastCache, fallback, key: key) }
                return fallback
            }
        }
        return await castFallback(animeId: animeId, limit: limit)
    }

    /// The characters rail without voice actors (`anime_characters`, its own cache), role-ordered
    /// like `anime_cast_v1`.
    private func castFallback(animeId: Int, limit: Int) async -> [CastMember] {
        let characters = await fetchCharactersForAnime(animeId: animeId)
        return Array(Self.castOrder(characters.map {
            CastMember(character: $0.character, role: $0.role, voiceActor: nil, language: nil)
        }).prefix(max(1, limit)))
    }

    /// MAIN, then SUPPORTING, then every other role; the input order inside each group.
    nonisolated static func castOrder(_ members: [CastMember]) -> [CastMember] {
        func rank(_ role: String) -> Int {
            switch role.uppercased() {
            case "MAIN": return 0
            case "SUPPORTING": return 1
            default: return 2
            }
        }
        return members.enumerated()
            .sorted { (rank($0.element.role), $0.offset) < (rank($1.element.role), $1.offset) }
            .map(\.element)
    }

    // MARK: Contract state

    private func voiceContractAvailable(_ contract: CatalogVoiceContract, now: Date = Date()) -> Bool {
        guard let at = undeployedVoiceContracts[contract] else { return true }
        if now.timeIntervalSince(at) < Self.voiceUndeployedRetryInterval { return false }
        undeployedVoiceContracts[contract] = nil
        return true
    }

    /// Records a "not deployed" answer; true when the failure is one (the fallback may be cached).
    private func voiceFailureIsUndeployed(_ contract: CatalogVoiceContract, _ error: any Error) -> Bool {
        let failure = ReleaseFailure.classify(error)
        #if DEBUG
        print("[Catalog] \(contract.rawValue) unavailable (\(failure)), using fallback: \(error)")
        #endif
        guard failure == .notDeployed else { return false }
        undeployedVoiceContracts[contract] = Date()
        return true
    }

    private func storeVoice<T>(_ cache: inout [String: TimedCache<[T]>], _ value: [T], key: String) {
        cache[key] = TimedCache(value: value, storedAt: Date())
        trimTimedCache(&cache, maxEntries: 100)
    }
}
#endif
