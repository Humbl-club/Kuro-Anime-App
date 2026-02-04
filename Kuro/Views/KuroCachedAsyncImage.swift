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

    var body: some View {
        content(phase)
            .task(id: url) {
                guard let url else {
                    phase = .empty
                    return
                }

                // Estimate a reasonable decode size; most covers are portrait.
                let maxPx: Int
#if canImport(UIKit)
                let scaleInt = max(1, Int(UIScreen.main.scale))
                // `maxPixelSize` is interpreted in points; convert to pixels for downsampling.
                maxPx = (maxPixelSize ?? 900) * scaleInt
#else
                maxPx = maxPixelSize ?? 900
#endif

                let ui = await ImagePipeline.shared.image(url: url, maxPixelSize: maxPx)
#if canImport(UIKit)
                if let ui {
                    let img = Image(uiImage: ui)
                    withTransaction(transaction) {
                        phase = .success(img)
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
