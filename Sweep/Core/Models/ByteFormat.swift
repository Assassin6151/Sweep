import Foundation

/// Formats byte counts for display. Split into value and unit so the UI can render big numbers.
enum ByteFormat {
    static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Splits "12,4 GB" into ("12,4", "GB").
    static func parts(_ bytes: Int64) -> (value: String, unit: String) {
        let formatted = string(bytes)
        guard let space = formatted.lastIndex(where: { $0 == " " || $0 == "\u{00A0}" }) else {
            return (formatted, "")
        }
        return (String(formatted[..<space]), String(formatted[formatted.index(after: space)...]))
    }
}

extension Date {
    /// "vor 3 Tagen", "gestern", …
    var relativeDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: .now)
    }
}
