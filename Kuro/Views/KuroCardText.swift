import Foundation

enum KuroCardText {
    static let countFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    static func countString(_ value: Int) -> String {
        countFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func sanitizeTitleForCard(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove "(2011)" / "(1999)" style suffixes since year is shown on the poster.
        t = t.replacingOccurrences(
            of: #"\s*\(\s*(?:19|20)\d{2}\s*\)\s*$"#,
            with: "",
            options: .regularExpression
        )
        // Encourage elegant breaks for long subtitles.
        if t.count >= 22 {
            if let range = t.range(of: ": ") {
                t.replaceSubrange(range, with: ":\n")
            } else if let range = t.range(of: " - ") {
                t.replaceSubrange(range, with: "\n")
            }
        }
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

