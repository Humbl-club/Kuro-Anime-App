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
    static let kuroBlack60 = Color.black.opacity(0.6)   // Secondary text
    static let kuroBlack30 = Color.black.opacity(0.3)   // Tertiary text
    static let kuroBlack08 = Color.black.opacity(0.08)  // Subtle backgrounds
    
    // Media Type Accents (Subtle)
    static let kuroAnime = Color.blue.opacity(0.8)      // Anime badge
    static let kuroManga = Color.green.opacity(0.8)     // Manga badge
    
    // System Colors
    #if os(macOS)
    static let kuroBackground = Color(NSColor.windowBackgroundColor)
    static let kuroSecondaryBackground = Color(NSColor.controlBackgroundColor)
    static let kuroTertiaryBackground = Color(NSColor.tertiarySystemFill)
    #else
    static let kuroBackground = Color(.systemBackground)
    static let kuroSecondaryBackground = Color(.secondarySystemBackground)
    static let kuroTertiaryBackground = Color(.tertiarySystemBackground)
    #endif
}

// MARK: - Editorial Typography System (Vogue/Miu Miu Inspired)
// Fashion-forward, dramatic, refined
extension Font {
    // HERO - Magazine covers, dramatic statements (56-72pt)
    static func kuroHero(weight: Font.Weight = .thin) -> Font {
        .system(size: 64, weight: weight, design: .serif)
    }

    // DISPLAY - Large section headers (40-48pt)
    static func kuroDisplay(weight: Font.Weight = .thin) -> Font {
        .system(size: 44, weight: weight, design: .serif)
    }

    // FEATURE - Feature titles, prominent elements (32-36pt)
    static func kuroFeature(weight: Font.Weight = .light) -> Font {
        .system(size: 34, weight: weight, design: .serif)
    }

    // HEADLINE - Card titles, subheaders (24-28pt)
    static func kuroHeadline(weight: Font.Weight = .light) -> Font {
        .system(size: 26, weight: weight, design: .serif)
    }

    // TITLE - Secondary titles (18-20pt)
    static func kuroTitle(weight: Font.Weight = .regular) -> Font {
        .system(size: 19, weight: weight, design: .serif)
    }

    // BODY - Descriptions, editorial content (15-16pt)
    static func kuroBody(weight: Font.Weight = .light) -> Font {
        .system(size: 15, weight: weight, design: .default)
    }

    // CAPTION - Small refined labels (11-12pt)
    static func kuroCaption(weight: Font.Weight = .light) -> Font {
        .system(size: 11, weight: weight, design: .default)
    }

    // MICRO - Tiny metadata, fashion-forward tight spacing (8-9pt)
    static func kuroMicro(weight: Font.Weight = .medium) -> Font {
        .system(size: 9, weight: weight, design: .default)
    }

    // NAVIGATION - Header labels (11pt) - kept for locked nav
    static func kuroNavigation(weight: Font.Weight = .regular) -> Font {
        .system(size: 11, weight: weight, design: .default)
    }

    // Legacy compatibility
    static func kuroCardTitle(weight: Font.Weight = .light) -> Font {
        .system(size: 26, weight: weight, design: .serif)
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
    static let editorialBounce: Animation = .spring(response: 0.45, dampingFraction: 0.75)

    // PARALLAX - Depth and dimension
    static let parallax: Animation = .easeOut(duration: 0.8)

    // Legacy compatibility
    static let spring: Animation = .spring(response: 0.4, dampingFraction: 0.8)
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

// MARK: - Screen Size Detection
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
    // Dynamic Type support
    static func adaptiveFont(_ base: Font, for category: ContentSizeCategory) -> Font {
        switch category {
        case .extraSmall, .small, .medium:
            return base
        case .large, .extraLarge:
            return base
        case .extraExtraLarge, .extraExtraExtraLarge:
            return base
        case .accessibilityMedium, .accessibilityLarge, .accessibilityExtraLarge, .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge:
            return base
        @unknown default:
            return base
        }
    }

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
    #else
    // macOS - no haptic feedback
    enum FeedbackStyle {
        case light, medium, heavy
    }
    static func successHaptic() { }
    static func errorHaptic() { }
    static func impactHaptic(_ style: FeedbackStyle = .medium) { }
    #endif
}

// MARK: - iOS 26 Specific Features
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

// MARK: - Component Styling
struct KuroStyle {
    // Card styling
    static func card() -> some View {
        RoundedRectangle(cornerRadius: KuroRadius.adaptive(KuroRadius.md, for: KuroScreen.width))
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
