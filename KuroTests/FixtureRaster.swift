import CoreGraphics
import UIKit

/// 1 px = 1 pt fixture images made the way a 1x screen makes them.
///
/// `drawHierarchy` into a 1x context resamples the window's device-pixel (3x) snapshot with a
/// sharpening filter: a 1 pt rule on the point grid comes out over three rows with lighter rings
/// above and below it (FIDELITY_REVIEW round 3, "Fixture raster"). Drawing at the screen's own scale
/// and averaging each scale × scale block gives every pixel its true coverage, so geometry on the
/// point grid stays crisp, as in the reference captures.
enum FixtureRaster {
    /// Draws `view`'s hierarchy at the screen scale and returns the block-averaged 1x PNG, or the
    /// device-pixel PNG when `diagnosticScale` asks for one (diagnosis only).
    @MainActor
    static func png(of view: UIView, size: CGSize, diagnosticScale: CGFloat?) -> Data? {
        let deviceScale = max(1, (view.window?.screen.scale ?? 3).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = diagnosticScale ?? deviceScale
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            // A very tall hierarchy (AX5) can be refused by the render server: fall back to the layer.
            if !view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true) {
                view.layer.render(in: context.cgContext)
            }
        }
        if diagnosticScale != nil { return image.pngData() }
        guard let source = image.cgImage else { return nil }
        return boxAverage(source, factor: Int(deviceScale)).flatMap { UIImage(cgImage: $0, scale: 1, orientation: .up).pngData() }
    }

    /// Averages each `factor` × `factor` block of `image` into one pixel (sRGB, 8 bits a channel).
    static func boxAverage(_ image: CGImage, factor: Int) -> CGImage? {
        guard factor > 1 else { return image }
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        let width = image.width, height = image.height
        let outWidth = width / factor, outHeight = height / factor
        guard outWidth > 0, outHeight > 0 else { return nil }
        var source = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = source.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space, bitmapInfo: info) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var output = [UInt8](repeating: 0, count: outWidth * outHeight * 4)
        let blockArea = factor * factor
        source.withUnsafeBufferPointer { src in
            output.withUnsafeMutableBufferPointer { dst in
                var sums = [Int](repeating: 0, count: outWidth * 4)
                for outY in 0..<outHeight {
                    for index in sums.indices { sums[index] = 0 }
                    for row in (outY * factor)..<(outY * factor + factor) {
                        let base = row * width * 4
                        for x in 0..<(outWidth * factor) {
                            let s = base + x * 4
                            let d = (x / factor) * 4
                            sums[d] += Int(src[s]); sums[d + 1] += Int(src[s + 1])
                            sums[d + 2] += Int(src[s + 2]); sums[d + 3] += Int(src[s + 3])
                        }
                    }
                    let outBase = outY * outWidth * 4
                    for index in 0..<(outWidth * 4) {
                        dst[outBase + index] = UInt8((sums[index] + blockArea / 2) / blockArea)
                    }
                }
            }
        }
        return output.withUnsafeMutableBytes { raw -> CGImage? in
            CGContext(data: raw.baseAddress, width: outWidth, height: outHeight, bitsPerComponent: 8,
                      bytesPerRow: outWidth * 4, space: space, bitmapInfo: info)?.makeImage()
        }
    }
}
