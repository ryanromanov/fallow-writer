import AppKit

/// The writing surface: plain text on TextKit 2 (which the later glyph animation needs),
/// drawn straight onto the background.
final class WriterTextView: NSTextView {
    /// Called for each key that should make a sound, before the text changes.
    var onKeystroke: ((KeyClass, _ isRepeat: Bool) -> Void)?

    /// Settles each typed letter into place. Set up by `make(in:)`.
    private(set) var letters: LetterAnimator!
    /// Whether typed letters animate; checked on every keystroke.
    var animatesTyping: () -> Bool = { false }
    /// Reduce Motion always turns the animation off. Tests replace this, since CI machines may
    /// have Reduce Motion on.
    var reducesMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// True while a typed character is being inserted, so `didChangeText` can tell typing
    /// from every other kind of edit.
    private var insertingTyped = false

    override func keyDown(with event: NSEvent) {
        if let kind = KeyClass(event: event) {
            // Settle running letters before a delete, so a still-transparent letter can't go
            // into the undo history.
            if kind == .delete { letters.finishAll() }
            onKeystroke?(kind, event.isARepeat)
        }
        super.keyDown(with: event)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        let composing = hasMarkedText()
        let start = selectedRange().location
        insertingTyped = true
        super.insertText(string, replacementRange: replacementRange)
        insertingTyped = false
        let text = (string as? NSAttributedString)?.string ?? string as? String ?? ""
        // Animate one character at a time, and never input-method text (marked text).
        guard !composing, animatesTyping(), (text as NSString).length == 1, !reducesMotion() else { return }
        let range = NSRange(location: selectedRange().location - 1, length: 1)
        if range.location >= 0, range.location >= start - 1 { letters.animate(range) }
    }

    override func didChangeText() {
        super.didChangeText()
        // Paste, undo, redo, autocorrect, dictation: anything but plain typing settles every letter.
        if !insertingTyped { letters.finishAll() }
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        letters.finishAll()
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
    }

    /// New text must never pick up the transparent color of a letter that's mid-animation.
    override var typingAttributes: [NSAttributedString.Key: Any] {
        get {
            var attributes = super.typingAttributes
            if let color = attributes[.foregroundColor] as? NSColor, color.alphaComponent == 0 {
                attributes[.foregroundColor] = Palette.text
            }
            return attributes
        }
        set { super.typingAttributes = newValue }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        letters?.finishAll()
    }

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
        textView.letters = LetterAnimator(textView: textView)
        return textView
    }

    /// Applies font, spacing and color to all the text and to what's typed next. Fallow's
    /// documents are plain text, so every character shares the same attributes.
    func apply(_ settings: WriterSettings) {
        letters?.finishAll()
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
    var insertionRect: NSRect? { characterRect(for: selectedRange()) }

    /// The box around `range` (its line's full height), in this view's coordinates.
    func characterRect(for range: NSRange) -> NSRect? {
        guard let window else { return nil }
        let screenRect = firstRect(forCharacterRange: range, actualRange: nil)
        guard screenRect != .zero else { return nil }
        return convert(window.convertFromScreen(screenRect), from: nil)
    }

    /// The baseline of the line holding the character at `index`, in this view's coordinates.
    func baseline(at index: Int) -> CGFloat? {
        guard let layout = textLayoutManager, let content = layout.textContentManager,
              let location = content.location(content.documentRange.location, offsetBy: index),
              let fragment = layout.textLayoutFragment(for: location)
        else { return nil }
        let paragraphStart = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
        let offset = index - paragraphStart
        guard let line = fragment.textLineFragments.first(where: { NSLocationInRange(offset, $0.characterRange) })
                ?? fragment.textLineFragments.last
        else { return nil }
        return textContainerOrigin.y + fragment.layoutFragmentFrame.minY + line.typographicBounds.minY + line.glyphOrigin.y
    }
}
