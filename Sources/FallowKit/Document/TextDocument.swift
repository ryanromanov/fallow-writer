import AppKit

/// A plain-text or Markdown file. Info.plist names this class (NSDocumentClass) for both types,
/// so its Objective-C name is fixed.
@objc(TextDocument)
public final class TextDocument: NSDocument {
    /// The text as last read from disk. While a window is open, the text view holds the live copy.
    public private(set) var text = ""

    override public class var autosavesInPlace: Bool { true }

    override public func makeWindowControllers() {
        let controller = WriterWindowController(sound: AppDelegate.isRunningApp ? SoundEngine.shared : nil)
        addWindowController(controller)
        controller.show(text)
    }

    override public func read(from data: Data, ofType typeName: String) throws {
        text = try Self.decode(data)
    }

    override public func data(ofType typeName: String) throws -> Data {
        Data(currentText.utf8)
    }

    override public func revert(toContentsOf url: URL, ofType typeName: String) throws {
        try super.revert(toContentsOf: url, ofType: typeName)
        for case let controller as WriterWindowController in windowControllers {
            controller.show(text)
        }
    }

    var currentText: String {
        windowControllers.lazy.compactMap { ($0 as? WriterWindowController)?.currentText }.first ?? text
    }

    /// Reads UTF-8 (with or without a BOM), UTF-16 with a BOM, and otherwise falls back to
    /// Windows-1252, then Latin-1, which accepts any bytes. Fallow always saves UTF-8.
    static func decode(_ data: Data) throws -> String {
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
