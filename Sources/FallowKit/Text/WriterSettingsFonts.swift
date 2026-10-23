import AppKit

extension FontStyle {
    /// The system's own designs (New York, SF Pro, SF Mono), so Fallow bundles no font files.
    var design: NSFontDescriptor.SystemDesign {
        switch self {
        case .serif: return .serif
        case .sans: return .default
        case .mono: return .monospaced
        }
    }
}

extension WriterSettings {
    public var font: NSFont {
        let base = NSFont.systemFont(ofSize: fontSize)
        guard let descriptor = base.fontDescriptor.withDesign(fontStyle.design) else { return base }
        return NSFont(descriptor: descriptor, size: fontSize) ?? base
    }

    /// Type for Fallow's own chrome (the status line, the sound panel) in the writing font's
    /// family, so the page reads as one piece. Monospaced is a weight lighter, because SF Mono
    /// looks heavy at small sizes.
    func chromeFont(size: CGFloat, weight: NSFont.Weight = .regular, italic: Bool = false) -> NSFont {
        let lighter: [NSFont.Weight: NSFont.Weight] = [.regular: .light, .medium: .regular, .semibold: .medium, .bold: .semibold]
        let adjusted = fontStyle == .mono ? lighter[weight] ?? weight : weight
        let base = NSFont.systemFont(ofSize: size, weight: adjusted).fontDescriptor
        var descriptor = base.withDesign(fontStyle.design) ?? base
        if italic { descriptor = descriptor.withSymbolicTraits(.italic) }
        return NSFont(descriptor: descriptor, size: size) ?? .systemFont(ofSize: size, weight: adjusted)
    }

    /// Extra space goes between lines (lineSpacing) rather than into each line's height
    /// (lineHeightMultiple): TextKit adds a taller line's extra height above the letters, and
    /// the insertion point grows with it.
    public var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let lineHeight = font.ascender - font.descender + font.leading
        style.lineSpacing = ((lineSpacing.multiple - 1) * lineHeight).rounded()
        // Small, because Markdown already separates paragraphs with a blank line.
        style.paragraphSpacing = (fontSize * 0.3).rounded()
        return style
    }
}
