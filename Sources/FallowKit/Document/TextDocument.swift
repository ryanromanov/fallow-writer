import AppKit
import UniformTypeIdentifiers

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

    // MARK: Export

    /// Markdown documents export formatted; plain text exports as typed.
    var isMarkdown: Bool {
        fileType == "net.daringfireball.markdown" || ["md", "markdown"].contains(fileURL?.pathExtension.lowercased() ?? "")
    }

    func typesetForExport(settings: WriterSettings = .shared) -> NSAttributedString {
        Exporter(settings: settings).typeset(currentText, markdown: isMarkdown)
    }

    /// Used by both File › Print and File › Export as PDF.
    override public func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        let info = printInfo.copy() as! NSPrintInfo
        info.dictionary().addEntries(from: printSettings)
        return Exporter(settings: .shared).printOperation(typesetForExport(), printInfo: info)
    }

    @objc func exportRichText(_ sender: Any?) {
        export(as: .rtf, extension: "rtf") { try Exporter(settings: .shared).richText($0) }
    }

    @objc func exportWordDocument(_ sender: Any?) {
        let docx = UTType("org.openxmlformats.wordprocessingml.document") ?? .data
        export(as: docx, extension: "docx") { try Exporter(settings: .shared).wordDocument($0) }
    }

    /// Asks where to save, then writes the typeset document there.
    private func export(as type: UTType, extension fileExtension: String, encode: @escaping (NSAttributedString) throws -> Data) {
        guard let window = windowForSheet else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = ((displayName as NSString).deletingPathExtension as NSString).appendingPathExtension(fileExtension) ?? displayName
        let text = typesetForExport()
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try encode(text).write(to: url, options: .atomic)
            } catch {
                self?.presentError(error, modalFor: window, delegate: nil, didPresent: nil, contextInfo: nil)
            }
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
