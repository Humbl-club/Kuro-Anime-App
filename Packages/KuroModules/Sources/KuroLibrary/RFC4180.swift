import Foundation

/// RFC 4180 field and row encoding for CSV text (§2.6 and §2.7: a field holding a comma, a double quote, a
/// CR or a LF is enclosed in double quotes, and a double quote inside such a field is doubled; every record
/// ends with CRLF).
///
/// This type is only the transport encoding. It does not neutralise spreadsheet formulas (a cell starting
/// with `=`, `+`, `-`, `@`, TAB or CR): `LibraryExport.csvSafeText(_:)` does that, and the export's CSV writer
/// calls it before `field(_:)`.
public enum RFC4180 {
    private static let quote: UInt8 = 0x22
    private static let comma: UInt8 = 0x2C
    private static let carriageReturn: UInt8 = 0x0D
    private static let lineFeed: UInt8 = 0x0A

    /// Encodes one field.
    ///
    /// The value is returned unchanged unless it contains a comma, a double quote, a CR or a LF; then it is
    /// wrapped in double quotes with each inner double quote doubled. The scan and the doubling work on bytes
    /// and Unicode scalars, not on `Character`s: `"\r\n"` is one `Character` and a quote followed by a
    /// combining mark is one grapheme, and neither may hide a delimiter from the encoder.
    ///
    /// - Parameter value: The field text, exactly as it must be read back.
    /// - Returns: The field as it appears inside a record, without a separator.
    public static func field(_ value: String) -> String {
        let needsQuoting = value.utf8.contains { byte in
            byte == quote || byte == comma || byte == carriageReturn || byte == lineFeed
        }
        guard needsQuoting else { return value }
        var encoded = String.UnicodeScalarView()
        encoded.append("\"")
        for scalar in value.unicodeScalars {
            if scalar == "\"" { encoded.append("\"") }
            encoded.append(scalar)
        }
        encoded.append("\"")
        return String(encoded)
    }

    /// Encodes one record: the fields joined by `,` and terminated by CRLF.
    ///
    /// - Parameter fields: The unencoded field values, in column order.
    /// - Returns: The record text including its trailing `"\r\n"`.
    public static func row(_ fields: [String]) -> String {
        fields.map(field).joined(separator: ",") + "\r\n"
    }
}
