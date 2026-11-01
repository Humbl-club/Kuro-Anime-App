import Foundation
import OSLog

#if canImport(UIKit)
import UIKit
import ImageIO
#endif

// Lightweight image pipeline:
// - in-memory cache (NSCache), keyed by URL AND decode size: one URL decoded for a 120 pt thumbnail
//   and for a 1200 px hero are two entries, and a request is served only by a decode of its own size
//   bucket or larger (never by a smaller one, which would look soft), or by the full image
// - URLCache-backed disk cache via URLRequest cachePolicy (the bytes are shared by every size)
// - de-dup in-flight requests (a request joins a running decode of its size or larger)
// - prefetch decodes at card size (`defaultPrefetchPixelSize`) unless the caller names a size, so a
//   rail prefetch no longer fills the memory cache with full-resolution decodes
//
// Intentionally minimal (no third-party dependency) to keep the app snappy.
actor ImagePipeline {
    static let shared = ImagePipeline()

    // MARK: Size buckets and cache keys (pure; tested)

    /// Decode sizes (longest side, pixels). A requested size rounds UP to the next bucket, so nearby
    /// requests share one decode. The last bucket equals the decode cap.
    nonisolated static let pixelBuckets: [Int] = [180, 240, 360, 480, 640, 900, 1200]
    /// Smallest and largest decode size; requests are clamped into this range first.
    nonisolated static let minDecodePixelSize = 180
    nonisolated static let maxDecodePixelSize = 1200
    /// The decode size of a prefetch that names none: a standard card (300 pt at 3x).
    nonisolated static let defaultPrefetchPixelSize = 900

    /// The bucket a request decodes at: nil (full image) stays nil; otherwise the requested size is
    /// clamped to [min, max] and rounded up to the next bucket.
    nonisolated static func pixelBucket(for requested: Int?) -> Int? {
        guard let requested else { return nil }
        let clamped = min(maxDecodePixelSize, max(minDecodePixelSize, requested))
        return pixelBuckets.first { $0 >= clamped } ?? maxDecodePixelSize
    }

    /// The memory/in-flight key of one decode: the URL plus its bucket ("#full" for an undownsampled
    /// decode, which serves every size).
    nonisolated static func cacheKey(url: URL, bucket: Int?) -> String {
        "\(url.absoluteString)#\(bucket.map { "px\($0)" } ?? "full")"
    }

    /// The keys that may serve a request of `bucket`, best first: the exact bucket, then every larger
    /// bucket, then the full image. A full-image request is served only by a full decode.
    nonisolated static func servingKeys(url: URL, bucket: Int?) -> [String] {
        guard let bucket else { return [cacheKey(url: url, bucket: nil)] }
        let candidates = pixelBuckets.filter { $0 >= bucket }
        return candidates.map { cacheKey(url: url, bucket: $0) } + [cacheKey(url: url, bucket: nil)]
    }

    /// The bucket a finished decode is stored under: when the source was smaller than the requested
    /// bucket the decode IS the full image (downsampling never upscales), so it is stored as "full" and
    /// serves every later request of that URL.
    nonisolated static func storageBucket(requested bucket: Int?, decodedLongestSide: Int) -> Int? {
        guard let bucket else { return nil }
        return decodedLongestSide < bucket ? nil : bucket
    }

#if canImport(UIKit)
    private let memory = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Kuro", category: "image")
    private let maxPrefetchFanout = 12
    private let maxInFlightCap = 40

    init() {
        // ~80MB in-memory images (roughly, cost is RGBA bytes).
        memory.totalCostLimit = 80 * 1024 * 1024
    }

    func clearMemoryCache() {
        memory.removeAllObjects()
    }

    /// Warms the caches for `urls` (at most `maxPrefetchFanout` new loads per call). `maxPixelSize`
    /// nil decodes at card size (`defaultPrefetchPixelSize`), not at full resolution.
    func prefetch(urls: [URL], maxPixelSize: Int? = nil) {
        let bucket = Self.pixelBucket(for: maxPixelSize ?? Self.defaultPrefetchPixelSize)
        var queued = 0
        var seen: Set<URL> = []
        let uniqueUrls = urls.filter { seen.insert($0).inserted }
        for url in uniqueUrls {
            if queued >= maxPrefetchFanout { break }
            if inFlight.count >= maxInFlightCap { break }
            if cachedImage(url: url, bucket: bucket) != nil { continue }
            if runningTask(url: url, bucket: bucket) != nil { continue }
            let key = Self.cacheKey(url: url, bucket: bucket)
            inFlight[key] = makeLoadTask(url: url, bucket: bucket, key: key)
            queued += 1
        }
    }

    func image(url: URL, maxPixelSize: Int? = nil) async -> UIImage? {
        let bucket = Self.pixelBucket(for: maxPixelSize)
        if let cached = cachedImage(url: url, bucket: bucket) {
            log.debug("mem hit \(url.absoluteString, privacy: .private(mask: .hash))")
            return cached
        }
        if let task = runningTask(url: url, bucket: bucket) { return await task.value }
        let key = Self.cacheKey(url: url, bucket: bucket)
        await waitForInFlightSlot(for: key)
        if let cached = cachedImage(url: url, bucket: bucket) {
            log.debug("mem hit after wait \(url.absoluteString, privacy: .private(mask: .hash))")
            return cached
        }
        if let task = runningTask(url: url, bucket: bucket) { return await task.value }

        let task = makeLoadTask(url: url, bucket: bucket, key: key)
        inFlight[key] = task
        return await task.value
    }

    /// The best cached decode that may serve `bucket` (same size or larger, or the full image).
    private func cachedImage(url: URL, bucket: Int?) -> UIImage? {
        for key in Self.servingKeys(url: url, bucket: bucket) {
            if let image = memory.object(forKey: key as NSString) { return image }
        }
        return nil
    }

    /// A running decode that may serve `bucket`.
    private func runningTask(url: URL, bucket: Int?) -> Task<UIImage?, Never>? {
        for key in Self.servingKeys(url: url, bucket: bucket) {
            if let task = inFlight[key] { return task }
        }
        return nil
    }

    private func makeLoadTask(url: URL, bucket: Int?, key: String) -> Task<UIImage?, Never> {
        Task<UIImage?, Never> { [weak self] in
            guard let self else { return nil }
            let image = await self.load(url: url, maxPixelSize: bucket)
            await self.finishInFlight(key: key)
            return image
        }
    }

    private func finishInFlight(key: String) {
        inFlight[key] = nil
    }

    private func waitForInFlightSlot(for key: String) async {
        while inFlight.count >= maxInFlightCap && inFlight[key] == nil {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
    }

    /// Stores a finished decode under its storage bucket (see `storageBucket`).
    private func store(_ image: UIImage, url: URL, requested bucket: Int?) {
        let longest = Int(max(image.size.width, image.size.height) * image.scale)
        let key = Self.cacheKey(url: url, bucket: Self.storageBucket(requested: bucket, decodedLongestSide: longest))
        memory.setObject(image, forKey: key as NSString, cost: imageCostBytes(image))
    }

    private func load(url: URL, maxPixelSize: Int?) async -> UIImage? {
        let perf = KuroPerf.begin("image.load")
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 20
        let decodePixelSize = maxPixelSize

        // Fast path: decode from URLCache first to avoid network/decode jitter.
        if let cached = URLCache.shared.cachedResponse(for: request),
           let image = decodeImage(data: cached.data, maxPixelSize: decodePixelSize) {
            store(image, url: url, requested: maxPixelSize)
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

            store(image, url: url, requested: maxPixelSize)
            KuroPerf.end(perf, message: "ok")
            return image
        } catch {
            KuroPerf.end(perf, message: "error")
            return nil
        }
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
