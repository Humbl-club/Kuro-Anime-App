import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// Drop-in replacement for `AsyncImage` with caching + de-dupe via `ImagePipeline`.
struct KuroCachedAsyncImage<Content: View>: View {
    private let url: URL?
    private let scale: CGFloat
    private let transaction: Transaction
    private let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase = .empty

    init(
        url: URL?,
        scale: CGFloat = 1.0,
        transaction: Transaction = Transaction(),
        @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
    ) {
        self.url = url
        self.scale = scale
        self.transaction = transaction
        self.content = content
    }

    init<I: View, P: View>(
        url: URL?,
        scale: CGFloat = 1.0,
        transaction: Transaction = Transaction(),
        @ViewBuilder content: @escaping (Image) -> I,
        @ViewBuilder placeholder: @escaping () -> P
    ) where Content == _ConditionalContent<I, P> {
        self.init(url: url, scale: scale, transaction: transaction) { phase in
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
                maxPx = 900 * scaleInt
#else
                maxPx = 900
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
