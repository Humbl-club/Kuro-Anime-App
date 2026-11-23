import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// Drop-in replacement for `AsyncImage` with caching + de-dupe via `ImagePipeline`.
struct KuroCachedAsyncImage<Content: View>: View {
    private let url: URL?
    private let scale: CGFloat
    private let transaction: Transaction
    // Max dimension in points; internally scaled by UIScreen scale.
    private let maxPixelSize: Int?
    private let content: (AsyncImagePhase) -> Content

    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: AsyncImagePhase = .empty

    init(
        url: URL?,
        scale: CGFloat = 1.0,
        transaction: Transaction = Transaction(),
        maxPixelSize: Int? = nil,
        @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
    ) {
        self.url = url
        self.scale = scale
        self.transaction = transaction
        self.maxPixelSize = maxPixelSize
        self.content = content
    }

    init<I: View, P: View>(
        url: URL?,
        scale: CGFloat = 1.0,
        transaction: Transaction = Transaction(),
        maxPixelSize: Int? = nil,
        @ViewBuilder content: @escaping (Image) -> I,
        @ViewBuilder placeholder: @escaping () -> P
    ) where Content == _ConditionalContent<I, P> {
        self.init(url: url, scale: scale, transaction: transaction, maxPixelSize: maxPixelSize) { phase in
            switch phase {
            case .success(let image):
                content(image)
            default:
                placeholder()
            }
        }
    }

    private var resolvedMaxPixelSize: Int {
#if canImport(UIKit)
        let scaleInt = max(1, Int(displayScale))
        return (maxPixelSize ?? 900) * scaleInt
#else
        return maxPixelSize ?? 900
#endif
    }

    private var effectivePhase: AsyncImagePhase {
        if case .success = phase { return phase }
#if canImport(UIKit)
        if let url, let cached = ImagePipeline.shared.cachedImageSync(url: url, maxPixelSize: resolvedMaxPixelSize) {
            return .success(Image(uiImage: cached))
        }
#endif
        return phase
    }

    var body: some View {
        content(effectivePhase)
            .task(id: url) {
                guard let url else {
                    phase = .empty
                    return
                }

                let maxPx = resolvedMaxPixelSize
#if canImport(UIKit)
                if let cached = ImagePipeline.shared.cachedImageSync(url: url, maxPixelSize: maxPx) {
                    phase = .success(Image(uiImage: cached))
                    return
                }
#endif

                let started = ContinuousClock.now
                let ui = await ImagePipeline.shared.image(url: url, maxPixelSize: maxPx)
                let shouldCrossfade = (ContinuousClock.now - started) >= .milliseconds(16) && !reduceMotion
#if canImport(UIKit)
                if let ui {
                    let img = Image(uiImage: ui)
                    if shouldCrossfade {
                        var crossfadeTransaction = transaction
                        if crossfadeTransaction.animation == nil {
                            crossfadeTransaction.animation = .easeOut(duration: 0.18)
                        }
                        withTransaction(crossfadeTransaction) {
                            phase = .success(img)
                        }
                    } else {
                        withTransaction(transaction) {
                            phase = .success(img)
                        }
                    }
                } else {
                    withTransaction(transaction) {
                        phase = .failure(URLError(.cannotDecodeContentData))
                    }
                }
#else
                _ = ui
#endif
            }
    }
}
