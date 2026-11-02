import SwiftUI

// MARK: - About > Contact us
// The in-app contact form (the Impressum's second fast contact channel; the website has the same
// form at /kontakt). State and transport live in `SupportStore` (the draft is account-scoped and is
// cleared on every account change); this view only edits the draft and shows the store's state.
// Prototype language: white page, serif headline with an ink rule, quiet filled fields with a hairline
// (ink while focused or flagged; never red), capsule topic pills, one ink primary button. Every target
// is at least 44 pt. Sending shows the branded busy mark in the button; offline is the branded band
// over the kept draft; a failure or the rate limit is the ridge with one plain sentence.

struct ContactSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SupportStore.self) private var support
    @Environment(IdentityStore.self) private var identity
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case email, name, message
    }

    var body: some View {
        let german = KuroLocale.isGerman
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.lg) {
                header(german: german)
                if support.state == .sent {
                    sentState(german: german)
                } else {
                    form(german: german)
                }
            }
            .padding(.horizontal, KuroDesignSpacing.padding)
            .padding(.top, 64)
            .padding(.bottom, KuroDesignSpacing.xxl)
            .kuroReadableWidth()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.kuroCanvasPage.ignoresSafeArea())
        .overlay(alignment: .top) {
            if support.state == .offline {
                KuroOfflineView(hasContent: true) { send() }
            }
        }
        .overlay(alignment: .topTrailing) { closeButton(german: german) }
        .onAppear {
            support.prepareForReopen()
            support.prepare(prefillEmail: identity.currentUserEmail)
        }
    }

    // MARK: Parts

    private func header(german: Bool) -> some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
            Text(german ? "Kontakt." : "Contact us.")
                .kuroRoleText(.headline)
                .foregroundStyle(Color.kuroInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Rectangle().fill(Color.kuroInk).frame(width: 46, height: 2)
            Text(german
                 ? "Schreib uns zu Kuro, deinem Konto oder deinen Daten. Wir antworten per E-Mail."
                 : "Write to us about Kuro, your account or your data. We reply by email.")
                .font(.kuroBody())
                .foregroundStyle(Color.kuroInkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func form(german: Bool) -> some View {
        let bound = Bindable(support)
        let flagged = flaggedFields

        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            fieldLabel(german ? "Thema" : "Topic", isActive: false)
            FlowLayout(spacing: KuroDesignSpacing.sm) {
                ForEach(ContactTopic.allCases) { topic in
                    TopicPill(title: topic.title(german: german), isSelected: support.draft.topic == topic) {
                        support.draft.topic = topic
                    }
                }
            }
            if support.draft.topic == .reportContent {
                reportContentHint(german: german)
            }
        }

        ContactTextField(
            title: german ? "E-Mail" : "Email",
            isFocused: focus == .email,
            isFlagged: flagged.contains(.email),
            flagLine: german ? "Bitte eine gültige E-Mail-Adresse angeben." : "Enter a valid email address."
        ) {
            TextField("", text: bound.draft.email,
                      prompt: Text(verbatim: "name@example.com").foregroundStyle(Color.kuroInkQuiet))
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: .email)
                .submitLabel(.next)
                .onSubmit { focus = .name }
        }
        .onChange(of: support.draft.email) { _, _ in support.clearFlag(.email) }

        ContactTextField(
            title: german ? "Name (optional)" : "Name (optional)",
            isFocused: focus == .name,
            isFlagged: flagged.contains(.name),
            flagLine: german ? "Höchstens 120 Zeichen." : "At most 120 characters."
        ) {
            TextField("", text: bound.draft.name,
                      prompt: Text(german ? "Wie dürfen wir dich nennen?" : "What should we call you?").foregroundStyle(Color.kuroInkQuiet))
                .textContentType(.name)
                .focused($focus, equals: .name)
                .submitLabel(.next)
                .onSubmit { focus = .message }
        }
        .onChange(of: support.draft.name) { _, _ in support.clearFlag(.name) }

        messageField(german: german, isFlagged: flagged.contains(.message))

        consentRow(german: german, isFlagged: flagged.contains(.consent))

        statusBlock(german: german)

        KuroInkButton(german ? "Senden" : "Send", isLoading: support.isSending) { send() }
            .accessibilityHint(german ? "Sendet deine Nachricht an Kuro" : "Sends your message to Kuro")

        Text(german
             ? "Oder per E-Mail: contact@lazy.space"
             : "Or by email: contact@lazy.space")
            .font(.kuroMeta())
            .foregroundStyle(Color.kuroInkQuiet)
            .textSelection(.enabled)
    }

    /// Art. 16(2) DSA: what a notice of illegal content should contain (Terms, section 7).
    private func reportContentHint(german: Bool) -> some View {
        Text(german
             ? "Bitte nenne: wo sich der Inhalt befindet (Club, Titel, möglichst mit Bildschirmfoto), warum er rechtswidrig ist, deinen Namen und die Erklärung, dass deine Angaben nach bestem Wissen richtig und vollständig sind."
             : "Please include: where the content is (club, title, ideally with a screenshot), why it is illegal, your name, and a statement that your information is accurate and complete to the best of your knowledge.")
            .font(.kuroMeta())
            .foregroundStyle(Color.kuroInkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }

    private func messageField(german: Bool, isFlagged: Bool) -> some View {
        let bound = Bindable(support)
        // Counted like the server (UTF-16 code units), so the counter and the server agree.
        let count = SupportStore.serverLength(support.draft.message)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                fieldLabel(german ? "Nachricht" : "Message", isActive: focus == .message)
                Spacer()
                Text("\(count) / \(ContactDraft.messageLimit)")
                    .font(.kuroMeta())
                    .monospacedDigit()
                    .foregroundStyle(count > ContactDraft.messageLimit ? Color.kuroInk : Color.kuroInkQuiet)
                    .accessibilityLabel(german ? "\(count) von \(ContactDraft.messageLimit) Zeichen" : "\(count) of \(ContactDraft.messageLimit) characters")
            }
            TextEditor(text: bound.draft.message)
                .font(.kuroCustom(17, weight: .regular, relativeTo: .body, maxSize: 30))
                .foregroundStyle(Color.kuroInk)
                .tint(Color.kuroInk)
                .scrollContentBackground(.hidden)
                .focused($focus, equals: .message)
                .frame(minHeight: 160)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(fieldBackground)
                .overlay(fieldStroke(isFocused: focus == .message, isFlagged: isFlagged))
                .accessibilityLabel(german ? "Nachricht" : "Message")
                .onChange(of: support.draft.message) { _, _ in support.clearFlag(.message) }
            if isFlagged {
                flagText(german ? "Bitte schreib eine Nachricht (höchstens 4.000 Zeichen)." : "Write a message (at most 4,000 characters).")
            }
        }
    }

    private func consentRow(german: Bool, isFlagged: Bool) -> some View {
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: KuroDesignSpacing.sm) {
                Button {
                    KuroAccessibility.impactHaptic(.light)
                    support.draft.consent.toggle()
                    support.clearFlag(.consent)
                } label: {
                    Image(systemName: support.draft.consent ? "checkmark.square.fill" : "square")
                        .font(.kuroCustom(22, weight: .regular, relativeTo: .body, maxSize: 32))
                        .foregroundStyle(Color.kuroInk)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(KuroPressStyle())
                .accessibilityLabel(german ? "Datenschutzhinweise gelesen" : "I have read the privacy information")
                .accessibilityValue(support.draft.consent ? (german ? "Ausgewählt" : "Selected") : (german ? "Nicht ausgewählt" : "Not selected"))
                .accessibilityAddTraits(.isToggle)

                consentText(german: german)
                    .padding(.top, 11)
            }
            if isFlagged {
                flagText(german ? "Bitte bestätigen." : "Please confirm.")
                    .padding(.leading, 44 + KuroDesignSpacing.sm)
            }
        }
    }

    private func consentText(german: Bool) -> some View {
        let lead = german
            ? "Ich habe die Hinweise zum Kontaktformular in der "
            : "I have read the contact form section of the "
        let linkTitle = german ? "Datenschutzerklärung" : "privacy policy"
        let tail = german
            ? " gelesen. Meine Angaben werden nur zur Bearbeitung meiner Anfrage verwendet."
            : ". My details are used only to handle my request."
        var text = AttributedString(lead)
        var link = AttributedString(linkTitle)
        if let privacy = KuroLegalLinks.privacyContactForm(german: german) {
            link.link = privacy
            link.underlineStyle = .single
        }
        text.append(link)
        text.append(AttributedString(tail))
        return Text(text)
            .font(.kuroMeta())
            .foregroundStyle(Color.kuroInkSecondary)
            .tint(Color.kuroInk)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Rate limit and failure: the ridge with one plain sentence; the draft stays.
    @ViewBuilder
    private func statusBlock(german: Bool) -> some View {
        switch support.state {
        case .rateLimited:
            ContactNotice(
                headline: german ? "Gerade zu viele Nachrichten." : "Too many messages just now.",
                message: german
                    ? "Versuch es in einer Stunde noch einmal oder schreib an contact@lazy.space."
                    : "Try again in an hour, or write to contact@lazy.space."
            )
        case .failed:
            ContactNotice(
                headline: german ? "Nicht gesendet." : "Not sent.",
                message: german
                    ? "Deine Nachricht ist noch hier. Versuch es gleich noch einmal oder schreib an contact@lazy.space."
                    : "Your message is still here. Try again in a moment, or write to contact@lazy.space."
            )
        case .invalid:
            Text(german ? "Bitte prüf die markierten Felder." : "Check the marked fields.")
                .font(.kuroMeta(weight: .medium))
                .foregroundStyle(Color.kuroInk)
                .frame(minHeight: 24, alignment: .leading)
                .accessibilityAddTraits(.updatesFrequently)
        default:
            EmptyView()
        }
    }

    private func sentState(german: Bool) -> some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
            KuroRidgeStroke(draws: true)
                .frame(height: 36)
                .frame(maxWidth: 220)
            Text(german ? "Nachricht gesendet." : "Message sent.")
                .kuroRoleText(.title)
                .foregroundStyle(Color.kuroInk)
                .accessibilityAddTraits(.isHeader)
            Text(german
                 ? "Danke. Wir antworten an \(support.draft.email)."
                 : "Thank you. We'll reply to \(support.draft.email).")
                .font(.kuroBody())
                .foregroundStyle(Color.kuroInkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            // Reopening starts a fresh form (`prepareForReopen` in onAppear); resetting here would
            // flash the empty form during the dismiss animation.
            KuroInkButton(german ? "Fertig" : "Done") { dismiss() }
                .padding(.top, KuroDesignSpacing.sm)
            KuroInkButton(german ? "Weitere Nachricht schreiben" : "Write another message", role: .secondary, haptic: false) {
                support.startNewMessage()
            }
        }
        .onAppear { KuroAccessibility.successHaptic() }
    }

    private func closeButton(german: Bool) -> some View {
        Button {
            KuroAccessibility.impactHaptic(.light)
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.kuroCustom(15, weight: .medium, relativeTo: .body, maxSize: 22))
                .foregroundStyle(Color.kuroInk)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.kuroWhite).overlay(Circle().strokeBorder(Color.kuroHairline, lineWidth: 0.5)))
        }
        .buttonStyle(KuroPressStyle())
        .accessibilityLabel(german ? "Schließen" : "Close")
        .padding(.top, 12)
        .padding(.trailing, 12)
    }

    // MARK: Helpers

    private var flaggedFields: Set<ContactField> {
        if case .invalid(let fields) = support.state { return Set(fields) }
        return []
    }

    private func send() {
        focus = nil
        Task { await support.submit() }
    }

    private func fieldLabel(_ title: String, isActive: Bool) -> some View {
        Text(title)
            .font(.kuroMeta(weight: .semibold))
            .foregroundStyle(isActive ? Color.kuroInk : Color.kuroInkSecondary)
            .accessibilityHidden(true)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous).fill(Color.kuroCanvasQuiet)
    }

    private func fieldStroke(isFocused: Bool, isFlagged: Bool) -> some View {
        RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
            .strokeBorder(isFocused || isFlagged ? Color.kuroInk : Color.kuroHairline,
                          lineWidth: isFocused || isFlagged ? 1.5 : 1)
    }

    private func flagText(_ text: String) -> some View {
        Text(text)
            .font(.kuroMeta(weight: .medium))
            .foregroundStyle(Color.kuroInk)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A labelled single-line field in the auth form's style (quiet fill, hairline, ink when focused or
/// flagged), with its flag line under it.
private struct ContactTextField<Input: View>: View {
    let title: String
    let isFocused: Bool
    let isFlagged: Bool
    let flagLine: String
    @ViewBuilder let input: () -> Input

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.kuroMeta(weight: .semibold))
                .foregroundStyle(isFocused ? Color.kuroInk : Color.kuroInkSecondary)
                .accessibilityHidden(true)
            input()
                .font(.kuroCustom(17, weight: .regular, relativeTo: .body, maxSize: 30))
                .foregroundStyle(Color.kuroInk)
                .tint(Color.kuroInk)
                .accessibilityLabel(title)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(minHeight: 52)
                .background(
                    RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous).fill(Color.kuroCanvasQuiet)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                        .strokeBorder(isFocused || isFlagged ? Color.kuroInk : Color.kuroHairline,
                                      lineWidth: isFocused || isFlagged ? 1.5 : 1)
                )
                .kuroAnimation(KuroMotion.contact, value: isFocused)
            if isFlagged {
                Text(flagLine)
                    .font(.kuroMeta(weight: .medium))
                    .foregroundStyle(Color.kuroInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A topic capsule: ink fill when selected, hairline otherwise; 44 pt tall.
private struct TopicPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            KuroAccessibility.impactHaptic(.light)
            action()
        } label: {
            Text(title)
                .font(.kuroMeta(weight: .medium))
                .foregroundStyle(isSelected ? Color.kuroWhite : Color.kuroInk)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(Capsule().fill(isSelected ? Color.kuroInk : Color.clear))
                .overlay(Capsule().strokeBorder(isSelected ? Color.kuroInk : Color.kuroHairline, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(KuroPressStyle())
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// The branded failure note inside the form: the ridge drawn once, a headline and one sentence.
private struct ContactNotice: View {
    let headline: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            KuroRidgeStroke(draws: true, lineWidth: 1.2)
                .frame(width: 120, height: 18)
            Text(headline)
                .font(.kuroCustom(15, weight: .semibold, relativeTo: .headline, maxSize: 30))
                .foregroundStyle(Color.kuroInk)
            Text(message)
                .font(.kuroMeta())
                .foregroundStyle(Color.kuroInkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
