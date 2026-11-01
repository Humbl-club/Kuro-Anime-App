//
//  ArtworkMaterialStore.swift
//  Kuro
//
//  Serves each artwork's material (`ArtworkMaterial`): the AniList seed colour at once (first paint),
//  then the material derived on device from the artwork itself, published when ready so views
//  crossfade to it. Cached per image URL in memory and on disk (Caches), so a title derives once per
//  install. Built once by `AppComposition` and read with `@Environment(ArtworkMaterialStore.self)`.
//
//  The image is loaded through the shared `ImagePipeline` (no second network path). A URL whose image
//  fails to load or decode keeps its seed (or the neutral base) and is not retried until the memory
//  cache is trimmed. Loading, decoding, derivation and disk IO run off the main actor.
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
    private var derived: [URL: ArtworkMaterial] = [:]
    /// URLs being loaded or derived (not observed: written while a view body runs).
    @ObservationIgnored private var inFlight: Set<URL> = []
    /// URLs whose image failed; they keep the seed until the memory cache is trimmed.
    @ObservationIgnored private var failed: Set<URL> = []
    @ObservationIgnored private let cacheDirectory: URL?
    @ObservationIgnored private let loader: Loader

    /// The most derived materials kept in memory (each is a few hundred bytes).
    static let memoryLimit = 600
    /// The disk cache folder in Caches (versioned with the algorithm).
    nonisolated static let defaultCacheFolder = "ArtworkMaterials-art-hue-v1"

    /// `cacheDirectory` nil keeps the cache in memory only; `loader` defaults to the shared image pipeline.
    init(
        cacheDirectory: URL? = ArtworkMaterialStore.defaultCacheDirectory(),
        loader: @escaping Loader = ArtworkMaterialStore.pipelineLoader
    ) {
        self.cacheDirectory = cacheDirectory
        self.loader = loader
    }

    /// The material for the artwork at `url`: the derived material when it is ready, otherwise the
    /// clamped `seedHex` (AniList `cover_image_color`; nil gives the neutral #3a3d3c base). The first
    /// call for a URL starts the derivation; the result is published to observing views.
    func material(for url: URL?, seedHex: String?) -> ArtworkMaterial {
        guard let url else { return ArtworkMaterial.fromHex(seedHex) }
        if let material = derived[url] { return material }
        if !failed.contains(url), !inFlight.contains(url) { start(url) }
        return ArtworkMaterial.fromHex(seedHex)
    }

    /// Drops the in-memory materials and failure marks. The disk cache stays. The store is not on the
    /// memory-pressure list: it holds at most `memoryLimit` small values.
    func trimMemory() {
        derived.removeAll()
        failed.removeAll()
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
            failed.insert(url)
            return
        }
        if derived.count >= Self.memoryLimit { derived.removeAll(keepingCapacity: true) }
        derived[url] = material
    }

    /// The disk-cached material, else the material derived from the loaded image (then written to disk).
    nonisolated private static func resolve(url: URL, file: URL?, banner: Bool, loader: Loader) async -> ArtworkMaterial? {
        if let file, let data = try? Data(contentsOf: file),
           let cached = try? JSONDecoder().decode(ArtworkMaterial.self, from: data),
           cached.method == "art-hue-v1" {
            return cached
        }
        guard !Task.isCancelled, let image = await loader(url) else { return nil }
        let material = ArtworkMaterial.derive(from: image, banner: banner)
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
