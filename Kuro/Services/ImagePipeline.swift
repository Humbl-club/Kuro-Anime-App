import Foundation
import OSLog

#if canImport(UIKit)
import UIKit
import ImageIO
#endif

// Lightweight image pipeline:
// - in-memory cache (NSCache)
// - URLCache-backed disk cache via URLRequest cachePolicy
// - de-dup in-flight requests
//
// Intentionally minimal (no third-party dependency) to keep the app snappy.
actor ImagePipeline {
    static let shared = ImagePipeline()

#if canImport(UIKit)
    private let memory = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Kuro", category: "image")
    private let maxPrefetchFanout = 12
    private let maxDecodePixelSize = 1200
    private let minDecodePixelSize = 180

    init() {
        // ~80MB in-memory images (roughly, cost is RGBA bytes).
        memory.totalCostLimit = 80 * 1024 * 1024
    }

    func prefetch(urls: [URL], maxPixelSize: Int? = nil) {
        let clampedPixelSize = clampPixelSize(maxPixelSize)
        var queued = 0
        var seen: Set<URL> = []
        let uniqueUrls = urls.filter { seen.insert($0).inserted }
        for url in uniqueUrls {
            if queued >= maxPrefetchFanout { break }
            if memory.object(forKey: url as NSURL) != nil { continue }
            if inFlight[url] != nil { continue }
            let task = makeLoadTask(url: url, maxPixelSize: clampedPixelSize)
            inFlight[url] = task
            queued += 1
        }
    }

    func image(url: URL, maxPixelSize: Int? = nil) async -> UIImage? {
        let clampedPixelSize = clampPixelSize(maxPixelSize)
        if let cached = memory.object(forKey: url as NSURL) {
            log.debug("mem hit \(url.absoluteString, privacy: .private(mask: .hash))")
            return cached
        }
        if let task = inFlight[url] { return await task.value }

        let task = makeLoadTask(url: url, maxPixelSize: clampedPixelSize)
        inFlight[url] = task
        return await task.value
    }

    private func makeLoadTask(url: URL, maxPixelSize: Int?) -> Task<UIImage?, Never> {
        Task<UIImage?, Never> { [weak self] in
            guard let self else { return nil }
            let image = await self.load(url: url, maxPixelSize: maxPixelSize)
            await self.finishInFlight(url: url)
            return image
        }
    }

    private func finishInFlight(url: URL) {
        inFlight[url] = nil
    }

    private func load(url: URL, maxPixelSize: Int?) async -> UIImage? {
        let perf = KuroPerf.begin("image.load")
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 20
        let decodePixelSize = clampPixelSize(maxPixelSize)

        // Fast path: decode from URLCache first to avoid network/decode jitter.
        if let cached = URLCache.shared.cachedResponse(for: request),
           let image = decodeImage(data: cached.data, maxPixelSize: decodePixelSize) {
            let cost = imageCostBytes(image)
            memory.setObject(image, forKey: url as NSURL, cost: cost)
            KuroPerf.end(perf, message: "disk cache hit")
            return image
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) == false {
                KuroPerf.end(perf, message: "http \(http.statusCode)")
                return nil
            }

            let image = decodeImage(data: data, maxPixelSize: decodePixelSize)

            guard let image else {
                KuroPerf.end(perf, message: "decode failed")
                return nil
            }

            // Populate URLCache explicitly so other call sites benefit too.
            let cached = CachedURLResponse(response: response, data: data)
            URLCache.shared.storeCachedResponse(cached, for: request)

            let cost = imageCostBytes(image)
            memory.setObject(image, forKey: url as NSURL, cost: cost)
            KuroPerf.end(perf, message: "ok")
            return image
        } catch {
            KuroPerf.end(perf, message: "error")
            return nil
        }
    }

    private func clampPixelSize(_ requested: Int?) -> Int? {
        guard let requested else { return nil }
        return min(maxDecodePixelSize, max(minDecodePixelSize, requested))
    }

    private func decodeImage(data: Data, maxPixelSize: Int?) -> UIImage? {
        if let maxPixelSize {
            return downsample(data: data, maxPixelSize: maxPixelSize)
        }
        return UIImage(data: data)
    }

    private func imageCostBytes(_ image: UIImage) -> Int {
        let px = Int(image.size.width * image.scale) * Int(image.size.height * image.scale)
        return max(1, px * 4)
    }

    private func downsample(data: Data, maxPixelSize: Int) -> UIImage? {
        guard maxPixelSize > 0 else { return UIImage(data: data) }
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceTypeIdentifierHint: "public.jpeg"
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            return UIImage(data: data)
        }
        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cg)
    }
#else
    // Non-UIKit platforms (not expected for this app).
    func prefetch(urls: [URL], maxPixelSize: Int? = nil) {}
#endif
}
