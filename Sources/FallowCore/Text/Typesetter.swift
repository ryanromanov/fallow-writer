#if os(macOS)
import AppKit
package typealias PlatformFont = NSFont
package typealias PlatformColor = NSColor
#else
import UIKit
package typealias PlatformFont = UIFont
package typealias PlatformColor = UIColor
#endif

/// Typesets a document for paper (PDF, printing, Rich Text and Word), the same on every
/// device: the writing font's family at a print size, in black, with the writer's line spacing.
/// Markdown documents come out formatted, so `# Heading`, `**bold**` and lists become real
/// headings, bold and lists. Plain text comes out as typed, except that the bold and italic
/// marks Fallow writes become real bold and italics.
package struct Typesetter {
    package static let bodySize: CGFloat = 12
    /// A US Letter or A4 page's text column, at 72 points per inch with one-inch margins.
    package static let margin: CGFloat = 72

    let fontStyle: FontStyle
    let lineSpacing: LineSpacing

    package init(settings: WriterSettings) {
        fontStyle = settings.fontStyle
        lineSpacing = settings.lineSpacing
    }

    package func typeset(_ text: String, markdown: Bool) -> NSAttributedString {
        markdown ? formatted(markdown: text) : emphasized(plain: text)
    }

    // MARK: Type

    private func font(size: CGFloat = bodySize, bold: Bool = false, italic: Bool = false, mono: Bool = false) -> PlatformFont {
        PlatformFont.fallow(size: size, bold: bold, italic: italic, design: mono ? .mono : fontStyle)
    }

    private func paragraph(spacingBefore: CGFloat = 0, indent: CGFloat = 0, hanging: CGFloat = 0) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let lineHeight = Self.bodySize * 1.2
        style.lineSpacing = ((lineSpacing.multiple - 1) * lineHeight).rounded()
        style.paragraphSpacing = (Self.bodySize * 0.6).rounded()
        style.paragraphSpacingBefore = spacingBefore
        style.firstLineHeadIndent = indent
        style.headIndent = indent + hanging
        // A list marker is followed by a tab, which lands on the item's text indent.
        if hanging > 0 { style.tabStops = [NSTextTab(textAlignment: .left, location: indent + hanging)] }
        return style
    }

    private func body() -> [NSAttributedString.Key: Any] {
        [.font: font(), .foregroundColor: PlatformColor.black, .paragraphStyle: paragraph()]
    }

    // MARK: Plain text

    /// Every ASCII punctuation mark but `*`, which Markdown would otherwise read as syntax.
    private static let notEmphasis = try! NSRegularExpression(pattern: #"[!-)+-/:-@\[-`{-~]"#)
    /// A `*` between digits, as in `2*3*4`, is multiplication.
    private static let multiplication = try! NSRegularExpression(pattern: #"(?<=\d)\*(?=\d)"#)

    /// Only `*italic*`, `**bold**` and `***both***`, read by Foundation's Markdown parser, which
    /// knows how marks pair up even when they touch. Everything else Markdown would read
    /// (links, code, headings, lists, escapes) is escaped first, so it comes out as typed.
    private func emphasized(plain text: String) -> NSAttributedString {
        let whole = { (text: String) in NSRange(location: 0, length: (text as NSString).length) }
        var escaped = Self.notEmphasis.stringByReplacingMatches(in: text, range: whole(text), withTemplate: #"\\$0"#)
        escaped = Self.multiplication.stringByReplacingMatches(in: escaped, range: whole(escaped), withTemplate: #"\\*"#)
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false, interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible)
        guard let parsed = try? AttributedString(markdown: escaped, options: options) else {
            return NSAttributedString(string: text, attributes: body())
        }
        let output = NSMutableAttributedString()
        for run in parsed.runs {
            let inline = run.inlinePresentationIntent ?? []
            var attributes = body()
            attributes[.font] = font(bold: inline.contains(.stronglyEmphasized), italic: inline.contains(.emphasized))
            output.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
        }
        return output
    }

    // MARK: Markdown

    /// Renders Markdown with Foundation's parser. It reports blocks (headings, list items,
    /// quotes) as each run's presentation intent but drops the line breaks between them and
    /// the list markers, so those are put back here.
    private func formatted(markdown text: String) -> NSAttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false, interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
        guard let parsed = try? AttributedString(markdown: text, options: options) else {
            return NSAttributedString(string: text, attributes: body())
        }

        let output = NSMutableAttributedString()
        var previousBlock: PresentationIntent?
        for run in parsed.runs {
            let block = run.presentationIntent
            let kinds = block?.components.map(\.kind) ?? []
            if block != previousBlock {
                if output.length > 0 { output.append(NSAttributedString(string: "\n", attributes: body())) }
                if let marker = listMarker(kinds) {
                    output.append(NSAttributedString(string: marker, attributes: blockAttributes(kinds)))
                }
                previousBlock = block
            }
            var attributes = blockAttributes(kinds)
            let inline = run.inlinePresentationIntent ?? []
            let size = (attributes[.font] as? PlatformFont)?.pointSize ?? Self.bodySize
            let heading = kinds.contains { if case .header = $0 { return true } else { return false } }
            let code = inline.contains(.code) || kinds.contains { if case .codeBlock = $0 { return true } else { return false } }
            attributes[.font] = font(
                size: code ? size * 0.92 : size,
                bold: heading || inline.contains(.stronglyEmphasized),
                italic: inline.contains(.emphasized) || kinds.contains(.blockQuote),
                mono: code)
            if inline.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let link = run.link { attributes[.link] = link }
            output.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
        }
        return output
    }

    /// Size and indentation for a block: headings larger with room above, quotes and lists indented.
    private func blockAttributes(_ kinds: [PresentationIntent.Kind]) -> [NSAttributedString.Key: Any] {
        var attributes = body()
        let lists = kinds.filter { if case .listItem = $0 { return true } else { return false } }.count
        let quoted = kinds.contains(.blockQuote)
        let indent = CGFloat(lists) * 18 + (quoted ? 18 : 0)
        for kind in kinds {
            if case .header(let level) = kind {
                let scale: [CGFloat] = [1.6, 1.35, 1.15, 1.05]
                attributes[.font] = font(size: Self.bodySize * scale[min(max(level, 1), 4) - 1], bold: true)
                attributes[.paragraphStyle] = paragraph(spacingBefore: Self.bodySize * 0.8)
                return attributes
            }
        }
        // A list item's first line starts one level out, where its marker hangs. Items sit
        // closer together than paragraphs.
        let style = paragraph(indent: max(0, indent - (lists > 0 ? 18 : 0)), hanging: lists > 0 ? 18 : 0).mutableCopy() as! NSMutableParagraphStyle
        if lists > 0 { style.paragraphSpacing = (Self.bodySize * 0.2).rounded() }
        attributes[.paragraphStyle] = style
        if quoted { attributes[.foregroundColor] = PlatformColor(white: 0.3, alpha: 1) }
        return attributes
    }

    /// "• " for a bulleted item, "3. " for a numbered one, nil for anything else.
    private func listMarker(_ kinds: [PresentationIntent.Kind]) -> String? {
        // Components run from the innermost block outward: the item, then its list.
        guard let itemIndex = kinds.firstIndex(where: { if case .listItem = $0 { return true } else { return false } }),
              case .listItem(let ordinal) = kinds[itemIndex]
        else { return nil }
        let list = kinds.dropFirst(itemIndex + 1).first
        if case .orderedList = list { return "\(ordinal).\t" }
        return "•\t"
    }
}

extension PlatformFont {
    /// The system font in a writing font's design (New York, SF Pro or SF Mono). Italic is
    /// added to the traits it has, so bold italic stays bold.
    static func fallow(size: CGFloat, bold: Bool, italic: Bool, design style: FontStyle) -> PlatformFont {
        let base = systemFont(ofSize: size, weight: bold ? .bold : .regular)
        #if os(macOS)
        let design: NSFontDescriptor.SystemDesign = style == .serif ? .serif : style == .mono ? .monospaced : .default
        var descriptor = base.fontDescriptor.withDesign(design) ?? base.fontDescriptor
        if italic { descriptor = descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(.italic)) }
        return NSFont(descriptor: descriptor, size: size) ?? base
        #else
        let design: UIFontDescriptor.SystemDesign = style == .serif ? .serif : style == .mono ? .monospaced : .default
        var descriptor = base.fontDescriptor.withDesign(design) ?? base.fontDescriptor
        if italic { descriptor = descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(.traitItalic)) ?? descriptor }
        return UIFont(descriptor: descriptor, size: size)
        #endif
    }
}
