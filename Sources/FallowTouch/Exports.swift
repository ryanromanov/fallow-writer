#if os(iOS)
import UIKit

/// PDF, Rich Text and printing for text typeset by FallowCore's `Typesetter`, on pages with
/// one-inch margins, as on the Mac.
enum Exports {
    /// US Letter where it's the custom, A4 everywhere else.
    static var pageSize: CGSize {
        let letter: Set<String> = ["US", "CA", "MX", "PH", "CL", "CO", "VE", "PR"]
        return letter.contains(Locale.current.region?.identifier ?? "") ? CGSize(width: 612, height: 792) : CGSize(width: 595, height: 842)
    }

    static func formatter(_ text: NSAttributedString) -> UISimpleTextPrintFormatter {
        let formatter = UISimpleTextPrintFormatter(attributedText: text)
        let margin = Typesetter.margin
        formatter.perPageContentInsets = UIEdgeInsets(top: margin, left: margin, bottom: margin, right: margin)
        return formatter
    }

    static func pdf(_ text: NSAttributedString, pageSize: CGSize = pageSize) -> Data {
        let renderer = PageRenderer(pageSize: pageSize)
        renderer.addPrintFormatter(formatter(text), startingAtPageAt: 0)
        let page = CGRect(origin: .zero, size: pageSize)
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, page, nil)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        for index in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: index, in: page)
        }
        UIGraphicsEndPDFContext()
        return data as Data
    }

    static func richText(_ text: NSAttributedString) throws -> Data {
        try text.data(from: NSRange(location: 0, length: text.length),
                      documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }

    /// Writes an export to a temporary file named after the document, for the share sheet.
    static func file(named name: String, extension fileExtension: String, data: Data) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name).appendingPathExtension(fileExtension)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Lays pages out on paper of a set size; a print renderer otherwise gets its paper from a printer.
    private final class PageRenderer: UIPrintPageRenderer {
        let pageSize: CGSize
        init(pageSize: CGSize) { self.pageSize = pageSize }
        override var paperRect: CGRect { CGRect(origin: .zero, size: pageSize) }
        override var printableRect: CGRect { paperRect }
    }
}
#endif
