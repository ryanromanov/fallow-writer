import AppKit

public enum FontStyle: String, CaseIterable {
    case serif, sans, mono

    var title: String {
        switch self {
        case .serif: return "Serif"
        case .sans: return "Sans Serif"
        case .mono: return "Monospaced"
        }
    }

    /// The system's own designs (New York, SF Pro, SF Mono), so Fallow bundles no font files.
    var design: NSFontDescriptor.SystemDesign {
        switch self {
        case .serif: return .serif
        case .sans: return .default
        case .mono: return .monospaced
        }
    }
}

public enum LineSpacing: String, CaseIterable {
    case tight, normal, relaxed, double

    var title: String { rawValue.capitalized }

    var multiple: CGFloat {
        switch self {
        case .tight: return 1.2
        case .normal: return 1.45
        case .relaxed: return 1.7
        case .double: return 2.0
        }
    }
}

/// How text looks and behaves, shared by every window and kept in user defaults.
/// Each change posts `didChange`.
public final class WriterSettings {
    public static let shared = WriterSettings(defaults: .standard)
    public static let didChange = Notification.Name("FallowWriterSettingsDidChange")
    public static let fontSizes: ClosedRange<CGFloat> = 12...36
    static let defaultFontSize: CGFloat = 19

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var fontStyle: FontStyle {
        get { defaults.string(forKey: "fontStyle").flatMap(FontStyle.init) ?? .serif }
        set { set(newValue.rawValue, for: "fontStyle") }
    }

    public var fontSize: CGFloat {
        get {
            let stored = defaults.double(forKey: "fontSize")
            return stored == 0 ? Self.defaultFontSize : min(max(stored, Self.fontSizes.lowerBound), Self.fontSizes.upperBound)
        }
        set { set(Double(min(max(newValue, Self.fontSizes.lowerBound), Self.fontSizes.upperBound)), for: "fontSize") }
    }

    public var lineSpacing: LineSpacing {
        get { defaults.string(forKey: "lineSpacing").flatMap(LineSpacing.init) ?? .normal }
        set { set(newValue.rawValue, for: "lineSpacing") }
    }

    /// Keeps the line being typed in the middle of the window.
    public var typewriterScrolling: Bool {
        get { defaults.object(forKey: "typewriterScrolling") as? Bool ?? true }
        set { set(newValue, for: "typewriterScrolling") }
    }

    public var font: NSFont {
        let base = NSFont.systemFont(ofSize: fontSize)
        guard let descriptor = base.fontDescriptor.withDesign(fontStyle.design) else { return base }
        return NSFont(descriptor: descriptor, size: fontSize) ?? base
    }

    public var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = lineSpacing.multiple
        // Small, because Markdown already separates paragraphs with a blank line.
        style.paragraphSpacing = (fontSize * 0.3).rounded()
        return style
    }

    private func set(_ value: Any, for key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
