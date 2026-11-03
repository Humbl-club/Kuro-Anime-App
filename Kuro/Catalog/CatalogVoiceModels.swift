import Foundation
import KuroCore

// Cast and voice-actor contract (2026-11-03, owner item 4). Public catalogue data read through the
// prepared RPCs `anime_cast_v1`, `character_voice_actors_v1` and `staff_voice_roles_v1`
// (supabase/prepared-migrations/20261103100000_character_voice_actors_v1.sql). Until they are
// live, `CatalogStore` answers the cast from `anime_characters` without voice actors and the two
// person readers answer empty (silent fallback, like ReleasesStore).

/// One character of an anime's cast with its primary voice actor (nil when none is stored).
struct CastMember: Identifiable {
    let character: Character
    /// AniList character role: MAIN, SUPPORTING or BACKGROUND.
    let role: String
    let voiceActor: Staff?
    /// AniList StaffLanguage of `voiceActor` (JAPANESE by default).
    let language: String?

    var id: Int { character.id }
}

/// One voice actor of a character, with the (non-adult) anime in which they voice it.
struct VoiceActorCredit: Identifiable {
    let staff: Staff
    let language: String
    let animeIds: [Int]

    var id: Int { staff.id }
}

/// One character a person voiced, in one anime (the staff page's "Voiced" rail).
struct VoiceRole: Identifiable {
    let character: Character
    let role: String
    let language: String
    let anime: VoiceRoleAnime

    var id: String { "\(character.id)-\(anime.id)" }
}

/// The card fields of the anime a voice role belongs to.
struct VoiceRoleAnime {
    let id: Int
    let titleEnglish: String?
    let titleRomaji: String?
    let titleNative: String?
    let coverImageLarge: String?
    let format: String?
    let year: Int?

    var key: MediaKey { MediaKey(kind: .anime, id: id) }
    /// English title, then romaji, then native.
    var displayTitle: String {
        [titleEnglish, titleRomaji, titleNative]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
    }
}

// MARK: - Wire rows (RPC result columns)

/// `anime_cast_v1` row.
nonisolated struct AnimeCastRow: Decodable, Sendable {
    let characterId: Int
    let characterAnilistId: Int?
    let characterNameFull: String?
    let characterNameNative: String?
    let characterImageLarge: String?
    let role: String?
    let staffId: Int?
    let staffAnilistId: Int?
    let staffNameFull: String?
    let staffNameNative: String?
    let staffImageLarge: String?
    let language: String?

    enum CodingKeys: String, CodingKey {
        case characterId = "character_id"
        case characterAnilistId = "character_anilist_id"
        case characterNameFull = "character_name_full"
        case characterNameNative = "character_name_native"
        case characterImageLarge = "character_image_large"
        case role
        case staffId = "staff_id"
        case staffAnilistId = "staff_anilist_id"
        case staffNameFull = "staff_name_full"
        case staffNameNative = "staff_name_native"
        case staffImageLarge = "staff_image_large"
        case language
    }
}

extension AnimeCastRow {
    @MainActor
    var member: CastMember {
        let character = Character(id: characterId, anilistId: characterAnilistId, nameFull: characterNameFull,
                                  nameNative: characterNameNative, imageLarge: characterImageLarge,
                                  description: nil, gender: nil, age: nil)
        let voice = staffId.map {
            Staff(id: $0, anilistId: staffAnilistId, nameFull: staffNameFull, nameNative: staffNameNative,
                  imageLarge: staffImageLarge, description: nil, primaryOccupations: nil)
        }
        return CastMember(character: character, role: role ?? "SUPPORTING", voiceActor: voice,
                          language: voice == nil ? nil : language)
    }
}

/// `character_voice_actors_v1` row.
nonisolated struct CharacterVoiceActorRow: Decodable, Sendable {
    let staffId: Int
    let anilistId: Int?
    let nameFull: String?
    let nameNative: String?
    let imageLarge: String?
    let language: String?
    let animeIds: [Int]?

    enum CodingKeys: String, CodingKey {
        case staffId = "staff_id"
        case anilistId = "anilist_id"
        case nameFull = "name_full"
        case nameNative = "name_native"
        case imageLarge = "image_large"
        case language
        case animeIds = "anime_ids"
    }
}

extension CharacterVoiceActorRow {
    @MainActor
    var credit: VoiceActorCredit {
        VoiceActorCredit(
            staff: Staff(id: staffId, anilistId: anilistId, nameFull: nameFull, nameNative: nameNative,
                         imageLarge: imageLarge, description: nil, primaryOccupations: nil),
            language: language ?? CatalogVoiceContract.defaultLanguage,
            animeIds: animeIds ?? [])
    }
}

/// `staff_voice_roles_v1` row.
nonisolated struct StaffVoiceRoleRow: Decodable, Sendable {
    let characterId: Int
    let characterAnilistId: Int?
    let characterNameFull: String?
    let characterNameNative: String?
    let characterImageLarge: String?
    let role: String?
    let language: String?
    let animeId: Int
    let titleEnglish: String?
    let titleRomaji: String?
    let titleNative: String?
    let coverImageLarge: String?
    let format: String?
    let seasonYear: Int?
    let startDateYear: Int?

    enum CodingKeys: String, CodingKey {
        case characterId = "character_id"
        case characterAnilistId = "character_anilist_id"
        case characterNameFull = "character_name_full"
        case characterNameNative = "character_name_native"
        case characterImageLarge = "character_image_large"
        case role, language
        case animeId = "anime_id"
        case titleEnglish = "title_english"
        case titleRomaji = "title_romaji"
        case titleNative = "title_native"
        case coverImageLarge = "cover_image_large"
        case format
        case seasonYear = "season_year"
        case startDateYear = "start_date_year"
    }
}

extension StaffVoiceRoleRow {
    @MainActor
    var voiceRole: VoiceRole {
        VoiceRole(
            character: Character(id: characterId, anilistId: characterAnilistId, nameFull: characterNameFull,
                                 nameNative: characterNameNative, imageLarge: characterImageLarge,
                                 description: nil, gender: nil, age: nil),
            role: role ?? "SUPPORTING",
            language: language ?? CatalogVoiceContract.defaultLanguage,
            anime: VoiceRoleAnime(id: animeId, titleEnglish: titleEnglish, titleRomaji: titleRomaji,
                                  titleNative: titleNative, coverImageLarge: coverImageLarge, format: format,
                                  year: seasonYear ?? startDateYear))
    }
}

// MARK: - RPC names and arguments

/// The prepared voice-actor RPCs (names are the deployed contract once applied).
nonisolated enum CatalogVoiceContract: String, CaseIterable, Sendable {
    case animeCast = "anime_cast_v1"
    case characterVoiceActors = "character_voice_actors_v1"
    case staffVoiceRoles = "staff_voice_roles_v1"

    /// AniList StaffLanguage the app shows (owner decision: Japanese voice actors).
    static let defaultLanguage = "JAPANESE"
}

/// RPC arguments (top-level so their `Encodable` conformance is not main-actor isolated).
struct RPCAnimeCastParams: Encodable, Sendable {
    let p_anime_id: Int
    let p_language: String
    let p_limit: Int
}

struct RPCCharacterVoiceActorsParams: Encodable, Sendable {
    let p_character_id: Int
    let p_language: String
}

struct RPCStaffVoiceRolesParams: Encodable, Sendable {
    let p_staff_id: Int
    let p_limit: Int
}

#if DEBUG
// MARK: - Fixtures (UI renders and tests; never shipped)

enum CatalogVoiceFixtures {
    static let hanazawa = Staff(id: 95_185, anilistId: 95_185, nameFull: "Kana Hanazawa", nameNative: "花澤香菜",
                                imageLarge: nil, description: nil, primaryOccupations: ["Voice Actor"])
    static let kaji = Staff(id: 95_672, anilistId: 95_672, nameFull: "Yuuki Kaji", nameNative: "梶裕貴",
                            imageLarge: nil, description: nil, primaryOccupations: ["Voice Actor"])

    /// A cast of four: two MAIN with voice actors, one SUPPORTING with, one BACKGROUND without.
    static func cast(animeId: Int = 990_042) -> [CastMember] {
        [
            CastMember(character: character(1, "Eren Yeager", "エレン・イェーガー"), role: "MAIN", voiceActor: kaji, language: "JAPANESE"),
            CastMember(character: character(2, "Mikasa Ackerman", "ミカサ・アッカーマン"), role: "MAIN",
                       voiceActor: Staff(id: 95_014, anilistId: 95_014, nameFull: "Yui Ishikawa", nameNative: "石川由依",
                                         imageLarge: nil, description: nil, primaryOccupations: nil), language: "JAPANESE"),
            CastMember(character: character(3, "Historia Reiss", "ヒストリア・レイス"), role: "SUPPORTING", voiceActor: hanazawa, language: "JAPANESE"),
            CastMember(character: character(4, "Garrison Soldier", nil), role: "BACKGROUND", voiceActor: nil, language: nil),
        ]
    }

    static func voiceActors(characterId: Int = 1) -> [VoiceActorCredit] {
        [VoiceActorCredit(staff: kaji, language: "JAPANESE", animeIds: [990_042, 990_043])]
    }

    static func voiceRoles(staffId: Int = 95_672) -> [VoiceRole] {
        [
            VoiceRole(character: character(1, "Eren Yeager", "エレン・イェーガー"), role: "MAIN", language: "JAPANESE",
                      anime: VoiceRoleAnime(id: 990_042, titleEnglish: "Attack on Titan", titleRomaji: "Shingeki no Kyojin",
                                            titleNative: "進撃の巨人", coverImageLarge: nil, format: "TV", year: 2013)),
            VoiceRole(character: character(5, "Todoroki Shouto", "轟焦凍"), role: "MAIN", language: "JAPANESE",
                      anime: VoiceRoleAnime(id: 990_050, titleEnglish: "My Hero Academia", titleRomaji: "Boku no Hero Academia",
                                            titleNative: nil, coverImageLarge: nil, format: "TV", year: 2016)),
        ]
    }

    private static func character(_ id: Int, _ name: String, _ native: String?) -> Character {
        Character(id: id, anilistId: id, nameFull: name, nameNative: native, imageLarge: nil,
                  description: nil, gender: nil, age: nil)
    }
}
#endif
