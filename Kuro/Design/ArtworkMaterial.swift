//
//  ArtworkMaterial.swift
//  Kuro
//
//  The colour material a title's artwork gives its surfaces (detail hero band, Home scene feet, song
//  panel, raised keys on art, card washes and borders). An exact on-device port of the approved
//  prototype's `art-hue-v1` algorithm, `material()` in `tools/design-directions/build_art_materials.py`
//  (spec §3, plan Task 2):
//
//  1. downsample the artwork: banners are centre-cropped to 104×32, posters fit inside 64×96;
//  2. a 24-bin hue histogram over pixels with value .12–.94 and saturation ≥ .12, each pixel weighted
//     s·(1 − |v − .55|); the heaviest bin's centre is the hue (no qualifying pixel: hue .4, as ported);
//  3. `base` = HLS(hue, .24, .20), mixed 5% toward black until white text reaches 7:1;
//  4. `deep` = base mixed 50% toward (.06,.07,.07); `wash` = 92% and `edge` = 72% toward (.98,.98,.96);
//     `ink` is white.
//
//  `fromHex` is the first paint from AniList's `cover_image_color` with the same contrast loop; a
//  missing or unreadable colour gives the neutral ink base #3a3d3c. No per-title override table ships
//  (the prototype's three manual overrides were for its sample art only).
//

import CoreGraphics
import Foundation
import SwiftUI

/// An sRGB colour with components in 0...1 (the unit the prototype's Python port computes in).
nonisolated struct KuroRGB: Equatable, Codable, Sendable, Hashable {
    var r: Double
    var g: Double
    var b: Double

    init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// `#RRGGBB`, `RRGGBB` or `#RGB` (any case). Nil for anything else.
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        if text.count == 3 { text = text.map { "\($0)\($0)" }.joined() }
        guard text.count == 6, text.allSatisfy(\.isHexDigit), let value = UInt32(text, radix: 16) else { return nil }
        self.init(
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }

    /// Lowercase `#rrggbb`, rounded like Python's `round` (half to even), clamped to 0...1.
    var hex: String {
        let channels = [r, g, b].map { Int((max(0, min(1, $0)) * 255).rounded(.toNearestOrEven)) }
        return "#" + channels.map { String(format: "%02x", $0) }.joined()
    }

    /// The SwiftUI colour.
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }

    /// WCAG relative luminance.
    var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return linear(r) * 0.2126 + linear(g) * 0.7152 + linear(b) * 0.0722
    }

    /// `a` mixed toward `b` by `t` (0 = a, 1 = b), per channel.
    static func mix(_ a: KuroRGB, _ b: KuroRGB, _ t: Double) -> KuroRGB {
        KuroRGB(a.r * (1 - t) + b.r * t, a.g * (1 - t) + b.g * t, a.b * (1 - t) + b.b * t)
    }

    /// The contrast ratio of white text on `background`.
    static func contrastOfWhite(on background: KuroRGB) -> Double {
        1.05 / (background.luminance + 0.05)
    }
}

/// A title's artwork material: the colours its surfaces take from its artwork (spec §3).
nonisolated struct ArtworkMaterial: Equatable, Codable, Sendable {
    /// Hero band, scene feet, song panel and raised keys on art. White text on it is ≥ 7:1.
    var base: KuroRGB
    /// The dark end of the base gradient (`base → deep`).
    var deep: KuroRGB
    /// The pale card fill on paper (progress card, Up next row).
    var wash: KuroRGB
    /// Borders of washed cards.
    var edge: KuroRGB
    /// Text on `base` / `deep` (always white).
    var ink: KuroRGB
    /// White-on-base contrast ratio, rounded to 2 decimals as in the prototype's output.
    var contrast: Double
    /// `art-hue-v1` (derived from the artwork), `seed-hex` (AniList colour) or `neutral` (no colour).
    var method: String

    /// The minimum white-on-base contrast ratio.
    static let contrastTarget = 7.0
    /// The light end the wash and edge mix toward (Python `(.98,.98,.96)`, ≈ #fafaf5).
    static let paper = KuroRGB(0.98, 0.98, 0.96)
    /// The dark end the deep tone mixes toward (Python `(.06,.07,.07)`).
    static let shadow = KuroRGB(0.06, 0.07, 0.07)
    /// The neutral ink base for a title without a usable colour or artwork.
    static let neutralBase = KuroRGB(0x3A / 255.0, 0x3D / 255.0, 0x3C / 255.0)
    /// The neutral material (#3a3d3c base).
    static let neutral = ArtworkMaterial(base: neutralBase, method: "neutral")

    /// The full material for an already-clamped `base`.
    init(base: KuroRGB, method: String) {
        self.base = base
        self.deep = KuroRGB.mix(base, Self.shadow, 0.5)
        self.wash = KuroRGB.mix(base, Self.paper, 0.92)
        self.edge = KuroRGB.mix(base, Self.paper, 0.72)
        self.ink = KuroRGB(1, 1, 1)
        self.contrast = (KuroRGB.contrastOfWhite(on: base) * 100).rounded() / 100
        self.method = method
    }

    /// `base` mixed 5% toward black until white text on it reaches the contrast target.
    static func clamped(_ base: KuroRGB) -> KuroRGB {
        var value = base
        var steps = 0
        while KuroRGB.contrastOfWhite(on: value) < contrastTarget, steps < 200 {
            value = KuroRGB.mix(value, KuroRGB(0, 0, 0), 0.05)
            steps += 1
        }
        return value
    }

    /// The first paint from AniList's `cover_image_color`: the seed clamped to 7:1. Nil, empty or
    /// unreadable gives the neutral material (#3a3d3c).
    static func fromHex(_ hex: String?) -> ArtworkMaterial {
        guard let hex, let seed = KuroRGB(hex: hex) else { return neutral }
        return ArtworkMaterial(base: clamped(seed), method: "seed-hex")
    }

    /// The `art-hue-v1` material of `cgImage`. `banner` selects the 104×32 centre crop (wide banner
    /// art); otherwise the poster is fitted inside 64×96 without upscaling.
    static func derive(from cgImage: CGImage, banner: Bool) -> ArtworkMaterial {
        let hue = dominantHue(of: cgImage, banner: banner) ?? 0.4
        let (r, g, b) = hlsToRGB(h: hue, l: 0.24, s: 0.20)
        return ArtworkMaterial(base: clamped(KuroRGB(r, g, b)), method: "art-hue-v1")
    }

    // MARK: - Port internals

    /// The centre of the heaviest hue bin, or nil when no pixel qualifies (or the image cannot be drawn).
    static func dominantHue(of image: CGImage, banner: Bool) -> Double? {
        guard let pixels = samplePixels(of: image, banner: banner) else { return nil }
        var bins = [Double](repeating: 0, count: 24)
        var any = false
        var index = 0
        while index + 2 < pixels.count {
            let (h, s, v) = rgbToHSV(
                Double(pixels[index]) / 255, Double(pixels[index + 1]) / 255, Double(pixels[index + 2]) / 255
            )
            index += 4
            if v < 0.12 || v > 0.94 || s < 0.12 { continue }
            let bucket = Int(h * 24) % 24
            bins[bucket] += s * (1 - abs(v - 0.55))
            any = true
        }
        guard any else { return nil }
        // Python's max(bins, key=bins.get) keeps the first bucket inserted among equals; ties are
        // vanishingly rare with real weights, so the lowest index stands in for it.
        var best = 0
        for bucket in 1..<24 where bins[bucket] > bins[best] { best = bucket }
        return (Double(best) + 0.5) / 24
    }

    /// RGBX bytes of the downsampled artwork (Pillow `ImageOps.fit` / `thumbnail` geometry).
    static func samplePixels(of image: CGImage, banner: Bool) -> [UInt8]? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        var source = image
        let target: (w: Int, h: Int)
        if banner {
            target = (104, 32)
            let aspect = 104.0 / 32.0
            let current = Double(width) / Double(height)
            var crop = CGRect(x: 0, y: 0, width: width, height: height)
            if current > aspect {
                let cropWidth = Double(height) * aspect
                crop = CGRect(x: (Double(width) - cropWidth) / 2, y: 0, width: cropWidth, height: Double(height))
            } else if current < aspect {
                let cropHeight = Double(width) / aspect
                crop = CGRect(x: 0, y: (Double(height) - cropHeight) / 2, width: Double(width), height: cropHeight)
            }
            if let cropped = image.cropping(to: crop.integral) { source = cropped }
        } else {
            target = thumbnailSize(width: width, height: height, box: (64, 96))
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: target.w, height: target.h, bitsPerComponent: 8, bytesPerRow: target.w * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: target.w, height: target.h))
        guard let data = context.data else { return nil }
        let count = target.w * target.h * 4
        return Array(UnsafeBufferPointer(start: data.bindMemory(to: UInt8.self, capacity: count), count: count))
    }

    /// Pillow `Image.thumbnail(box)` size: never upscales, keeps the aspect, rounds toward the closer aspect.
    static func thumbnailSize(width: Int, height: Int, box: (Int, Int)) -> (w: Int, h: Int) {
        let (x, y) = box
        if x >= width && y >= height { return (width, height) }
        let aspect = Double(width) / Double(height)
        func roundAspect(_ number: Double, key: (Int) -> Double) -> Int {
            let low = Int(number.rounded(.down))
            let high = Int(number.rounded(.up))
            return max(key(low) <= key(high) ? low : high, 1)
        }
        if Double(x) / Double(y) >= aspect {
            let w = roundAspect(Double(y) * aspect) { abs(aspect - Double($0) / Double(y)) }
            return (w, y)
        }
        let h = roundAspect(Double(x) / aspect) { $0 == 0 ? 0 : abs(aspect - Double(x) / Double($0)) }
        return (x, h)
    }

    /// Python `colorsys.rgb_to_hsv` (hue in 0..<1).
    static func rgbToHSV(_ r: Double, _ g: Double, _ b: Double) -> (h: Double, s: Double, v: Double) {
        let maxc = max(r, g, b)
        let minc = min(r, g, b)
        let v = maxc
        guard minc != maxc else { return (0, 0, v) }
        let range = maxc - minc
        let s = range / maxc
        let rc = (maxc - r) / range
        let gc = (maxc - g) / range
        let bc = (maxc - b) / range
        var h: Double
        if r == maxc {
            h = bc - gc
        } else if g == maxc {
            h = 2 + rc - bc
        } else {
            h = 4 + gc - rc
        }
        h /= 6
        h -= h.rounded(.down) // Python's `% 1.0`: always non-negative
        return (h, s, v)
    }

    /// Python `colorsys.hls_to_rgb`.
    static func hlsToRGB(h: Double, l: Double, s: Double) -> (Double, Double, Double) {
        guard s != 0 else { return (l, l, l) }
        let m2 = l <= 0.5 ? l * (1 + s) : l + s - l * s
        let m1 = 2 * l - m2
        func channel(_ hue: Double) -> Double {
            let hue = hue - hue.rounded(.down)
            if hue < 1.0 / 6.0 { return m1 + (m2 - m1) * hue * 6 }
            if hue < 0.5 { return m2 }
            if hue < 2.0 / 3.0 { return m1 + (m2 - m1) * (2.0 / 3.0 - hue) * 6 }
            return m1
        }
        return (channel(h + 1.0 / 3.0), channel(h), channel(h - 1.0 / 3.0))
    }
}
