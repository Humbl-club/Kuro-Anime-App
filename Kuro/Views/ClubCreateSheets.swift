import KuroCore
import SwiftUI

// MARK: - Club form parts
// Shared by the club sheets (create/join club in ClubsView, rail and poll here, settings): a kicker
// plus serif title, a labelled field on the quiet surface with an optional character count, a
// typographic choice row, and the inline error line. Tokens only; every string EN/DE at the call site.

/// Kicker and serif title at the top of a club sheet.
struct ClubSheetTitle: View {
    let kicker: String
    let title: String
    /// The club seal above the title (create club / rail / poll; spec §7.4, visual only).
    var showsSeal: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
            if showsSeal {
                // The room's seal keeps its own dark ground (its inks are drawn for the room).
                ClubSeal(ring: ClubSeal.compactRing)
                    .padding(6)
                    .background(Circle().fill(ClubRoomPalette.room))
                    .padding(.bottom, 10)
                    .accessibilityHidden(true)
            }
            Text(kicker)
                .kuroKicker()
                .accessibilityHidden(true)
            Text(title)
                .kuroRoleText(.headline)
                .foregroundStyle(Color.kuroInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A labelled text field on the quiet surface, with a live count when `limit` is set.
struct ClubFormField: View {
    let label: String
    let prompt: String
    @Binding var text: String
    var limit: Int? = nil
    var axis: Axis = .horizontal

    /// The length the server checks: Postgres `char_length` counts Unicode code points, not the
    /// grapheme clusters of `String.count` (an emoji with joiners is several code points).
    static func serverLength(_ text: String) -> Int {
        text.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count
    }

    private var count: Int { Self.serverLength(text) }
    private var isOverLimit: Bool { limit.map { count > $0 } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.kuroMeta(weight: .medium))
                    .foregroundStyle(Color.kuroInkSecondary)
                Spacer(minLength: KuroDesignSpacing.sm)
                if let limit, count > 0 {
                    Text(verbatim: "\(count)/\(limit)")
                        .font(.kuroMeta())
                        .monospacedDigit()
                        .foregroundStyle(isOverLimit ? Color.kuroError : Color.kuroInkQuiet)
                        .accessibilityLabel(KuroLocale.text("\(count) of \(limit) characters", "\(count) von \(limit) Zeichen"))
                }
            }
            .accessibilityElement(children: .combine)

            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(Color.kuroInkQuiet), axis: axis)
                .font(.kuroBody(weight: .regular))
                .foregroundStyle(Color.kuroInk)
                .lineLimit(axis == .vertical ? 3...6 : 1...1)
                .padding(.horizontal, KuroDesignSpacing.md)
                .padding(.vertical, 14)
                .frame(minHeight: 48)
                .background(
                    RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                        .fill(Color.kuroCanvasQuiet)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                        .strokeBorder(isOverLimit ? Color.kuroError : Color.clear, lineWidth: 1)
                )
                .accessibilityLabel(label)
        }
    }
}

/// One option of a typographic single choice: a title, one explanatory line, an ink check.
struct ClubChoiceRow: View {
    let title: String
    let detail: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: KuroDesignSpacing.md) {
                VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
                    Text(title)
                        .font(.kuroBody(weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(Color.kuroInk)
                    Text(detail)
                        .font(.kuroMeta())
                        .foregroundStyle(Color.kuroInkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "checkmark")
                    .font(.kuroMeta(weight: .semibold))
                    .foregroundStyle(Color.kuroInk)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, KuroDesignSpacing.md)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(KuroPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// An inline error line (red is for errors only).
struct ClubInlineError: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.kuroMeta())
            .foregroundStyle(Color.kuroError)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Unsaved input (navigation contract N7)

/// Whether a club form holds input that Cancel or swipe-down would lose. Pure (NavclubsTests).
nonisolated enum ClubFormRules {
    /// The audience a new club starts with (`CreateClubSheet`).
    static let defaultSharingLevel = "status"

    static func hasText(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Create club: a name, a description, or an audience other than the default.
    static func createClubIsDirty(name: String, description: String, sharingLevel: String) -> Bool {
        hasText(name) || hasText(description) || sharingLevel != defaultSharingLevel
    }

    /// Create rail: a title or a description.
    static func createRailIsDirty(title: String, description: String) -> Bool {
        hasText(title) || hasText(description)
    }

    /// Create poll: a question, any option text, or options added or removed (it starts with two).
    static func createPollIsDirty(question: String, options: [String]) -> Bool {
        hasText(question) || options.contains(where: hasText) || options.count != 2
    }
}

// MARK: - Create Club Rail Sheet

struct CreateClubRailSheet: View {
    let clubId: String
    var onCreated: (() -> Void)? = nil

    @Environment(ClubsStore.self) private var clubs
    @Environment(\.dismiss) private var dismiss
    @State private var actionScope = AccountActionScope()

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var isWorking = false
    @State private var errorText: String? = nil
    @State private var confirmDiscard = false
    @FocusState private var focus: Field?

    private enum Field: Hashable { case title, description }

    private var isDirty: Bool { ClubFormRules.createRailIsDirty(title: title, description: description) }

    static let descriptionLimit = 500

    var body: some View {
        let origin = actionScope.capture(session: clubs.accountSession)
        return NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: KuroDesignSpacing.lg) {
                    ClubSheetTitle(kicker: KuroLocale.text("New rail", "Neue Liste"),
                                   title: KuroLocale.text("Start a shared list.", "Lege eine gemeinsame Liste an."),
                                   showsSeal: true)

                    ClubFormField(label: KuroLocale.text("Title", "Titel"),
                                  prompt: KuroLocale.text("Watching together", "Schauen wir gemeinsam"),
                                  text: $title)
                        .focused($focus, equals: .title)
                        .submitLabel(.next)
                        .onSubmit { focus = .description }

                    ClubFormField(label: KuroLocale.text("Description (optional)", "Beschreibung (optional)"),
                                  prompt: KuroLocale.text("A line for the club", "Eine Zeile für den Club"),
                                  text: $description,
                                  limit: Self.descriptionLimit,
                                  axis: .vertical)
                        .focused($focus, equals: .description)

                    if let errorText {
                        ClubInlineError(text: errorText)
                    }

                    KuroInkButton(KuroLocale.text("Create rail", "Liste anlegen"), isLoading: isWorking) {
                        actionScope.launch(origin: origin, session: clubs.accountSession) { ticket in await create(origin: ticket) }
                    }
                    .disabled(!canSubmit)
                }
                .padding(.horizontal, KuroDesignSpacing.padding)
                .padding(.top, KuroDesignSpacing.md)
                .padding(.bottom, KuroDesignSpacing.xl)
                .kuroReadableWidth()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.kuroCanvasPage)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(KuroLocale.text("Cancel", "Abbrechen")) { cancel() }
                        .font(.kuroBody(weight: .regular))
                        .tint(Color.kuroInk)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .kuroDiscardGuard(isDirty: isDirty, isBusy: isWorking, isConfirming: $confirmDiscard) { dismiss() }
        .onAppear {
            actionScope.activate(session: clubs.accountSession)
            focus = .title
        }
        .onDisappear { actionScope.deactivate(); isWorking = false }
    }

    /// Cancel (N7): a clean form closes; unsaved input asks "Discard changes?" first.
    private func cancel() {
        switch KuroDiscardGuard.cancelStep(isDirty: isDirty) {
        case .close: dismiss()
        case .confirm: confirmDiscard = true
        }
    }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && ClubFormField.serverLength(description) <= Self.descriptionLimit
    }

    private func create(origin: AccountActionScope.Ticket) async {
        guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let d = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSubmit, !isWorking else { return }

        errorText = nil
        isWorking = true
        focus = nil
        defer { if actionScope.isCurrent(origin, session: clubs.accountSession) { isWorking = false } }

        do {
            _ = try await clubs.createClubRail(
                clubId: clubId,
                title: t,
                description: d.isEmpty ? nil : d
            )
            guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
            KuroAccessibility.successHaptic()
            onCreated?()
            dismiss()
        } catch {
            guard actionScope.isCurrent(origin, session: clubs.accountSession), !(error is CancellationError) else { return }
            let message = ClubCopy.createRailError(error as? ClubError, german: KuroLocale.isGerman)
            errorText = message
            AccessibilityNotification.Announcement(message).post()
            KuroAccessibility.errorHaptic()
        }
    }
}

// MARK: - Create Club Poll Sheet

struct CreateClubPollSheet: View {
    let clubId: String
    var onCreated: (() -> Void)? = nil

    @Environment(ClubsStore.self) private var clubs
    @Environment(\.dismiss) private var dismiss
    @State private var actionScope = AccountActionScope()

    @State private var question: String = ""
    @State private var options: [PollOptionDraft] = [PollOptionDraft(), PollOptionDraft()]
    @State private var isWorking = false
    @State private var errorText: String? = nil
    @State private var confirmDiscard = false
    @FocusState private var focus: Field?

    private enum Field: Hashable { case question, option(UUID) }

    private var isDirty: Bool {
        ClubFormRules.createPollIsDirty(question: question, options: options.map(\.text))
    }

    /// One editable option; a stable id keeps focus and rows right when an option is removed.
    struct PollOptionDraft: Identifiable, Equatable {
        let id = UUID()
        var text = ""
    }

    static let maxOptions = 10

    var body: some View {
        let origin = actionScope.capture(session: clubs.accountSession)
        return NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: KuroDesignSpacing.lg) {
                    ClubSheetTitle(kicker: KuroLocale.text("New poll", "Neue Umfrage"),
                                   title: KuroLocale.text("Ask the club.", "Frag den Club."),
                                   showsSeal: true)

                    ClubFormField(label: KuroLocale.text("Question", "Frage"),
                                  prompt: KuroLocale.text("What should we watch next?", "Was schauen wir als Nächstes?"),
                                  text: $question)
                        .focused($focus, equals: .question)
                        .submitLabel(.next)
                        .onSubmit { focus = options.first.map { .option($0.id) } }

                    VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                        Text(KuroLocale.text("Options", "Antworten"))
                            .font(.kuroMeta(weight: .medium))
                            .foregroundStyle(Color.kuroInkSecondary)
                            .accessibilityAddTraits(.isHeader)

                        ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                            HStack(spacing: KuroDesignSpacing.sm) {
                                TextField(
                                    "",
                                    text: binding(for: option.id),
                                    prompt: Text(KuroLocale.text("Option \(index + 1)", "Antwort \(index + 1)"))
                                        .foregroundStyle(Color.kuroInkQuiet)
                                )
                                .font(.kuroBody(weight: .regular))
                                .foregroundStyle(Color.kuroInk)
                                .focused($focus, equals: .option(option.id))
                                .submitLabel(index == options.count - 1 ? .done : .next)
                                .onSubmit { focusAfter(option.id) }
                                .padding(.horizontal, KuroDesignSpacing.md)
                                .frame(minHeight: 48)
                                .background(
                                    RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                                        .fill(Color.kuroCanvasQuiet)
                                )
                                .accessibilityLabel(KuroLocale.text("Option \(index + 1)", "Antwort \(index + 1)"))

                                if options.count > 2 {
                                    Button {
                                        options.removeAll { $0.id == option.id }
                                    } label: {
                                        Image(systemName: "minus.circle")
                                            .font(.kuroCustom(18, weight: .regular, relativeTo: .body, maxSize: 28))
                                            .foregroundStyle(Color.kuroInkSecondary)
                                            .frame(width: 44, height: 44)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(KuroPressStyle())
                                    .accessibilityLabel(KuroLocale.text("Remove option \(index + 1)", "Antwort \(index + 1) entfernen"))
                                }
                            }
                        }

                        if options.count < Self.maxOptions {
                            Button {
                                let draft = PollOptionDraft()
                                options.append(draft)
                                focus = .option(draft.id)
                            } label: {
                                HStack(spacing: KuroDesignSpacing.sm) {
                                    Image(systemName: "plus")
                                        .font(.kuroMeta(weight: .medium))
                                    Text(KuroLocale.text("Add option", "Antwort hinzufügen"))
                                        .font(.kuroMeta(weight: .medium))
                                }
                                .foregroundStyle(Color.kuroInk)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(KuroPressStyle())
                        }
                    }

                    if let errorText {
                        ClubInlineError(text: errorText)
                    }

                    KuroInkButton(KuroLocale.text("Start poll", "Umfrage starten"), isLoading: isWorking) {
                        actionScope.launch(origin: origin, session: clubs.accountSession) { ticket in await create(origin: ticket) }
                    }
                    .disabled(!canSubmit)
                }
                .padding(.horizontal, KuroDesignSpacing.padding)
                .padding(.top, KuroDesignSpacing.md)
                .padding(.bottom, KuroDesignSpacing.xl)
                .kuroReadableWidth()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.kuroCanvasPage)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(KuroLocale.text("Cancel", "Abbrechen")) { cancel() }
                        .font(.kuroBody(weight: .regular))
                        .tint(Color.kuroInk)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .kuroDiscardGuard(isDirty: isDirty, isBusy: isWorking, isConfirming: $confirmDiscard) { dismiss() }
        .onAppear {
            actionScope.activate(session: clubs.accountSession)
            focus = .question
        }
        .onDisappear { actionScope.deactivate(); isWorking = false }
    }

    /// Cancel (N7): a clean form closes; unsaved input asks "Discard changes?" first.
    private func cancel() {
        switch KuroDiscardGuard.cancelStep(isDirty: isDirty) {
        case .close: dismiss()
        case .confirm: confirmDiscard = true
        }
    }

    private func binding(for id: UUID) -> Binding<String> {
        Binding(
            get: { options.first { $0.id == id }?.text ?? "" },
            set: { newValue in
                guard let index = options.firstIndex(where: { $0.id == id }) else { return }
                options[index].text = newValue
            }
        )
    }

    private func focusAfter(_ id: UUID) {
        guard let index = options.firstIndex(where: { $0.id == id }) else { return }
        let next = options.index(after: index)
        focus = next < options.endIndex ? .option(options[next].id) : nil
    }

    private var validOptions: [String] {
        options.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private var canSubmit: Bool {
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && validOptions.count >= 2
    }

    private func create(origin: AccountActionScope.Ticket) async {
        guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSubmit, !isWorking else { return }

        errorText = nil
        isWorking = true
        focus = nil
        defer { if actionScope.isCurrent(origin, session: clubs.accountSession) { isWorking = false } }

        do {
            _ = try await clubs.createClubPoll(
                clubId: clubId,
                question: q,
                options: validOptions
            )
            guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
            KuroAccessibility.successHaptic()
            onCreated?()
            dismiss()
        } catch {
            guard actionScope.isCurrent(origin, session: clubs.accountSession), !(error is CancellationError) else { return }
            let message = ClubCopy.createPollError(error as? ClubError, german: KuroLocale.isGerman)
            errorText = message
            AccessibilityNotification.Announcement(message).post()
            KuroAccessibility.errorHaptic()
        }
    }
}
