//
//  ArtworkMaterialTests.swift
//  KuroTests
//
//  Prototype-fidelity Task 2: the on-device port of the prototype's `art-hue-v1` artwork material
//  (`tools/design-directions/build_art_materials.py`, `material()`), the AniList seed colour path
//  (`fromHex`), and the cached store that serves the seed first and the derived material after.
//  Reference values come from the prototype's generated `instrument-art-materials.js`.
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Kuro

@Suite("Artwork material (art-hue-v1 port)", .timeLimit(.minutes(1)))
struct ArtworkMaterialTests {
    /// `tools/design-directions/assets/<name>`, read straight from the repo checkout.
    static func prototypeAsset(_ name: String) throws -> CGImage {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tools/design-directions/assets/\(name)")
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil), "missing \(url.path)")
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    /// Each channel of `hex` within `tolerance` 8-bit steps of `expected`.
    static func close(_ rgb: KuroRGB, _ expected: String, tolerance: Int = 2) -> Bool {
        guard let want = KuroRGB(hex: expected) else { return false }
        let pairs = [(rgb.r, want.r), (rgb.g, want.g), (rgb.b, want.b)]
        return pairs.allSatisfy { abs(Int(($0.0 * 255).rounded()) - Int(($0.1 * 255).rounded())) <= tolerance }
    }

    @Test("derive matches the Python reference for anime0.jpg (#493a31, ≥ 7:1)")
    func deriveMatchesPythonReference() throws {
        let material = ArtworkMaterial.derive(from: try Self.prototypeAsset("anime0.jpg"), banner: false)
        #expect(Self.close(material.base, "#493a31"), "base \(material.base.hex)")
        #expect(Self.close(material.deep, "#2c2621"), "deep \(material.deep.hex)")
        #expect(Self.close(material.wash, "#ecebe5"), "wash \(material.wash.hex)")
        #expect(Self.close(material.edge, "#c8c4be"), "edge \(material.edge.hex)")
        #expect(material.ink.hex == "#ffffff")
        #expect(material.contrast >= 7)
        #expect(material.method == "art-hue-v1")
    }

    @Test("derive matches the Python reference for more posters (incl. the red bin 23/0 border)",
          arguments: [("anime1.jpg", "#313a49"), ("anime2.jpg", "#493134"), ("anime3.jpg", "#314049"),
                      ("manga0.jpg", "#493431")])
    func deriveMatchesMorePosters(name: String, base: String) throws {
        let material = ArtworkMaterial.derive(from: try Self.prototypeAsset(name), banner: false)
        #expect(Self.close(material.base, base), "\(name): base \(material.base.hex), expected \(base)")
        #expect(material.contrast >= 7)
    }

    @Test("A missing seed colour uses the neutral ink base #3a3d3c at ≥ 7:1")
    func missingImageUsesNeutralBase() {
        let material = ArtworkMaterial.fromHex(nil)
        #expect(material.base.hex == "#3a3d3c")
        #expect(material.contrast >= 7)
        #expect(ArtworkMaterial.fromHex("not a colour").base.hex == "#3a3d3c")
        #expect(ArtworkMaterial.fromHex("").base.hex == "#3a3d3c")
    }

    @Test("A bright AniList colour is darkened until white text reaches 7:1")
    func brightHexIsDarkenedToContrast() {
        let material = ArtworkMaterial.fromHex("#f4e4a1")
        #expect(material.contrast >= 7)
        #expect(KuroRGB.contrastOfWhite(on: material.base) >= 7)
        #expect(material.base != KuroRGB(hex: "#f4e4a1"), "the seed must have been darkened")
        // A seed that already passes is kept as it is.
        #expect(ArtworkMaterial.fromHex("#28484b").base.hex == "#28484b")
        #expect(ArtworkMaterial.fromHex("28484B").base.hex == "#28484b", "no # and upper case still parse")
    }

    @Test("wash is the base mixed 92% toward the paper (#fafaf5), edge 72%, deep 50% toward ink")
    func washIs92PercentPaper() {
        let material = ArtworkMaterial.fromHex("#493134")
        #expect(material.wash == KuroRGB.mix(material.base, ArtworkMaterial.paper, 0.92))
        #expect(material.edge == KuroRGB.mix(material.base, ArtworkMaterial.paper, 0.72))
        #expect(material.deep == KuroRGB.mix(material.base, ArtworkMaterial.shadow, 0.5))
        #expect(ArtworkMaterial.paper.hex == "#fafaf5")
        // The prototype's own values for Jujutsu Kaisen (#493134 → #2c2123 / #eceae5 / #c8c2bf).
        #expect(Self.close(material.deep, "#2c2123", tolerance: 1))
        #expect(Self.close(material.wash, "#eceae5", tolerance: 1))
        #expect(Self.close(material.edge, "#c8c2bf", tolerance: 1))
    }

    @Test("The shipped 360 px decode derives the same base as the full-size artwork",
          arguments: [("anime0.jpg", "#493a31"), ("anime1.jpg", "#313a49"), ("anime2.jpg", "#493134"),
                      ("anime3.jpg", "#314049"), ("manga0.jpg", "#493431")])
    func thumbnailDecodeMatchesReference(name: String, base: String) throws {
        // Production derives from `ImagePipeline` at maxPixelSize 360 (`ArtworkMaterialStore.pipelineLoader`).
        let material = ArtworkMaterial.derive(from: try Self.prototypeThumbnail(name, maxPixelSize: 360), banner: false)
        #expect(Self.close(material.base, base), "\(name) at 360 px: base \(material.base.hex), expected \(base)")
    }

    @Test("Artwork with no qualifying hue (greyscale) has no derived hue; derive itself stays the exact port")
    func greyscaleHasNoHue() throws {
        let grey = try #require(Self.solidImage(gray: 0.5))
        #expect(ArtworkMaterial.deriveIfHued(from: grey, banner: false) == nil)
        // The port keeps Python's hue .4 fallback; the store never publishes it (see the store tests).
        #expect(ArtworkMaterial.derive(from: grey, banner: false).method == "art-hue-v1")
        let colour = try Self.prototypeAsset("anime0.jpg")
        #expect(ArtworkMaterial.deriveIfHued(from: colour, banner: false) == ArtworkMaterial.derive(from: colour, banner: false))
    }

    /// `tools/design-directions/assets/<name>` decoded as a thumbnail, like the image pipeline does.
    static func prototypeThumbnail(_ name: String, maxPixelSize: Int) throws -> CGImage {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tools/design-directions/assets/\(name)")
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil), "missing \(url.path)")
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return try #require(CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary))
    }

    /// A 32×48 image of one grey level (no pixel has saturation).
    static func solidImage(gray: CGFloat) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: 32, height: 48, bitsPerComponent: 8, bytesPerRow: 32 * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(srgbRed: gray, green: gray, blue: gray, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 48))
        return context.makeImage()
    }

    @Test("A material survives a JSON round trip unchanged (disk cache)")
    func codableRoundTrip() throws {
        let material = ArtworkMaterial.derive(from: try Self.prototypeAsset("anime2.jpg"), banner: false)
        let decoded = try JSONDecoder().decode(ArtworkMaterial.self, from: JSONEncoder().encode(material))
        #expect(decoded == material)
    }
}

@MainActor
@Suite("Artwork material store", .timeLimit(.minutes(1)))
struct ArtworkMaterialStoreTests {
    private static func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("artwork-materials-\(UUID().uuidString)")
    }

    private static func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test("Returns the seed at once, then publishes the derived material")
    func seedThenDerived() async throws {
        let directory = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = try ArtworkMaterialTests.prototypeAsset("anime0.jpg")
        let box = MaterialImageBox(image)
        let store = ArtworkMaterialStore(cacheDirectory: directory) { _ in box.image }
        let url = try #require(URL(string: "https://example.invalid/cover/anime0.jpg"))
        let first = store.material(for: url, seedHex: "#28484b")
        #expect(first == ArtworkMaterial.fromHex("#28484b"), "first paint is the seed")
        await Self.waitUntil { store.material(for: url, seedHex: "#28484b").method == "art-hue-v1" }
        let derived = store.material(for: url, seedHex: "#28484b")
        #expect(derived == ArtworkMaterial.derive(from: image, banner: false))
    }

    @Test("A failed load keeps the seed, and the neutral base without a seed")
    func failedLoadKeepsSeed() async throws {
        let directory = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let calls = MaterialLoadCounter()
        let store = ArtworkMaterialStore(cacheDirectory: directory) { _ in calls.increment(); return nil }
        let url = try #require(URL(string: "https://example.invalid/cover/broken.jpg"))
        #expect(store.material(for: url, seedHex: nil).base.hex == "#3a3d3c")
        await Self.waitUntil { calls.value > 0 }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(store.material(for: url, seedHex: nil).base.hex == "#3a3d3c")
        #expect(store.material(for: url, seedHex: "#28484b") == ArtworkMaterial.fromHex("#28484b"))
        #expect(store.material(for: nil, seedHex: nil).base.hex == "#3a3d3c")
        #expect(calls.value == 1, "a failed URL is not retried on every body evaluation")
    }

    @Test("A second store reads the derived material from disk without loading the image")
    func diskCacheHit() async throws {
        let directory = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = try ArtworkMaterialTests.prototypeAsset("manga0.jpg")
        let box = MaterialImageBox(image)
        let url = try #require(URL(string: "https://example.invalid/cover/manga0.jpg"))
        let first = ArtworkMaterialStore(cacheDirectory: directory) { _ in box.image }
        _ = first.material(for: url, seedHex: nil)
        await Self.waitUntil { first.material(for: url, seedHex: nil).method == "art-hue-v1" }
        try? await Task.sleep(for: .milliseconds(100))

        let calls = MaterialLoadCounter()
        let second = ArtworkMaterialStore(cacheDirectory: directory) { _ in calls.increment(); return nil }
        _ = second.material(for: url, seedHex: nil)
        await Self.waitUntil { second.material(for: url, seedHex: nil).method == "art-hue-v1" }
        #expect(second.material(for: url, seedHex: nil) == first.material(for: url, seedHex: nil))
        #expect(calls.value == 0, "the disk cache answered; the image was never loaded")
    }

    @Test("Clear cache forgets every material and removes the disk folder; the disk is pruned to its bound")
    func clearAllAndPrune() async throws {
        let directory = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = try ArtworkMaterialTests.prototypeAsset("anime0.jpg")
        let box = MaterialImageBox(image)
        let url = try #require(URL(string: "https://example.invalid/cover/anime0.jpg"))
        let store = ArtworkMaterialStore(cacheDirectory: directory) { _ in box.image }
        _ = store.material(for: url, seedHex: "#28484b")
        await Self.waitUntil { store.material(for: url, seedHex: "#28484b").method == "art-hue-v1" }
        try? await Task.sleep(for: .milliseconds(100))
        #expect(FileManager.default.fileExists(atPath: directory.path))
        await store.clearAll()
        #expect(!FileManager.default.fileExists(atPath: directory.path), "the disk folder is gone")
        #expect(store.material(for: url, seedHex: "#28484b") == ArtworkMaterial.fromHex("#28484b"),
                "memory is reset: the seed paints first again")

        // The per-launch prune keeps the newest files only.
        let prune = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: prune) }
        try FileManager.default.createDirectory(at: prune, withIntermediateDirectories: true)
        for index in 0..<5 {
            let file = prune.appendingPathComponent("\(index).json")
            try Data("{}".utf8).write(to: file)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(1_000 + index))],
                                                  ofItemAtPath: file.path)
        }
        ArtworkMaterialStore.pruneDisk(prune, keeping: 2)
        let left = try FileManager.default.contentsOfDirectory(atPath: prune.path).sorted()
        #expect(left == ["3.json", "4.json"])
    }

    @Test("A failed URL is tried again after the retry interval (e.g. offline at launch, then back online)")
    func failedLoadRetriesAfterInterval() async throws {
        let clock = MaterialClock()
        let image = try ArtworkMaterialTests.prototypeAsset("anime2.jpg")
        let source = MaterialSwitchableLoader(image)
        let store = ArtworkMaterialStore(cacheDirectory: nil, failureRetryInterval: 60, now: { clock.now }) { _ in
            source.load()
        }
        let url = try #require(URL(string: "https://example.invalid/cover/offline.jpg"))
        _ = store.material(for: url, seedHex: "#28484b")
        await Self.waitUntil { source.calls > 0 }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(store.material(for: url, seedHex: "#28484b").method == "seed-hex")
        #expect(source.calls == 1, "inside the interval the failure is not retried")
        source.succeeds = true
        clock.advance(by: 61)
        _ = store.material(for: url, seedHex: "#28484b")
        await Self.waitUntil { store.material(for: url, seedHex: "#28484b").method == "art-hue-v1" }
        #expect(store.material(for: url, seedHex: "#28484b") == ArtworkMaterial.derive(from: image, banner: false))
        #expect(source.calls == 2)
    }

    @Test("Greyscale artwork keeps the AniList seed (no invented tint), and the decision is cached")
    func greyscaleArtworkKeepsSeed() async throws {
        let directory = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let grey = try #require(ArtworkMaterialTests.solidImage(gray: 0.4))
        let box = MaterialImageBox(grey)
        let calls = MaterialLoadCounter()
        let store = ArtworkMaterialStore(cacheDirectory: directory) { _ in calls.increment(); return box.image }
        let url = try #require(URL(string: "https://example.invalid/cover/monochrome.jpg"))
        _ = store.material(for: url, seedHex: "#5d4a3a")
        await Self.waitUntil { calls.value > 0 }
        try? await Task.sleep(for: .milliseconds(100))
        #expect(store.material(for: url, seedHex: "#5d4a3a") == ArtworkMaterial.fromHex("#5d4a3a"))
        #expect(store.material(for: url, seedHex: nil).base.hex == "#3a3d3c", "no seed: the neutral base")
        #expect(calls.value == 1, "the no-hue decision is kept, not re-derived")

        // A second store reads the decision from disk and still keeps the seed.
        let second = ArtworkMaterialStore(cacheDirectory: directory) { _ in calls.increment(); return nil }
        _ = second.material(for: url, seedHex: "#5d4a3a")
        try? await Task.sleep(for: .milliseconds(150))
        #expect(second.material(for: url, seedHex: "#5d4a3a") == ArtworkMaterial.fromHex("#5d4a3a"))
        #expect(calls.value == 1, "the disk cache answered")
    }

    @Test("Over the memory limit the oldest material is evicted, not every material at once")
    func evictsOldestFirst() async throws {
        let image = try ArtworkMaterialTests.prototypeAsset("anime1.jpg")
        let box = MaterialImageBox(image)
        let calls = MaterialLoadCounter()
        let store = ArtworkMaterialStore(cacheDirectory: nil, memoryLimit: 2) { _ in calls.increment(); return box.image }
        let urls = try (0..<3).map { try #require(URL(string: "https://example.invalid/cover/\($0).jpg")) }
        for (index, url) in urls.enumerated() {
            _ = store.material(for: url, seedHex: nil)
            await Self.waitUntil { calls.value > index && store.material(for: url, seedHex: nil).method == "art-hue-v1" }
        }
        #expect(store.material(for: urls[1], seedHex: nil).method == "art-hue-v1")
        #expect(store.material(for: urls[2], seedHex: nil).method == "art-hue-v1")
        #expect(calls.value == 3)
        // The oldest (urls[0]) was evicted: asking again starts a new derivation.
        #expect(store.material(for: urls[0], seedHex: nil).method == "neutral")
    }

    @Test("Banner URLs are derived with the banner crop")
    func bannerDetection() throws {
        let banner = try #require(URL(string: "https://s4.anilist.co/file/anilistcdn/media/anime/banner/16498-8jpFCOcDmneX.jpg"))
        let cover = try #require(URL(string: "https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/bx16498.jpg"))
        #expect(ArtworkMaterialStore.isBanner(banner))
        #expect(!ArtworkMaterialStore.isBanner(cover))
    }
}

/// A CGImage handed to the store's `@Sendable` loader in tests.
private final class MaterialImageBox: @unchecked Sendable {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

/// Counts loader calls across the store's background task.
private final class MaterialLoadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

/// A loader that fails until `succeeds` is set (offline, then back online).
private final class MaterialSwitchableLoader: @unchecked Sendable {
    private let lock = NSLock()
    private let image: CGImage
    private var count = 0
    private var willSucceed = false
    init(_ image: CGImage) { self.image = image }
    var calls: Int { lock.withLock { count } }
    var succeeds: Bool {
        get { lock.withLock { willSucceed } }
        set { lock.withLock { willSucceed = newValue } }
    }
    func load() -> CGImage? {
        lock.withLock {
            count += 1
            return willSucceed ? image : nil
        }
    }
}

/// A settable clock for the store's failure retry interval.
private final class MaterialClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSinceReferenceDate: 0)
    var now: Date { lock.withLock { current } }
    func advance(by seconds: TimeInterval) { lock.withLock { current += seconds } }
}
