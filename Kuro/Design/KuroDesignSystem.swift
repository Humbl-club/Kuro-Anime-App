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
    
    // System Colors for iOS 26
    static let kuroBackground = Color(.systemBackground)
    static let kuroSecondaryBackground = Color(.secondarySystemBackground)
    static let kuroTertiaryBackground = Color(.tertiarySystemBackground)
}

// MARK: - Typography System - iOS 26 Optimized
extension Font {
    // Micro Text (10-11pt) - Labels, captions
    static func kuroMicro(weight: Font.Weight = .light) -> Font {
        .system(size: 10, weight: weight, design: .default)
    }
    
    // Body Text (14-16pt) - Content, descriptions
    static func kuroBody(weight: Font.Weight = .light) -> Font {
        .system(size: 14, weight: weight, design: .default)
    }
    
    // Display Text (24-32pt) - Titles, heroes
    static func kuroDisplay(weight: Font.Weight = .ultraLight) -> Font {
        .system(size: 24, weight: weight, design: .serif)
    }
    
    // Navigation Text (11pt) - Tab labels, navigation
    static func kuroNavigation(weight: Font.Weight = .regular) -> Font {
        .system(size: 11, weight: weight, design: .default)
    }
    
    // Card Title (18-20pt) - Content card titles
    static func kuroCardTitle(weight: Font.Weight = .ultraLight) -> Font {
        .system(size: 18, weight: weight, design: .serif)
    }
}

// MARK: - Spacing System - 8px Base Unit
struct KuroSpacing {
    // Base unit: 8px
    static let xs: CGFloat = 4    // 0.5 units
    static let sm: CGFloat = 8    // 1 unit
    static let md: CGFloat = 16   // 2 units
    static let lg: CGFloat = 24   // 3 units
    static let xl: CGFloat = 32   // 4 units
    static let xxl: CGFloat = 48  // 6 units
    static let xxxl: CGFloat = 64 // 8 units
    
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

// MARK: - Animation System - iOS 26 Optimized
struct KuroAnimation {
    // Standard timing
    static let fast: Animation = .easeInOut(duration: 0.2)
    static let standard: Animation = .easeInOut(duration: 0.3)
    static let slow: Animation = .easeInOut(duration: 0.4)
    
    // Spring animations for iOS 26
    static let spring: Animation = .spring(response: 0.4, dampingFraction: 0.8)
    static let springBouncy: Animation = .spring(response: 0.5, dampingFraction: 0.6)
    
    // Haptic feedback integration
    static func withHaptic(_ animation: Animation, style: UIImpactFeedbackGenerator.FeedbackStyle = .light) -> Animation {
        // Trigger haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: style)
        impactFeedback.impactOccurred()
        return animation
    }
}

// MARK: - Screen Size Detection
struct KuroScreen {
    static var width: CGFloat {
        UIScreen.main.bounds.width
    }
    
    static var height: CGFloat {
        UIScreen.main.bounds.height
    }
    
    static var safeAreaTop: CGFloat {
        UIApplication.shared.windows.first?.safeAreaInsets.top ?? 0
    }
    
    static var safeAreaBottom: CGFloat {
        UIApplication.shared.windows.first?.safeAreaInsets.bottom ?? 0
    }
    
    // Device type detection
    static var isIPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }
    
    static var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
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
    static func padding(_ base: CGFloat = KuroSpacing.lg) -> CGFloat {
        KuroSpacing.adaptive(base, for: KuroScreen.width)
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

// MARK: - Accessibility Support - iOS 26
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
    
    // Haptic feedback
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
            .padding(.horizontal, KuroSpacing.sm)
            .padding(.vertical, KuroSpacing.xs)
            .background(
                Capsule()
                    .fill(isAnime ? Color.kuroAnime : Color.kuroManga)
            )
    }
}

