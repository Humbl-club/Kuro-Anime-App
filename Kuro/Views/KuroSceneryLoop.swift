import SwiftUI

/// Seamless mountain banner shared by the login welcome and an empty Home.
/// Login keeps the original saturation. Empty Home cools the sky so the warm artwork
/// does not tint the white page. Drift stops when the surface is hidden, backgrounded,
/// Reduce Motion is on, or Low Power Mode is on. The still frame is the start of the same loop.
struct KuroSceneryLoop: View {
    enum Tone {
        /// Accepted login welcome.
        case login
        /// Empty Home on the neutral canvas.
        case neutralCanvas
    }

    var tone: Tone = .login
    /// False when the parent has left the screen. Scene phase covers backgrounding.
    var isActive: Bool = true
    /// Pulls the ridge up into a tall cover. Login stays at 1.
    var magnify: CGFloat = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let tileWidth = height * 3.0
            let animates = isActive && KuroMotion.ambientDriftAllowed(
                reduceMotion: reduceMotion,
                lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                sceneIsActive: scenePhase == .active
            )
            Group {
                if animates {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                        strip(width: geo.size.width, height: height, tileWidth: tileWidth, shift: shift(tileWidth: tileWidth, date: context.date))
                    }
                } else {
                    strip(width: geo.size.width, height: height, tileWidth: tileWidth, shift: 0)
                }
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func shift(tileWidth: CGFloat, date: Date) -> CGFloat {
        let period: Double = 34
        let progress = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        return tileWidth * progress
    }

    private func strip(width: CGFloat, height: CGFloat, tileWidth: CGFloat, shift: CGFloat) -> some View {
        HStack(spacing: 0) {
            tile(width: tileWidth, height: height)
            tile(width: tileWidth, height: height)
        }
        .frame(width: width, height: height, alignment: .leading)
        .offset(x: -shift)
        .saturation(tone == .login ? 1.02 : 0.55)
        .overlay(toneOverlay)
    }

    private func tile(width: CGFloat, height: CGFloat) -> some View {
        Image("KuroZenMountains")
            .resizable()
            .scaledToFill()
            .scaleEffect(magnify, anchor: .bottom)
            .frame(width: width, height: height, alignment: .bottom)
            .clipped()
    }

    @ViewBuilder
    private var toneOverlay: some View {
        switch tone {
        case .login:
            LinearGradient(
                colors: [
                    Color.white.opacity(0.04),
                    Color.white.opacity(0.0),
                    Color.white.opacity(0.12)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .neutralCanvas:
            LinearGradient(
                colors: [
                    Color.white.opacity(0.02),
                    Color.clear,
                    Color.kuroCanvasPage.opacity(0.55)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}
