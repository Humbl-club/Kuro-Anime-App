import SwiftUI

extension Color {
    init(hex: String, opacity: Double = 1.0) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }

        // Support `RRGGBB` and `AARRGGBB`.
        if s.count == 3 {
            // Expand `RGB` -> `RRGGBB`
            s = s.map { "\($0)\($0)" }.joined()
        }

        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)

        let a: Double
        let r: Double
        let g: Double
        let b: Double

        if s.count == 8 {
            a = Double((value & 0xFF00_0000) >> 24) / 255.0
            r = Double((value & 0x00FF_0000) >> 16) / 255.0
            g = Double((value & 0x0000_FF00) >> 8) / 255.0
            b = Double(value & 0x0000_00FF) / 255.0
        } else {
            a = 1.0
            r = Double((value & 0xFF00_00) >> 16) / 255.0
            g = Double((value & 0x00FF_00) >> 8) / 255.0
            b = Double(value & 0x0000_FF) / 255.0
        }

        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a * opacity)
    }
}

