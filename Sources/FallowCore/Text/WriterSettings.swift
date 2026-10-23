import Foundation

public enum FontStyle: String, CaseIterable {
    case serif, sans, mono

    package var title: String {
        switch self {
        case .serif: return "Serif"
        case .sans: return "Sans Serif"
        case .mono: return "Monospaced"
        }
    }

    /// The writing column's width in characters. Monospaced letters are wider, so its lines
    /// are a little shorter to keep a comfortable measure.
    package var measure: CGFloat { self == .mono ? 60 : 66 }
}

public enum LineSpacing: String, CaseIterable {
    case tight, normal, relaxed, double

    package var title: String { rawValue.capitalized }

    package var multiple: CGFloat {
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

    package init(defaults: UserDefaults) {
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

    /// Typed letters settle into place. Off whenever Reduce Motion is on, whatever this says.
    public var animatesTyping: Bool {
        get { defaults.object(forKey: "animatesTyping") as? Bool ?? true }
        set { set(newValue, for: "animatesTyping") }
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

    /// The scene behind the text, by id, or Drift (`Library.driftID`). The library falls back
    /// to Paper if it's missing or locked.
    public var sceneChoice: String {
        get { defaults.string(forKey: "sceneChoice") ?? BuiltIn.paper.id }
        set { set(newValue, for: "sceneChoice") }
    }

    /// The ambient sound, by id, played while `ambientSound` is on.
    public var ambientChoice: String {
        get { defaults.string(forKey: "ambientChoice") ?? BuiltIn.lowField.id }
        set { set(newValue, for: "ambientChoice") }
    }

    /// The keystroke sounds, by id, played while `keystrokeSounds` is on.
    public var keystrokeChoice: String {
        get { defaults.string(forKey: "keystrokeChoice") ?? BuiltIn.marimba.id }
        set { set(newValue, for: "keystrokeChoice") }
    }

    private func set(_ value: Any, for key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
