import AppKit

/// What sits behind the text. Later phases add more scenes, and packs supply their own.
protocol Background {
    func makeLayer() -> CALayer
    /// Called when the layer is created and whenever the appearance changes.
    func update(_ layer: CALayer, dark: Bool)
}

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

/// Hosts a `Background`'s layer and keeps it in step with light and dark appearance.
final class BackgroundView: NSView {
    private let background: Background

    init(background: Background) {
        self.background = background
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func makeBackingLayer() -> CALayer { background.makeLayer() }

    // AppKit doesn't call updateLayer for a layer the view makes itself, so recolor directly.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        recolor()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        recolor()
    }

    override func layout() {
        super.layout()
        recolor()
    }

    private func recolor() {
        guard let layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        background.update(layer, dark: effectiveAppearance.isDark)
        CATransaction.commit()
    }
}
