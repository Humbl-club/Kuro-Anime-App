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
        // Remove "(2011)" / "(1999)" style suffixes; the year is shown in the metadata line.
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

    /// Balances the trailing words of multi-word editorial headlines by pairing a short trailing word
    /// with its predecessor using a non-breaking space so headlines never end on a single-word orphan line.
    static func balancedHeadline(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        let prefix: String
        let lastLine: String
        if let newline = trimmed.lastIndex(of: "\n") {
            let next = trimmed.index(after: newline)
            prefix = String(trimmed[..<next])
            lastLine = String(trimmed[next...])
        } else {
            prefix = ""
            lastLine = trimmed
        }
        let words = lastLine.split(separator: " ", omittingEmptySubsequences: true)
        guard words.count >= 3 else { return trimmed }
        let previous = words[words.count - 2]
        let last = words[words.count - 1]
        guard !last.contains("\u{00A0}"), last.count <= 10, previous.count + 1 + last.count <= 18 else {
            return trimmed
        }
        let balancedLine = (words.dropLast(2).map(String.init) + ["\(previous)\u{00A0}\(last)"]).joined(separator: " ")
        return prefix + balancedLine
    }
}
