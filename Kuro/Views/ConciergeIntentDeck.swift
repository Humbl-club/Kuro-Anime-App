import SwiftUI

// The opening "intent deck" should feel like Kuro curation, not a settings menu.
// Two primary tiles (Import / Curate) + one secondary "Examples" affordance.

struct ConciergeIntentDeck: View {
    let onPaste: () -> Void
    let onImportLibrary: () -> Void
    let onStartCurate: () -> Void
    let onInsertExample: (_ text: String) -> Void
    let onImportAniList: () -> Void

    @State private var showExamples = false

    private var isGermanLocale: Bool {
        let language = Locale.current.language.languageCode?.identifier.lowercased() ?? "en"
        return language.hasPrefix("de")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                tile(
                    systemImage: "doc.on.clipboard",
                    eyebrow: isGermanLocale ? "IMPORT" : "IMPORT",
                    title: isGermanLocale ? "Aus deiner Bibliothek" : "From your library",
                    subtitle: isGermanLocale ? "Nutze Kuro-Listen direkt" : "Use your current Kuro list",
                    action: onImportLibrary
                )

                tile(
                    systemImage: "doc.on.doc",
                    eyebrow: isGermanLocale ? "ÜBERNAHME" : "PASTE",
                    title: isGermanLocale ? "Aus Zwischenablage einfügen" : "From clipboard",
                    subtitle: isGermanLocale ? "Für eine manuelle Liste" : "For a manual list",
                    action: onPaste
                )

                tile(
                    systemImage: "sparkles",
                    eyebrow: isGermanLocale ? "KURATIEREN" : "CURATE",
                    title: isGermanLocale ? "Kuratiere für mich" : "Curate for me",
                    subtitle: isGermanLocale ? "Zwei Rails, sofort" : "Two rails, right away",
                    action: onStartCurate
                )
            }

            Button(action: {
                KuroAccessibility.impactHaptic(.light)
                showExamples = true
            }) {
                HStack(spacing: 8) {
                    Text(isGermanLocale ? "Beispiele zeigen" : "Show examples")
                        .font(.kuroCaption(weight: .medium))
                        .foregroundStyle(.black.opacity(0.62))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.22))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.03))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.black.opacity(0.08), lineWidth: 0.6)
                        )
                )
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showExamples) {
                ConciergeExamplesSheet(
                    isGermanLocale: isGermanLocale,
                    onInsertExample: onInsertExample
                )
                .presentationDetents([.medium])
            }

            Button(action: {
                KuroAccessibility.impactHaptic(.light)
                onImportAniList()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "person.text.rectangle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.28))
                    Text(isGermanLocale ? "Aus AniList importieren" : "Import from AniList")
                        .font(.kuroCaption(weight: .medium))
                        .foregroundStyle(.black.opacity(0.62))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.22))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: KuroRadius.lg, style: .continuous)
                        .fill(Color.white.opacity(0.92))
                        .overlay(
                            RoundedRectangle(cornerRadius: KuroRadius.lg, style: .continuous)
                                .stroke(Color.black.opacity(0.08), lineWidth: 0.7)
                        )
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func tile(
        systemImage: String,
        eyebrow: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            KuroAccessibility.impactHaptic(.light)
            action()
        }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    Circle()
                        .fill(Color.black.opacity(0.05))
                        .frame(width: 30, height: 30)
                        .overlay {
                            Image(systemName: systemImage)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.black.opacity(0.62))
                        }

                    Spacer(minLength: 0)

                    Text(eyebrow)
                        .font(.kuroMicro(weight: .medium))
                        .tracking(2.2)
                        .foregroundStyle(.black.opacity(0.38))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .light, design: .serif))
                        .foregroundStyle(.black.opacity(0.84))
                        .lineLimit(2)

                    Text(subtitle)
                        .font(.kuroCaption(weight: .light))
                        .foregroundStyle(.black.opacity(0.55))
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 98, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: KuroRadius.lg, style: .continuous)
                    .fill(Color.white.opacity(0.92))
                    .overlay(
                        RoundedRectangle(cornerRadius: KuroRadius.lg, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 0.7)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ConciergeExamplesSheet: View {
    let isGermanLocale: Bool
    let onInsertExample: (_ text: String) -> Void

    @Environment(\.dismiss) private var dismiss

    private struct Example: Identifiable {
        let id = UUID()
        let title: String
        let prompt: String
    }

    private var examples: [Example] {
        if isGermanLocale {
            return [
                .init(title: "Dunkel, kein Gore", prompt: "Etwas düster und ernst, ohne Gore, nicht lang."),
                .init(title: "Ein perfekter Film", prompt: "Ein perfekter Anime-Film — intensiv, ohne Romance."),
                .init(title: "Unterschätzt", prompt: "Unterschätzte Klassiker mit starkem Handwerk.")
            ]
        }
        return [
            .init(title: "Dark, not gory", prompt: "Something dark and serious, not gory, short."),
            .init(title: "One perfect film", prompt: "One perfect anime film — intense, no romance."),
            .init(title: "Underseen", prompt: "Underseen classics with strong craft.")
        ]
    }

    private var importExample: String {
        if isGermanLocale {
            return """
            Attack on Titan (abgeschlossen)
            Jujutsu Kaisen bis Folge 12
            Hunter x Hunter (2011)
            """
        }
        return """
        Attack on Titan (completed)
        Jujutsu Kaisen up to ep 12
        Hunter x Hunter (2011)
        """
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(isGermanLocale ? "Beispiele" : "Examples")
                        .font(.system(size: 24, weight: .ultraLight, design: .serif))
                        .foregroundStyle(.black.opacity(0.84))

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(examples) { ex in
                            exampleRow(title: ex.title, prompt: ex.prompt)
                        }
                    }

                    Rectangle()
                        .fill(Color.black.opacity(0.06))
                        .frame(height: 0.5)
                        .padding(.top, 6)

                    Text(isGermanLocale ? "Import-Format" : "Import format")
                        .font(.kuroMicro(weight: .medium))
                        .tracking(1.8)
                        .foregroundStyle(.black.opacity(0.38))
                        .padding(.top, 2)

                    exampleRow(
                        title: isGermanLocale ? "Liste einfügen" : "Paste a list",
                        prompt: importExample
                    )
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isGermanLocale ? "Fertig" : "Done") { dismiss() }
                        .font(.kuroCaption(weight: .medium))
                }
            }
        }
    }

    private func exampleRow(title: String, prompt: String) -> some View {
        Button(action: {
            KuroAccessibility.impactHaptic(.light)
            onInsertExample(prompt)
            dismiss()
        }) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.kuroCaption(weight: .medium))
                    .foregroundStyle(.black.opacity(0.80))

                Text(prompt)
                    .font(.kuroCaption(weight: .light))
                    .foregroundStyle(.black.opacity(0.55))
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: KuroRadius.lg, style: .continuous)
                    .fill(Color.white.opacity(0.94))
                    .overlay(
                        RoundedRectangle(cornerRadius: KuroRadius.lg, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 0.7)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
