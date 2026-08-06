import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Taste Deck (ADR 2026-07-31 — flagship of the One Hero Grammar; v2 redesign)
// Full-page, one-title-at-a-time decide ritual: NOT FOR ME / I KNOW THIS / CALLS TO ME.
// The image fills the entire page body edge-to-edge (below the app header, down to the
// screen's bottom edge); a floating monochrome glass container on top carries the serif
// title, caption line and the three actions. The deck is ENDLESS — no session boundary,
// no interstitial; batches prefetch whenever three or fewer cards remain, and the quiet
// judged count sits by the leanings button. The "summary" only appears when the catalog
// is genuinely exhausted. Leanings come from the server profile only. Flick gestures on
// the image (right = calls to me, left = pass, up = I know this); the root pager still
// owns drags from the screen edges and fast flings.

// MARK: - View Model

struct TasteDeckOutcome: Sendable {
    let card: TasteDeckCard
    let action: TasteDeckAction
}

enum TasteDeckExitDirection: Sendable {
    case left, up, right

    init(action: TasteDeckAction) {
        switch action {
        case .skip: self = .left
        case .pass: self = .left
        case .known: self = .up
        case .love: self = .right
        case .retract: self = .up
        }
    }

    var tilt: Double {
        switch self {
        case .left: return -8
        case .up: return 8
        case .right: return 8
        }
    }

    var travel: CGSize {
        switch self {
        case .left: return CGSize(width: -560, height: -60)
        case .up: return CGSize(width: 0, height: -980)
        case .right: return CGSize(width: 560, height: -60)
        }
    }
}

@MainActor
@Observable
final class TasteDeckModel {
    enum Phase: Equatable {
        case loading
        case dealing
        /// The catalog is genuinely exhausted (or never had anything to deal).
        /// This is the only "summary" the deck still has.
        case empty
    }

    /// Cards dealt per RPC batch. The deck is endless: batches keep coming
    /// whenever the queue runs low — there is no session length.
    let batchSize = 12

    private(set) var phase: Phase = .loading
    private(set) var queue: [TasteDeckCard] = []
    /// Total titles judged since the deck mounted — the quiet progress count.
    private(set) var totalJudged: Int = 0
    /// When the last signal was recorded. The leanings sheet compares this with
    /// the server profile's computed_at to flag swipes Kuro hasn't digested yet.
    private(set) var lastSignalAt: Date? = nil
    private(set) var undoCandidate: TasteDeckOutcome? = nil
    var removalDirection: TasteDeckExitDirection = .up

    /// A signal whose record RPC failed; retried once on the next commit and
    /// once on appear. In-memory only — deck signals are taste hints, and the
    /// queue never outlives the session.
    private struct PendingSignal {
        let mediaType: String
        let mediaId: Int
        let action: TasteDeckAction
        /// Total failed delivery attempts (initial try + retries).
        var failures: Int
    }

    private var dealtKeys: Set<String> = []
    private var isFetchingBatch = false
    private var batchExhausted = false
    private var undoClearTask: Task<Void, Never>? = nil
    private var fetchTask: Task<Void, Never>? = nil
    private var pendingSignals: [PendingSignal] = []
    private var isFlushingSignals = false
    /// True once a signal has failed delivery three times (initial + two
    /// retries); the view surfaces a transient banner. Resets when the queue
    /// fully drains, so one outage = one banner.
    private(set) var signalsNeedAttention = false
    /// Set when a batch fetch fails with an empty queue — the view swaps the
    /// loading shimmer for a quiet retry state instead of shimmering forever.
    private(set) var initialLoadFailed = false

    var current: TasteDeckCard? { queue.first }
    var upcomingCards: [TasteDeckCard] { Array(queue.dropFirst().prefix(3)) }

    /// Offline recovery keeps dealing; only retry when the queue ran dry and the
    /// catalog isn't already known to be exhausted.
    var shouldRetryAfterReconnect: Bool {
        queue.isEmpty && !batchExhausted
    }

    func loadInitial(using service: SupabaseService) async {
        phase = .loading
        batchExhausted = false
        initialLoadFailed = false
        // Appear retry: queued (previously failed) signals get one more shot.
        await flushPendingSignals(using: service)
        await fetchNextBatch(using: service)
        // A failed initial fetch keeps the loading phase so the view can show
        // its retry state; a genuinely empty catalog still lands on .empty.
        if phase == .loading && !(initialLoadFailed && queue.isEmpty) {
            phase = queue.isEmpty ? .empty : .dealing
        }
    }

    func retry(using service: SupabaseService) async {
        await loadInitial(using: service)
    }

    func commit(_ action: TasteDeckAction, using service: SupabaseService) {
        guard let card = current else { return }
        removalDirection = TasteDeckExitDirection(action: action)
        queue.removeFirst()
        dealtKeys.insert(card.stableKey)
        totalJudged += 1
        lastSignalAt = Date()

        undoCandidate = TasteDeckOutcome(card: card, action: action)
        scheduleUndoClear()

        // Fire-and-forget; the deck never waits on the write. Failures queue
        // and retry on the next commit/appear instead of vanishing.
        recordSignal(mediaType: card.mediaType, mediaId: card.mediaId, action: action, using: service)

        if queue.isEmpty && batchExhausted {
            phase = .empty
        } else if queue.count <= 3 {
            // Endless: keep dealing — the batch RPC returns fresh unseen titles.
            prefetchNextBatch(using: service)
        }
    }

    func undoLast(using service: SupabaseService) {
        guard let outcome = undoCandidate else { return }
        undoCandidate = nil
        undoClearTask?.cancel()
        undoClearTask = nil
        totalJudged = max(0, totalJudged - 1)
        lastSignalAt = Date()
        queue.insert(outcome.card, at: 0)
        phase = .dealing
        recordSignal(
            mediaType: outcome.card.mediaType,
            mediaId: outcome.card.mediaId,
            action: .retract,
            using: service
        )
    }

    func cancelPendingWork() {
        undoClearTask?.cancel()
        undoClearTask = nil
        fetchTask?.cancel()
        fetchTask = nil
    }

    /// Fire-and-forget record with a safety net: the pending queue is flushed
    /// first (older signals replay in order), then this signal is recorded; a
    /// failure is queued for retry instead of being dropped.
    private func recordSignal(mediaType: String, mediaId: Int, action: TasteDeckAction, using service: SupabaseService) {
        Task {
            await flushPendingSignals(using: service)
            let recorded = await service.recordTasteDeckSignal(mediaType: mediaType, mediaId: mediaId, action: action)
            guard !recorded else { return }
            #if DEBUG
            print("⚠️ taste signal queued for retry: \(action.rawValue) \(mediaType)-\(mediaId)")
            #endif
            pendingSignals.append(PendingSignal(mediaType: mediaType, mediaId: mediaId, action: action, failures: 1))
        }
    }

    /// Serially retries every queued signal once. Failures stay queued with an
    /// incremented count; after the third failed delivery the deck flags it so
    /// the view can show the transient "didn't save" banner.
    private func flushPendingSignals(using service: SupabaseService) async {
        guard !isFlushingSignals, !pendingSignals.isEmpty else { return }
        isFlushingSignals = true
        defer { isFlushingSignals = false }
        // Snapshot + clear so signals enqueued mid-flush are never lost.
        let batch = pendingSignals
        pendingSignals = []
        var stillPending: [PendingSignal] = []
        for var signal in batch {
            let recorded = await service.recordTasteDeckSignal(
                mediaType: signal.mediaType,
                mediaId: signal.mediaId,
                action: signal.action
            )
            guard !recorded else { continue }
            signal.failures += 1
            if signal.failures >= 3 {
                signalsNeedAttention = true
            }
            stillPending.append(signal)
        }
        pendingSignals.append(contentsOf: stillPending)
        if pendingSignals.isEmpty {
            signalsNeedAttention = false
        }
    }

    private func scheduleUndoClear() {
        undoClearTask?.cancel()
        // VoiceOver users need time to locate the chip — double the window for
        // them rather than keeping it persistent, so the quiet chrome contract
        // (and the visual tie to the exited card) holds for everyone else.
        let windowNs: UInt64 = {
            #if canImport(UIKit)
            return UIAccessibility.isVoiceOverRunning ? 8_000_000_000 : 4_000_000_000
            #else
            return 4_000_000_000
            #endif
        }()
        undoClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: windowNs)
            guard !Task.isCancelled else { return }
            self?.undoCandidate = nil
        }
    }

    private func prefetchNextBatch(using service: SupabaseService) {
        guard fetchTask == nil else { return }
        fetchTask = Task { [weak self] in
            guard let self else { return }
            await self.fetchNextBatch(using: service)
            self.fetchTask = nil
        }
    }

    private func fetchNextBatch(using service: SupabaseService) async {
        guard !isFetchingBatch, !batchExhausted else { return }
        isFetchingBatch = true
        defer { isFetchingBatch = false }
        guard let rows = await service.fetchTasteDeckBatch(limit: batchSize) else {
            // Transport/server error: not proof of exhaustion. Leave the phase alone so
            // the offline/loading UI (and reconnect retry) can recover; flag empty-queue
            // failures so the view can offer a retry instead of shimmering forever.
            if queue.isEmpty {
                initialLoadFailed = true
                if phase == .dealing { phase = .loading }
            }
            return
        }
        initialLoadFailed = false
        let fresh = rows.filter { dealtKeys.insert($0.stableKey).inserted }
        if fresh.isEmpty {
            batchExhausted = true
            if queue.isEmpty {
                phase = .empty
            }
        } else {
            queue.append(contentsOf: fresh)
        }
    }
}

// MARK: - Exit Transition (commit: directional slide + 8° tilt)

private struct TasteDeckExitModifier: ViewModifier {
    let direction: TasteDeckExitDirection
    let progress: CGFloat // 0 = in place, 1 = fully exited

    func body(content: Content) -> some View {
        content
            .offset(
                x: direction.travel.width * progress,
                y: direction.travel.height * progress
            )
            .rotationEffect(.degrees(direction.tilt * progress))
            .opacity(Double(1 - progress))
    }
}

extension AnyTransition {
    static func deckCommit(_ direction: TasteDeckExitDirection) -> AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.96).combined(with: .opacity),
            removal: .modifier(
                active: TasteDeckExitModifier(direction: direction, progress: 1),
                identity: TasteDeckExitModifier(direction: direction, progress: 0)
            )
        )
    }
}

// MARK: - Glass height reporting (anchors the undo chip just above the glass)

private struct KuroDeckGlassHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

extension View {
    fileprivate func reportDeckGlassHeight() -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: KuroDeckGlassHeightKey.self, value: proxy.size.height)
            }
        )
    }
}

// MARK: - Card Surface (v2 — full-page art; glass holds title, caption, actions)

/// One dealt card: the image fills the entire page body edge-to-edge. A floating
/// monochrome glass container carries the serif title, the caption line and the
/// three actions; the meta strip (medium first) stays top-left on the art.
/// The whole surface owns the deck flick (right/left/up) and registers itself as
/// a pager swipe-exclusion zone; only screen edges and fast flings still page.
/// Drag offset is per-card state so an exiting card keeps its flick position
/// while the next deals clean.
private struct TasteDeckCardSurface: View {
    let card: TasteDeckCard
    let bottomInset: CGFloat
    var onCommit: (TasteDeckAction) -> Void
    var onSynopsis: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var dragOffset: CGSize = .zero

    private let commitDistance: CGFloat = 90
    private let commitPredictedDistance: CGFloat = 240
    private let maxDragTilt: Double = 8

    /// Accessibility text sizes blow the one-line action labels past their
    /// capsules ("NOT F…"); only then do the labels wrap/shrink (see actions).
    private var isAccessibilityTextSize: Bool { dynamicTypeSize >= .accessibility1 }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                imageLayer(size: geo.size)

                // Grain (club-hero recipe)
                Rectangle()
                    .fill(Color.kuroWhite04)
                    .blendMode(.overlay)
                    .allowsHitTesting(false)

                // Hero-grammar dual gradient: legibility bottom (behind the glass)…
                LinearGradient(
                    colors: [Color.kuroBlack65, Color.kuroBlack25, Color.clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .frame(height: geo.size.height * 0.52)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)

                // …vignette top (behind the meta strip).
                LinearGradient(
                    colors: [Color.kuroBlack35, Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 96)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)

                metaStrip
                    .padding(.horizontal, KuroDesignSpacing.padding)
                    .padding(.top, KuroDesignSpacing.sm + 2)

                glassPanel
                    .padding(.horizontal, KuroDesignSpacing.md)
                    .padding(.bottom, bottomInset + KuroDesignSpacing.md)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.35) {
                onSynopsis()
            }
            .offset(dragOffset)
            .rotationEffect(.degrees(reduceMotion ? 0 : dragTilt))
            .gesture(flickGesture(cardWidth: geo.size.width))
        }
        .kuroSwipeExclusionZone()
    }

    private var dragTilt: Double {
        max(-maxDragTilt, min(maxDragTilt, Double(dragOffset.width) / 20))
    }

    // MARK: Image (full-bleed — H4 placeholder spec: secondary background + shimmer + 0.2s fade-in)

    private func imageLayer(size: CGSize) -> some View {
        KuroCachedAsyncImage(
            url: card.imageURL,
            transaction: Transaction(animation: .easeOut(duration: 0.2)),
            maxPixelSize: 1100
        ) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                Color.kuroSecondaryBackground
                    .overlay(
                        Image(systemName: "photo")
                            .font(.kuroHeadline(weight: .ultraLight))
                            .foregroundColor(.kuroTextTertiary)
                    )
            case .empty:
                Color.kuroSecondaryBackground
                    .kuroShimmer()
            @unknown default:
                Color.kuroSecondaryBackground
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    /// Modern monochrome capsules: sans micro type on a quiet scrim.
    /// The first chip is always the medium ("ANIME" / "MANGA").
    private var metaStrip: some View {
        HStack(spacing: KuroDesignSpacing.xs + 2) {
            ForEach(card.metaChips, id: \.self) { chip in
                Text(chip)
                    .font(.kuroMicro(weight: .medium))
                    .tracking(1.4)
                    .foregroundColor(.kuroWhite)
                    .padding(.horizontal, KuroDesignSpacing.sm + 2)
                    .padding(.vertical, KuroDesignSpacing.xs + 1)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.kuroBlack45)
                    )
            }
        }
    }

    // MARK: Glass panel (serif title, caption, the three actions)

    private var glassPanel: some View {
        KuroGlassCard(tone: .onImage) {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.sm + 2) {
                Text(card.title)
                    .font(.kuroHeadline(weight: .light))
                    .foregroundColor(.kuroWhite)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    // VoiceOver affordance for the long-press synopsis gesture.
                    .accessibilityAction(named: Text("Read synopsis")) {
                        onSynopsis()
                    }

                if !card.captionLine.isEmpty {
                    Text(card.captionLine)
                        .font(.kuroCaption(weight: .light))
                        .tracking(0.6)
                        .foregroundColor(.kuroWhite85)
                        .lineLimit(1)
                }

                HStack {
                    passButton
                    Spacer(minLength: KuroDesignSpacing.xs)
                    knownButton
                    Spacer(minLength: KuroDesignSpacing.xs)
                    loveButton
                }
                .padding(.top, KuroDesignSpacing.xs)
            }
            .padding(.horizontal, KuroDesignSpacing.md)
            .padding(.top, KuroDesignSpacing.md)
            .padding(.bottom, KuroDesignSpacing.md + 2)
        }
        .reportDeckGlassHeight()
    }

    private var passButton: some View {
        Button { onCommit(.skip) } label: {
            Text("NOT FOR ME")
                .font(.kuroCaption(weight: .medium))
                .tracking(1.4)
                .foregroundColor(.kuroWhite90)
                .lineLimit(isAccessibilityTextSize ? 2 : 1)
                .minimumScaleFactor(isAccessibilityTextSize ? 0.8 : 1.0)
                .multilineTextAlignment(isAccessibilityTextSize ? .center : .leading)
                .padding(.horizontal, KuroDesignSpacing.sm + 6)
                .padding(.vertical, KuroDesignSpacing.sm + 4)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.kuroWhite55, lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pass")
    }

    private var knownButton: some View {
        Button { onCommit(.known) } label: {
            Text("I KNOW THIS")
                .font(.kuroCaption(weight: .light))
                .tracking(1.2)
                // kuroWhite80: 60% white on the onImage glass failed contrast
                // over bright cover art.
                .foregroundColor(.kuroWhite80)
                .lineLimit(isAccessibilityTextSize ? 2 : 1)
                .minimumScaleFactor(isAccessibilityTextSize ? 0.8 : 1.0)
                .multilineTextAlignment(isAccessibilityTextSize ? .center : .leading)
                .padding(.vertical, KuroDesignSpacing.sm + 4)
                .padding(.horizontal, KuroDesignSpacing.xs)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("I know this")
    }

    private var loveButton: some View {
        Button { onCommit(.love) } label: {
            Text("CALLS TO ME")
                .font(.kuroCaption(weight: .medium))
                .tracking(1.4)
                .foregroundColor(.kuroBlack)
                .lineLimit(isAccessibilityTextSize ? 2 : 1)
                .minimumScaleFactor(isAccessibilityTextSize ? 0.8 : 1.0)
                .multilineTextAlignment(isAccessibilityTextSize ? .center : .leading)
                .padding(.horizontal, KuroDesignSpacing.sm + 6)
                .padding(.vertical, KuroDesignSpacing.sm + 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.kuroWhite)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Calls to me")
    }

    // MARK: Flick (right = calls to me, left = pass, up = I know this)

    private func flickGesture(cardWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                // Drags starting in the outer screen-edge margin are leave-the-deck
                // swipes owned by the root pager — never turn them into judgments.
                guard !Self.isPagerEdgeStart(value.startLocation, cardWidth: cardWidth) else { return }
                dragOffset = value.translation
            }
            .onEnded { value in
                guard !Self.isPagerEdgeStart(value.startLocation, cardWidth: cardWidth) else { return }
                guard let action = flickAction(for: value) else {
                    withAnimation(KuroMotion.resolve(KuroAnimation.editorial)) {
                        dragOffset = .zero
                    }
                    return
                }
                // Keep the offset: the commit exit transition takes over from the
                // finger position; the next card deals with fresh state.
                onCommit(action)
            }
    }

    /// The card is full-bleed, so local x maps 1:1 to screen x and the pager's
    /// edge margin can be checked against the card width directly.
    private static func isPagerEdgeStart(_ start: CGPoint, cardWidth: CGFloat) -> Bool {
        let margin = KuroGesturePolicy.edgeMarginPt
        return start.x <= margin || start.x >= cardWidth - margin
    }

    /// Commit at ~90pt of travel, or earlier on a fast flick (predicted end).
    private func flickAction(for value: DragGesture.Value) -> TasteDeckAction? {
        let dx = value.translation.width
        let dy = value.translation.height
        let predictedDx = value.predictedEndTranslation.width
        let predictedDy = value.predictedEndTranslation.height
        if abs(dx) >= abs(dy) {
            if dx >= commitDistance || predictedDx >= commitPredictedDistance { return .love }
            if dx <= -commitDistance || predictedDx <= -commitPredictedDistance { return .skip }
        } else if dy <= -commitDistance || predictedDy <= -commitPredictedDistance {
            return .known
        }
        return nil
    }
}

// MARK: - Deck View

struct TasteDeckView: View {
    @Environment(SupabaseService.self) private var supabaseService
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var model = TasteDeckModel()
    @State private var showingSynopsis = false
    @State private var showLeaningsSheet = false
    @State private var exhaustedRevealStep = 0
    @State private var exhaustedRevealTask: Task<Void, Never>? = nil
    @State private var glassHeight: CGFloat = 0
    @State private var loadingStalled = false
    @State private var loadingWatchdogTask: Task<Void, Never>? = nil

    /// Bottom safe-area inset, plumbed from the root pager: the art continues to
    /// the screen's bottom edge while the glass floats above the home indicator.
    var bottomInset: CGFloat = 0

    /// Deck exhausted or dismissed — return to Discover.
    var onDone: () -> Void = {}

    var body: some View {
        ZStack {
            Color.kuroBackground.ignoresSafeArea()
            content
        }
        .task {
            startLoadingWatchdog()
            await model.loadInitial(using: supabaseService)
            prefetchUpcoming()
        }
        .onDisappear {
            model.cancelPendingWork()
            stopLoadingWatchdog()
            exhaustedRevealTask?.cancel()
            exhaustedRevealTask = nil
        }
        .onChange(of: networkMonitor.reconnectionGeneration) { _, _ in
            guard networkMonitor.isConnected, model.shouldRetryAfterReconnect else { return }
            Task {
                await model.retry(using: supabaseService)
                prefetchUpcoming()
            }
        }
        .onChange(of: model.phase) { _, newPhase in
            if newPhase == .loading {
                startLoadingWatchdog()
            } else {
                stopLoadingWatchdog()
            }
            if newPhase == .empty && model.totalJudged > 0 {
                runExhaustedReveal()
            }
        }
        .onChange(of: model.signalsNeedAttention) { _, needsAttention in
            guard needsAttention else { return }
            supabaseService.showTransientBanner("Signal didn't save — will retry")
        }
        .sheet(isPresented: $showLeaningsSheet) {
            TasteLeaningsSheet(latestSignalAt: model.lastSignalAt)
                .environment(supabaseService)
        }
    }

    @ViewBuilder
    private var content: some View {
        let exhaustedWithSignals = model.phase == .empty && model.totalJudged > 0
        if !networkMonitor.isConnected && model.current == nil && !exhaustedWithSignals {
            offlineState
        } else {
            switch model.phase {
            case .loading:
                loadingState
            case .empty:
                if model.totalJudged > 0 {
                    exhaustedState
                } else {
                    emptyState
                }
            case .dealing:
                dealingState
            }
        }
    }

    // MARK: Dealing

    private var dealingState: some View {
        ZStack(alignment: .topTrailing) {
            if let card = model.current {
                deckCard(card)
                    .id(card.stableKey)
                    .transition(reduceMotion ? .opacity : .deckCommit(model.removalDirection))
            } else {
                // Between batches.
                loadingState
            }

            // Static deck chrome (never flies with the card): the quiet judged
            // count glued to the persistent Your-leanings access.
            leaningsChrome
                .padding(.horizontal, KuroDesignSpacing.padding)
                .padding(.top, KuroDesignSpacing.sm + 2)
        }
    }

    /// "47 · LEANINGS" — kuroMicro on the same quiet scrim as the meta chips.
    private var leaningsChrome: some View {
        Button {
            showLeaningsSheet = true
        } label: {
            Text(model.totalJudged > 0 ? "\(model.totalJudged) · LEANINGS" : "LEANINGS")
                .font(.kuroMicro(weight: .medium))
                .tracking(1.4)
                .foregroundColor(.kuroWhite)
                .padding(.horizontal, KuroDesignSpacing.sm + 2)
                .padding(.vertical, KuroDesignSpacing.xs + 1)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.kuroBlack45)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.totalJudged > 0
            ? "Your leanings, \(model.totalJudged) titles judged"
            : "Your leanings")
    }

    private func deckCard(_ card: TasteDeckCard) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                TasteDeckCardSurface(
                    card: card,
                    bottomInset: bottomInset,
                    onCommit: commit,
                    onSynopsis: {
                        withAnimation(KuroMotion.resolve(KuroAnimation.fast)) {
                            showingSynopsis = true
                        }
                    }
                )
                .frame(width: geo.size.width, height: geo.size.height)

                if showingSynopsis {
                    synopsisOverlay(card, size: geo.size)
                        .transition(.opacity)
                }
            }
            .onPreferenceChange(KuroDeckGlassHeightKey.self) { glassHeight = $0 }
            .overlay(alignment: .bottom) {
                if model.undoCandidate != nil {
                    undoChip
                        .padding(.bottom, bottomInset + KuroDesignSpacing.md + glassHeight + KuroDesignSpacing.sm)
                        .transition(.opacity)
                }
            }
            .animation(KuroMotion.resolve(KuroAnimation.fast), value: model.undoCandidate != nil)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(card.title)
    }

    /// Long-press: the art dims and a glass sheet carries the synopsis.
    private func synopsisOverlay(_ card: TasteDeckCard, size: CGSize) -> some View {
        ZStack {
            Color.kuroBlack45

            KuroGlassCard(tone: .onImage) {
                VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
                    Text("SYNOPSIS")
                        .font(.kuroMicro(weight: .medium))
                        .tracking(2.4)
                        .foregroundColor(.kuroWhite60)

                    Text(card.title)
                        .font(.kuroHeadline(weight: .light))
                        .foregroundColor(.kuroWhite)

                    ScrollView(.vertical, showsIndicators: false) {
                        Text(card.cleanSynopsis ?? "No synopsis yet — let the cover speak for this one.")
                            .font(.kuroBody(weight: .light))
                            .foregroundColor(.kuroWhite85)
                            .lineSpacing(5)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Text("Tap anywhere to return")
                        .font(.kuroMicro(weight: .medium))
                        .tracking(1.6)
                        .foregroundColor(.kuroWhite60)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.horizontal, KuroDesignSpacing.lg)
                .padding(.vertical, KuroDesignSpacing.lg)
                .frame(maxHeight: size.height * 0.66)
            }
            .padding(.horizontal, KuroDesignSpacing.md)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(KuroMotion.resolve(KuroAnimation.fast)) {
                showingSynopsis = false
            }
        }
    }

    private var undoChip: some View {
        Button {
            withAnimation(KuroMotion.resolve(KuroAnimation.editorial)) {
                model.undoLast(using: supabaseService)
            }
        } label: {
            Text("Undo")
                .font(.kuroCaption(weight: .light))
                .foregroundColor(.kuroWhite)
                .padding(.horizontal, KuroDesignSpacing.md)
                .padding(.vertical, KuroDesignSpacing.sm)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.kuroBlack45)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Undo last decision")
    }

    // MARK: Exhausted (the only "summary" left — the catalog is genuinely done)

    private var exhaustedState: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: KuroDesignSpacing.sm + 2) {
                Text("THE DECK IS EMPTY")
                    .font(.kuroMicro(weight: .medium))
                    .tracking(2.4)
                    .foregroundColor(.kuroTextTertiary)

                Text("You've seen everything\nKuro has — for now.")
                    .font(.kuroDisplay(weight: .light))
                    .foregroundColor(.kuroBlack)
                    .multilineTextAlignment(.center)

                Text("\(model.totalJudged) titles judged")
                    .font(.kuroCaption(weight: .light))
                    .tracking(0.6)
                    .foregroundColor(.kuroTextSecondary)
            }
            .opacity(exhaustedRevealStep >= 1 ? 1 : 0)
            .offset(y: exhaustedRevealStep >= 1 ? 0 : 14)
            .padding(.horizontal, KuroDesignSpacing.xl)

            Spacer()

            VStack(spacing: KuroDesignSpacing.md) {
                Button {
                    showLeaningsSheet = true
                } label: {
                    Text("Your leanings")
                        .font(.kuroCaption(weight: .medium))
                        .tracking(1.6)
                        .foregroundColor(.kuroBlack80)
                        .padding(.horizontal, KuroDesignSpacing.lg)
                        .padding(.vertical, KuroDesignSpacing.sm + 4)
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.kuroBlack20, lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)

                Button(action: onDone) {
                    Text("BACK TO DISCOVER")
                        .font(.kuroCaption(weight: .medium))
                        .tracking(1.6)
                        .foregroundColor(.kuroWhite)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, KuroDesignSpacing.md)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.kuroBlack)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, KuroDesignSpacing.xl)
            }
            .opacity(exhaustedRevealStep >= 2 ? 1 : 0)
            .offset(y: exhaustedRevealStep >= 2 ? 0 : 10)
            .padding(.bottom, KuroDesignSpacing.xxl + bottomInset)
        }
    }

    private func runExhaustedReveal() {
        exhaustedRevealTask?.cancel()
        if reduceMotion {
            exhaustedRevealStep = 2
            return
        }
        exhaustedRevealStep = 0
        exhaustedRevealTask = Task { @MainActor in
            for step in 1...2 {
                try? await Task.sleep(nanoseconds: step == 1 ? 120_000_000 : 260_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(KuroAnimation.editorial) {
                    exhaustedRevealStep = step
                }
            }
        }
    }

    // MARK: Loading / Empty / Offline

    @ViewBuilder
    private var loadingState: some View {
        if model.initialLoadFailed || loadingStalled {
            loadingRetryState
        } else {
            Color.kuroSecondaryBackground
                .kuroShimmer()
                .overlay(
                    Text("DEALING")
                        .font(.kuroMicro(weight: .medium))
                        .tracking(2.4)
                        .foregroundColor(.kuroTextTertiary)
                )
        }
    }

    /// Quiet retry after ~8s of unresolved loading or an immediate batch
    /// failure — same voice as the offline state (serif line + RETRY capsule).
    private var loadingRetryState: some View {
        VStack(spacing: KuroDesignSpacing.lg) {
            Spacer()
            VStack(spacing: KuroDesignSpacing.sm + 2) {
                Text("The deck is taking longer than it should.")
                    .font(.kuroHeadline(weight: .light))
                    .foregroundColor(.kuroBlack80)
                    .multilineTextAlignment(.center)
                Text("The catalog didn't answer — try again.")
                    .font(.kuroCaption(weight: .light))
                    .foregroundColor(.kuroTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, KuroDesignSpacing.xl)
            Button {
                startLoadingWatchdog()
                Task {
                    await model.retry(using: supabaseService)
                    prefetchUpcoming()
                }
            } label: {
                Text("RETRY")
                    .font(.kuroCaption(weight: .medium))
                    .tracking(1.6)
                    .foregroundColor(.kuroWhite)
                    .padding(.horizontal, KuroDesignSpacing.lg)
                    .padding(.vertical, KuroDesignSpacing.sm + 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.kuroBlack)
                    )
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    /// After ~8s stuck in the loading phase, swap the shimmer for the retry
    /// state (an immediate batch failure flips there without waiting).
    private func startLoadingWatchdog() {
        loadingWatchdogTask?.cancel()
        loadingStalled = false
        loadingWatchdogTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            loadingStalled = true
        }
    }

    private func stopLoadingWatchdog() {
        loadingWatchdogTask?.cancel()
        loadingWatchdogTask = nil
        loadingStalled = false
    }

    private var emptyState: some View {
        VStack(spacing: KuroDesignSpacing.lg) {
            Spacer()
            Text("The deck is empty — Kuro will deal more as the catalog grows.")
                .font(.kuroHeadline(weight: .light))
                .foregroundColor(.kuroBlack80)
                .multilineTextAlignment(.center)
                .padding(.horizontal, KuroDesignSpacing.xl)
            Spacer()
            Button(action: onDone) {
                Text("Back to Discover")
                    .font(.kuroCaption(weight: .light))
                    .foregroundColor(.kuroTextSecondary)
                    .padding(.vertical, KuroDesignSpacing.xs)
            }
            .buttonStyle(.plain)
            .padding(.bottom, KuroDesignSpacing.xxl + bottomInset)
        }
    }

    private var offlineState: some View {
        VStack(spacing: KuroDesignSpacing.lg) {
            Spacer()
            VStack(spacing: KuroDesignSpacing.sm + 2) {
                Text("The deck is quiet without a connection.")
                    .font(.kuroHeadline(weight: .light))
                    .foregroundColor(.kuroBlack80)
                    .multilineTextAlignment(.center)
                Text("Kuro will deal again once you're back online.")
                    .font(.kuroCaption(weight: .light))
                    .foregroundColor(.kuroTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, KuroDesignSpacing.xl)
            Button {
                Task {
                    await model.retry(using: supabaseService)
                    prefetchUpcoming()
                }
            } label: {
                Text("RETRY")
                    .font(.kuroCaption(weight: .medium))
                    .tracking(1.6)
                    .foregroundColor(.kuroWhite)
                    .padding(.horizontal, KuroDesignSpacing.lg)
                    .padding(.vertical, KuroDesignSpacing.sm + 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.kuroBlack)
                    )
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    // MARK: Actions

    private func commit(_ action: TasteDeckAction) {
        // Light-to-medium haptic ladder: the stronger the signal, the deeper the tap.
        #if os(iOS)
        KuroAccessibility.impactHaptic(action == .love ? .medium : .light)
        #endif
        showingSynopsis = false
        withAnimation(KuroMotion.resolve(KuroAnimation.editorial)) {
            model.commit(action, using: supabaseService)
        }
        prefetchUpcoming()
    }

    private func prefetchUpcoming() {
        let urls = model.upcomingCards.compactMap(\.imageURL)
        guard !urls.isEmpty else { return }
        // Downsample prefetches like the card does (1100pt × screen scale, which
        // clamps to the pipeline's 1200px cap) so prefetched images land in the
        // memory cache at display size instead of full resolution.
        Task { await ImagePipeline.shared.prefetch(urls: urls, maxPixelSize: 1200) }
    }
}

// MARK: - "Your leanings" sheet (server profile is the only source)

struct TasteLeaningsSheet: View {
    @Environment(SupabaseService.self) private var supabaseService
    @Environment(\.dismiss) private var dismiss

    /// The deck's most recent signal. When newer than the profile's computed_at,
    /// a quiet note says Kuro hasn't folded the latest swipes in yet.
    var latestSignalAt: Date? = nil

    @State private var profile: TasteProfile? = nil
    @State private var realmMeta: [String: RealmMeta] = [:]
    @State private var realmBarsVisible = false
    @State private var didLoad = false

    /// `seededProfile` skips the network fetch — used by the #Preview below.
    init(latestSignalAt: Date? = nil, seededProfile: TasteProfile? = nil) {
        self.latestSignalAt = latestSignalAt
        _profile = State(initialValue: seededProfile)
        _didLoad = State(initialValue: seededProfile != nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: KuroDesignSpacing.lg) {
                    if !didLoad {
                        leaningsSkeleton
                    } else if let profile {
                        leaningsContent(profile)
                    } else {
                        noProfileContent
                    }
                }
                .padding(.horizontal, KuroDesignSpacing.padding)
                .padding(.top, KuroDesignSpacing.md)
                .padding(.bottom, KuroDesignSpacing.xxl)
            }
            .background(Color.kuroBackground)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("YOUR LEANINGS")
                        .font(.kuroNavigation(weight: .regular))
                        .tracking(1.5)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.kuroBody(weight: .light))
                }
            }
        }
        .task {
            guard !didLoad else { return }
            async let metaFetch = supabaseService.fetchRealmMeta()
            profile = await supabaseService.fetchMyTasteProfile()
            realmMeta = Dictionary(uniqueKeysWithValues: await metaFetch.map { ($0.realm, $0) })
            didLoad = true
        }
    }

    @ViewBuilder
    private func leaningsContent(_ profile: TasteProfile) -> some View {
        freshnessNote(profile)
        if !profile.realms.isEmpty {
            realmsSection(Array(profile.topRealms.prefix(6)))
        }
        if !profile.genres.isEmpty {
            weightSection(title: "GENRES", entries: Array(profile.topGenres.prefix(6)))
        }
        if !profile.tags.isEmpty {
            weightSection(title: "TAGS", entries: Array(profile.topTags.prefix(6)))
        }
        if !profile.avoidedTags.isEmpty {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                sectionEyebrow("YOU STEER AWAY FROM")
                Text(profile.avoidedTags.joined(separator: " · "))
                    .font(.kuroBody(weight: .light))
                    .foregroundColor(.kuroTextSecondary)
            }
        }
        VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
            Rectangle()
                .fill(Color.kuroBlack08)
                .frame(height: 0.5)
            Text("Kuro knows you: \(profile.confidenceWord)")
                .font(.kuroTitle(weight: .light))
                .italic()
                .foregroundColor(.kuroBlack80)
        }
        .padding(.top, KuroDesignSpacing.sm)
    }

    /// "UPDATED N MIN AGO" from the profile's computed_at, plus a quiet note when
    /// the deck has recorded signals the server hasn't folded in yet.
    @ViewBuilder
    private func freshnessNote(_ profile: TasteProfile) -> some View {
        let computedAt = profile.computedAt ?? profile.updatedAt
        let hasFreshSignals: Bool = {
            guard let latestSignalAt else { return false }
            guard let computedAt else { return true }
            return latestSignalAt > computedAt
        }()
        if computedAt != nil || hasFreshSignals {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
                if let computedAt {
                    Text("UPDATED \(Self.relativeAge(from: computedAt).uppercased())")
                        .font(.kuroMicro(weight: .medium))
                        .tracking(1.6)
                        .foregroundColor(.kuroTextTertiary)
                }
                if hasFreshSignals {
                    Text("Kuro is still thinking about your latest swipes.")
                        .font(.kuroCaption(weight: .light))
                        .italic()
                        .foregroundColor(.kuroTextSecondary)
                }
            }
        }
    }

    private static func relativeAge(from date: Date) -> String {
        let seconds = max(0, Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return minutes == 1 ? "1 min ago" : "\(minutes) min ago" }
        let hours = minutes / 60
        if hours < 24 { return hours == 1 ? "1 hr ago" : "\(hours) hr ago" }
        let days = hours / 24
        return days == 1 ? "1 day ago" : "\(days) days ago"
    }

    private var noProfileContent: some View {
        VStack(spacing: KuroDesignSpacing.sm + 2) {
            Spacer(minLength: KuroDesignSpacing.xxl)
            Text("Not enough signals yet.")
                .font(.kuroHeadline(weight: .light))
                .foregroundColor(.kuroBlack80)
                .multilineTextAlignment(.center)
            Text("A little time with the deck and Kuro begins to learn your taste.")
                .font(.kuroCaption(weight: .light))
                .foregroundColor(.kuroTextSecondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: KuroDesignSpacing.xxl)
        }
        .frame(maxWidth: .infinity)
    }

    private var leaningsSkeleton: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: KuroRadius.xs, style: .continuous)
                    .fill(Color.kuroSecondaryBackground)
                    .frame(height: 28)
                    .kuroShimmer()
            }
        }
        .padding(.top, KuroDesignSpacing.sm)
    }

    private func sectionEyebrow(_ title: String) -> some View {
        Text(title)
            .font(.kuroMicro(weight: .medium))
            .tracking(2.2)
            .foregroundColor(.kuroTextTertiary)
    }

    /// Realms lead the sheet: the Realm Graph's top mood-worlds, each a serif
    /// name, a quiet family caption, and a monochrome weight bar — no raw numbers.
    private func realmsSection(_ realms: [TasteRealm]) -> some View {
        let maxWeight = realms.map(\.weight).max() ?? 1
        return VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            sectionEyebrow("YOUR REALMS")
            VStack(spacing: 0) {
                ForEach(Array(realms.enumerated()), id: \.offset) { index, realm in
                    VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(realmDisplayName(realm))
                                .font(.kuroTitle(weight: .regular))
                                .foregroundColor(.kuroBlack80)
                            Spacer(minLength: KuroDesignSpacing.md)
                            Text(realm.humanizedFamily)
                                .font(.kuroCaption(weight: .light))
                                .foregroundColor(.kuroTextTertiary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule(style: .continuous)
                                    .fill(Color.kuroBlack06)
                                Capsule(style: .continuous)
                                    .fill(Color.kuroBlack20)
                                    .frame(width: max(2, geo.size.width * (realmBarsVisible ? realm.weight / max(maxWeight, 0.0001) : 0)))
                            }
                        }
                        .frame(height: 2)
                    }
                    .padding(.vertical, KuroDesignSpacing.sm + 2)
                    if index < realms.count - 1 {
                        Rectangle()
                            .fill(Color.kuroBlack08)
                            .frame(height: 0.5)
                    }
                }
            }
        }
        .onAppear {
            withAnimation(KuroMotion.resolve(KuroAnimation.editorial)) {
                realmBarsVisible = true
            }
        }
    }

    /// realm_meta display copy when loaded, humanized stable key otherwise.
    private func realmDisplayName(_ realm: TasteRealm) -> String {
        realmMeta[realm.realm]?.displayName ?? realm.humanizedRealm
    }

    private func weightSection(title: String, entries: [(name: String, weight: Double)]) -> some View {
        let maxWeight = entries.map(\.weight).max() ?? 1
        return VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            sectionEyebrow(title)
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    HStack(spacing: KuroDesignSpacing.md) {
                        Text(entry.name)
                            .font(.kuroBody(weight: .light))
                            .foregroundColor(.kuroBlack80)
                        Spacer()
                        ZStack(alignment: .leading) {
                            Capsule(style: .continuous)
                                .fill(Color.kuroBlack06)
                            Capsule(style: .continuous)
                                .fill(Color.kuroBlack45)
                                .frame(width: max(2, 96 * (entry.weight / max(maxWeight, 0.0001))))
                        }
                        .frame(width: 96, height: 2)
                    }
                    .padding(.vertical, KuroDesignSpacing.sm + 2)
                    if index < entries.count - 1 {
                        Rectangle()
                            .fill(Color.kuroBlack08)
                            .frame(height: 0.5)
                    }
                }
            }
        }
    }
}


// MARK: - Previews

#Preview("Leanings — Realms") {
    TasteLeaningsSheet(
        latestSignalAt: Date(),
        seededProfile: TasteProfile(
            vector: TasteProfileVector(
                genres: ["Drama": 0.82, "Sci-Fi": 0.41, "Romance": 0.3],
                tags: ["Found Family": 0.3, "Slow Burn": 0.22],
                avoidedTags: ["Ecchi"],
                realms: [
                    TasteRealm(realm: "quiet-melancholy", family: "emotional-core", weight: 0.42),
                    TasteRealm(realm: "auteur-cinema", family: "craft-art", weight: 0.35),
                    TasteRealm(realm: "coming-of-age", family: "emotional-core", weight: 0.28),
                    TasteRealm(realm: "time-parallel-worlds", family: "speculative-worlds", weight: 0.21),
                    TasteRealm(realm: "slice-of-life-iyashikei", family: "emotional-core", weight: 0.14),
                    TasteRealm(realm: "psychological-thriller", family: "mind-thrill", weight: 0.09)
                ],
                confidence: 0.2,
                eventCount: 34,
                computedAt: Date().addingTimeInterval(-12 * 60)
            ),
            updatedAt: nil
        )
    )
    .environment(SupabaseService())
}

#Preview("Leanings — Empty") {
    TasteLeaningsSheet()
        .environment(SupabaseService())
}
