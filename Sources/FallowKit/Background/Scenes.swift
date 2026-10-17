import AppKit

/// One scene's colors: a vertical wash (top, middle, bottom) and a soft glow from the top.
public struct ScenePalette: Equatable {
    public let top: UInt32, middle: UInt32, bottom: UInt32
    public let glow: UInt32, glowAlpha: CGFloat

    /// Colors as 0xRRGGBB in sRGB. Text is drawn in Fallow's own colors over every scene, so a
    /// light palette needs dark-enough text contrast (7:1) and a dark one the reverse.
    public init(top: UInt32, middle: UInt32, bottom: UInt32, glow: UInt32, glowAlpha: CGFloat) {
        self.top = top
        self.middle = middle
        self.bottom = bottom
        self.glow = glow
        self.glowAlpha = glowAlpha
    }

    static func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
    }

    /// The wash for a CAGradientLayer, whose y runs upward on macOS: bottom color first.
    var washColors: [CGColor] { [bottom, middle, top].map { Self.color($0) } }
    var glowColors: [CGColor] { [Self.color(glow, alpha: glowAlpha), Self.color(glow, alpha: 0)] }
}

/// Paints the chosen scene behind the text. Switching scenes crossfades; Drift is one long
/// Core Animation loop that the render server runs on its own, so it costs no CPU here.
final class BackgroundView: NSView {
    /// Seconds Drift holds each scene, and then spends moving to the next.
    static let driftHold: CFTimeInterval = 30
    static let driftMove: CFTimeInterval = 30
    static let crossfade: CFTimeInterval = 1.2

    /// A scene's id, or Drift's.
    var choice: String = BuiltIn.paper.id {
        didSet { if choice != oldValue { repaint(animated: true) } }
    }
    var library = Library.shared

    private let wash = CAGradientLayer()
    private let glow = CAGradientLayer()
    /// What's painted now, so layout and redisplay don't restart a crossfade or Drift.
    private var painted: (choice: String, dark: Bool)?

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

    /// Repaints after packs are added or unlocked, which can change what a choice shows.
    func libraryChanged() {
        painted = nil
        repaint(animated: true)
    }

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

        let palettes = (library.scene(for: choice).map { [$0] } ?? library.driftScenes).map { $0.palette(dark: dark) }
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
