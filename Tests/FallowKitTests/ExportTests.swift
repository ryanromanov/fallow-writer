import AppKit
import Testing
@testable import FallowCore
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
        let text = exporter().typeset("# Not a heading\n\n- nor a list", markdown: false)
        #expect(text.string == "# Not a heading\n\n- nor a list")
        #expect(font(text, at: "nor").pointSize == Exporter.bodySize)
        #expect((text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor) == .black)
    }

    /// Format › Font's bold and italic marks become real bold and italics in plain text too.
    @Test func plainTextKeepsItsBoldAndItalics() {
        let text = exporter().typeset("A **bold** word, an *italic* one, ***both*** at once.", markdown: false)
        #expect(text.string == "A bold word, an italic one, both at once.")
        func traits(_ word: String) -> NSFontDescriptor.SymbolicTraits { font(text, at: word).fontDescriptor.symbolicTraits }
        #expect(traits("bold").contains(.bold) && !traits("bold").contains(.italic))
        #expect(traits("italic").contains(.italic) && !traits("italic").contains(.bold))
        #expect(traits("both").contains(.bold) && traits("both").contains(.italic))
        #expect(!traits("word").contains(.bold) && !traits("word").contains(.italic))
    }

    /// ⌘I on part of a word puts the marks inside it.
    @Test func plainTextMarksCanBeInsideWords() {
        let text = exporter().typeset("un*believ*able and half**way**", markdown: false)
        #expect(text.string == "unbelievable and halfway")
        #expect(font(text, at: "believ").fontDescriptor.symbolicTraits.contains(.italic))
        #expect(font(text, at: "way").fontDescriptor.symbolicTraits.contains(.bold))
        #expect(!font(text, at: "un").fontDescriptor.symbolicTraits.contains(.italic))
    }

    /// Marks for neighboring words touch; they pair up as Markdown pairs them.
    @Test func plainTextMarksThatTouch() {
        let text = exporter().typeset("*one*two **three***four*", markdown: false)
        #expect(text.string == "onetwo threefour")
        func traits(_ word: String) -> NSFontDescriptor.SymbolicTraits { font(text, at: word).fontDescriptor.symbolicTraits }
        #expect(traits("one").contains(.italic) && !traits("two").contains(.italic))
        #expect(traits("three").contains(.bold) && traits("four").contains(.italic) && !traits("four").contains(.bold))
    }

    /// Nothing else Markdown would read changes plain text.
    @Test func plainTextKeepsOtherMarkdownAsTyped() {
        for typed in ["`code` and [a link](https://example.com)", "C:\\path\\to\\file", "&amp; <b>tag</b> _under_ ~strike~",
                      "# Not a heading\n- nor a list\n> nor a quote", "two spaces  \nthen a line"] {
            #expect(exporter().typeset(typed, markdown: false).string == typed)
        }
    }

    @Test func plainTextLeavesOtherAsterisksAlone() {
        for typed in ["2*3*4 = 24", "a * b * c", "**not closed", "*\nacross lines*"] {
            #expect(exporter().typeset(typed, markdown: false).string == typed)
        }
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

    func pages(_ typed: String) throws -> Int {
        _ = NSApplication.shared
        let exporter = exporter()
        let text = exporter.typeset(typed, markdown: false)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fallow-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        let operation = exporter.printOperation(text, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        #expect(operation.run())
        return try #require(CGPDFDocument(url as CFURL)).numberOfPages
    }

    @Test func pdfHasPagesOfText() throws {
        #expect(try pages(String(repeating: "A field left to rest is not an empty field. ", count: 400)) >= 2)
    }

    /// It once printed a blank page after any text shorter than a page.
    @Test func shortTextIsOnePage() throws {
        #expect(try pages("A few words.") == 1)
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
