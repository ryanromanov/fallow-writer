import AppKit
import Testing
@testable import FallowKit

@Suite @MainActor struct ExportTests {
    static let markdown = """
        # A Field

        Some **bold** words and *quiet* ones, with `code` and a [link](https://example.com).

        - first
        - second

        1. one
        2. two

        > Left to rest.
        """

    func exporter() -> Exporter {
        let name = "FallowExport-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return Exporter(settings: WriterSettings(defaults: defaults))
    }

    func font(_ text: NSAttributedString, at substring: String) -> NSFont {
        let range = (text.string as NSString).range(of: substring)
        return text.attribute(.font, at: range.location, effectiveRange: nil) as! NSFont
    }

    @Test func plainTextExportsAsTyped() {
        let text = exporter().typeset("# Not a heading\n\n**still plain**", markdown: false)
        #expect(text.string == "# Not a heading\n\n**still plain**")
        #expect(font(text, at: "still").pointSize == Exporter.bodySize)
        #expect((text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor) == .black)
    }

    @Test func markdownBecomesFormatting() {
        let text = exporter().typeset(Self.markdown, markdown: true)
        let lines = text.string.components(separatedBy: "\n")
        #expect(lines.first == "A Field")
        #expect(!text.string.contains("**") && !text.string.contains("# "))
        #expect(font(text, at: "A Field").pointSize > Exporter.bodySize)
        #expect(font(text, at: "A Field").fontDescriptor.symbolicTraits.contains(.bold))
        #expect(font(text, at: "bold").fontDescriptor.symbolicTraits.contains(.bold))
        #expect(font(text, at: "quiet").fontDescriptor.symbolicTraits.contains(.italic))
        #expect(font(text, at: "code").fontDescriptor.symbolicTraits.contains(.monoSpace))
        let link = (text.string as NSString).range(of: "link")
        #expect(text.attribute(.link, at: link.location, effectiveRange: nil) as? URL == URL(string: "https://example.com"))
        #expect(lines.contains("•\tfirst") && lines.contains("•\tsecond"))
        #expect(lines.contains("1.\tone") && lines.contains("2.\ttwo"))
        #expect(lines.contains("Left to rest."))
    }

    @Test func richTextAndWordFiles() throws {
        let exporter = exporter()
        let text = exporter.typeset(Self.markdown, markdown: true)
        let rtf = try exporter.richText(text)
        #expect(String(decoding: rtf.prefix(5), as: UTF8.self) == "{\\rtf")
        let docx = try exporter.wordDocument(text)
        #expect(docx.prefix(2) == Data("PK".utf8))   // a .docx is a zip archive
        // Rich Text round-trips with its formatting.
        let back = try NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        #expect(back.string == text.string)
        #expect(font(back, at: "bold").fontDescriptor.symbolicTraits.contains(.bold))
    }

    @Test func pdfHasPagesOfText() throws {
        _ = NSApplication.shared
        let exporter = exporter()
        let long = String(repeating: "A field left to rest is not an empty field. ", count: 400)
        let text = exporter.typeset(long, markdown: false)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fallow-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        let operation = exporter.printOperation(text, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        #expect(operation.run())
        let pdf = try #require(CGPDFDocument(url as CFURL))
        #expect(pdf.numberOfPages >= 2)
    }

    @Test func documentKnowsItsKind() throws {
        let markdown = TextDocument()
        markdown.fileType = "net.daringfireball.markdown"
        #expect(markdown.isMarkdown)
        let plain = TextDocument()
        plain.fileType = "public.plain-text"
        #expect(!plain.isMarkdown)
    }
}
