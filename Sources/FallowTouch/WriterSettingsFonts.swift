#if os(iOS)
import UIKit

extension FontStyle {
    /// The system's own designs (New York, SF Pro, SF Mono), so Fallow bundles no font files.
    var design: UIFontDescriptor.SystemDesign {
        switch self {
        case .serif: return .serif
        case .sans: return .default
        case .mono: return .monospaced
        }
    }
}

extension WriterSettings {
    var font: UIFont {
        let base = UIFont.systemFont(ofSize: fontSize)
        guard let descriptor = base.fontDescriptor.withDesign(fontStyle.design) else { return base }
        return UIFont(descriptor: descriptor, size: fontSize)
    }

    /// Type for Fallow's own chrome in the writing font's family. Monospaced is a weight
    /// lighter, because SF Mono looks heavy at small sizes.
    func chromeFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let lighter: [UIFont.Weight: UIFont.Weight] = [.regular: .light, .medium: .regular, .semibold: .medium, .bold: .semibold]
        let adjusted = fontStyle == .mono ? lighter[weight] ?? weight : weight
        let base = UIFont.systemFont(ofSize: size, weight: adjusted)
        guard let descriptor = base.fontDescriptor.withDesign(fontStyle.design) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    /// Extra space goes between lines rather than into each line's height, as on the Mac.
    var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = ((lineSpacing.multiple - 1) * font.lineHeight).rounded()
        // Small, because Markdown already separates paragraphs with a blank line.
        style.paragraphSpacing = (fontSize * 0.3).rounded()
        return style
    }
}
#endif
