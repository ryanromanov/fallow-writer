import AppKit

/// One scene's colors: a vertical wash (top, middle, bottom) and a soft glow from the top.
struct ScenePalette: Equatable {
    let top: UInt32, middle: UInt32, bottom: UInt32
    let glow: UInt32, glowAlpha: CGFloat

    static func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
    }

    /// The wash for a CAGradientLayer, whose y runs upward on macOS: bottom color first.
    var washColors: [CGColor] { [bottom, middle, top].map { Self.color($0) } }
    var glowColors: [CGColor] { [Self.color(glow, alpha: glowAlpha), Self.color(glow, alpha: 0)] }
}

/// The scenes behind the text. Each is a light and dark pair, so Fallow keeps following the
/// Mac's appearance; Drift (chromotherapy) moves slowly through the scenes of the current one.
public enum SceneChoice: String, CaseIterable {
    case paper, dusk, mist, meadow, drift

    static let scenes: [SceneChoice] = [.paper, .dusk, .mist, .meadow]

    /// One name per scene, day and night alike.
    var title: String {
        switch self {
        case .paper: return "Paper"
        case .dusk: return "Dusk"
        case .mist: return "Mist"
        case .meadow: return "Meadow"
        case .drift: return "Drift"
        }
    }

    /// The menu's longer name, which explains Drift.
    var menuTitle: String { self == .drift ? "Drift (Chromotherapy)" : title }

    /// Nil for Drift, which has no single palette.
    func palette(dark: Bool) -> ScenePalette? {
        switch (self, dark) {
        case (.paper, false): return ScenePalette(top: 0xF6F2EA, middle: 0xF0EADF, bottom: 0xE7DFD1, glow: 0xFFFFFF, glowAlpha: 0.45)
        case (.paper, true): return ScenePalette(top: 0x26221F, middle: 0x1D1B18, bottom: 0x161412, glow: 0xFFD9B3, glowAlpha: 0.05)
        case (.dusk, false): return ScenePalette(top: 0xF9E1CF, middle: 0xF2CDC3, bottom: 0xE0C3D4, glow: 0xFFF0DC, glowAlpha: 0.5)
        case (.dusk, true): return ScenePalette(top: 0x3A2420, middle: 0x2C1B19, bottom: 0x201414, glow: 0xFF8A55, glowAlpha: 0.12)
        case (.mist, false): return ScenePalette(top: 0xE5EEE7, middle: 0xD7E3DB, bottom: 0xC6D6CF, glow: 0xFFFFFF, glowAlpha: 0.45)
        case (.mist, true): return ScenePalette(top: 0x1F2542, middle: 0x181C34, bottom: 0x121528, glow: 0x9FB1FF, glowAlpha: 0.1)
        case (.meadow, false): return ScenePalette(top: 0xF4EFD0, middle: 0xE6E8C2, bottom: 0xD3DCAD, glow: 0xFFFCE0, glowAlpha: 0.45)
        case (.meadow, true): return ScenePalette(top: 0x23311F, middle: 0x1A2518, bottom: 0x131B12, glow: 0xB8E08A, glowAlpha: 0.09)
        case (.drift, _): return nil
        }
    }
}

/// Paints the chosen scene behind the text. Switching scenes crossfades; Drift is one long
/// Core Animation loop that the render server runs on its own, so it costs no CPU here.
final class BackgroundView: NSView {
    /// Seconds Drift holds each scene, and then spends moving to the next.
    static let driftHold: CFTimeInterval = 30
    static let driftMove: CFTimeInterval = 30
    static let crossfade: CFTimeInterval = 1.2

    var choice: SceneChoice = .paper {
        didSet { if choice != oldValue { repaint(animated: true) } }
    }

    private let wash = CAGradientLayer()
    private let glow = CAGradientLayer()
    /// What's painted now, so layout and redisplay don't restart a crossfade or Drift.
    private var painted: (choice: SceneChoice, dark: Bool)?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        glow.type = .radial
        glow.startPoint = CGPoint(x: 0.5, y: 1.05)
        glow.endPoint = CGPoint(x: 1.25, y: 0.1)
        wash.locations = [0, 0.55, 1]
        wash.addSublayer(glow)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func makeBackingLayer() -> CALayer { wash }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        repaint(animated: false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        repaint(animated: false)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glow.frame = wash.bounds
        CATransaction.commit()
    }

    /// Whether Drift's loop is running, for tests.
    var isDrifting: Bool { wash.animation(forKey: "drift") != nil }

    private func repaint(animated: Bool) {
        let dark = effectiveAppearance.isDark
        if let painted, painted.choice == choice, painted.dark == dark { return }
        painted = (choice, dark)

        // Start any change from what's on screen, mid-crossfade or mid-drift included.
        let fromWash = wash.presentation()?.colors ?? wash.colors
        let fromGlow = glow.presentation()?.colors ?? glow.colors
        for layer in [wash, glow] {
            layer.removeAnimation(forKey: "drift")
            layer.removeAnimation(forKey: "crossfade")
        }

        let palettes = choice == .drift
            ? SceneChoice.scenes.compactMap { $0.palette(dark: dark) }
            : [choice.palette(dark: dark)!]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wash.colors = palettes[0].washColors
        glow.colors = palettes[0].glowColors
        CATransaction.commit()

        if animated, let fromWash, let fromGlow {
            crossfade(wash, from: fromWash, to: palettes[0].washColors)
            crossfade(glow, from: fromGlow, to: palettes[0].glowColors)
        }
        if palettes.count > 1 {
            drift(wash, through: palettes.map(\.washColors), delay: animated ? Self.crossfade : 0)
            drift(glow, through: palettes.map(\.glowColors), delay: animated ? Self.crossfade : 0)
        }
    }

    private func crossfade(_ layer: CAGradientLayer, from: [Any], to: [CGColor]) {
        let animation = CABasicAnimation(keyPath: "colors")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = Self.crossfade
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "crossfade")
    }

    /// Holds each palette, then eases to the next, and loops back to the first.
    private func drift(_ layer: CAGradientLayer, through palettes: [[CGColor]], delay: CFTimeInterval) {
        let step = Self.driftHold + Self.driftMove
        let total = step * Double(palettes.count)
        var values: [[CGColor]] = [], times: [NSNumber] = []
        for (index, colors) in palettes.enumerated() {
            values += [colors, colors]
            times += [NSNumber(value: Double(index) * step / total), NSNumber(value: (Double(index) * step + Self.driftHold) / total)]
        }
        values.append(palettes[0])
        times.append(1)
        let animation = CAKeyframeAnimation(keyPath: "colors")
        animation.values = values
        animation.keyTimes = times
        animation.duration = total
        animation.repeatCount = .infinity
        animation.calculationMode = .linear
        animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + delay
        animation.fillMode = .backwards
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: "drift")
    }
}
