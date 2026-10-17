import AppKit

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}

/// Colors for text and chrome, chosen to sit on the soil-toned backgrounds.
enum Palette {
    static let text = NSColor(name: nil) { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 0.86, green: 0.83, blue: 0.78, alpha: 1)
            : NSColor(srgbRed: 0.21, green: 0.19, blue: 0.16, alpha: 1)
    }
    static let secondary = NSColor(name: nil) { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 0.86, green: 0.83, blue: 0.78, alpha: 0.45)
            : NSColor(srgbRed: 0.21, green: 0.19, blue: 0.16, alpha: 0.45)
    }
    /// A loamy brown for the insertion point.
    static let caret = NSColor(name: nil) { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 0.80, green: 0.56, blue: 0.38, alpha: 1)
            : NSColor(srgbRed: 0.60, green: 0.36, blue: 0.21, alpha: 1)
    }
    static let selection = NSColor(name: nil) { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 0.80, green: 0.56, blue: 0.38, alpha: 0.28)
            : NSColor(srgbRed: 0.60, green: 0.36, blue: 0.21, alpha: 0.18)
    }
}
