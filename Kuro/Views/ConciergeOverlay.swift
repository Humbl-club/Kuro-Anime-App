import SwiftUI

// Custom "expanding glass" presentation for Concierge.
// This replaces the default sheet so it feels premium and instantaneous.
struct ConciergeOverlay: View {
    @Binding var isPresented: Bool
    let originFrame: CGRect

    @State private var openT: CGFloat = 0
    @State private var dragOffsetY: CGFloat = 0
    @State private var heightFraction: CGFloat = 0.62
    @State private var sheenPhase: Bool = false
    @State private var dismissTask: Task<Void, Never>? = nil

    private let minFraction: CGFloat = 0.62
    private let maxFraction: CGFloat = 0.92

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let targetHeight = size.height * heightFraction
            let targetFrame = CGRect(
                x: 12,
                y: max(10, size.height - targetHeight - 10),
                width: size.width - 24,
                height: targetHeight
            )

            let from = originFrame == .zero
                ? CGRect(x: size.width - 52, y: 52, width: 32, height: 32)
                : originFrame

            // Interpolate between the icon frame and the bottom panel.
            let frame = lerp(from: from, to: targetFrame, t: openT)
            let radius = lerp(a: 16, b: 28, t: openT)

            let dismissT = min(1, max(0, dragOffsetY / 220))
            let bgOpacity = 0.18 * Double(openT) * (1.0 - Double(dismissT))

            ZStack {
                // Dim layer (keep it lightweight; full-screen material can get janky in Debug/Simulator).
                Rectangle()
                    .fill(Color.black.opacity(bgOpacity))
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }

                // The expanding glass panel.
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.75), Color.white.opacity(0.16), Color.black.opacity(0.06)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.9
                                )
                        )
                        .overlay(
                            // Sheen.
                            LinearGradient(
                                colors: [Color.white.opacity(0.60), Color.white.opacity(0.0)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .frame(width: frame.width * 0.7, height: frame.height * 0.45)
                            .rotationEffect(.degrees(-22))
                            .offset(
                                x: frame.width * (sheenPhase ? 0.24 : 0.16),
                                y: -frame.height * (sheenPhase ? 0.15 : 0.10)
                            )
                            .blendMode(.screen)
                            .opacity(0.55 * openT)
                            .allowsHitTesting(false)
                        )
                        .shadow(color: Color.black.opacity(0.10 * Double(openT)), radius: 26, x: 0, y: 16)

                    if openT > 0.98 {
                        // Content only after the expansion finishes (prevents weird layout during morph).
                        VStack(spacing: 0) {
                            // Drag handle (keeps gestures away from controls so taps always work).
                            Capsule(style: .continuous)
                                .fill(Color.black.opacity(0.16))
                                .frame(width: 44, height: 5)
                                .padding(.top, 8)
                                .padding(.bottom, 6)
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                                .highPriorityGesture(panelDrag(screenSize: size))

                            header
                                .padding(.horizontal, 14)
                                .padding(.bottom, 8)

                            Divider()
                                .opacity(0.10)

                            ConciergeView(assistantEnabled: false)
                        }
                        .transition(.opacity)
                    }
                }
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
                .offset(y: dragOffsetY)
                .scaleEffect(1.0 - 0.02 * dismissT)
            }
            .onAppear {
                heightFraction = minFraction
                dragOffsetY = 0
                withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.86)) {
                    openT = 1
                }
                withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                    sheenPhase = true
                }
            }
            .onDisappear {
                dismissTask?.cancel()
                dismissTask = nil
            }
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 10) {
            KuroChanMascot(size: 26, style: .refined, showsSparkle: false, animates: true, showsShadow: false)
            VStack(alignment: .leading, spacing: 1) {
                Text("KURO-CHAN")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1.9)
                    .foregroundColor(.black.opacity(0.82))
                Text("Concierge")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.black.opacity(0.55))
            }
            Spacer(minLength: 0)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.black.opacity(0.62))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(0.30)))
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .zIndex(10)
        }
        .contentShape(Rectangle())
    }

    private func panelDrag(screenSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in
                let dy = value.translation.height
                let dx = value.translation.width
                // Ignore diagonal "swipes" so it doesn't fight horizontal paging.
                guard abs(dy) > abs(dx) * 0.9 else { return }

                if dy < 0 {
                    // Drag up: expand.
                    let amt = min(1, max(0, (-dy) / 220))
                    heightFraction = min(maxFraction, minFraction + (maxFraction - minFraction) * amt)
                    dragOffsetY = 0
                } else {
                    // Drag down: dismiss affordance.
                    dragOffsetY = min(320, dy)
                }
            }
            .onEnded { value in
                let dy = value.translation.height
                if dy > 140 {
                    dismiss()
                    return
                }
                withAnimation(.interactiveSpring(response: 0.26, dampingFraction: 0.88)) {
                    dragOffsetY = 0
                    // Snap expanded/collapsed.
                    if dy < -120 {
                        heightFraction = maxFraction
                    } else {
                        heightFraction = minFraction
                    }
                }
            }
    }

    private func dismiss() {
        dismissTask?.cancel()
        withAnimation(.interactiveSpring(response: 0.30, dampingFraction: 0.92)) {
            openT = 0
            dragOffsetY = 0
        }
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 240_000_000)
            if !Task.isCancelled {
                isPresented = false
            }
        }
    }

    private func lerp(from a: CGRect, to b: CGRect, t: CGFloat) -> CGRect {
        CGRect(
            x: lerp(a: a.origin.x, b: b.origin.x, t: t),
            y: lerp(a: a.origin.y, b: b.origin.y, t: t),
            width: lerp(a: a.size.width, b: b.size.width, t: t),
            height: lerp(a: a.size.height, b: b.size.height, t: t)
        )
    }

    private func lerp(a: CGFloat, b: CGFloat, t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }
}
