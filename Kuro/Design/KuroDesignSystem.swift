import SwiftUI
import Foundation

// MARK: - KURO DESIGN SYSTEM - iOS 26 Mobile-First
// "Elevated Minimalism" / "Editorial Minimalism" Design System
// Optimized for iOS 26 with modern mobile patterns

// MARK: - Color System
extension Color {
    // Primary Colors - Black & White with Opacity Variations
    static let kuroBlack = Color.black
    static let kuroWhite = Color.white

    // Opacity Variations (8px base unit system)
    static let kuroBlack80 = Color.black.opacity(0.8)   // Primary text
    static let kuroBlack85 = Color.black.opacity(0.85)  // High-emphasis text
    static let kuroBlack75 = Color.black.opacity(0.75)  // Strong overlays
    static let kuroBlack70 = Color.black.opacity(0.7)   // Emphasis text / badges
    static let kuroBlack65 = Color.black.opacity(0.65)  // Deep gradients / overlays
    static let kuroBlack60 = Color.black.opacity(0.6)   // Secondary text
    static let kuroBlack45 = Color.black.opacity(0.45)  // Metadata / hints
    static let kuroBlack40 = Color.black.opacity(0.4)   // Disabled text
    static let kuroBlack35 = Color.black.opacity(0.35)  // Iconography / subdued affordances
    static let kuroBlack30 = Color.black.opacity(0.3)   // Tertiary text (legacy — prefer kuroBlack45)
    static let kuroBlack25 = Color.black.opacity(0.25)  // Soft gradient stops
    static let kuroBlack20 = Color.black.opacity(0.2)   // Dividers / borders
    static let kuroBlack15 = Color.black.opacity(0.15)  // Empty-state accents
    static let kuroBlack14 = Color.black.opacity(0.14)  // Floating surface shadow
    static let kuroBlack12 = Color.black.opacity(0.12)  // Hairline strokes
    static let kuroBlack10 = Color.black.opacity(0.10)  // Capsule borders / overlays
    static let kuroBlack08 = Color.black.opacity(0.08)  // Subtle backgrounds
    static let kuroBlack06 = Color.black.opacity(0.06)  // Surface chips / pills
    static let kuroBlack05 = Color.black.opacity(0.05)  // Loading placeholders
    static let kuroBlack04 = Color.black.opacity(0.04)  // Quiet surfaces
    static let kuroBlack02 = Color.black.opacity(0.02)  // Glass overlays

    static let kuroWhite92 = Color.white.opacity(0.92)  // Light capsule overlays
    static let kuroWhite90 = Color.white.opacity(0.9)   // Strong white text
    static let kuroWhite85 = Color.white.opacity(0.85)  // Secondary white text
    static let kuroWhite80 = Color.white.opacity(0.8)   // White strokes / captions
    static let kuroWhite60 = Color.white.opacity(0.6)   // Tertiary white text
    static let kuroWhite55 = Color.white.opacity(0.55)  // Sharp highlight shadow
    static let kuroWhite20 = Color.white.opacity(0.2)   // Soft hero pills
    static let kuroWhite15 = Color.white.opacity(0.15)  // Glass overlays
    static let kuroWhite04 = Color.white.opacity(0.04)  // Grain layer
    static let kuroError = Color.red.opacity(0.85)      // Inline error text / destructive feedback

    // WCAG AA contrast-safe text tokens (black on white)
    // 0.55 => ~4.7:1 ratio — passes AA for normal text
    static let kuroTextSecondary = Color.black.opacity(0.55) // Body-level secondary text
    /// Legacy name for captions, hints and metadata. It now resolves to `kuroInkQuiet` (#6B6B6B,
    /// 5.3:1): the former black at 45% (3.4:1) failed AA for normal text (rulebook §3.1).
    static let kuroTextTertiary = kuroInkQuiet

    // Media Type Accents (Monochrome)
    static let kuroAnime = Color.black.opacity(0.55)    // Anime badge
    static let kuroManga = Color.black.opacity(0.45)    // Manga badge

    // MARK: - Page and surface roles (light mode only)
    // The app is light mode only (`KuroApp`). The legacy names resolve to the frozen neutral roles
    // below, so no page or surface picks up the system greys' blue cast (rulebook §3).
    /// Legacy page name. Same as `kuroCanvasPage`.
    static let kuroBackground = kuroCanvasPage
    /// Legacy secondary surface name. Same as `kuroCanvasQuiet` (was the system's blue-grey #F2F2F7).
    static let kuroSecondaryBackground = kuroCanvasQuiet
    /// Legacy tertiary surface name. Same as `kuroCanvasPage`.
    static let kuroTertiaryBackground = kuroCanvasPage

    // MARK: - Foreground roles (legacy names, light mode only)
    // These were the system label colors, prepared for a dark mode that is not active. They now
    // resolve to the neutral ink roles; a future dark mode defines its own roles.
    /// Primary foreground. Same as `kuroInk`.
    static let kuroForeground = kuroInk
    /// Secondary foreground. Same as `kuroInkSecondary`.
    static let kuroForegroundSecondary = kuroInkSecondary
    /// Tertiary foreground. Same as `kuroInkQuiet` (the system tertiary label failed AA).
    static let kuroForegroundTertiary = kuroInkQuiet
    /// Separator. Same as `kuroHairline`.
    static let kuroSeparator = kuroHairline
    /// Grouped background. Same as `kuroCanvasQuiet`.
    static let kuroGroupedBackground = kuroCanvasQuiet
    /// Card surface. Same as `kuroCanvasPage`.
    static let kuroSurface = kuroCanvasPage

    // MARK: - Neutral palette (frozen roles, rulebook §3.1)
    // Use only these roles for new work. Artwork keeps its own color; statuses never carry color.
    /// Primary page for every screen. Clean white, no yellow or green cast.
    static let kuroCanvasPage = Color(hex: "FFFFFF")
    /// Secondary groups and contained controls. Never a whole-page background.
    static let kuroCanvasQuiet = Color(hex: "F6F6F6")
    /// Headlines, title names, primary actions and progress numerals. The prototype's `--ink`
    /// #252625 (15.2:1 on white; was #181818 before the prototype-fidelity pass).
    static let kuroInk = Color(hex: "252625")
    /// Explanatory text and ordinary metadata (6.7:1 on white).
    static let kuroInkSecondary = Color(hex: "5C5C5C")
    /// Captions and kickers (5.3:1 on white). The lightest ink allowed for text that carries meaning.
    static let kuroInkQuiet = Color(hex: "6B6B6B")
    /// Separators. Black at 10%, inside the 8–12% hairline range.
    static let kuroHairline = Color.black.opacity(0.10)
    /// Neutral stand-in when a title has no artwork, or the artwork fails to decode.
    static let kuroMissingArt = Color(hex: "E6E6E6")
    /// Inset rim of the light advance key and the chapter ticket stroke. Black at 12%.
    static let kuroKeyRim = Color.black.opacity(0.12)
    /// The private club room: a neutral near-black (replaces the prototype's green #252B28).
    static let kuroRoom = Color(hex: "222222")
    /// Primary text inside the club room.
    static let kuroRoomText = Color.white.opacity(0.9)
    /// Secondary text inside the club room.
    static let kuroRoomTextSecondary = Color.white.opacity(0.6)
    /// Pressed fill of an ink control (the primary capsule while held).
    static let kuroInkPressed = Color(hex: "2E2E2E")
    /// Destructive text, outline and spinner (about 5.7:1 on white, AA for normal text). Red stays
    /// reserved for destructive actions; `kuroError` remains for icons and inline error marks.
    static let kuroDestructiveInk = Color(hex: "C4271D")

    // MARK: - Prototype palette (prototype-fidelity pass, PROTOTYPE_SPEC.md §2)
    // The approved prototype's component palette returns (owner, 2026-11-01). Statuses stay
    // monochrome; red stays reserved for destructive actions. Artwork colour comes from
    // `ArtworkMaterial`, never from a fixed per-title table.
    /// The Home (Poster) canvas, also the Taste page: warm paper white `#fffef8`.
    static let kuroCanvasHome = Color(hex: "FFFEF8")
    /// The detail sheet paper `#f5f5f4` (`--paper`).
    static let kuroPaper = Color(hex: "F5F5F4")
    /// Secondary text, e.g. the header's page name (`--muted` #696c6b, about 5.3:1 on white).
    static let kuroMuted = Color(hex: "696C6B")
    /// Hairlines (`--line`: CSS `#272b2920`, i.e. #272b29 at alpha 0x20).
    static let kuroLine = Color(hex: "272B29", opacity: Double(0x20) / 255)
    /// Top of the raised light key face (`--key-face` light: #f1f4f2 → #d5ded8).
    static let kuroKeyLightTop = Color(hex: "F1F4F2")
    /// Bottom of the raised light key face.
    static let kuroKeyLightBottom = Color(hex: "D5DED8")
    /// Top of the raised dark key face where no artwork material exists (#444a47 → #2c322f).
    static let kuroKeyDarkTop = Color(hex: "444A47")
    /// Bottom of the raised dark key face.
    static let kuroKeyDarkBottom = Color(hex: "2C322F")
}

// MARK: - Dynamic Type Scaling
// Every Kuro role scales a base size with `UIFontMetrics` relative to a text style, then caps it.
// The category comes from `KuroTypeScale.current`, which follows the system's content-size
// notification on its own (so every root, signed in or out, is covered) and the signed-in root's
// SwiftUI `\.dynamicTypeSize` (`.kuroDynamicTypeScale()`). Reading it inside a role registers an
// Observation dependency, so every view body that uses a role is re-evaluated when the user changes
// the text size while the app runs (no relaunch, no per-call-site change).

/// The Dynamic Type category the Kuro type roles scale to.
@MainActor
@Observable
final class KuroTypeScale {
    /// The one scale the type roles read. UI infrastructure, not business state.
    static let current = KuroTypeScale()

    /// The category in effect (the app's category at launch, then the latest system change or
    /// root report).
    private(set) var category: UIContentSizeCategory?
    @ObservationIgnored private var traits: UITraitCollection?
    /// The content-size observer (the shared scale lives for the whole process).
    @ObservationIgnored private var sizeObserver: (any NSObjectProtocol)?

    private init() {
        // Start from the app's current category so the first frame is already right and the root's
        // initial report changes nothing (no extra re-render at launch).
        let initial = UIApplication.shared.preferredContentSizeCategory
        category = initial
        traits = UITraitCollection(preferredContentSizeCategory: initial)
        // Independent of any root modifier: the signed-out root (Auth) follows text-size changes too.
        sizeObserver = NotificationCenter.default.addObserver(
            forName: UIContentSizeCategory.didChangeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                KuroTypeScale.current.update(category: UIApplication.shared.preferredContentSizeCategory)
            }
        }
    }

    /// Called by `.kuroDynamicTypeScale()` whenever SwiftUI's dynamic type size changes.
    func update(_ size: DynamicTypeSize) {
        update(category: Self.category(for: size))
    }

    /// Applies a category (from the system notification or a root report); unchanged: no-op.
    func update(category next: UIContentSizeCategory) {
        guard next != category, next != .unspecified else { return }
        traits = UITraitCollection(preferredContentSizeCategory: next)
        category = next
    }

    /// `baseSize` scaled for the current category relative to `textStyle`.
    func scaled(_ baseSize: CGFloat, relativeTo textStyle: UIFont.TextStyle) -> CGFloat {
        let metrics = UIFontMetrics(forTextStyle: textStyle)
        // Reading `category` registers the dependency even when the traits are not built yet.
        guard category != nil, let traits else { return metrics.scaledValue(for: baseSize) }
        return metrics.scaledValue(for: baseSize, compatibleWith: traits)
    }

    /// SwiftUI's size mapped onto UIKit's category (exhaustive, so a new case fails the build).
    nonisolated static func category(for size: DynamicTypeSize) -> UIContentSizeCategory {
        switch size {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        @unknown default: return .large
        }
    }
}

private func kuroScaled(_ baseSize: CGFloat, relativeTo textStyle: UIFont.TextStyle) -> CGFloat {
    KuroTypeScale.current.scaled(baseSize, relativeTo: textStyle)
}

private struct KuroDynamicTypeScaleModifier: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content.onChange(of: dynamicTypeSize, initial: true) { _, size in
            KuroTypeScale.current.update(size)
        }
    }
}

extension View {
    /// Keeps the Kuro type roles in step with SwiftUI's text size at this root (`KuroRootView`).
    /// Optional elsewhere: `KuroTypeScale` also follows the system content-size notification.
    func kuroDynamicTypeScale() -> some View {
        modifier(KuroDynamicTypeScaleModifier())
    }
}

/// The point size of each role (shared by the `Font` roles and by code that must measure text
/// with the same size it draws, e.g. the header's section window).
enum KuroTypeRole {
    case hero, display, feature, headline, title, body, caption, micro, navigation
    case titleName, meta, buttonLabel
    /// The medium switch words (ANIME / MANGA): prototype SF 36 w850, tracking −1.9, uppercase.
    case mediumWord

    /// Base size at the default text size, the text style it scales with, and its cap.
    var spec: (base: CGFloat, style: UIFont.TextStyle, cap: CGFloat) {
        switch self {
        case .hero: return (64, .largeTitle, 96)
        case .display: return (44, .largeTitle, 72)
        case .feature: return (34, .title1, 60)
        case .headline: return (26, .title2, 48)
        case .title: return (19, .title3, 40)
        case .body: return (15, .body, 34)
        case .caption: return (11, .caption1, 24)
        case .micro: return (9, .caption2, 18)
        case .navigation: return (11, .caption1, 20)
        case .titleName: return (17, .headline, 36)
        case .meta: return (13, .footnote, 28)
        case .buttonLabel: return (17, .body, 30)
        // Capped so the longer word still fits its half of the switch at the largest text sizes.
        case .mediumWord: return (36, .largeTitle, 44)
        }
    }

    /// The prototype's tracking as a fraction of the point size (em), so it scales with Dynamic Type.
    /// Measured in PROTOTYPE_SPEC.md §4: the medium word 36/−1.9, the detail title 27/−1.1, "Coming
    /// up." 24/−0.85 and the "Seasons" heading 18/−0.7. Roles the prototype does not track return 0.
    var trackingEm: CGFloat {
        switch self {
        case .hero, .mediumWord: return -1.9 / 36
        case .display, .feature: return -1.1 / 27
        case .headline: return -0.85 / 24
        case .title: return -0.7 / 18
        case .body, .caption, .micro, .navigation, .titleName, .meta, .buttonLabel: return 0
        }
    }

    /// The tracking in points at the current text size (`trackingEm` × `pointSize`).
    var tracking: CGFloat { trackingEm * pointSize }

    /// The scaled, capped point size for the current text size.
    var pointSize: CGFloat {
        let spec = spec
        return min(kuroScaled(spec.base, relativeTo: spec.style), spec.cap)
    }
}

// MARK: - Typography System (prototype-fidelity pass)
// The display roles (hero, display, feature, headline, title) speak the prototype's language: the system
// sans (SF Pro) at the prototype's weights. A `Font` cannot carry tracking, so the matching tight
// tracking is `KuroTypeRole.tracking` / `.kuroTracking(_:)` at the call site. The serif is reserved for
// the prototype's few editorial headings (`kuroEditorial`). Explicit `weight:` arguments are honoured.
extension Font {
    /// A custom size that scales with Dynamic Type relative to `textStyle`. `maxSize` caps it
    /// (nil: no cap, the legacy behaviour).
    static func kuroCustom(
        _ baseSize: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        relativeTo textStyle: UIFont.TextStyle = .body,
        maxSize: CGFloat? = nil
    ) -> Font {
        let scaled = kuroScaled(baseSize, relativeTo: textStyle)
        return .system(size: maxSize.map { min(scaled, $0) } ?? scaled, weight: weight, design: design)
    }

    private static func kuroRole(_ role: KuroTypeRole, weight: Font.Weight, design: Font.Design) -> Font {
        .system(size: role.pointSize, weight: weight, design: design)
    }

    // HERO - Dramatic statements (64pt sans heavy; prototype w850 at display size)
    static func kuroHero(weight: Font.Weight = .heavy) -> Font {
        kuroRole(.hero, weight: weight, design: .default)
    }

    // DISPLAY - Large section headers and the one cover line per screen (44pt sans semibold;
    // prototype detail title w600)
    static func kuroDisplay(weight: Font.Weight = .semibold) -> Font {
        kuroRole(.display, weight: weight, design: .default)
    }

    // FEATURE - Feature titles, prominent elements (34pt sans semibold)
    static func kuroFeature(weight: Font.Weight = .semibold) -> Font {
        kuroRole(.feature, weight: weight, design: .default)
    }

    // HEADLINE - Section headings, card titles (26pt sans semibold; prototype "Coming up." w550)
    static func kuroHeadline(weight: Font.Weight = .semibold) -> Font {
        kuroRole(.headline, weight: weight, design: .default)
    }

    // TITLE - Secondary titles, section heads (19pt sans semibold; prototype "Seasons" w550)
    static func kuroTitle(weight: Font.Weight = .semibold) -> Font {
        kuroRole(.title, weight: weight, design: .default)
    }

    // EDITORIAL - The prototype's few serif headings (system serif, New York, standing in for its
    // Georgia): the club name and quote, "Between us.", the manga detail title and hook, "Your
    // bookmark", manga row numbers (italic at the call site) and "Seen the anime?"
    // (PROTOTYPE_SPEC.md §2, §8.1). `size` is the prototype's size at the default text size.
    static func kuroEditorial(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let style: UIFont.TextStyle
        switch size {
        case 28...: style = .title1
        case 22..<28: style = .title2
        case 17..<22: style = .title3
        default: style = .body
        }
        return kuroCustom(size, weight: weight, design: .serif, relativeTo: style, maxSize: size * 1.75)
    }

    // MEDIUM WORD - The medium switch (ANIME / MANGA): heavy sans. Uppercase and tracking need the
    // view: use `.kuroMediumWordStyle()`. `size` 36 at 390 pt, 30 on small phones (≤ 360 pt).
    static func kuroMediumWord(size: CGFloat = 36) -> Font {
        let spec = KuroTypeRole.mediumWord.spec
        return kuroCustom(size, weight: .heavy, relativeTo: spec.style, maxSize: size * spec.cap / spec.base)
    }

    // BODY - Descriptions, editorial content (15pt sans)
    static func kuroBody(weight: Font.Weight = .light) -> Font {
        kuroRole(.body, weight: weight, design: .default)
    }

    // CAPTION - Nonessential captions (11pt sans)
    static func kuroCaption(weight: Font.Weight = .light) -> Font {
        kuroRole(.caption, weight: weight, design: .default)
    }

    // MICRO - Kickers and redundant labels only (9pt sans)
    static func kuroMicro(weight: Font.Weight = .medium) -> Font {
        kuroRole(.micro, weight: weight, design: .default)
    }

    // NAVIGATION - Header labels (11pt sans)
    static func kuroNavigation(weight: Font.Weight = .regular) -> Font {
        kuroRole(.navigation, weight: weight, design: .default)
    }

    // TITLE NAME - A title's name on a lead card or row (17pt sans, rulebook §4)
    static func kuroTitleName(weight: Font.Weight = .medium) -> Font {
        kuroRole(.titleName, weight: weight, design: .default)
    }

    // META - Dates, counts, control text (13pt sans)
    static func kuroMeta(weight: Font.Weight = .regular) -> Font {
        kuroRole(.meta, weight: weight, design: .default)
    }

    // BUTTON LABEL - Primary and secondary button labels (17pt sans semibold)
    static func kuroButtonLabel(weight: Font.Weight = .semibold) -> Font {
        kuroRole(.buttonLabel, weight: weight, design: .default)
    }

    // Legacy compatibility
    static func kuroCardTitle(weight: Font.Weight = .light) -> Font {
        kuroHeadline(weight: weight)
    }
}

extension View {
    /// The prototype's tight tracking for `role` at the current text size (0 for untracked roles).
    func kuroTracking(_ role: KuroTypeRole) -> some View {
        tracking(role.tracking)
    }

    /// A medium switch word: heavy sans, uppercase, the prototype's −1.9 / 36 tracking at `size`.
    func kuroMediumWordStyle(size: CGFloat = 36) -> some View {
        let spec = KuroTypeRole.mediumWord.spec
        let scaled = min(kuroScaled(size, relativeTo: spec.style), size * spec.cap / spec.base)
        return font(.kuroMediumWord(size: size))
            .tracking(KuroTypeRole.mediumWord.trackingEm * scaled)
            .textCase(.uppercase)
    }

    /// The small Kuro voice: wide-tracked caps, quiet ink. Pairs with a light serif cover line and a short ink rule.
    func kuroKicker() -> some View {
        font(.kuroMicro(weight: .medium))
            .tracking(2.1)
            .textCase(.uppercase)
            .foregroundStyle(Color.kuroInkQuiet)
    }
}

// MARK: - Spacing System - 8px Base Unit
struct KuroDesignSpacing {
    // Base unit: 8px
    static let xs: CGFloat = 4    // 0.5 units
    static let sm: CGFloat = 8    // 1 unit
    static let md: CGFloat = 16   // 2 units
    static let lg: CGFloat = 24   // 3 units
    static let xl: CGFloat = 32   // 4 units
    static let xxl: CGFloat = 48  // 6 units
    static let xxxl: CGFloat = 64 // 8 units
    
    // Legacy properties for compatibility
    static let containerSpacing: CGFloat = 16
    static let padding: CGFloat = 20
    static let rowSpacing: CGFloat = 16
    
    static let modernCardRadius: CGFloat = 16  // Modern rounded corners
    static let modernShadowRadius: CGFloat = 20  // Soft shadows
    static let modernShadowOpacity: Double = 0.04  // Subtle depth
    static let secondaryShadowRadius: CGFloat = 5   // Secondary shadow
    static let secondaryShadowOpacity: Double = 0.02 // Very subtle
    
    // Pixel alignment helper (using standard 3x scale for modern iPhones)
    private static func pixelAlign(_ value: CGFloat) -> CGFloat {
        let scale: CGFloat = 3.0
        return floor(value * scale) / scale
    }
    
    // Pixel-perfect spacing helpers
    static var perfectContainerSpacing: CGFloat {
        pixelAlign(containerSpacing)
    }
    
    static var perfectPadding: CGFloat {
        pixelAlign(padding)
    }
    
    // Responsive spacing based on screen size
    static func adaptive(_ base: CGFloat, for width: CGFloat) -> CGFloat {
        switch width {
        case 0..<375:    return base * 0.8  // iPhone SE, mini
        case 375..<414:  return base        // iPhone standard
        case 414..<768:  return base * 1.2  // iPhone Plus, Pro Max
        case 768..<1024: return base * 1.5  // iPad Portrait
        default:         return base * 2.0  // iPad Landscape
        }
    }
}

// MARK: - Legacy Spacing Alias (for backward compatibility)
// Some views still reference KuroSpacing.*. Mirror KuroDesignSpacing here to fix build errors.
struct KuroSpacing {
    static let xs = KuroDesignSpacing.xs
    static let sm = KuroDesignSpacing.sm
    static let md = KuroDesignSpacing.md
    static let lg = KuroDesignSpacing.lg
    static let xl = KuroDesignSpacing.xl
    static let xxl = KuroDesignSpacing.xxl
    static let xxxl = KuroDesignSpacing.xxxl
}

// MARK: - Corner Radius System
struct KuroRadius {
    static let xs: CGFloat = 4    // Small elements
    static let sm: CGFloat = 8    // Cards, buttons
    static let md: CGFloat = 12   // Large cards
    static let lg: CGFloat = 16   // Hero elements
    
    // Responsive radius
    static func adaptive(_ base: CGFloat, for width: CGFloat) -> CGFloat {
        switch width {
        case 0..<375:    return base * 0.8
        case 375..<414:  return base
        case 414..<768:  return base * 1.2
        case 768..<1024: return base * 1.5
        default:         return base * 2.0
        }
    }
}

// MARK: - Shadow System
struct KuroShadow {
    struct ShadowStyle {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }
    
    static let subtle = ShadowStyle(
        color: Color.kuroBlack08,
        radius: 4,
        x: 0,
        y: 2
    )
    
    static let card = ShadowStyle(
        color: Color.kuroBlack08,
        radius: 8,
        x: 0,
        y: 4
    )
    
    static let hero = ShadowStyle(
        color: Color.kuroBlack08,
        radius: 16,
        x: 0,
        y: 8
    )
}

// MARK: - Editorial Animation System (Vogue/Miu Miu Inspired)
// Elegant, refined, sophisticated transitions
struct KuroAnimation {
    // FADE - Elegant opacity transitions
    static let fadeIn: Animation = .easeOut(duration: 0.6)
    static let fadeOut: Animation = .easeIn(duration: 0.4)

    // SLIDE - Smooth editorial reveals
    static let slideIn: Animation = .easeOut(duration: 0.5)
    static let slideOut: Animation = .easeIn(duration: 0.3)

    // SCALE - Subtle zoom effects
    static let scaleUp: Animation = .spring(response: 0.5, dampingFraction: 0.85)
    static let scaleDown: Animation = .spring(response: 0.3, dampingFraction: 0.9)

    // STANDARD - General purpose
    static let fast: Animation = .easeInOut(duration: 0.25)
    static let standard: Animation = .easeInOut(duration: 0.4)
    static let slow: Animation = .easeInOut(duration: 0.6)

    // EDITORIAL - Fashion-forward spring
    static let editorial: Animation = .spring(response: 0.6, dampingFraction: 0.82)
    /// Visible overshoot. Forbidden for new work (rulebook §8); kept for legacy call sites.
    static let editorialBounce: Animation = .spring(response: 0.45, dampingFraction: 0.75)

    // PARALLAX - Depth and dimension
    static let parallax: Animation = .easeOut(duration: 0.8)

    // Legacy compatibility
    static let spring: Animation = .spring(response: 0.4, dampingFraction: 0.8)
    /// Visible overshoot. Forbidden for new work (rulebook §8); kept for legacy call sites.
    static let springBouncy: Animation = .spring(response: 0.5, dampingFraction: 0.6)

    // Haptic feedback integration
    static func withHaptic(_ animation: Animation, style: Int = 0) -> Animation {
        #if os(iOS)
        let impactFeedback = UIImpactFeedbackGenerator(style: UIImpactFeedbackGenerator.FeedbackStyle(rawValue: style) ?? .light)
        impactFeedback.impactOccurred()
        #endif
        return animation
    }
}

// MARK: - Reduce Motion Support
// View modifier and helpers to respect the user's Reduce Motion preference.
// When reduce motion is on, springs/bounces are replaced with a subtle cross-fade
// (.easeInOut 0.2s) rather than snapping instantly.
// Usage: withAnimation(KuroMotion.resolve(.editorial)) { ... }
//   or:  .kuroAnimation(.editorial, value: someValue)
struct KuroMotion {
    /// A subtle cross-fade used when Reduce Motion is enabled.
    static let reducedMotionFallback: Animation = .easeInOut(duration: 0.2)

    /// The prototype's ease, `cubic-bezier(.2,.8,.25,1)` (`--ease`), over `duration` seconds.
    static func ease(_ duration: Double) -> Animation {
        .timingCurve(0.2, 0.8, 0.25, 1, duration: duration)
    }

    /// Press contact: immediate, reversible (`--motion-contact` 120 ms, prototype ease).
    static let contact: Animation = ease(0.12)
    /// Settle after a press or a small state change (`--motion-settle` 220 ms, prototype ease).
    static let settle: Animation = ease(0.22)
    /// A medium change, e.g. the canvas colour on a medium switch (`--motion-medium` 320 ms).
    static let medium: Animation = ease(0.32)
    /// A progress count change (the Stamp, 160 ms).
    static let stamp: Animation = .easeOut(duration: 0.16)
    /// A clear context change: medium switch, season selection (220 ms crossfade, no overshoot).
    static let contextChange: Animation = .easeInOut(duration: 0.22)

    /// Returns the given animation, or a subtle cross-fade when Reduce Motion is on.
    /// Call from within a View body or anywhere UIAccessibility is available.
    static func resolve(_ animation: Animation) -> Animation {
        #if os(iOS)
        UIAccessibility.isReduceMotionEnabled ? reducedMotionFallback : animation
        #else
        animation
        #endif
    }

    /// Ambient welcome drift. A still frame is the treatment for Reduce Motion, Low Power Mode,
    /// and any surface that is offscreen, backgrounded, or dismissed.
    static func ambientDriftAllowed(reduceMotion: Bool, lowPowerMode: Bool, sceneIsActive: Bool) -> Bool {
        sceneIsActive && !reduceMotion && !lowPowerMode
    }
}

extension View {
    /// Apply an animation that automatically respects Reduce Motion.
    /// When reduce motion is enabled, uses a subtle cross-fade instead of the full animation.
    func kuroAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        self.modifier(KuroReduceMotionModifier(base: animation, value: value))
    }
}

private struct KuroReduceMotionModifier<V: Equatable>: ViewModifier {
    let base: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? KuroMotion.reducedMotionFallback : base, value: value)
    }
}

// MARK: - Screen Size Detection
/// Fixed iPhone 14 Pro numbers. **Forbidden for new layout** (rulebook §5/§13): derive widths from
/// the container (`GeometryReader`, `containerRelativeFrame`, `onGeometryChange`) instead; the
/// pager width (`\.kuroPagerWidth`) is a gesture value, not a content width. Kept only
/// so legacy call sites compile until their lanes migrate them.
struct KuroScreen {
    // Use reasonable defaults for modern iPhones
    // In SwiftUI, prefer GeometryReader for dynamic sizing
    static var width: CGFloat {
        393 // iPhone 14 Pro standard width
    }

    static var height: CGFloat {
        852 // iPhone 14 Pro standard height
    }

    static var safeAreaTop: CGFloat {
        59 // Standard iPhone with Dynamic Island
    }

    static var safeAreaBottom: CGFloat {
        34 // Standard iPhone bottom safe area
    }
    
    // Device type detection
    static var isIPhone: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }

    static var isIPad: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad
        #else
        return false
        #endif
    }
    
    static var isSmallScreen: Bool {
        width < 375
    }
    
    static var isLargeScreen: Bool {
        width > 768
    }
}

// MARK: - Responsive Layout Helpers
/// Width breakpoints over `KuroScreen.width` (a constant 393). **Forbidden for new layout**
/// (rulebook §13); use Dynamic Type roles and container widths. Kept for legacy call sites.
struct ResponsiveLayout {
    // Adaptive padding based on screen size
    static func padding(_ base: CGFloat = KuroDesignSpacing.lg) -> CGFloat {
        KuroDesignSpacing.adaptive(base, for: KuroScreen.width)
    }
    
    // Adaptive font size
    static func fontSize(_ base: CGFloat) -> CGFloat {
        switch KuroScreen.width {
        case 0..<375:    return base * 0.9
        case 375..<414:  return base
        case 414..<768:  return base * 1.1
        case 768..<1024: return base * 1.2
        default:         return base * 1.3
        }
    }
    
    // Adaptive image height
    static func imageHeight(_ base: CGFloat = 300) -> CGFloat {
        switch KuroScreen.width {
        case 0..<375:    return base * 0.7  // Smaller for small phones
        case 375..<414:  return base        // Standard iPhone
        case 414..<768:  return base * 1.2  // iPhone Plus
        case 768..<1024: return base * 1.5  // iPad Portrait
        default:         return base * 2.0  // iPad Landscape
        }
    }
}

// MARK: - Accessibility Support
struct KuroAccessibility {
    // VoiceOver support
    static func voiceOverLabel(_ text: String) -> String {
        return text
    }

    // Haptic feedback (iOS only)
    #if os(iOS)
    static func successHaptic() {
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.success)
    }

    static func errorHaptic() {
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.error)
    }

    static func impactHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let impactFeedback = UIImpactFeedbackGenerator(style: style)
        impactFeedback.impactOccurred()
    }

    /// A selection tick (advance key, word switches).
    static func selectionHaptic() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
    #else
    // macOS - no haptic feedback
    enum FeedbackStyle {
        case light, medium, heavy
    }
    static func successHaptic() { }
    static func errorHaptic() { }
    static func impactHaptic(_ style: FeedbackStyle = .medium) { }
    static func selectionHaptic() { }
    #endif
}

// MARK: - iOS 26 Specific Features
#if os(iOS)
@available(iOS 26.0, *)
struct KuroiOS26 {
    // Enhanced haptic feedback
    static func enhancedHaptic(_ intensity: Float = 1.0) {
        // iOS 26 enhanced haptic patterns
        let impactFeedback = UIImpactFeedbackGenerator()
        impactFeedback.impactOccurred()
    }

    // Advanced animations
    static var advancedSpring: Animation {
        .spring(response: 0.3, dampingFraction: 0.7, blendDuration: 0.1)
    }

    // Dynamic Island integration
    static func dynamicIslandHeight() -> CGFloat {
        // Return dynamic island height for proper spacing
        return 54 // Approximate height
    }
}
#endif

// MARK: - Card Metrics (Single source of truth)
struct KuroCardMetrics {
    // Global constants to keep all cards uniform
    static let horizontalPadding: CGFloat = 20
    static let interItemSpacing: CGFloat = 16
    static let rowSpacing: CGFloat = 16
    static let imageAspectRatio: CGFloat = 0.7 // Portrait
    static let textBlockHeight: CGFloat = 60
    static let imageToTextSpacing: CGFloat = 8

    // Computes a 2-column grid with fixed, pixel-aligned card sizes
    static func grid(for containerWidth: CGFloat, columns count: Int = 2) -> (columns: [GridItem], cardWidth: CGFloat, cardHeight: CGFloat) {
        let totalSpacing = CGFloat(count - 1) * interItemSpacing
        let availableWidth = containerWidth - (2 * horizontalPadding) - totalSpacing
        // Pixel-align width to avoid subpixel rendering differences
        let rawWidth = availableWidth / CGFloat(count)
        let scale: CGFloat = 3.0 // Standard for modern iPhones
        let cardWidth = floor(rawWidth * scale) / scale

        let imageHeight = cardWidth / imageAspectRatio
        let cardHeight = floor(imageHeight + imageToTextSpacing + textBlockHeight)

        let columns = Array(repeating: GridItem(.fixed(cardWidth), spacing: interItemSpacing, alignment: .top), count: count)
        return (columns, cardWidth, cardHeight)
    }
}

// MARK: - Shimmer Modifier
/// Shared shimmer effect for skeleton/loading placeholders.
/// Uses a single TimelineView animation driver; pass the same phase to siblings
/// to keep all skeletons in sync without per-element timers.
struct KuroShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var active: Bool = true

    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                if active && !reduceMotion {
                    GeometryReader { geo in
                        let w = geo.size.width
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.0),
                                Color.black.opacity(0.06),
                                Color.black.opacity(0.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: w * 0.6)
                        .offset(x: phase * (w * 1.6) - (w * 0.3))
                    }
                    .clipped()
                    .allowsHitTesting(false)
                    .onAppear {
                        withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                            phase = 1
                        }
                    }
                }
            }
    }
}

extension View {
    /// Applies an animated shimmer overlay suitable for skeleton loading states.
    /// Automatically disabled when Reduce Motion is on.
    func kuroShimmer(active: Bool = true) -> some View {
        modifier(KuroShimmerModifier(active: active))
    }
}

// MARK: - Component Styling
struct KuroStyle {
    // Card styling
    static func card() -> some View {
        RoundedRectangle(cornerRadius: KuroRadius.md)
            .fill(Color.kuroWhite)
            .shadow(
                color: KuroShadow.card.color,
                radius: KuroShadow.card.radius,
                x: KuroShadow.card.x,
                y: KuroShadow.card.y
            )
    }

    // Button styling
    static func primaryButton() -> some View {
        RoundedRectangle(cornerRadius: KuroRadius.sm)
            .fill(Color.kuroBlack)
            .overlay(
                Text("BUTTON")
                    .font(.kuroMicro(weight: .medium))
                    .foregroundColor(.kuroWhite)
            )
    }

    // Badge styling
    static func mediaBadge(_ text: String, isAnime: Bool) -> some View {
        Text(text)
            .font(.kuroMicro(weight: .medium))
            .foregroundColor(.kuroWhite)
            .padding(.horizontal, KuroDesignSpacing.sm)
            .padding(.vertical, KuroDesignSpacing.xs)
            .background(
                Capsule()
                    .fill(isAnime ? Color.kuroAnime : Color.kuroManga)
            )
    }
}

// MARK: - Editorial Layout Helpers (Vogue/Miu Miu Inspired)
struct EditorialLayout {
    // Magazine-style asymmetric grid
    enum GridStyle {
        case asymmetric       // Varied sizes, editorial feel
        case masonry          // Pinterest-style flowing layout
        case featured         // One large + multiple small
        case symmetric        // Traditional 2-column grid
    }

    // Hero image proportions
    static let heroAspectRatio: CGFloat = 1.25  // 5:4 - editorial hero
    static let featureAspectRatio: CGFloat = 1.5 // 3:2 - feature image
    static let standardAspectRatio: CGFloat = 0.7 // 2:3 - portrait standard

    // Magazine spacing
    static let gutterLarge: CGFloat = 32   // Between major sections
    static let gutterMedium: CGFloat = 24  // Between items
    static let gutterSmall: CGFloat = 16   // Between related elements
    static let marginEditorial: CGFloat = 24 // Page margins

    // Dramatic dividers
    static func divider(thickness: CGFloat = 1.0, opacity: Double = 0.12) -> some View {
        Rectangle()
            .fill(Color.black.opacity(opacity))
            .frame(height: thickness)
    }

    // Editorial pull quote styling
    static func pullQuote(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(Color.black)
                .frame(width: 40, height: 2)

            Text(text)
                .font(.kuroFeature(weight: .light))
                .foregroundColor(.black)
                .tracking(0.4)
                .lineSpacing(8)
                .multilineTextAlignment(.leading)
        }
    }

    // Magazine-style number badge
    static func numberBadge(_ number: Int) -> some View {
        Text("\(number)")
            .font(.kuroCaption(weight: .medium))
            .foregroundColor(.black.opacity(0.5))
            .frame(width: 28, height: 28)
            .background(
                Circle()
                    .stroke(Color.black.opacity(0.2), lineWidth: 1)
            )
    }
}
