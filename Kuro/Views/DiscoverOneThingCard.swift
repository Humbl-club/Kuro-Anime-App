import SwiftUI

// MARK: - The One Thing (Discover P1)
// The magazine cover: one boosted title per day. Hero grammar (ADR 2026-07-31
// H1): full-bleed art + grain + dual gradient + bottom-pinned monochrome glass
// carrying a tracked eyebrow, serif title and the 2-3 sentence argument.
// Crop: fixed 4:5 (height = width x 1.25). Between the proposal's 4:5..16:10
// bounds; tall enough for the glass panel over banners (wide) and covers
// (portrait) alike, and it matches the editorial cover feel better than a
// cinematic strip. Tap routes to the standard MediaDetailSheet.

struct DiscoverOneThingCard: View {
    let feature: DailyFeature
    let width: CGFloat

    @State private var showDetail = false
    @State private var isPressed = false
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps

    private var height: CGFloat {
        floor(width * 1.25) // 4:5 crop — see header note
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Art (H4 placeholder spec: secondary background + shimmer + 0.2s fade-in)
            KuroCachedAsyncImage(
                url: feature.artURL,
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
            .frame(width: width, height: height)
            .clipped()

            // Grain (club-hero recipe)
            Rectangle()
                .fill(Color.kuroWhite04)
                .blendMode(.overlay)
                .allowsHitTesting(false)

            // Dual gradient: legibility bottom (behind the glass)…
            LinearGradient(
                colors: [Color.kuroBlack65, Color.kuroBlack25, Color.clear],
                startPoint: .bottom,
                endPoint: .top
            )
            .frame(height: height * 0.58)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)

            // …vignette top.
            LinearGradient(
                colors: [Color.kuroBlack35, Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 96)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)

            // Bottom-pinned glass card
            KuroGlassCard(tone: .onImage) {
                VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                    HStack(alignment: .center) {
                        Text("THE ONE THING")
                            .font(.kuroMicro(weight: .medium))
                            .tracking(1.8)
                            .foregroundColor(.kuroWhite80)

                        Spacer(minLength: KuroDesignSpacing.sm)

                        Image(systemName: "chevron.right")
                            .font(.kuroCaption(weight: .semibold))
                            .foregroundColor(.kuroWhite60)
                    }

                    Text(feature.title)
                        .font(.kuroHeadline(weight: .light))
                        .foregroundColor(.kuroWhite)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if let argument = feature.argument, !argument.isEmpty {
                        Text(argument)
                            .font(.kuroBody(weight: .light))
                            .foregroundColor(.kuroWhite80)
                            .lineLimit(5)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, KuroDesignSpacing.md)
                .padding(.vertical, KuroDesignSpacing.md)
            }
            .padding(.horizontal, KuroDesignSpacing.md)
            .padding(.bottom, KuroDesignSpacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: KuroRadius.lg, style: .continuous))
        .contentShape(Rectangle())
        .kuroDeliberateTap {
            guard !suppressCardTaps else { return }
            KuroAccessibility.impactHaptic(.light)
            showDetail = true
        }
        .scaleEffect(isPressed ? 0.99 : 1.0)
        .kuroAnimation(KuroAnimation.editorial, value: isPressed)
        .pressable($isPressed, duration: 0.15)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("The One Thing. \(feature.title)"))
        .accessibilityHint("Opens details")
        .accessibilityAddTraits(.isButton)
        .sheet(isPresented: $showDetail) {
            MediaDetailSheet(kind: feature.kind, id: feature.mediaId)
        }
    }
}

// MARK: - Skeleton (H4: shimmer while the daily feature RPC is in flight)
struct DiscoverOneThingSkeleton: View {
    let width: CGFloat

    private var height: CGFloat {
        floor(width * 1.25)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: KuroRadius.lg, style: .continuous)
            .fill(Color.kuroSecondaryBackground)
            .frame(width: width, height: height)
            .kuroShimmer()
    }
}
