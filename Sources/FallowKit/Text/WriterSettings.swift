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

    public var keystrokeSounds: Bool {
        get { defaults.object(forKey: "keystrokeSounds") as? Bool ?? true }
        set { set(newValue, for: "keystrokeSounds") }
    }

    public var ambientSound: Bool {
        get { defaults.object(forKey: "ambientSound") as? Bool ?? true }
        set { set(newValue, for: "ambientSound") }
    }

    /// Keystrokes start about 8 dB down: at full level their sharp attack stands well above the ambient sound.
    static let defaultKeystrokeVolume: Float = 0.4

    /// 0…1, applied to all keystroke sounds.
    public var keystrokeVolume: Float {
        get { (defaults.object(forKey: "keystrokeVolume") as? Float).map { min(max($0, 0), 1) } ?? Self.defaultKeystrokeVolume }
        set { set(min(max(newValue, 0), 1), for: "keystrokeVolume") }
    }

    /// 0…1, applied to the ambient scene.
    public var ambientVolume: Float {
        get { (defaults.object(forKey: "ambientVolume") as? Float).map { min(max($0, 0), 1) } ?? 1 }
        set { set(min(max(newValue, 0), 1), for: "ambientVolume") }
    }

    public var ambientChoice: AmbientChoice {
        get { defaults.string(forKey: "ambientChoice").flatMap(AmbientChoice.init) ?? .lowField }
        set { set(newValue.rawValue, for: "ambientChoice") }
    }

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
