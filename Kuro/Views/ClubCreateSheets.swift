import SwiftUI

// MARK: - Create Club Rail Sheet

struct CreateClubRailSheet: View {
    let clubId: String
    var onCreated: (() -> Void)? = nil

    @Environment(SupabaseService.self) private var supabaseService
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var isWorking = false
    @State private var errorText: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kuroBackground.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TITLE")
                                .font(.kuroMicro(weight: .medium))
                                .tracking(1.4)
                                .foregroundColor(.kuroBlack30)

                            TextField("", text: $title, prompt: Text("e.g. Watch Together").foregroundColor(.kuroBlack30))
                                .font(.kuroBody())
                                .foregroundColor(.kuroBlack80)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.black.opacity(0.04))
                                )
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("DESCRIPTION")
                                .font(.kuroMicro(weight: .medium))
                                .tracking(1.4)
                                .foregroundColor(.kuroBlack30)

                            TextField("", text: $description, prompt: Text("Optional").foregroundColor(.kuroBlack30), axis: .vertical)
                                .font(.kuroBody())
                                .foregroundColor(.kuroBlack80)
                                .lineLimit(3...6)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.black.opacity(0.04))
                                )
                        }

                        if let errorText {
                            Text(errorText)
                                .font(.kuroCaption())
                                .foregroundColor(.red.opacity(0.85))
                        }

                        Button {
                            Task { await create() }
                        } label: {
                            HStack(spacing: 10) {
                                if isWorking {
                                    ProgressView()
                                        .tint(.white)
                                        .scaleEffect(0.85)
                                }
                                Text("CREATE RAIL")
                                    .font(.kuroCaption(weight: .semibold))
                                    .tracking(1.6)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(canSubmit ? Color.black : Color.black.opacity(0.2))
                            )
                            .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSubmit || isWorking)
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, KuroDesignSpacing.padding)
                    .padding(.top, KuroDesignSpacing.md)
                }
            }
            .navigationTitle("NEW RAIL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.kuroBody())
                        .foregroundColor(.kuroBlack60)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func create() async {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let d = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }

        errorText = nil
        isWorking = true
        defer { isWorking = false }

        do {
            _ = try await supabaseService.createClubRail(
                clubId: clubId,
                title: t,
                description: d.isEmpty ? nil : d
            )
            onCreated?()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - Create Club Poll Sheet

struct CreateClubPollSheet: View {
    let clubId: String
    var onCreated: (() -> Void)? = nil

    @Environment(SupabaseService.self) private var supabaseService
    @Environment(\.dismiss) private var dismiss

    @State private var question: String = ""
    @State private var options: [String] = ["", ""]
    @State private var isWorking = false
    @State private var errorText: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kuroBackground.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("QUESTION")
                                .font(.kuroMicro(weight: .medium))
                                .tracking(1.4)
                                .foregroundColor(.kuroBlack30)

                            TextField("", text: $question, prompt: Text("What should we watch next?").foregroundColor(.kuroBlack30))
                                .font(.kuroBody())
                                .foregroundColor(.kuroBlack80)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.black.opacity(0.04))
                                )
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("OPTIONS")
                                .font(.kuroMicro(weight: .medium))
                                .tracking(1.4)
                                .foregroundColor(.kuroBlack30)

                            ForEach(options.indices, id: \.self) { index in
                                HStack(spacing: 8) {
                                    TextField("", text: $options[index], prompt: Text("Option \(index + 1)").foregroundColor(.kuroBlack30))
                                        .font(.kuroBody())
                                        .foregroundColor(.kuroBlack80)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .fill(Color.black.opacity(0.04))
                                        )

                                    if options.count > 2 {
                                        Button {
                                            options.remove(at: index)
                                        } label: {
                                            Image(systemName: "minus.circle")
                                                .font(.system(size: 18, weight: .regular))
                                                .foregroundColor(.red.opacity(0.6))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            if options.count < 10 {
                                Button {
                                    options.append("")
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "plus")
                                            .font(.system(size: 12, weight: .medium))
                                        Text("Add option")
                                            .font(.kuroCaption(weight: .regular))
                                    }
                                    .foregroundColor(.black.opacity(0.55))
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 4)
                            }
                        }

                        if let errorText {
                            Text(errorText)
                                .font(.kuroCaption())
                                .foregroundColor(.red.opacity(0.85))
                        }

                        Button {
                            Task { await create() }
                        } label: {
                            HStack(spacing: 10) {
                                if isWorking {
                                    ProgressView()
                                        .tint(.white)
                                        .scaleEffect(0.85)
                                }
                                Text("CREATE POLL")
                                    .font(.kuroCaption(weight: .semibold))
                                    .tracking(1.6)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(canSubmit ? Color.black : Color.black.opacity(0.2))
                            )
                            .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSubmit || isWorking)
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, KuroDesignSpacing.padding)
                    .padding(.top, KuroDesignSpacing.md)
                }
            }
            .navigationTitle("NEW POLL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.kuroBody())
                        .foregroundColor(.kuroBlack60)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var validOptions: [String] {
        options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private var canSubmit: Bool {
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && validOptions.count >= 2
    }

    private func create() async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, validOptions.count >= 2 else { return }

        errorText = nil
        isWorking = true
        defer { isWorking = false }

        do {
            _ = try await supabaseService.createClubPoll(
                clubId: clubId,
                question: q,
                options: validOptions
            )
            onCreated?()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
