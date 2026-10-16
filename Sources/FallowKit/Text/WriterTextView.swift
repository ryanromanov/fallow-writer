import AppKit

/// The writing surface: plain text on TextKit 2 (which the later glyph animation needs),
/// drawn straight onto the background.
final class WriterTextView: NSTextView {
    /// Makes a text view sized to live in `scrollView`.
    static func make(in scrollView: NSScrollView) -> WriterTextView {
        let textView = WriterTextView(usingTextLayoutManager: true)
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)

        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.insertionPointColor = Palette.caret
        textView.selectedTextAttributes = [.backgroundColor: Palette.selection]
        return textView
    }

    /// Applies font, spacing and color to all the text and to what's typed next. Fallow's
    /// documents are plain text, so every character shares the same attributes.
    func apply(_ settings: WriterSettings) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: settings.font,
            .paragraphStyle: settings.paragraphStyle,
            .foregroundColor: Palette.text,
        ]
        font = settings.font
        defaultParagraphStyle = settings.paragraphStyle
        typingAttributes = attributes
        if let storage = textStorage, storage.length > 0 {
            storage.beginEditing()
            storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
            storage.endEditing()
        }
    }

    /// Where the insertion point is, in this view's coordinates, or nil before layout.
    var insertionRect: NSRect? {
        guard let window else { return nil }
        let screenRect = firstRect(forCharacterRange: selectedRange(), actualRange: nil)
        guard screenRect != .zero else { return nil }
        return convert(window.convertFromScreen(screenRect), from: nil)
    }
}
