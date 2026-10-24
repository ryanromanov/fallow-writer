#if os(iOS)
import UIKit
import Testing
@testable import FallowTouch

/// PDF and Rich Text from the shared typesetter, on pages with one-inch margins.
@Suite @MainActor struct ExportTests {
    func typeset(_ text: String, markdown: Bool = false) -> NSAttributedString {
        Typesetter(settings: freshSettings()).typeset(text, markdown: markdown)
    }

    func pages(_ data: Data) throws -> [CGRect] {
        let document = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        return (1...document.numberOfPages).compactMap { document.page(at: $0)?.getBoxRect(.mediaBox) }
    }

    @Test func pdfIsOnePagePerPageful() throws {
        let letter = CGSize(width: 612, height: 792)
        let short = try pages(Exports.pdf(typeset("A quiet place to write."), pageSize: letter))
        #expect(short == [CGRect(origin: .zero, size: letter)])
        let long = String(repeating: "A quiet place to write, page after page.\n\n", count: 120)
        #expect(try pages(Exports.pdf(typeset(long), pageSize: letter)).count > 1)
    }

    @Test func pdfUsesTheChosenPaper() throws {
        let a4 = CGSize(width: 595, height: 842)
        #expect(try pages(Exports.pdf(typeset("Words."), pageSize: a4)).first?.size == a4)
        #expect([CGSize(width: 612, height: 792), a4].contains(Exports.pageSize))
    }

    @Test func richTextKeepsBold() throws {
        let data = try Exports.richText(typeset("a **quiet** place", markdown: true))
        let text = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        #expect(text.string == "a quiet place")
        let font = try #require(text.attribute(.font, at: 3, effectiveRange: nil) as? UIFont)
        #expect(font.fontDescriptor.symbolicTraits.contains(.traitBold))
    }

    @Test func exportsAreNamedAfterTheDocument() throws {
        let url = try Exports.file(named: "Chapter One", extension: "pdf", data: Data("x".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(url.lastPathComponent == "Chapter One.pdf")
        #expect(try Data(contentsOf: url) == Data("x".utf8))
    }
}
#endif
