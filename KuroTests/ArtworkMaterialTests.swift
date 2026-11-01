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
