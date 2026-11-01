import SwiftUI

// MARK: - Motion effects (prototype-fidelity Task 3; PROTOTYPE_SPEC.md §3)
// Ports of the prototype's three keyframes and its count roll:
//   confirm   650 ms, `--ease` (.2,.8,.25,1): the ✓ cap pops in 0.8 → 1 by 20 %, holds to 65 %, fades.
//   restore   650 ms, plain `ease` (.25,.1,.25,1): the + cap is hidden until 65 %, then returns.
//   count     the live count roll (§3.2, §8.7): opacity .55 / y +2 → 1 / 0, 220 ms (.2,.75,.25,1);
//             the manga page turn: opacity .45, rotateX −48° (origin bottom) → 0, 280 ms.
// Every effect is one-shot on its trigger (nothing loops, nothing runs offscreen) and shows the
// composed final frame under Reduce Motion or Low Power Mode: the ✓ cap stays hidden, the + cap stays
// visible, the count sits still.

extension KuroMotion {
    /// True when decorative motion may play: neither Reduce Motion nor Low Power Mode is on. Pure.
    nonisolated static func playsMotion(reduceMotion: Bool, lowPower: Bool) -> Bool {
        !reduceMotion && !lowPower
    }

    /// `playsMotion` with Low Power Mode read now, for one-off animation sites (`withAnimation`,
    /// `.animation(_:value:)`) that re-evaluate on every change. Views whose motion runs on are
    /// wrapped in `KuroMotionAllowance` instead, which observes Low Power live.
    static func playsMotionNow(reduceMotion: Bool) -> Bool {
        playsMotion(reduceMotion: reduceMotion, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    /// CSS `cubic-bezier(.2,.8,.25,1)` (`--ease`) as a keyframe curve.
    static let easeCurve = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.2, y: 0.8),
                                            endControlPoint: UnitPoint(x: 0.25, y: 1))
    /// CSS `ease` (`cubic-bezier(.25,.1,.25,1)`), used by `restore`.
    static let cssEaseCurve = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.25, y: 0.1),
                                               endControlPoint: UnitPoint(x: 0.25, y: 1))
    /// The key press settle on save: `cubic-bezier(.2,.7,.3,1)`.
    static let pressSettleCurve = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.2, y: 0.7),
                                                   endControlPoint: UnitPoint(x: 0.3, y: 1))
    /// The count roll and section entrances: `cubic-bezier(.2,.75,.25,1)`.
    static let rollCurve = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.2, y: 0.75),
                                            endControlPoint: UnitPoint(x: 0.25, y: 1))
}

/// Hands its content whether decorative motion may play, from Reduce Motion and Low Power Mode.
/// Low Power Mode is observed live (an async notification sequence, no Combine), so turning it on
/// stops running motion at once.
struct KuroMotionAllowance<Content: View>: View {
    let content: (Bool) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    init(@ViewBuilder content: @escaping (Bool) -> Content) {
        self.content = content
    }

    var body: some View {
        content(KuroMotion.playsMotion(reduceMotion: reduceMotion, lowPower: lowPower))
            .task {
                for await _ in NotificationCenter.default.notifications(named: .NSProcessInfoPowerStateDidChange) {
                    lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
                }
            }
    }
}

extension View {
    /// The prototype's `confirm`: apply to the ✓ success cap. At rest (and under Reduce Motion or
    /// Low Power) the cap is hidden; each change of `trigger` pops it in, holds and fades it (650 ms).
    func kuroConfirmStamp<T: Equatable>(trigger: T) -> some View {
        modifier(KuroConfirmStampModifier(trigger: trigger))
    }

    /// The prototype's `restore`: apply to the + key cap. At rest it is visible; each change of
    /// `trigger` hides it while the ✓ shows and fades it back over the last 35 % (650 ms, CSS ease).
    func kuroRestore<T: Equatable>(trigger: T) -> some View {
        modifier(KuroRestoreModifier(trigger: trigger))
    }

    /// The count roll: each change of `value` rolls the number in (220 ms lift, or the manga Home's
    /// 280 ms page turn with `pageTurn: true`). Still under Reduce Motion or Low Power.
    func kuroCountRoll<V: Equatable>(value: V, pageTurn: Bool = false) -> some View {
        modifier(KuroCountRollModifier(value: value, pageTurn: pageTurn))
    }

    /// The key press settle on save (§3.2): scale 0.96 → 1 over 160 ms, `cubic-bezier(.2,.7,.3,1)`.
    func kuroPressSettle<T: Equatable>(trigger: T) -> some View {
        modifier(KuroPressSettleModifier(trigger: trigger))
    }
}

private struct KuroPressSettleModifier<T: Equatable>: ViewModifier {
    let trigger: T

    func body(content: Content) -> some View {
        KuroMotionAllowance { plays in
            if plays {
                content.keyframeAnimator(initialValue: CGFloat(1), trigger: trigger) { view, scale in
                    view.scaleEffect(scale)
                } keyframes: { _ in
                    KeyframeTrack {
                        MoveKeyframe(0.96)
                        LinearKeyframe(1, duration: 0.16, timingCurve: KuroMotion.pressSettleCurve)
                    }
                }
            } else {
                content
            }
        }
    }
}

private struct KuroConfirmFrame {
    var opacity: Double = 0
    var scale: CGFloat = 0.8
}

private struct KuroConfirmStampModifier<T: Equatable>: ViewModifier {
    let trigger: T

    func body(content: Content) -> some View {
        KuroMotionAllowance { plays in
            if plays {
                content.keyframeAnimator(initialValue: KuroConfirmFrame(), trigger: trigger) { view, frame in
                    view.opacity(frame.opacity).scaleEffect(frame.scale)
                } keyframes: { _ in
                    // 0 % → 20 % (130 ms) in, hold to 65 % (293 ms), fade to 100 % (227 ms).
                    // Each track starts from the keyframe's 0 % values, so a second +1 replays the
                    // whole pop instead of starting from the previous stamp's end (scale 1).
                    KeyframeTrack(\.opacity) {
                        MoveKeyframe(0)
                        LinearKeyframe(1, duration: 0.13, timingCurve: KuroMotion.easeCurve)
                        LinearKeyframe(1, duration: 0.2925)
                        LinearKeyframe(0, duration: 0.2275, timingCurve: KuroMotion.easeCurve)
                    }
                    KeyframeTrack(\.scale) {
                        MoveKeyframe(0.8)
                        LinearKeyframe(1, duration: 0.13, timingCurve: KuroMotion.easeCurve)
                        LinearKeyframe(1, duration: 0.52)
                    }
                }
            } else {
                // The final frame: the ✓ cap is hidden (the prototype hides it under reduced motion).
                content.opacity(0)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct KuroRestoreModifier<T: Equatable>: ViewModifier {
    let trigger: T

    func body(content: Content) -> some View {
        KuroMotionAllowance { plays in
            if plays {
                content.keyframeAnimator(initialValue: 1.0, trigger: trigger) { view, opacity in
                    view.opacity(opacity)
                } keyframes: { _ in
                    KeyframeTrack {
                        MoveKeyframe(0)
                        LinearKeyframe(0, duration: 0.4225)
                        LinearKeyframe(1, duration: 0.2275, timingCurve: KuroMotion.cssEaseCurve)
                    }
                }
            } else {
                content
            }
        }
    }
}

private struct KuroRollFrame {
    var opacity: Double = 1
    var offset: CGFloat = 0
    var tilt: Double = 0
}

private struct KuroCountRollModifier<V: Equatable>: ViewModifier {
    let value: V
    let pageTurn: Bool

    func body(content: Content) -> some View {
        KuroMotionAllowance { plays in
            if plays {
                content.keyframeAnimator(initialValue: KuroRollFrame(), trigger: value) { view, frame in
                    view
                        .opacity(frame.opacity)
                        .rotation3DEffect(.degrees(frame.tilt), axis: (x: 1, y: 0, z: 0),
                                          anchor: .bottom, perspective: 0.6)
                        .offset(y: frame.offset)
                } keyframes: { _ in
                    let duration = pageTurn ? 0.28 : 0.22
                    KeyframeTrack(\.opacity) {
                        MoveKeyframe(pageTurn ? 0.45 : 0.55)
                        LinearKeyframe(1, duration: duration, timingCurve: KuroMotion.rollCurve)
                    }
                    KeyframeTrack(\.offset) {
                        MoveKeyframe(2)
                        LinearKeyframe(0, duration: duration, timingCurve: KuroMotion.rollCurve)
                    }
                    KeyframeTrack(\.tilt) {
                        MoveKeyframe(pageTurn ? -48 : 0)
                        LinearKeyframe(0, duration: duration, timingCurve: KuroMotion.rollCurve)
                    }
                }
            } else {
                content
            }
        }
    }
}
