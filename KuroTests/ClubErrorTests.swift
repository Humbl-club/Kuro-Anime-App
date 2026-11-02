//
//  ClubErrorTests.swift
//  KuroTests
//
//  `ClubError` (E6c2; E8: thrown by `ClubsStore` itself, the one classifier): the typed club failure
//  the club views branch on instead of the SDK's `PostgrestError`. Asserted on every code carrier and
//  SQLSTATE fallback, on the answers the deployed club SQL sends (decoded the way the SDK decodes
//  them), and against the rules it replaced (ported verbatim below as oracles): the per-view rules (the
//  views must keep showing the same thing for every answer the server can send) and the store's former
//  revocation rule (`ClubRPCErrorCode`: the same clubs must be revoked for every such answer).
//

import Testing
import Foundation
import Supabase
@testable import Kuro

@Suite("Clubs: typed club errors for the views")
struct ClubErrorTests {

    struct CodeCase: Sendable, CustomTestStringConvertible {
        let raw: String
        let expected: ClubError
        var testDescription: String { raw }
    }

    /// Every server code the club views branch on, with its case.
    nonisolated static let codeCases: [CodeCase] = [
        CodeCase(raw: "UNAUTHENTICATED", expected: .unauthenticated),
        CodeCase(raw: "NOT_A_MEMBER", expected: .notAMember),
        CodeCase(raw: "CLUB_NOT_FOUND", expected: .clubNotFound),
        CodeCase(raw: "INVALID_NAME", expected: .invalidName),
        CodeCase(raw: "DESCRIPTION_TOO_LONG", expected: .descriptionTooLong),
        CodeCase(raw: "TOO_MANY_CLUBS", expected: .tooManyClubs),
        CodeCase(raw: "RATE_LIMITED", expected: .rateLimited),
        CodeCase(raw: "INVALID_CODE", expected: .invalidCode),
        CodeCase(raw: "CODE_EXPIRED", expected: .codeExpired),
        CodeCase(raw: "CODE_EXHAUSTED", expected: .codeExhausted),
        CodeCase(raw: "CLUB_ARCHIVED", expected: .clubArchived),
        CodeCase(raw: "CLUB_FULL", expected: .clubFull),
        CodeCase(raw: "ALREADY_MEMBER", expected: .alreadyMember),
        CodeCase(raw: "RAIL_NOT_FOUND", expected: .railNotFound),
        CodeCase(raw: "RAIL_LOCKED", expected: .railLocked),
        CodeCase(raw: "MEDIA_NOT_FOUND", expected: .mediaNotFound),
        CodeCase(raw: "INVALID_MEDIA_TYPE", expected: .invalidMediaType),
        CodeCase(raw: "NOTE_TOO_LONG", expected: .noteTooLong),
        CodeCase(raw: "DUPLICATE_ITEM", expected: .duplicateItem),
        CodeCase(raw: "POLL_CLOSED", expected: .pollClosed),
    ]

    @Test("Each server code is read from the message, detail or hint with the token rule", arguments: codeCases)
    func serverCodeInEveryCarrier(code: CodeCase) {
        // `RAISE EXCEPTION '<CODE>'` (most club RPCs): the code is the message.
        #expect(ClubError(PostgrestError(code: "P0001", message: code.raw)) == code.expected)
        // `RAISE EXCEPTION '<CODE>: <text>'` (create_club's INVALID_NAME / DESCRIPTION_TOO_LONG).
        #expect(ClubError(PostgrestError(code: "P0001", message: "\(code.raw): max 500 characters")) == code.expected)
        // DETAIL code with a prose message (add_club_rail_item), and HINT.
        #expect(ClubError(PostgrestError(detail: code.raw, code: "P0001", message: "Prose message")) == code.expected)
        #expect(ClubError(PostgrestError(hint: code.raw, code: "P0001", message: "Prose message")) == code.expected)
        // Trimmed; case-sensitive (codes are upper-case identifiers, prose is not a code).
        #expect(ClubError(PostgrestError(message: "  \(code.raw) \n")) == code.expected)
        let prose = code.raw.lowercased()
        #expect(ClubError(PostgrestError(message: prose)) == .other(message: prose))
    }

    struct FallbackCase: Sendable, CustomTestStringConvertible {
        let name: String
        let error: PostgrestError
        let expected: ClubError
        var testDescription: String { name }
    }

    nonisolated static let fallbackCases: [FallbackCase] = [
        FallbackCase(name: "42501 without a code -> permissionDenied",
                     error: PostgrestError(code: "42501", message: "permission denied for table club_members"),
                     expected: .permissionDenied),
        FallbackCase(name: "23505 without a code -> uniqueViolation",
                     error: PostgrestError(code: "23505", message: "Duplicate rail item"),
                     expected: .uniqueViolation),
        FallbackCase(name: "23505 with its DETAIL code -> the code",
                     error: PostgrestError(detail: "DUPLICATE_ITEM", code: "23505", message: "Duplicate rail item"),
                     expected: .duplicateItem),
        FallbackCase(name: "a code wins over 42501",
                     error: PostgrestError(code: "42501", message: "NOT_A_MEMBER"),
                     expected: .notAMember),
        FallbackCase(name: "prose P0001 -> other",
                     error: PostgrestError(code: "P0001", message: "Not a club member"),
                     expected: .other(message: "Not a club member")),
        FallbackCase(name: "code the views do not branch on -> other",
                     error: PostgrestError(code: "P0001", message: "INVALID_EMOJI"),
                     expected: .other(message: "INVALID_EMOJI")),
        FallbackCase(name: "code-like token that is not a code -> other",
                     error: PostgrestError(code: "P0001", message: "INVITE_CODE_GENERATION_FAILED"),
                     expected: .other(message: "INVITE_CODE_GENERATION_FAILED")),
        FallbackCase(name: "blank detail is skipped",
                     error: PostgrestError(detail: "  ", code: "P0001", message: "POLL_CLOSED"),
                     expected: .pollClosed),
        // F17 precedence: hint, then the message's leading `CODE` token, then detail (which this SDK
        // never fills from PostgREST's `details`), then SQLSTATE.
        FallbackCase(name: "message before detail",
                     error: PostgrestError(detail: "RAIL_LOCKED", code: "P0001", message: "NOT_A_MEMBER"),
                     expected: .notAMember),
        FallbackCase(name: "hint before message",
                     error: PostgrestError(hint: "CLUB_FULL", code: "P0001", message: "RATE_LIMITED"),
                     expected: .clubFull),
        FallbackCase(name: "hint before detail",
                     error: PostgrestError(detail: "RAIL_LOCKED", hint: "DUPLICATE_ITEM", code: "23505", message: "Duplicate rail item"),
                     expected: .duplicateItem),
        FallbackCase(name: "hint prose is not a code (exact vocabulary only)",
                     error: PostgrestError(hint: "Ask an admin to re-invite you", code: "P0001", message: "Rail is locked"),
                     expected: .other(message: "Rail is locked")),
        FallbackCase(name: "a code-like prefix of a longer token is not a code",
                     error: PostgrestError(hint: "NOT_A_MEMBER_YET", code: "P0001", message: "Membership pending"),
                     expected: .other(message: "Membership pending")),
    ]

    @Test("SQLSTATE fallbacks, precedence and unknown answers", arguments: fallbackCases)
    func fallbacks(fallback: FallbackCase) {
        #expect(ClubError(fallback.error) == fallback.expected)
    }

    @Test("Failures that are not server answers are `other`; a ClubError is kept")
    func nonServerErrors() {
        let timeout = URLError(.timedOut)
        #expect(ClubError(timeout) == .other(message: timeout.localizedDescription))
        let cancelled = CancellationError()
        #expect(ClubError(cancelled) == .other(message: cancelled.localizedDescription))
        #expect(ClubError(ClubError.notAMember) == .notAMember)
        #expect(ClubError(ClubError.other(message: "x")) == .other(message: "x"))
    }

    struct LiveAnswer: Sendable, CustomTestStringConvertible {
        let name: String
        let body: String
        let expected: ClubError
        var testDescription: String { name }
    }

    /// PostgREST error bodies of the deployed club RPCs, decoded with the SDK's own decoder (as
    /// `PostgrestBuilder` does), so the SDK's `detail`/`details` defect is part of the assertion.
    nonisolated static let liveAnswers: [LiveAnswer] = [
        LiveAnswer(name: "fetch_club_bundle NOT_A_MEMBER",
                   body: #"{"code":"P0001","details":null,"hint":null,"message":"NOT_A_MEMBER"}"#, expected: .notAMember),
        LiveAnswer(name: "fetch_club_bundle CLUB_NOT_FOUND",
                   body: #"{"code":"P0001","details":null,"hint":null,"message":"CLUB_NOT_FOUND"}"#, expected: .clubNotFound),
        LiveAnswer(name: "cast_club_vote POLL_CLOSED",
                   body: #"{"code":"P0001","details":null,"hint":null,"message":"POLL_CLOSED"}"#, expected: .pollClosed),
        LiveAnswer(name: "create_club INVALID_NAME with text",
                   body: #"{"code":"P0001","details":null,"hint":null,"message":"INVALID_NAME: name must be <= 80 characters"}"#,
                   expected: .invalidName),
        LiveAnswer(name: "join_club CODE_EXPIRED",
                   body: #"{"code":"P0001","details":null,"hint":null,"message":"CODE_EXPIRED"}"#, expected: .codeExpired),
        LiveAnswer(name: "RLS denial",
                   body: #"{"code":"42501","details":null,"hint":null,"message":"permission denied for table club_members"}"#,
                   expected: .permissionDenied),
        // The SDK decodes `detail` while PostgREST sends `details`. ClubError reads `details` from the
        // wire body (and production/stub clients map `details` → `detail` for SDK throws).
        LiveAnswer(name: "add_club_rail_item duplicate (details -> DUPLICATE_ITEM)",
                   body: #"{"code":"23505","details":"DUPLICATE_ITEM","hint":null,"message":"Duplicate rail item"}"#,
                   expected: .duplicateItem),
        LiveAnswer(name: "add_club_rail_item RAIL_LOCKED (details)",
                   body: #"{"code":"P0001","details":"RAIL_LOCKED","hint":null,"message":"Rail is locked"}"#,
                   expected: .railLocked),
        // Its prose "Unauthenticated" message is not the code; details carries UNAUTHENTICATED.
        LiveAnswer(name: "add_club_rail_item UNAUTHENTICATED (details)",
                   body: #"{"code":"P0001","details":"UNAUTHENTICATED","hint":null,"message":"Unauthenticated"}"#,
                   expected: .unauthenticated),
        LiveAnswer(name: "unknown details text stays other",
                   body: #"{"code":"P0001","details":"not a known code","hint":null,"message":"Something went wrong"}"#,
                   expected: .other(message: "Something went wrong")),
    ]

    @Test("Deployed answers, decoded as the SDK decodes them", arguments: liveAnswers)
    func liveAnswer(answer: LiveAnswer) throws {
        let error = try ClubError.postgrestDecoder().decode(PostgrestError.self, from: Data(answer.body.utf8))
        #expect(ClubError(error) == answer.expected)
        #expect(ClubError(postgrestJSON: Data(answer.body.utf8)) == answer.expected)
    }

    @Test("Realistic PostgREST JSON: details-only DUPLICATE_ITEM reaches ClubError; unknown stays other")
    func detailsFromRealisticPostgrestBody() throws {
        let duplicate = Data(#"{"code":"23505","details":"DUPLICATE_ITEM","hint":null,"message":"Duplicate rail item"}"#.utf8)
        #expect(ClubError(postgrestJSON: duplicate) == .duplicateItem)
        let unknown = Data(#"{"code":"P0001","details":"WIBBLE","hint":null,"message":"No idea"}"#.utf8)
        #expect(ClubError(postgrestJSON: unknown) == .other(message: "No idea"))
    }

    // MARK: - The per-view rules ClubError replaced

    /// The club views' failure branches (E6a state), each with the result it showed.
    enum Surface: String, CaseIterable, Sendable {
        case createClub, joinClub, loadBundle, castVote, addRailItemSheet, leaveClub, addToClubRail
    }

    /// The codes each view's private enum recognised.
    nonisolated static func legacyCodes(_ surface: Surface) -> Set<String> {
        switch surface {
        case .createClub: return ["INVALID_NAME", "DESCRIPTION_TOO_LONG", "RATE_LIMITED", "TOO_MANY_CLUBS"]
        case .joinClub: return ["INVALID_CODE", "CODE_EXPIRED", "CODE_EXHAUSTED", "CLUB_ARCHIVED", "CLUB_FULL", "ALREADY_MEMBER", "RATE_LIMITED"]
        case .loadBundle, .castVote: return ["NOT_A_MEMBER", "CLUB_NOT_FOUND", "POLL_CLOSED"]
        case .addRailItemSheet:
            return ["DUPLICATE_ITEM", "NOT_A_MEMBER", "RAIL_LOCKED", "MEDIA_NOT_FOUND", "INVALID_MEDIA_TYPE", "UNAUTHENTICATED", "NOTE_TOO_LONG", "RAIL_NOT_FOUND"]
        case .leaveClub, .addToClubRail: return ["NOT_A_MEMBER"]
        }
    }

    /// Verbatim port of the views' `errorCode(from:)` / `rpcErrorCode(from:)` token rule.
    nonisolated static func legacyTokenCode(_ error: Error, codes: Set<String>) -> String? {
        guard let pgError = error as? PostgrestError else { return nil }
        let candidates = [pgError.detail, pgError.hint, pgError.message]
        for raw in candidates {
            guard let raw else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let token = trimmed.split(separator: ":", maxSplits: 1).first.map(String.init) ?? trimmed
            let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if codes.contains(normalized) { return normalized }
        }
        return nil
    }

    /// What the view showed before E6c2 (the branch taken, named by its code or fallback).
    @MainActor
    static func legacyOutcome(_ surface: Surface, _ error: Error) -> String {
        let codes = legacyCodes(surface)
        switch surface {
        case .loadBundle:
            switch legacyTokenCode(error, codes: codes) {
            case "NOT_A_MEMBER": return "NOT_A_MEMBER"
            case "CLUB_NOT_FOUND": return "CLUB_NOT_FOUND"
            default: return LegacyStoreRule.isMembershipLoss(error) ? "PERMISSION_DENIED" : "generic"
            }
        case .castVote:
            switch legacyTokenCode(error, codes: codes) {
            case "NOT_A_MEMBER": return "NOT_A_MEMBER"
            case "POLL_CLOSED": return "POLL_CLOSED"
            default: return "generic"
            }
        case .addRailItemSheet:
            // `mapRailItemError`: exact DETAIL, then HINT; else SQLSTATE 23505; non-SDK errors generic.
            guard let pgError = error as? PostgrestError else { return "generic" }
            let detailsCode = pgError.detail.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let hintCode = pgError.hint.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let structured = detailsCode.flatMap { codes.contains($0) ? $0 : nil } ?? hintCode.flatMap { codes.contains($0) ? $0 : nil }
            if let structured { return structured }
            return pgError.code == "23505" ? "DUPLICATE_ITEM" : "generic"
        case .createClub, .joinClub, .leaveClub, .addToClubRail:
            return legacyTokenCode(error, codes: codes) ?? "generic"
        }
    }

    /// What a view shows now for a failure of its club request (E8): it reads what the store throws
    /// (`ClubsStore.boundaryError`) as `error as? ClubError`; anything else (a transport failure or a
    /// cancellation, which the store lets through) takes the view's generic branch.
    @MainActor
    static func viewOutcome(_ surface: Surface, _ error: Error) -> String {
        guard let clubError = ClubsStore.boundaryError(error) as? ClubError else { return "generic" }
        return outcome(surface, clubError)
    }

    /// What the view shows now: its switch over `ClubError`.
    nonisolated static func outcome(_ surface: Surface, _ clubError: ClubError) -> String {
        switch surface {
        case .loadBundle:
            switch clubError {
            case .notAMember: return "NOT_A_MEMBER"
            case .clubNotFound: return "CLUB_NOT_FOUND"
            case .permissionDenied: return "PERMISSION_DENIED"
            default: return "generic"
            }
        case .castVote:
            switch clubError {
            case .notAMember: return "NOT_A_MEMBER"
            case .pollClosed: return "POLL_CLOSED"
            default: return "generic"
            }
        case .addRailItemSheet:
            switch clubError {
            case .duplicateItem, .uniqueViolation: return "DUPLICATE_ITEM"
            case .notAMember: return "NOT_A_MEMBER"
            case .railLocked: return "RAIL_LOCKED"
            case .mediaNotFound: return "MEDIA_NOT_FOUND"
            case .invalidMediaType: return "INVALID_MEDIA_TYPE"
            case .unauthenticated: return "UNAUTHENTICATED"
            case .noteTooLong: return "NOTE_TOO_LONG"
            case .railNotFound: return "RAIL_NOT_FOUND"
            default: return "generic"
            }
        case .createClub:
            switch clubError {
            case .invalidName: return "INVALID_NAME"
            case .descriptionTooLong: return "DESCRIPTION_TOO_LONG"
            case .rateLimited: return "RATE_LIMITED"
            case .tooManyClubs: return "TOO_MANY_CLUBS"
            default: return "generic"
            }
        case .joinClub:
            switch clubError {
            case .invalidCode: return "INVALID_CODE"
            case .codeExpired: return "CODE_EXPIRED"
            case .codeExhausted: return "CODE_EXHAUSTED"
            case .clubArchived: return "CLUB_ARCHIVED"
            case .clubFull: return "CLUB_FULL"
            case .alreadyMember: return "ALREADY_MEMBER"
            case .rateLimited: return "RATE_LIMITED"
            default: return "generic"
            }
        case .leaveClub, .addToClubRail:
            return clubError == .notAMember ? "NOT_A_MEMBER" : "generic"
        }
    }

    /// Every answer the deployed club SQL can send to `surface`'s request (no club function sets HINT or
    /// raises with SQLSTATE 42501; `add_club_rail_item` alone puts its code in DETAIL, always with a
    /// prose message, so the add-item sheet never receives a code in the message), in both the shape the
    /// SDK decodes today (DETAIL lost) and the shape it would decode once fixed, plus the non-server
    /// failures.
    nonisolated static func deployedAnswers(for surface: Surface) -> [Error] {
        let messageCodes = [
            "UNAUTHENTICATED", "NOT_A_MEMBER", "CLUB_NOT_FOUND", "RATE_LIMITED", "TOO_MANY_CLUBS",
            "INVALID_NAME: name must not be empty", "INVALID_NAME: name must be <= 80 characters",
            "DESCRIPTION_TOO_LONG: max 500 characters", "INVALID_SHARING_LEVEL", "INVITE_CODE_GENERATION_FAILED",
            "INVALID_CODE", "CODE_EXPIRED", "CODE_EXHAUSTED", "CLUB_ARCHIVED", "CLUB_FULL", "ALREADY_MEMBER",
            "POLL_CLOSED", "INVALID_EMOJI", "ITEM_NOT_FOUND", "RAIL_NOT_FOUND", "RAIL_LOCKED",
        ]
        let addRailItem: [(detail: String, sqlState: String, message: String)] = [
            ("UNAUTHENTICATED", "P0001", "Unauthenticated"), ("INVALID_MEDIA_TYPE", "P0001", "Invalid media type"),
            ("RAIL_NOT_FOUND", "P0001", "Rail not found"), ("NOT_A_MEMBER", "P0001", "Not a club member"),
            ("RAIL_LOCKED", "P0001", "Rail is locked"), ("MEDIA_NOT_FOUND", "P0001", "Media not found"),
            ("NOTE_TOO_LONG", "P0001", "Note too long"), ("DUPLICATE_ITEM", "23505", "Duplicate rail item"),
        ]
        var answers: [Error] = surface == .addRailItemSheet ? [] : messageCodes.map { PostgrestError(code: "P0001", message: $0) }
        for answer in addRailItem {
            answers.append(PostgrestError(code: answer.sqlState, message: answer.message))
            answers.append(PostgrestError(detail: answer.detail, code: answer.sqlState, message: answer.message))
        }
        answers.append(PostgrestError(code: "42501", message: "permission denied for table club_members"))
        answers.append(PostgrestError(code: "42501", message: "permission denied for function fetch_club_bundle"))
        answers.append(PostgrestError(code: "23505", message: "duplicate key value violates unique constraint"))
        answers.append(PostgrestError(code: "PGRST202", message: "Could not find the function"))
        answers.append(URLError(.timedOut))
        answers.append(URLError(.notConnectedToInternet))
        answers.append(CancellationError())
        return answers
    }

    @Test("Every view shows what it showed before for every deployed answer", arguments: Surface.allCases)
    @MainActor
    func viewsKeepTheirOutcome(surface: Surface) {
        for error in Self.deployedAnswers(for: surface) {
            #expect(Self.viewOutcome(surface, error) == Self.legacyOutcome(surface, error), "\(error)")
        }
    }

    struct Divergence: Sendable, CustomTestStringConvertible {
        let name: String
        let surface: Surface
        let error: PostgrestError
        let legacy: String
        let now: String
        var testDescription: String { name }
    }

    /// Answers no deployed club function sends, on which the one shared rule differs from a view's own
    /// rule (documented, not defects): the first carrier with ANY known code wins; a code wins over
    /// SQLSTATE 42501; the add-item sheet now also reads the message and the token rule; codes are
    /// case-sensitive (the token-rule views upper-cased).
    /// (F17: with hint > message > detail, "two codes in two carriers" — detail RAIL_LOCKED, message
    /// NOT_A_MEMBER — reads NOT_A_MEMBER again, as the legacy leave rule did: no longer a divergence.)
    nonisolated static let divergences: [Divergence] = [
        Divergence(name: "a create/join code together with 42501 (club load)", surface: .loadBundle,
                   error: PostgrestError(code: "42501", message: "RATE_LIMITED"),
                   legacy: "PERMISSION_DENIED", now: "generic"),
        Divergence(name: "add_club_rail_item code in the message", surface: .addRailItemSheet,
                   error: PostgrestError(code: "P0001", message: "RAIL_LOCKED"),
                   legacy: "generic", now: "RAIL_LOCKED"),
        Divergence(name: "add_club_rail_item DETAIL with a ':' suffix", surface: .addRailItemSheet,
                   error: PostgrestError(detail: "RAIL_LOCKED: rail 7", code: "P0001", message: "Rail is locked"),
                   legacy: "generic", now: "RAIL_LOCKED"),
        Divergence(name: "lower-case code (leave)", surface: .leaveClub,
                   error: PostgrestError(code: "P0001", message: "not_a_member: removed by an admin"),
                   legacy: "NOT_A_MEMBER", now: "generic"),
    ]

    @Test("Documented divergences on answers the server never sends", arguments: divergences)
    @MainActor
    func documentedDivergence(divergence: Divergence) {
        #expect(Self.legacyOutcome(divergence.surface, divergence.error) == divergence.legacy)
        #expect(Self.viewOutcome(divergence.surface, divergence.error) == divergence.now)
    }

    // MARK: - The message the rail and poll sheets show

    /// Every answer the deployed `create_club_rail` and `create_club_poll` send (their `RAISE EXCEPTION`
    /// messages, plus an unknown-function answer): the create-rail and create-poll sheets show the
    /// failure's `localizedDescription`, which for the SDK's error was its message.
    nonisolated static let railAndPollSheetAnswers: [String] = [
        "UNAUTHENTICATED", "NOT_A_MEMBER",
        "NOT_ADMIN: only owner or admin can create rails",
        "INVALID_TITLE: title must not be empty", "INVALID_TITLE: title must be <= 120 characters",
        "DESCRIPTION_TOO_LONG: max 500 characters",
        "INVALID_QUESTION: question must not be empty", "INVALID_QUESTION: question must be <= 200 characters",
        "INVALID_OPTIONS: at least 2 options required", "INVALID_OPTIONS: max 10 options",
        "INVALID_CLOSES_AT: must be in the future", "OPTION_TOO_LONG: each option must be <= 120 characters",
        "Could not find the function",
    ]

    @Test("The create-rail and create-poll sheets show the same text for every deployed answer (the store's ClubError describes itself with the server's message)")
    @MainActor
    func railAndPollSheetsKeepTheirText() {
        for message in Self.railAndPollSheetAnswers {
            let answer = PostgrestError(code: "P0001", message: message)
            let thrown = ClubsStore.boundaryError(answer)
            #expect(thrown is ClubError)
            #expect(thrown.localizedDescription == answer.localizedDescription, "\(message)")
        }
        // Failures that are not server answers keep their description too.
        let configuration = MissingSupabaseConfiguration()
        #expect(ClubsStore.boundaryError(configuration).localizedDescription == configuration.localizedDescription)
    }

    // MARK: - The store's former revocation rule

    /// Verbatim port of the store's former classifier `ClubRPCErrorCode` (E6a; deleted in E8, when the
    /// store started throwing `ClubError` and revoking on `ClubError.isMembershipLoss`): the oracle of
    /// the revocation rule it replaced.
    nonisolated enum LegacyStoreRule {
        static let codes: Set<String> = [
            "UNAUTHENTICATED", "NOT_A_MEMBER", "CLUB_NOT_FOUND", "RAIL_NOT_FOUND", "RAIL_LOCKED",
            "MEDIA_NOT_FOUND", "INVALID_MEDIA_TYPE", "NOTE_TOO_LONG", "DUPLICATE_ITEM", "POLL_CLOSED",
        ]

        /// `ClubRPCErrorCode.code(from:)`: the first known code in detail, hint or message (upper-cased).
        static func code(from error: Error) -> String? {
            guard let pgError = error as? PostgrestError else { return nil }
            let candidates = [pgError.detail, pgError.hint, pgError.message]
            for raw in candidates {
                guard let raw else { continue }
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let token = trimmed.split(separator: ":", maxSplits: 1).first.map(String.init) ?? trimmed
                let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                if codes.contains(normalized) { return normalized }
            }
            return nil
        }

        /// `ClubRPCErrorCode.isMembershipLoss(_:)`.
        static func isMembershipLoss(_ error: Error) -> Bool {
            switch code(from: error) {
            case "NOT_A_MEMBER", "CLUB_NOT_FOUND":
                return true
            default:
                return (error as? PostgrestError)?.code == "42501"
            }
        }
    }

    @Test("The store revokes exactly the clubs it revoked before for every deployed answer (ClubError.isMembershipLoss against the former rule)",
          arguments: Surface.allCases)
    func revocationKeepsItsOutcome(surface: Surface) {
        for error in Self.deployedAnswers(for: surface) {
            #expect(ClubError(error).isMembershipLoss == LegacyStoreRule.isMembershipLoss(error), "\(error)")
        }
    }

    struct RevocationDivergence: Sendable, CustomTestStringConvertible {
        let name: String
        let error: PostgrestError
        var testDescription: String { name }
    }

    /// Answers no deployed club function sends (no club SQL raises 42501 or sends a lower-case code),
    /// on which the one classifier no longer revokes while the former store rule did: codes are
    /// case-sensitive, and a code wins over SQLSTATE 42501 and over a later carrier's code.
    nonisolated static let revocationDivergences: [RevocationDivergence] = [
        RevocationDivergence(name: "lower-case code", error: PostgrestError(code: "P0001", message: "not_a_member: removed by an admin")),
        RevocationDivergence(name: "a rail code together with 42501", error: PostgrestError(code: "42501", message: "RAIL_LOCKED")),
        RevocationDivergence(name: "a create/join code together with 42501", error: PostgrestError(code: "42501", message: "RATE_LIMITED")),
        // (F17: "a create/join code in DETAIL before NOT_A_MEMBER in the message" now reads the message
        // first, NOT_A_MEMBER, as the former store rule did: no longer a divergence.)
    ]

    @Test("Documented revocation divergences on answers the server never sends", arguments: revocationDivergences)
    func revocationDivergence(divergence: RevocationDivergence) {
        #expect(LegacyStoreRule.isMembershipLoss(divergence.error))
        #expect(!ClubError(divergence.error).isMembershipLoss)
    }
}

@Suite("Clubs: deleted authors")
struct ClubAuthorDecodingTests {
    @Test("A rail item, rail and poll whose author was deleted decode with a nil author")
    func nullAuthorsDecode() throws {
        let item = try JSONDecoder().decode(ClubRailItem.self, from: Data("""
        {"id":"item","media_type":"ANIME","media_id":7,"sort_order":0,"note":null,"added_by":null,"title_display":"Frieren","cover_image_medium":null,"average_score":null,"year":2023,"format":"TV","episode_count":28,"chapter_count":null}
        """.utf8))
        #expect(item.added_by == nil)

        let rail = try JSONDecoder().decode(ClubRail.self, from: Data("""
        {"id":"rail","title":"Watching","description":null,"is_locked":false,"sort_order":0,"created_by":null,"items":[]}
        """.utf8))
        #expect(rail.created_by == nil)

        let poll = try JSONDecoder().decode(ClubPoll.self, from: Data("""
        {"id":"poll","question":"Next?","is_closed":false,"closes_at":null,"created_by":null,"created_at":"2026-10-05T00:00:00Z","options":[],"my_vote_option_id":null}
        """.utf8))
        #expect(poll.created_by == nil)
    }
}
