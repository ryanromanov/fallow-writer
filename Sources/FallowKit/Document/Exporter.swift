import AppKit

/// Exports a document typeset for paper by FallowCore's `Typesetter`: as a PDF or a printout,
/// Rich Text or Word.
struct Exporter {
    static let bodySize = Typesetter.bodySize
    static let margin = Typesetter.margin

    let settings: WriterSettings

    func typeset(_ text: String, markdown: Bool) -> NSAttributedString {
        Typesetter(settings: settings).typeset(text, markdown: markdown)
    }

    // MARK: Files

    func richText(_ text: NSAttributedString) throws -> Data {
        try text.data(from: NSRange(location: 0, length: text.length),
                      documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }

    func wordDocument(_ text: NSAttributedString) throws -> Data {
        try text.data(from: NSRange(location: 0, length: text.length),
                      documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
    }

    /// A print operation over a text view laid out on the page; NSDocument uses it for both
    /// Print and Export as PDF.
    func printOperation(_ text: NSAttributedString, printInfo: NSPrintInfo) -> NSPrintOperation {
        let info = printInfo.copy() as! NSPrintInfo
        info.topMargin = Self.margin
        info.bottomMargin = Self.margin
        info.leftMargin = Self.margin
        info.rightMargin = Self.margin
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: info.paperSize.height))
        // Only as tall as the text: at a whole page tall plus margins, short text printed a
        // blank second page.
        view.minSize = NSSize(width: width, height: 0)
        view.isVerticallyResizable = true
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.drawsBackground = false
        view.textStorage?.setAttributedString(text)
        view.sizeToFit()
        return NSPrintOperation(view: view, printInfo: info)
    }
}
