//
//  ArtworkMaterialStore.swift
//  Kuro
//
//  Serves each artwork's material (`ArtworkMaterial`): the AniList seed colour at once (first paint),
//  then the material derived on device from the artwork itself, published when ready so views
//  crossfade to it. Cached per image URL in memory and on disk (Caches), so a title derives once per
//  install. Built once by `AppComposition` and read with `@Environment(ArtworkMaterialStore.self)`.
//
//  The image is loaded through the shared `ImagePipeline` (no second network path) at its 360 px decode
//  bucket, and derived from that thumbnail, not the full-size file: the port's own 64×96 / 104×32
//  downsample follows it. For nearly every artwork this lands in the same hue bin as the full-size
//  reference (pinned by `ArtworkMaterialTests.thumbnailDecodeMatchesReference`); a cover whose two
//  strongest bins are almost tied can flip to the neighbour bin (measured: `journal-manga-23-cover.jpg`,
//  #493431 full size vs #493134 at 360 px). Accepted: the decode stays small and the material stays a
//  close, contrast-safe tint of the artwork.
//
//  Artwork with no qualifying hue (greyscale, black-and-white manga covers) keeps the AniList seed (or
//  the neutral base): the store never publishes the port's invented hue .4. That decision is cached
//  like a material (`method == "no-hue"`).
//
//  A URL whose image fails to load or decode keeps its seed (or the neutral base) and is tried again
//  after `failureRetryInterval` (60 s), so an offline launch recovers once the connection is back. The
//  memory cache keeps the `memoryLimit` most recent materials and evicts the oldest first. Loading,
//  decoding, derivation and disk IO run off the main actor.
//

import CoreGraphics
import CryptoKit
import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class ArtworkMaterialStore {
    /// Loads the artwork for `url` (nil: failed). Runs off the main actor.
    typealias Loader = @Sendable (URL) async -> CGImage?

    /// The derived materials published so far, by image URL (the observed state views re-render on).
    /// A `no-hue` entry means "keep the seed".
    private var derived: [URL: ArtworkMaterial] = [:]
    /// `derived`'s keys, oldest first (eviction order).
    @ObservationIgnored private var order: [URL] = []
    /// URLs being loaded or derived (not observed: written while a view body runs).
    @ObservationIgnored private var inFlight: Set<URL> = []
    /// URLs whose image failed, with the time of the failure; retried after `failureRetryInterval`.
    @ObservationIgnored private var failed: [URL: Date] = [:]
    @ObservationIgnored private let cacheDirectory: URL?
    @ObservationIgnored private let loader: Loader
    @ObservationIgnored private let memoryLimit: Int
    @ObservationIgnored private let failureRetryInterval: TimeInterval
    @ObservationIgnored private let now: () -> Date

    /// The most derived materials kept in memory by default (each is a few hundred bytes).
    static let defaultMemoryLimit = 600
    /// The disk cache folder in Caches (versioned with the algorithm).
    nonisolated static let defaultCacheFolder = "ArtworkMaterials-art-hue-v1"
    /// The marker method for artwork without a qualifying hue (keep the seed).
    nonisolated static let noHueMethod = "no-hue"

    /// `cacheDirectory` nil keeps the cache in memory only; `loader` defaults to the shared image pipeline.
    /// `memoryLimit`, `failureRetryInterval` and `now` are injectable for tests.
    init(
        cacheDirectory: URL? = ArtworkMaterialStore.defaultCacheDirectory(),
        memoryLimit: Int = ArtworkMaterialStore.defaultMemoryLimit,
        failureRetryInterval: TimeInterval = 60,
        now: @escaping () -> Date = Date.init,
        loader: @escaping Loader = ArtworkMaterialStore.pipelineLoader
    ) {
        self.cacheDirectory = cacheDirectory
        self.memoryLimit = max(1, memoryLimit)
        self.failureRetryInterval = failureRetryInterval
        self.now = now
        self.loader = loader
    }

    /// The material for the artwork at `url`: the derived material when it is ready, otherwise the
    /// clamped `seedHex` (AniList `cover_image_color`; nil gives the neutral #3a3d3c base). The first
    /// call for a URL starts the derivation; the result is published to observing views. Artwork
    /// without a qualifying hue keeps the seed.
    func material(for url: URL?, seedHex: String?) -> ArtworkMaterial {
        guard let url else { return ArtworkMaterial.fromHex(seedHex) }
        if let material = derived[url] {
            return material.method == Self.noHueMethod ? ArtworkMaterial.fromHex(seedHex) : material
        }
        if !inFlight.contains(url), canRetry(url) { start(url) }
        return ArtworkMaterial.fromHex(seedHex)
    }

    /// True when `url` never failed, or failed at least `failureRetryInterval` ago.
    private func canRetry(_ url: URL) -> Bool {
        guard let failedAt = failed[url] else { return true }
        return now().timeIntervalSince(failedAt) >= failureRetryInterval
    }

    // MARK: - Derivation

    private func start(_ url: URL) {
        inFlight.insert(url)
        let loader = loader
        let file = Self.cacheFile(for: url, in: cacheDirectory)
        let banner = Self.isBanner(url)
        Task { [weak self] in
            let material = await Task.detached(priority: .utility) {
                await Self.resolve(url: url, file: file, banner: banner, loader: loader)
            }.value
            self?.finish(url, material: material)
        }
    }

    private func finish(_ url: URL, material: ArtworkMaterial?) {
        inFlight.remove(url)
        guard let material else {
            failed[url] = now()
            return
        }
        failed[url] = nil
        // Oldest first, one at a time, so visible cards never all snap back to their seed together.
        while derived.count >= memoryLimit, !order.isEmpty {
            derived[order.removeFirst()] = nil
        }
        derived[url] = material
        order.append(url)
    }

    /// The disk-cached material, else the material derived from the loaded image (then written to disk).
    /// No qualifying hue gives the `no-hue` marker (cached too). Nil: the image did not load.
    nonisolated private static func resolve(url: URL, file: URL?, banner: Bool, loader: Loader) async -> ArtworkMaterial? {
        if let file, let data = try? Data(contentsOf: file),
           let cached = try? JSONDecoder().decode(ArtworkMaterial.self, from: data),
           cached.method == "art-hue-v1" || cached.method == noHueMethod {
            return cached
        }
        guard !Task.isCancelled, let image = await loader(url) else { return nil }
        let material = ArtworkMaterial.deriveIfHued(from: image, banner: banner)
            ?? ArtworkMaterial(base: ArtworkMaterial.neutralBase, method: noHueMethod)
        if let file, let data = try? JSONEncoder().encode(material) {
            try? FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try? data.write(to: file, options: .atomic)
        }
        return material
    }

    // MARK: - Helpers

    /// Wide banner art (AniList `…/banner/…`) takes the 104×32 crop; everything else is a poster.
    nonisolated static func isBanner(_ url: URL) -> Bool {
        url.path.lowercased().contains("banner")
    }

    /// `Caches/ArtworkMaterials-art-hue-v1`, or nil when Caches is unavailable.
    nonisolated static func defaultCacheDirectory() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(defaultCacheFolder, isDirectory: true)
    }

    /// One JSON file per image URL, named by the URL's SHA-256 (stable across launches).
    nonisolated static func cacheFile(for url: URL, in directory: URL?) -> URL? {
        guard let directory else { return nil }
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(name).json")
    }

    /// The production loader: the shared image pipeline at a small decode bucket.
    nonisolated static let pipelineLoader: Loader = { url in
        await ImagePipeline.shared.image(url: url, maxPixelSize: 360)?.cgImage
    }
}
