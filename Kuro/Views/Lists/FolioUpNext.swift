import SwiftUI
import KuroCore
import KuroLibrary

// MARK: - W10 "Up next in your series" on Collection's Completed view
// A horizontal rail of the direct sequels (or next reviewed seasons) of titles the account completed.
// One Plan key per card (stamps on success), a long-press "Not interested" as the only removal, and a
// tap that opens the title. Results go to Collection's one notice slot (`FolioNoticeBar`).

/// Where the section shows. One line to move it: an owner may prefer Planning or Watching.
nonisolated enum FolioUpNextPlacement {
    /// Only on the Completed view, outside search, selection and the imported-titles view, and only
    /// while `collection_up_next_v1` is on (so the view neither mounts the section nor loads it).
    static func shows(status: FolioStatus, isImportedView: Bool, isSearching: Bool, isSelecting: Bool,
                      isEnabled: Bool) -> Bool {
        isEnabled && status == .completed && !isImportedView && !isSearching && !isSelecting
    }
}

nonisolated enum FolioUpNextNotices {
    /// created: "Added to your list." with Undo; not created: "Already in your library." and no action.
    static func planned(_ receipt: UpNextPlanReceipt, german: Bool) -> FolioNotice {
        if receipt.offersUndo {
            return FolioNotice(tone: .confirmation, message: TastePlanCopy.message(.added, german: german),
                               actionTitle: TastePlanCopy.undo(german: german), undo: .upNextPlan(receipt))
        }
        return FolioNotice(tone: .confirmation, message: UpNextCopy.alreadyInLibrary(german: german), actionTitle: nil)
    }

    static func dismissed(_ receipt: DiscoverFeedbackReceipt, german: Bool) -> FolioNotice {
        FolioNotice(tone: .confirmation, message: DiscoverMenuCopy.toast(.notInterested, medium: receipt.key.kind, german: german),
                    actionTitle: TastePlanCopy.undo(german: german), undo: .upNextDismiss(receipt))
    }

    static func failed(german: Bool) -> FolioNotice {
        FolioNotice(tone: .problem, message: TastePlanCopy.message(.failed, german: german), actionTitle: nil)
    }
}

struct FolioUpNextSection: View {
    let medium: MediaKind
    let gutter: CGFloat
    let width: CGFloat
    let onPlanned: (UpNextPlanReceipt) -> Void
    let onDismissed: (DiscoverFeedbackReceipt) -> Void
    var onPlanFailed: () -> Void = {}

    @Environment(UpNextStore.self) private var upNext: UpNextStore?
    @Environment(InteractionTelemetry.self) private var telemetry: InteractionTelemetry?
    @State private var shownReported = false

    private var german: Bool { KuroLocale.isGerman }

    var body: some View {
        if let upNext {
            let items = upNext.visible(medium)
            if !items.isEmpty {
                rail(items, upNext: upNext)
                    .onAppear { reportShown(items.count) }
            } else if upNext.isEnabled, upNext.phase[medium] == .offline {
                KuroOfflineView(hasContent: false, retry: { Task { await upNext.load(medium, force: true) } })
                    .padding(.horizontal, gutter)
            }
        }
    }

    private func rail(_ items: [UpNextItem], upNext: UpNextStore) -> some View {
        let cardWidth = KuroRailPeek.cardWidth(visible: max(0, width - gutter))
        return VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
            KuroSectionHeader(UpNextCopy.heading(german: german), size: .title)
                .padding(.horizontal, gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: KuroRailPeek.spacing) {
                    ForEach(items) { item in
                        UpNextCard(item: item, width: cardWidth, german: german,
                                   onPlan: { plan(item, upNext: upNext) },
                                   onDismiss: { dismiss(item, upNext: upNext) })
                    }
                }
                .padding(.horizontal, gutter)
            }
            .kuroSwipeExclusionZone()
        }
        .padding(.bottom, KuroDesignSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func plan(_ item: UpNextItem, upNext: UpNextStore) {
        Task {
            if let receipt = await upNext.plan(item) {
                telemetry?.trackInteractionEvent("up_next_plan", surface: "collection", result: "success",
                                                 extra: ["media_type": item.key.kind.rawValue, "media_id": item.key.id])
                onPlanned(receipt)
            } else {
                onPlanFailed()
            }
        }
    }

    private func dismiss(_ item: UpNextItem, upNext: UpNextStore) {
        if let receipt = upNext.dismiss(item) { onDismissed(receipt) }
    }

    /// The denominator of the plan-tap outcome: once per visit where the section shows at least one row.
    private func reportShown(_ count: Int) {
        guard !shownReported, count > 0 else { return }
        shownReported = true
        telemetry?.trackInteractionEvent("up_next_shown", surface: "collection", result: "shown",
                                         extra: ["media_type": medium.rawValue])
    }
}

private struct UpNextCard: View {
    let item: UpNextItem
    let width: CGFloat
    let german: Bool
    let onPlan: () -> Void
    let onDismiss: () -> Void

    @Environment(\.kuroRoutes) private var routes
    @State private var stamp = 0

    var body: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            Button {
                routes.openMedia(MediaRoute(item.key))
            } label: {
                VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
                    poster
                    Text(item.title)
                        .font(.kuroMeta(weight: .medium))
                        .foregroundStyle(Color.kuroInk)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(UpNextCopy.after(item.afterTitle, german: german))
                        .font(.kuroCaption())
                        .foregroundStyle(Color.kuroInkSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if item.isAnnounced {
                        Text(UpNextCopy.announced(german: german))
                            .font(.kuroCaption(weight: .medium))
                            .foregroundStyle(Color.kuroInk)
                    }
                }
                .frame(width: width, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(KuroPressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(item.title), \(UpNextCopy.after(item.afterTitle, german: german).lowercasedFirst)")
            .accessibilityAddTraits(.isButton)
            planKey
        }
        .frame(width: width, alignment: .leading)
        .contextMenu {
            Button(role: .none) { onDismiss() } label: {
                Label(DiscoverMenuCopy.notInterested(german: german), systemImage: "eye.slash")
                Text(UpNextCopy.dismissSubtitle(german: german))
            }
        }
    }

    private var poster: some View {
        let height = (width * 3 / 2).rounded()
        return ZStack {
            if let url = item.coverImage.flatMap(URL.init(string:)) {
                KuroCachedAsyncImage(url: url, maxPixelSize: 360) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: KuroBrandedTile(kind: item.key.kind == .manga ? "Manga" : "Anime", title: item.title)
                    }
                }
            } else {
                KuroBrandedTile(kind: item.key.kind == .manga ? "Manga" : "Anime", title: item.title)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .accessibilityHidden(true)
    }

    private var planKey: some View {
        Button {
            KuroAccessibility.impactHaptic(.light)
            stamp += 1
            onPlan()
        } label: {
            HStack(spacing: 5) {
                Text(UpNextCopy.plan(german: german))
                    .font(.kuroCustom(11, weight: .medium, relativeTo: .caption1, maxSize: 20))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 2)
                ZStack {
                    Image(systemName: "plus").font(.system(size: 13, weight: .light))
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold))
                        .kuroConfirmStamp(trigger: stamp)
                }
                .frame(width: 18, height: 28)
                .accessibilityHidden(true)
            }
            .foregroundStyle(Color.kuroInk)
            .padding(.horizontal, 8)
            .frame(width: width, alignment: .leading)
            .frame(minHeight: 44)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.kuroInk, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(KuroPressStyle())
        .accessibilityLabel("\(UpNextCopy.plan(german: german)), \(item.title)")
    }
}

private extension String {
    /// "Sequel to X" read inside a sentence: "sequel to X".
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
