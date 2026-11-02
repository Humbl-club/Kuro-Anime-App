//
//  SupportContactTests.swift
//  KuroTests
//
//  The in-app contact form owner (`SupportStore`) over the real supabase-swift client whose requests
//  a `StubServer` answers in-process (StubPostgREST): the request shape of `contact-submit` (signed-in
//  bearer, no user id in the body, honeypot empty, consent true), the answer mapping (sent / invalid /
//  rate-limited / offline / failed), the pure validation rules, and the account scope (an account
//  change clears the draft; a late answer for an ended account writes nothing).
//  The function's own behaviour is tested offline in supabase/functions/contact-submit/handler_test.ts.
//

import Foundation
import KuroCore
import Supabase
import Testing
@testable import Kuro

@MainActor
@Suite("Support: contact form", .timeLimit(.minutes(1)))
struct SupportContactTests {
    nonisolated static func isContact(_ request: RecordedRequest) -> Bool {
        request.path.hasSuffix("/functions/v1/contact-submit")
    }

    /// Sign-in answers from `StubAuth`; `contact` answers the function (default: `{ ok: true }`).
    static func harness(
        contact: @escaping StubServer.Responder = { _ in .json(#"{"ok":true}"#) }
    ) throws -> SessionSDKHarness {
        try SessionSDKHarness(responder: StubAuth.signInResponder { request in
            isContact(request) ? contact(request) : .emptyArray
        })
    }

    static func fill(_ store: SupportStore) {
        store.draft = ContactDraft(
            topic: .reportContent,
            email: "  a@example.com ",
            name: "  ",
            message: "  The reminder for episode 4 never fired.\n",
            consent: true
        )
    }

    // MARK: Request shape

    @Test("Send: one POST to contact-submit with the signed-in bearer and the exact body (no user id)")
    func requestShape() async throws {
        let h = try Self.harness()
        try await h.signIn()
        let store = SupportStore(
            client: h.client,
            accountSession: h.graph.accountSession,
            appVersion: "1.4 (220)",
            preferredLanguages: { ["de-DE", "en-US"] }
        )
        Self.fill(store)

        await store.submit()

        let sent = h.server.requests.filter(Self.isContact)
        #expect(sent.count == 1)
        let request = try #require(sent.first)
        #expect(request.method == "POST")
        #expect(request.bearerSubject == StubAuth.userA.lowercased(), "the SDK attaches the signed-in session")
        #expect(request.header("apikey") == StubSupabase.anonKey)
        #expect(request.canonicalBody ==
            #"{"app_version":"1.4 (220)","consent":true,"email":"a@example.com","locale":"de","message":"The reminder for episode 4 never fired.","topic":"report_content","website":""}"#)
        #expect(request.jsonObject?["user_id"] == nil, "identity comes only from the JWT on the server")
        #expect(request.jsonObject?["name"] == nil, "an empty name is omitted")
        #expect(store.state == .sent)
        #expect(store.draft == ContactDraft(email: "  a@example.com "), "the sent message is cleared, the email kept")
        await h.tearDown()
    }

    @Test("Send: invalid draft is flagged locally and nothing is sent")
    func invalidDraftSendsNothing() async throws {
        let h = try Self.harness()
        try await h.signIn()
        let store = SupportStore(client: h.client, accountSession: h.graph.accountSession)
        store.draft = ContactDraft(topic: .general, email: "not-an-email", name: "", message: "   ", consent: false)

        await store.submit()

        #expect(store.state == .invalid([.email, .message, .consent]))
        #expect(h.server.requests.filter(Self.isContact).isEmpty)
        store.clearFlag(.email)
        #expect(store.state == .invalid([.message, .consent]))
        await h.tearDown()
    }

    // MARK: Answer mapping

    @Test("Answers: 429 is rate-limited, 400 maps the server's fields, 500 is failed, offline is offline; the draft stays")
    func answerMapping() async throws {
        let cases: [(StubResponse, ContactSubmitState)] = [
            (.json(#"{"error":"rate_limited","retry_after_s":1200}"#, status: 429), .rateLimited),
            (.json(#"{"error":"invalid","fields":["email","message"]}"#, status: 400), .invalid([.email, .message])),
            (.json(#"{"error":"internal"}"#, status: 500), .failed),
            (.failure(.notConnectedToInternet), .offline),
            (.failure(.timedOut), .failed),
        ]
        for (answer, expected) in cases {
            let h = try Self.harness(contact: { _ in answer })
            try await h.signIn()
            let store = SupportStore(client: h.client, accountSession: h.graph.accountSession)
            Self.fill(store)
            let draft = store.draft

            await store.submit()

            #expect(store.state == expected, "answer \(answer.status) \(String(describing: answer.failure))")
            #expect(store.draft == draft, "a failed send keeps the draft")
            #expect(h.server.requests.filter(Self.isContact).count == 1, "never retried automatically")
            await h.tearDown()
        }
    }

    // MARK: Account scope

    @Test("Account change: signing in as another account clears the draft and its state")
    func accountChangeClearsDraft() async throws {
        let h = try Self.harness(contact: { _ in .json(#"{"error":"internal"}"#, status: 500) })
        try await h.signIn()
        let store = h.graph.support
        #expect(h.session.accountScopedStates.contains { $0 === store }, "registered in makeAccountScopedStates")
        Self.fill(store)
        await store.submit()
        #expect(store.state == .failed)

        try await h.session.signInWithEmail(email: "b@example.com", password: "pw")

        #expect(store.draft == ContactDraft())
        #expect(store.state == .idle)
        await h.tearDown()
    }

    @Test("Account end: a send still in flight when the account ends writes nothing afterwards")
    func lateAnswerForEndedAccountIsDropped() async throws {
        let gate = StubGate()
        let h = try Self.harness(contact: { _ in StubResponse.json(#"{"ok":true}"#).held(by: gate) })
        try await h.signIn()
        let store = h.graph.support
        Self.fill(store)

        let send = Task { await store.submit() }
        _ = await h.server.waitForRequest(where: Self.isContact)
        #expect(store.state == .sending)

        await h.session.endSession()
        gate.open()
        await send.value

        #expect(store.state == .idle, "not .sent: the answer belonged to the ended account")
        #expect(store.draft == ContactDraft())
        await h.tearDown()
    }

    // MARK: Pure rules

    @Test("Validation: email shape and limits, name limit, message limit, consent")
    func validationRules() {
        var draft = ContactDraft(topic: .general, email: "fan@example.com", name: "", message: "Hi", consent: true)
        #expect(SupportStore.validate(draft).isEmpty)

        for bad in ["", "fan", "fan@", "@example.com", "fan@example", "fan@@example.com", "fan @example.com", "fan@example."] {
            draft.email = bad
            #expect(SupportStore.validate(draft) == [.email], "\(bad)")
        }
        draft.email = String(repeating: "a", count: ContactDraft.emailLimit - 12) + "@example.com"
        #expect(SupportStore.validate(draft).isEmpty, "254 characters is allowed")
        draft.email = "a" + draft.email
        #expect(SupportStore.validate(draft) == [.email])
        draft.email = "fan@example.com"

        draft.name = String(repeating: "n", count: ContactDraft.nameLimit + 1)
        #expect(SupportStore.validate(draft) == [.name])
        draft.name = ""

        draft.message = String(repeating: "m", count: ContactDraft.messageLimit)
        #expect(SupportStore.validate(draft).isEmpty)
        draft.message += "m"
        #expect(SupportStore.validate(draft) == [.message])
        draft.message = "Hi"

        draft.consent = false
        #expect(SupportStore.validate(draft) == [.consent])
    }

    @Test("Validation: lengths are counted in UTF-16 code units, like the server's JavaScript .length")
    func validationCountsUTF16() {
        var draft = ContactDraft(topic: .general, email: "fan@example.com", name: "", message: "", consent: true)
        // 2,000 emoji are 2,000 characters but 4,000 UTF-16 units: exactly the server's limit.
        draft.message = String(repeating: "😀", count: 2000)
        #expect(SupportStore.serverLength(draft.message) == 4000)
        #expect(SupportStore.validate(draft).isEmpty)
        // 2,001 emoji: 2,001 characters (under 4,000) but 4,002 units, which the server rejects.
        draft.message = String(repeating: "😀", count: 2001)
        #expect(draft.message.count == 2001)
        #expect(SupportStore.validate(draft) == [.message])
        draft.message = "Hi"
        // A flag is one character but four UTF-16 units.
        draft.name = String(repeating: "🇩🇪", count: 31)
        #expect(draft.name.count == 31)
        #expect(SupportStore.validate(draft) == [.name], "124 units is over the 120 limit")
    }

    @Test("Reopen: a sent message starts a fresh form; a stale failure clears but keeps the draft")
    func reopenResetsStaleState() async throws {
        let sent = try Self.harness()
        try await sent.signIn()
        let sentStore = SupportStore(client: sent.client, accountSession: sent.graph.accountSession)
        Self.fill(sentStore)
        await sentStore.submit()
        #expect(sentStore.state == .sent)
        sentStore.prepareForReopen()
        #expect(sentStore.state == .idle)
        #expect(sentStore.draft == ContactDraft(email: "  a@example.com "), "the email is kept for a follow-up")
        await sent.tearDown()

        let failed = try Self.harness(contact: { _ in .json(#"{"error":"internal"}"#, status: 500) })
        try await failed.signIn()
        let failedStore = SupportStore(client: failed.client, accountSession: failed.graph.accountSession)
        Self.fill(failedStore)
        let draft = failedStore.draft
        await failedStore.submit()
        #expect(failedStore.state == .failed)
        failedStore.prepareForReopen()
        #expect(failedStore.state == .idle)
        #expect(failedStore.draft == draft, "the unsent draft stays")
        await failed.tearDown()

        let flagged = SupportStore(client: nil, accountSession: AccountSessionCoordinator())
        await flagged.submit()
        #expect(flagged.state == .invalid([.email, .message, .consent]))
        flagged.prepareForReopen()
        #expect(flagged.state == .invalid([.email, .message, .consent]), "field flags stay")
    }

    @Test("Consent link: the privacy policy's contact-form section on the live legal site, per language")
    func privacyContactFormLink() {
        #expect(KuroLegalLinks.privacyContactForm(german: true)?.absoluteString
            == "https://kuro-legal.vercel.app/datenschutz#kontaktformular")
        #expect(KuroLegalLinks.privacyContactForm(german: false)?.absoluteString
            == "https://kuro-legal.vercel.app/datenschutz#contact-form")
    }

    @Test("Locale: only a plain language subtag is sent")
    func localeTag() {
        #expect(SupportStore.localeTag(preferredLanguages: ["de-DE"]) == "de")
        #expect(SupportStore.localeTag(preferredLanguages: ["zh-Hans-CN"]) == "zh")
        #expect(SupportStore.localeTag(preferredLanguages: ["en"]) == "en")
        #expect(SupportStore.localeTag(preferredLanguages: []) == nil)
        #expect(SupportStore.localeTag(preferredLanguages: ["x1-Y"]) == nil)
    }

    @Test("Prefill: the account email fills an empty field only")
    func prefill() {
        let store = SupportStore(client: nil, accountSession: AccountSessionCoordinator())
        store.prepare(prefillEmail: " me@example.com ")
        #expect(store.draft.email == "me@example.com")
        store.draft.email = "other@example.com"
        store.prepare(prefillEmail: "me@example.com")
        #expect(store.draft.email == "other@example.com")
    }
}
