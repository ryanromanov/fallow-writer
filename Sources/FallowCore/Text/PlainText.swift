import Foundation

/// Fallow's documents are plain text, whether they're .txt or Markdown.
package enum PlainText {
    /// Reads UTF-8 (with or without a BOM), UTF-16 with a BOM, and otherwise falls back to
    /// Windows-1252, then Latin-1, which accepts any bytes. Fallow always saves UTF-8.
    package static func decode(_ data: Data) throws -> String {
        if let string = String(data: data, encoding: .utf8) {
            return string.hasPrefix("\u{FEFF}") ? String(string.dropFirst()) : string
        }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let string = String(data: data, encoding: .utf16) {
            return string.hasPrefix("\u{FEFF}") ? String(string.dropFirst()) : string
        }
        if let string = String(data: data, encoding: .windowsCP1252) ?? String(data: data, encoding: .isoLatin1) {
            return string
        }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }
}
