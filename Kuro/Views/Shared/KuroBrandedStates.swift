import SwiftUI

// MARK: - Branded states (prototype-fidelity Task 3; spec §5.4)
// One family for every moment a surface is not showing its content, built from the prototype's
// materials (it only shows confirm / count / restore; these states are an extrapolation):
//   KuroLoadingView   .inline: the travelling ink scrub line. .page: the KURO wordmark settling
//                     letter by letter (60 ms stagger) above the scrub line. Launch / first loads.
//                     A caller's `label` ("Searching the catalogue.") shows as a muted caption.
//   KuroBusyMark      a short scrub line for a control that is working (button labels, rows).
//   KuroSkeleton      quiet blocks shaped like the real component, with the scrub line under them.
//   KuroErrorView     one ink stroke draws the mountain ridge once (1.2 s), a serif headline that
//                     names what happened, one plain sentence, an ink-rule "Try again →".
//   KuroOfflineView   the same ridge held still. With content: a slim band ("You're offline. Showing
//                     what you saw last."). Without: the page state with Try again.
//   KuroEmptyView     the prototype's new-account "＋" mark, a headline, a line, and actions.
// `KuroBrandedState.resolve` decides which one a surface shows. Motion: the scrub line loops only
// while loading and visible; everything else plays once. Reduce Motion and Low Power show the
// composed final frame (the ridge drawn, the letters settled, the scrub line resting).
// This file is the only place under Kuro/ allowed to use `ProgressView(`
// (scripts/quality-gates/check_branded_states.sh).

/// What a surface shows instead of (or over) its content. Pure.
nonisolated enum KuroBrandedState: Equatable, Sendable {
    case loading
    case empty
    /// No connection. `hasContent`: earlier content is still on screen (show the offline band).
    case offline(hasContent: Bool)
    /// The read failed. `hasContent`: earlier content is still on screen.
    case failed(hasContent: Bool)

    /// The one precedence rule, in order:
    /// 1. content, online, no failure → `nil` (show the content, no overlay), loading or not;
    /// 2. offline → `.offline(hasContent:)` (offline is named before a failure, which it usually caused);
    /// 3. failed → `.failed(hasContent:)`;
    /// 4. loading → `.loading`;
    /// 5. otherwise → `.empty`.
    /// A cold offline launch therefore shows the offline state with Try again, never an endless loader.
    static func resolve(isLoading: Bool, hasContent: Bool, isOffline: Bool, failed: Bool) -> KuroBrandedState? {
        if hasContent && !isOffline && !failed { return nil }
        if isOffline { return .offline(hasContent: hasContent) }
        if failed { return .failed(hasContent: hasContent) }
        if isLoading { return .loading }
        return .empty
    }
}

/// EN/DE copy for the branded states. Pure, so tests can pin it. Views pass `KuroLocale.isGerman`.
nonisolated enum KuroBrandedCopy {
    static func retryTitle(german: Bool) -> String {
        german ? "Erneut versuchen" : "Try again"
    }

    static func loadingLabel(german: Bool) -> String {
        german ? "Wird geladen" : "Loading"
    }

    /// The default error headline when the caller has nothing more specific.
    static func errorHeadline(german: Bool) -> String {
        german ? "Konnte nicht geladen werden." : "Couldn't load this."
    }

    static func errorMessage(german: Bool) -> String {
        german ? "Versuch es gleich noch einmal." : "Try again in a moment."
    }

    static func offlineHeadline(german: Bool) -> String {
        german ? "Du bist offline." : "You're offline."
    }

    /// The band over earlier content, or the line under the offline headline without content.
    static func offlineLine(hasContent: Bool, german: Bool) -> String {
        switch (hasContent, german) {
        case (true, false): return "You're offline. Showing what you saw last."
        case (true, true): return "Du bist offline. Du siehst den letzten Stand."
        case (false, false): return "Connect to load this."
        case (false, true): return "Verbinde dich, um das zu laden."
        }
    }

    static func emptyHeadline(german: Bool) -> String {
        german ? "Hier ist noch nichts." : "Nothing here yet."
    }
}

// MARK: - The mountain ridge

/// The `KuroZenMountains` ridge, traced once from the asset (the centre third of the 3:1 loop,
/// median-filtered so the pines do not spike the line) into normalized points: x 0…1 left to right,
/// y 0 (highest peak) … 1 (lowest). The ends are brought down to the foot of the range.
nonisolated enum KuroRidge {
    private static let samples: [(x: CGFloat, y: CGFloat)] = [
        (0.0, 0.72), (0.0179, 0.4884), (0.0357, 0.3876), (0.0536, 0.3566), (0.0714, 0.3566),
        (0.0893, 0.3721), (0.1071, 0.3721), (0.125, 0.4884), (0.1429, 0.3798), (0.1607, 0.3488),
        (0.1786, 0.3643), (0.1964, 0.4419), (0.2143, 0.4806), (0.2321, 0.5271), (0.25, 0.5736),
        (0.2679, 0.5814), (0.2857, 0.3953), (0.3036, 0.3566), (0.3214, 0.2868), (0.3393, 0.2171),
        (0.3571, 0.2171), (0.375, 0.1395), (0.3929, 0.1008), (0.4107, 0.0078), (0.4286, 0.0),
        (0.4464, 0.0698), (0.4643, 0.1395), (0.4821, 0.1938), (0.5, 0.186), (0.5179, 0.1938),
        (0.5357, 0.1395), (0.5536, 0.0698), (0.5714, 0.0), (0.5893, 0.0078), (0.6071, 0.1008),
        (0.625, 0.1395), (0.6429, 0.2171), (0.6607, 0.2171), (0.6786, 0.2868), (0.6964, 0.3566),
        (0.7143, 0.3953), (0.7321, 0.5814), (0.75, 0.5736), (0.7679, 0.5271), (0.7857, 0.4806),
        (0.8036, 0.4419), (0.8214, 0.3643), (0.8393, 0.3488), (0.8571, 0.3798), (0.875, 0.4884),
        (0.8929, 0.3721), (0.9107, 0.3721), (0.9286, 0.3566), (0.9464, 0.3566), (0.9643, 0.3876),
        (0.9821, 0.4884), (1.0, 0.72),
    ]

    static let points: [CGPoint] = samples.map { CGPoint(x: $0.x, y: $0.y) }

    /// The ridge scaled into `rect`, smoothed through the midpoints between samples.
    static func path(in rect: CGRect) -> Path {
        var path = Path()
        let scaled = points.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) }
        guard let first = scaled.first else { return path }
        path.move(to: first)
        for index in 1..<scaled.count {
            let previous = scaled[index - 1]
            let current = scaled[index]
            let mid = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
            path.addQuadCurve(to: mid, control: previous)
        }
        if let last = scaled.last { path.addLine(to: last) }
        return path
    }
}

/// The ridge as a `Shape`, so `trim(from:to:)` can draw it.
struct KuroRidgeShape: Shape {
    func path(in rect: CGRect) -> Path {
        KuroRidge.path(in: rect)
    }
}

/// One ink stroke along the ridge. `draws`: draw it once on appear (1.2 s); otherwise held still.
struct KuroRidgeStroke: View {
    var draws: Bool = true
    var lineWidth: CGFloat = 1.4

    @State private var progress: CGFloat = 0

    var body: some View {
        KuroMotionAllowance { plays in
            KuroRidgeShape()
                .trim(from: 0, to: (draws && plays) ? progress : 1)
                .stroke(Color.kuroInk, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                .onAppear {
                    guard progress < 1 else { return }
                    if draws && plays {
                        withAnimation(KuroMotion.ease(1.2)) { progress = 1 }
                    } else {
                        // Appeared still (Reduce Motion / Low Power): the ridge counts as drawn, so it
                        // stays whole when motion is allowed again (Low Power turns off by itself at 80 %).
                        progress = 1
                    }
                }
                .onChange(of: plays) { _, _ in
                    // Motion turning on or off after the view appeared never replays or hides the stroke.
                    if progress < 1 { progress = 1 }
                }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - The scrub line

/// The prototype's progress underline as a loading cue: a short ink trace that travels the hairline
/// once every 1.6 s while it is visible, the scene is active and motion may play. Otherwise it rests
/// at the start of the line (the composed final frame). "Visible" is both mounted (`onAppear`) and
/// inside its scroll view's bounds (`onScrollVisibilityChange`), so stacked skeletons in a non-lazy
/// stack stop when scrolled offscreen.
struct KuroScrubLine: View {
    /// Fraction of the line the trace covers.
    var traceFraction: CGFloat = 0.28
    /// The travelling trace (white on an ink button).
    var tint: Color = .kuroInk
    /// The hairline it travels on.
    var track: Color = .kuroLine

    init(traceFraction: CGFloat = 0.28, tint: Color = .kuroInk, track: Color = .kuroLine) {
        self.traceFraction = traceFraction
        self.tint = tint
        self.track = track
    }

    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var inScrollBounds = true

    private static let period: Double = 1.6

    var body: some View {
        KuroMotionAllowance { plays in
            GeometryReader { geo in
                let width = geo.size.width
                let trace = max(8, width * traceFraction)
                ZStack(alignment: .leading) {
                    Rectangle().fill(track)
                    if plays && visible && inScrollBounds && scenePhase == .active {
                        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                            Rectangle()
                                .fill(tint)
                                .frame(width: trace)
                                .offset(x: offset(width: width, trace: trace, date: context.date))
                        }
                    } else {
                        Rectangle().fill(tint).frame(width: trace)
                    }
                }
                .frame(height: 1)
                .frame(maxHeight: .infinity, alignment: .center)
                .clipped()
            }
        }
        .frame(height: 2)
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .onScrollVisibilityChange(threshold: 0.01) { inScrollBounds = $0 }
        .accessibilityHidden(true)
    }

    /// Eased travel from the left edge to the right edge over one period.
    private func offset(width: CGFloat, trace: CGFloat, date: Date) -> CGFloat {
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.period) / Self.period
        // Smoothstep: slow at both ends, like the prototype's eased trace.
        let eased = phase * phase * (3 - 2 * phase)
        return (width - trace) * CGFloat(eased)
    }
}

// MARK: - Loading

/// The KURO wordmark (prototype header: SF 18 w800, tracking 3) with its letters settling in
/// sequence (60 ms stagger, settle timing) once on appear.
struct KuroWordmarkSettle: View {
    private static let letters = Array("KURO").map(String.init)
    @State private var settled = false

    var body: some View {
        KuroMotionAllowance { plays in
            HStack(spacing: 3) {
                ForEach(Array(Self.letters.enumerated()), id: \.offset) { index, letter in
                    Text(letter)
                        .font(.kuroCustom(18, weight: .heavy, relativeTo: .headline, maxSize: 28))
                        .foregroundStyle(Color.kuroInk)
                        .opacity(settled || !plays ? 1 : 0)
                        .offset(y: settled || !plays ? 0 : 5)
                        .animation(plays ? KuroMotion.settle.delay(Double(index) * 0.06) : nil, value: settled)
                }
            }
            .onAppear { settled = true }
        }
        .accessibilityHidden(true)
    }
}

/// A control that is working (a button's label, a row's trailing slot): a short scrub line in place
/// of a system spinner. Decorative; the control carries the spoken state ("In progress").
struct KuroBusyMark: View {
    var width: CGFloat = 32
    var tint: Color = .kuroInk
    var track: Color = .kuroLine

    init(width: CGFloat = 32, tint: Color = .kuroInk, track: Color = .kuroLine) {
        self.width = width
        self.tint = tint
        self.track = track
    }

    var body: some View {
        KuroScrubLine(traceFraction: 0.4, tint: tint, track: track)
            .frame(width: width)
            .frame(minHeight: 20)
    }
}

/// A loading state. `.inline` is the scrub line in its section; `.page` adds the settling wordmark,
/// centred in the available space (launch, bootstrap, first page loads). A `label` names the work in
/// progress: it is spoken and shown as a small muted caption under the line.
struct KuroLoadingView: View {
    enum Scope {
        case inline
        case page
    }

    var scope: Scope = .page
    /// Spoken label; defaults to "Loading".
    var label: String? = nil

    init(scope: Scope = .page, label: String? = nil) {
        self.scope = scope
        self.label = label
    }

    /// The visible caption for `label`: the caller's words, or nil (a bare line) when none are given.
    nonisolated static func caption(for label: String?) -> String? {
        guard let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    var body: some View {
        let caption = Self.caption(for: label)
        Group {
            switch scope {
            case .inline:
                VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                    KuroScrubLine().frame(maxWidth: 120)
                    if let caption { captionText(caption, alignment: .leading) }
                }
                .padding(.vertical, KuroDesignSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
            case .page:
                VStack(spacing: KuroDesignSpacing.md) {
                    KuroWordmarkSettle()
                    KuroScrubLine().frame(width: 64)
                    if let caption { captionText(caption, alignment: .center) }
                }
                .padding(.horizontal, KuroDesignSpacing.padding)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? KuroBrandedCopy.loadingLabel(german: KuroLocale.isGerman))
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func captionText(_ text: String, alignment: TextAlignment) -> some View {
        Text(text)
            .font(.kuroMeta())
            .foregroundStyle(Color.kuroMuted)
            .multilineTextAlignment(alignment)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Skeletons

/// Quiet blocks in the shape of the real component, in translucent ink (visible on every canvas), with the scrub line
/// travelling under them. Widths come from the container; nothing is hardcoded to a device.
struct KuroSkeleton: View {
    enum Kind {
        /// Anime Home scene card: artwork window over the material foot.
        case sceneCard
        /// Manga Home leaf: equal cover, title lines, the "Ch. N" + key row.
        case coverLeaf
        /// Calendar day: date chip, day name and count.
        case calendarDay
        /// A detail page section: heading and three lines.
        case detailSection
        /// A list row: thumbnail and two lines.
        case row
    }

    let kind: Kind

    init(kind: Kind) {
        self.kind = kind
    }

    /// The block is translucent ink, so it stays visible on every canvas it lands on (Home
    /// `#fffef8`, manga Home `#f5f5f3`, detail paper `#f5f5f4`); an opaque light grey such as
    /// `kuroCanvasQuiet` (`#f6f6f6`) vanishes on the two grey canvases. Pinned in `KuroTests`.
    nonisolated static let blockInkOpacity: Double = 0.08
    /// The scene card's material foot: a second, deeper tone over the same canvas.
    nonisolated static let deepBlockInkOpacity: Double = 0.13

    /// The block's colour composited over `canvas` (pure; the visibility test reads it).
    nonisolated static func block(on canvas: KuroRGB) -> KuroRGB {
        KuroRGB.mix(canvas, KuroRGB(0x25 / 255, 0x26 / 255, 0x25 / 255), blockInkOpacity)
    }

    private var block: Color { Color.kuroInk.opacity(Self.blockInkOpacity) }
    private var deepBlock: Color { Color.kuroInk.opacity(Self.deepBlockInkOpacity) }

    var body: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            shape
            KuroScrubLine().frame(maxWidth: 96)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(KuroBrandedCopy.loadingLabel(german: KuroLocale.isGerman))
    }

    @ViewBuilder
    private var shape: some View {
        switch kind {
        case .sceneCard:
            VStack(spacing: 0) {
                Rectangle().fill(block).aspectRatio(350 / 107.7, contentMode: .fit)
                HStack(spacing: KuroDesignSpacing.sm) {
                    line(width: nil, height: 12, fill: Color.white.opacity(0.18))
                    Spacer(minLength: 64)
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 34, height: 34)
                }
                .padding(.leading, 14)
                .padding(.trailing, 10)
                .frame(height: 58)
                .background(deepBlock)
                Rectangle().fill(deepBlock.opacity(0.8)).frame(height: 41)
            }
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        case .coverLeaf:
            VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(block).aspectRatio(2 / 3, contentMode: .fit)
                line(width: nil, height: 10)
                HStack {
                    line(width: 36, height: 10)
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(deepBlock).frame(width: 38, height: 38)
                }
            }
        case .calendarDay:
            HStack(spacing: KuroDesignSpacing.md) {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(block).frame(width: 40, height: 44)
                VStack(alignment: .leading, spacing: 6) {
                    line(width: 72, height: 12)
                    line(width: 56, height: 9)
                }
                Spacer(minLength: 0)
            }
        case .detailSection:
            VStack(alignment: .leading, spacing: 10) {
                line(width: 140, height: 16)
                line(width: nil, height: 10)
                line(width: nil, height: 10)
                HStack { line(width: nil, height: 10); Spacer(minLength: 80) }
            }
        case .row:
            HStack(spacing: KuroDesignSpacing.md) {
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(block).frame(width: 44, height: 66)
                VStack(alignment: .leading, spacing: 8) {
                    HStack { line(width: nil, height: 12); Spacer(minLength: 48) }
                    line(width: 64, height: 9)
                }
            }
        }
    }

    /// A text-line block; `width` nil fills the row.
    private func line(width: CGFloat?, height: CGFloat, fill: Color? = nil) -> some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(fill ?? block)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

// MARK: - Error

/// A failed read. The ridge draws once, then a serif headline names what happened ("Couldn't load
/// your clubs."), one plain sentence, and an ink-rule "Try again →" when the caller can retry.
struct KuroErrorView: View {
    let headline: String
    var message: String?
    var retryTitle: String?
    var retry: (() -> Void)?

    /// `headline` nil: "Couldn't load this."; `message` nil: the plain "Try again in a moment."
    init(headline: String? = nil, message: String? = nil, retryTitle: String? = nil, retry: (() -> Void)? = nil) {
        self.headline = headline ?? KuroBrandedCopy.errorHeadline(german: KuroLocale.isGerman)
        self.message = message ?? KuroBrandedCopy.errorMessage(german: KuroLocale.isGerman)
        self.retryTitle = retryTitle
        self.retry = retry
    }

    var body: some View {
        KuroStateLayout(stroke: KuroRidgeStroke(draws: true), headline: headline, message: message) {
            if let retry {
                KuroInkButton(retryTitle ?? KuroBrandedCopy.retryTitle(german: KuroLocale.isGerman),
                              role: .secondary, haptic: false, action: retry)
                    .frame(maxWidth: 280)
            }
        }
    }
}

// MARK: - Offline

/// No connection. With earlier content on screen: a slim band over it. Without: the page state
/// with the ridge held still and Try again.
struct KuroOfflineView: View {
    let hasContent: Bool
    var retry: (() -> Void)?

    init(hasContent: Bool, retry: (() -> Void)? = nil) {
        self.hasContent = hasContent
        self.retry = retry
    }

    private var german: Bool { KuroLocale.isGerman }

    var body: some View {
        if hasContent {
            band
        } else {
            KuroStateLayout(stroke: KuroRidgeStroke(draws: false), headline: KuroBrandedCopy.offlineHeadline(german: german),
                            message: KuroBrandedCopy.offlineLine(hasContent: false, german: german)) {
                if let retry {
                    KuroInkButton(KuroBrandedCopy.retryTitle(german: german), role: .secondary, haptic: false, action: retry)
                        .frame(maxWidth: 280)
                }
            }
        }
    }

    private var band: some View {
        HStack(spacing: KuroDesignSpacing.md) {
            KuroRidgeStroke(draws: false, lineWidth: 1)
                .frame(width: 36, height: 10)
            Text(KuroBrandedCopy.offlineLine(hasContent: true, german: german))
                .font(.kuroMeta())
                .foregroundStyle(Color.kuroInk)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let retry {
                Button(KuroBrandedCopy.retryTitle(german: german), action: retry)
                    .font(.kuroMeta(weight: .medium))
                    .foregroundStyle(Color.kuroInk)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .buttonStyle(KuroPressStyle())
            }
        }
        .padding(.horizontal, KuroDesignSpacing.md)
        .frame(minHeight: 44)
        .background(Color.kuroPaper)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.kuroLine).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Empty

/// The prototype's new-account invitation: a light "＋" (SF 42 w200), a bold sans headline
/// (24 w700, −0.8), one muted line, then the caller's actions (`KuroOutlineButton` matches the
/// prototype's "Explore Taste").
struct KuroEmptyView<Actions: View>: View {
    let headline: String
    var message: String?
    let actions: Actions

    init(headline: String? = nil, message: String? = nil, @ViewBuilder actions: () -> Actions) {
        self.headline = headline ?? KuroBrandedCopy.emptyHeadline(german: KuroLocale.isGerman)
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("＋")
                .font(.kuroCustom(42, weight: .ultraLight, relativeTo: .largeTitle, maxSize: 64))
                .foregroundStyle(Color.kuroMuted)
                .padding(.bottom, 26)
                .accessibilityHidden(true)
            Text(headline)
                .font(.kuroCustom(24, weight: .bold, relativeTo: .title2, maxSize: 44))
                .tracking(-0.8)
                .foregroundStyle(Color.kuroInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let message {
                Text(message)
                    .font(.kuroMeta())
                    .foregroundStyle(Color.kuroMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 260)
                    .padding(.top, 14)
            }
            VStack(spacing: KuroDesignSpacing.sm) { actions }
                .padding(.top, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 25)
        .padding(.top, 50)
        .padding(.bottom, 70)
        .accessibilityElement(children: .contain)
    }
}

extension KuroEmptyView where Actions == EmptyView {
    init(headline: String? = nil, message: String? = nil) {
        self.init(headline: headline, message: message) { EmptyView() }
    }
}

/// The prototype's quiet outlined button ("Explore Taste"): 44 pt tall, 1 pt `#bfc4bd` border,
/// radius 12, ink SF 14.
struct KuroOutlineButton: View {
    /// The prototype's `.empty-home button` border (`#bfc4bd`); no shared token carries it.
    private static let outline = Color(hex: "BFC4BD")

    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.kuroCustom(14, relativeTo: .subheadline, maxSize: 26))
                .foregroundStyle(Color.kuroInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .frame(minHeight: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Self.outline, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(KuroPressStyle())
    }
}

// MARK: - Shared layout

/// Stroke, serif headline, message and actions, centred in the available space. Shared by the error
/// and offline states and by the `KuroStateView` wrapper.
struct KuroStateLayout<Stroke: View, Actions: View>: View {
    let stroke: Stroke
    let headline: String
    let message: String?
    let actions: Actions

    init(stroke: Stroke, headline: String, message: String?, @ViewBuilder actions: () -> Actions) {
        self.stroke = stroke
        self.headline = headline
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: KuroDesignSpacing.md) {
            stroke.frame(width: 148, height: 36)
            // The prototype's empty-block headline (SF 24 w700, tracking −0.8), as `KuroEmptyView`.
            Text(headline)
                .font(.kuroCustom(24, weight: .bold, relativeTo: .title2, maxSize: 44))
                .tracking(-0.8)
                .foregroundStyle(Color.kuroInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let message {
                Text(message)
                    .font(.kuroMeta())
                    .foregroundStyle(Color.kuroMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions.padding(.top, KuroDesignSpacing.sm)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, KuroDesignSpacing.padding)
        .padding(.vertical, KuroDesignSpacing.xl)
        .accessibilityElement(children: .contain)
    }
}
