// W9 tool sheets: the list name sheet (create / rename) and the tags-and-lists sheet of one title.
// Both are tool sheets: they leave the journey (`.kuroLeavesJourney()` at the presenter), register a
// navigation layer there, and guard unsaved input with `.kuroDiscardGuard`.

import KuroCore
import SwiftUI

// MARK: - Create / rename

struct CustomListNameSheet: View {
    /// nil creates a list; a name renames.
    let initialName: String?
    var forcedGerman: Bool?
    /// Returns the error to show, or nil when saved (the sheet then closes).
    let onSave: (String) async -> OrganiseError?

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var error: OrganiseError?
    @State private var isSaving = false
    @State private var confirmDiscard = false
    @FocusState private var focused: Bool

    private var german: Bool { forcedGerman ?? KuroLocale.isGerman }
    private func text(_ key: OrganiseCopy.Key) -> String { OrganiseCopy.string(key, german: german) }
    private var isDirty: Bool { name.trimmingCharacters(in: .whitespacesAndNewlines) != (initialName ?? "") }

    init(initialName: String? = nil, forcedGerman: Bool? = nil, onSave: @escaping (String) async -> OrganiseError?) {
        self.initialName = initialName
        self.forcedGerman = forcedGerman
        self.onSave = onSave
        _name = State(initialValue: initialName ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
            Text(text(initialName == nil ? .newList : .rename))
                .font(.kuroTitle())
                .foregroundStyle(Color.kuroInk)
                .accessibilityAddTraits(.isHeader)
            TextField(text(.listName), text: $name)
                .font(.kuroBody(weight: .regular))
                .focused($focused)
                .submitLabel(.done)
                .padding(KuroDesignSpacing.md)
                .frame(minHeight: 44)
                .background(RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous).fill(Color.kuroCanvasQuiet))
                .accessibilityIdentifier("lists.name.field")
            if let error {
                Text(OrganiseCopy.error(error, german: german))
                    .font(.kuroMeta(weight: .medium))
                    .foregroundStyle(Color.kuroError)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: KuroDesignSpacing.lg) {
                Button(text(.cancel)) { cancel() }
                    .font(.kuroMeta(weight: .medium))
                    .foregroundStyle(Color.kuroInkSecondary)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("lists.name.cancel")
                Spacer(minLength: 0)
                Button(text(.save)) { save() }
                    .font(.kuroMeta(weight: .semibold))
                    .foregroundStyle(Color.kuroInk)
                    .underline(true, color: Color.kuroInk)
                    .frame(minHeight: 44)
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("lists.name.save")
            }
            Spacer(minLength: 0)
        }
        .padding(KuroDesignSpacing.padding)
        .kuroReadableWidth()
        .background(Color.kuroCanvasPage)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .kuroDiscardGuard(isDirty: isDirty, isBusy: isSaving, isConfirming: $confirmDiscard) { dismiss() }
        .onAppear { focused = true }
    }

    private func cancel() {
        if isDirty { confirmDiscard = true } else { dismiss() }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        error = nil
        Task {
            let failure = await onSave(name)
            isSaving = false
            if let failure { error = failure } else { dismiss() }
        }
    }
}

// MARK: - Tags and lists of one title

struct TitleOrganiseSheet: View {
    let media: Media
    var forcedGerman: Bool?

    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryTagsStore.self) private var tags
    @Environment(CustomListsStore.self) private var lists

    /// What the sheet showed when it opened: the base the saved delta is computed from.
    @State private var originalTags: [String] = []
    @State private var originalListIds: Set<UUID> = []
    @State private var editedTags: [String] = []
    @State private var editedListIds: Set<UUID> = []
    @State private var snapshotTaken = false
    @State private var newTag = ""
    @State private var error: OrganiseError?
    @State private var isSaving = false
    @State private var confirmDiscard = false

    private var german: Bool { forcedGerman ?? KuroLocale.isGerman }
    private func text(_ key: OrganiseCopy.Key) -> String { OrganiseCopy.string(key, german: german) }
    private var key: MediaKey { media.libraryKey }

    private var delta: TitleOrganisationDelta {
        .between(key: key, originalTags: originalTags, editedTags: editedTags,
                 originalListIds: originalListIds, editedListIds: editedListIds)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.lg) {
                VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
                    Text(OrganiseCopy.string(.tagsAndLists, german: german).replacingOccurrences(of: "…", with: ""))
                        .font(.kuroTitle())
                        .foregroundStyle(Color.kuroInk)
                        .accessibilityAddTraits(.isHeader)
                    Text(media.title)
                        .font(.kuroMeta())
                        .foregroundStyle(Color.kuroInkSecondary)
                        .lineLimit(2)
                }
                tagsSection
                listsSection
                if let error {
                    Text(OrganiseCopy.error(error, german: german))
                        .font(.kuroMeta(weight: .medium))
                        .foregroundStyle(Color.kuroError)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: KuroDesignSpacing.lg) {
                    Button(text(.cancel)) { cancel() }
                        .font(.kuroMeta(weight: .medium))
                        .foregroundStyle(Color.kuroInkSecondary)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("organise.cancel")
                    Spacer(minLength: 0)
                    Button(text(.save)) { save() }
                        .font(.kuroMeta(weight: .semibold))
                        .foregroundStyle(Color.kuroInk)
                        .underline(true, color: Color.kuroInk)
                        .frame(minHeight: 44)
                        .disabled(isSaving || delta.isEmpty)
                        .accessibilityIdentifier("organise.save")
                }
            }
            .padding(KuroDesignSpacing.padding)
            .kuroReadableWidth()
        }
        .background(Color.kuroCanvasPage)
        .presentationDragIndicator(.visible)
        .kuroDiscardGuard(isDirty: snapshotTaken && !delta.isEmpty, isBusy: isSaving, isConfirming: $confirmDiscard) { dismiss() }
        .task {
            await tags.load()
            await lists.load()
            takeSnapshot()
        }
    }

    // MARK: Sections

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            KuroSectionHeader(text(.tags), size: .title)
            FlowWords(items: editedTags) { tag in
                Button {
                    editedTags.removeAll { LibraryTagRules.key($0) == LibraryTagRules.key(tag) }
                } label: {
                    HStack(spacing: KuroDesignSpacing.xs) {
                        Text(tag).font(.kuroMeta(weight: .medium)).foregroundStyle(Color.kuroInk)
                        Image(systemName: "xmark").font(.kuroCustom(10, weight: .semibold, relativeTo: .caption1, maxSize: 14))
                            .foregroundStyle(Color.kuroInkQuiet)
                    }
                    .padding(.horizontal, KuroDesignSpacing.sm)
                    .frame(minHeight: 44)
                    .overlay(Capsule().strokeBorder(Color.kuroKeyRim, lineWidth: 1).padding(.vertical, 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(german ? "\(tag) entfernen" : "Remove \(tag)")
            }
            TextField(text(.addTag), text: $newTag)
                .font(.kuroBody(weight: .regular))
                .submitLabel(.done)
                .onSubmit(addTag)
                .padding(KuroDesignSpacing.md)
                .frame(minHeight: 44)
                .background(RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous).fill(Color.kuroCanvasQuiet))
                .accessibilityIdentifier("organise.tag.field")
        }
    }

    private var listsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            KuroSectionHeader(text(.lists), size: .title)
            if lists.lists.isEmpty {
                Text(text(.noLists))
                    .font(.kuroMeta())
                    .foregroundStyle(Color.kuroInkQuiet)
                    .frame(minHeight: 44, alignment: .leading)
            }
            ForEach(lists.lists) { list in
                let isOn = editedListIds.contains(list.id)
                Button {
                    if isOn { editedListIds.remove(list.id) } else { editedListIds.insert(list.id) }
                } label: {
                    HStack(spacing: KuroDesignSpacing.md) {
                        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                            .font(.kuroCustom(20, relativeTo: .title3, maxSize: 28))
                            .foregroundStyle(isOn ? Color.kuroInk : Color.kuroInkQuiet)
                        Text(list.name).font(.kuroBody(weight: .regular)).foregroundStyle(Color.kuroInk)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
                .accessibilityIdentifier("organise.list.\(list.name)")
            }
        }
    }

    // MARK: Actions

    private func takeSnapshot() {
        guard !snapshotTaken else { return }
        snapshotTaken = true
        originalTags = tags.tags(for: key)
        editedTags = originalTags
        originalListIds = Set(lists.lists.filter { $0.items.contains(key) }.map(\.id))
        editedListIds = originalListIds
    }

    private func addTag() {
        error = nil
        guard let tag = LibraryTagRules.normalised(newTag) else { return }
        newTag = ""
        guard !editedTags.contains(where: { LibraryTagRules.key($0) == LibraryTagRules.key(tag) }) else { return }
        guard LibraryTagRules.length(tag) <= LibraryTagRules.maxLength else { error = .tagTooLong; return }
        guard editedTags.count < LibraryTagRules.maxTags else { error = .tagLimit; return }
        editedTags.append(tag)
    }

    private func cancel() {
        if snapshotTaken && !delta.isEmpty { confirmDiscard = true } else { dismiss() }
    }

    private func save() {
        guard !isSaving, snapshotTaken else { return }
        addTagIfTyped()
        let delta = delta
        isSaving = true
        error = nil
        Task {
            let result = await tags.saveOrganisation(delta)
            isSaving = false
            switch result {
            case .success: dismiss()
            case .failure(let failure): error = failure
            }
        }
    }

    private func addTagIfTyped() {
        if !newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { addTag() }
    }
}

/// Words that wrap onto several lines.
private struct FlowWords<Item: Hashable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        WrappingLayout(spacing: KuroDesignSpacing.xs) {
            ForEach(items, id: \.self) { content($0) }
        }
    }
}

private struct WrappingLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arranged = arrange(width: bounds.width, subviews: subviews)
        for (index, frame) in arranged.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                                  proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: min(maxX, width.isFinite ? width : maxX), height: y + rowHeight), frames)
    }
}
