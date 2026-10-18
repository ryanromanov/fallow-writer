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

/// Something that moves over a scene's colors, such as drifting particles. Core Animation runs
/// it in the render server, so it costs Fallow no CPU while it plays. Motion is left out when
/// Reduce Motion is on, and removed while the window can't be seen.
///
/// Keep it slow and faint: it sits behind the text the whole time someone is writing.
public protocol SceneMotion {
    /// Makes the moving layer, for the light or the dark palette. It's made again whenever it
    /// comes back into view, so it shouldn't depend on having run before.
    func makeLayer(dark: Bool) -> CALayer
    /// Fits the layer to the background whenever its size changes. By default, fills it.
    func layout(_ layer: CALayer, in bounds: CGRect)
    /// How long the motion seems to have been running already when it appears, so particles
    /// are spread across the window instead of all starting at once.
    var warmUp: CFTimeInterval { get }
}

extension SceneMotion {
    public func layout(_ layer: CALayer, in bounds: CGRect) { layer.frame = bounds }
    public var warmUp: CFTimeInterval { 0 }
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
    /// Whether to leave motion out. Replaced in tests.
    var reducesMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// Whether the window can be seen at all. Replaced in tests.
    lazy var isOnScreen: () -> Bool = { [weak self] in self?.window?.occlusionState.contains(.visible) ?? false }

    private let wash = CAGradientLayer()
    private let glow = CAGradientLayer()
    /// What's painted now, so layout and redisplay don't restart a crossfade or Drift.
    private var painted: (choice: String, dark: Bool)?

    /// A scene's motion, inside a holder layer that fades it with the scene. The holder stays while
    /// the motion itself is taken out, when Reduce Motion is on or the window is hidden.
    private struct Moving {
        let holder: CALayer
        let motion: SceneMotion
        let dark: Bool
    }
    private var moving: [Moving] = []

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        glow.type = .radial
        glow.startPoint = CGPoint(x: 0.5, y: 1.05)
        glow.endPoint = CGPoint(x: 1.25, y: 0.1)
        wash.locations = [0, 0.55, 1]
        wash.addSublayer(glow)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(motionMayHaveChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit { NSWorkspace.shared.notificationCenter.removeObserver(self) }

    override func makeBackingLayer() -> CALayer { wash }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if let window {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: window)
        }
        if let newWindow {
            NotificationCenter.default.addObserver(
                self, selector: #selector(motionMayHaveChanged),
                name: NSWindow.didChangeOcclusionStateNotification, object: newWindow)
        }
    }

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
        for item in moving {
            item.holder.frame = wash.bounds
            for layer in item.holder.sublayers ?? [] { item.motion.layout(layer, in: wash.bounds) }
        }
        CATransaction.commit()
    }

    /// Whether Drift's loop is running, for tests.
    var isDrifting: Bool { wash.animation(forKey: "drift") != nil }
    /// The motion layers playing now, for tests.
    var motionLayers: [CALayer] { moving.flatMap { $0.holder.sublayers ?? [] } }

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

        let scenes = library.scene(for: choice).map { [$0] } ?? library.driftScenes
        let palettes = scenes.map { $0.palette(dark: dark) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wash.colors = palettes[0].washColors
        glow.colors = palettes[0].glowColors
        CATransaction.commit()

        // Drift goes on first so the crossfade, added after it, shows over Drift's held start.
        let delay = animated ? Self.crossfade : 0
        if palettes.count > 1 {
            let times = Self.driftTimes(count: palettes.count)
            loop(wash, "colors", values: Self.driftValues(palettes.map(\.washColors)), times: times, delay: delay)
            loop(glow, "colors", values: Self.driftValues(palettes.map(\.glowColors)), times: times, delay: delay)
        }
        if animated, let fromWash, let fromGlow {
            crossfade(wash, "colors", from: fromWash, to: palettes[0].washColors)
            crossfade(glow, "colors", from: fromGlow, to: palettes[0].glowColors)
        }
        showMotion(of: scenes, dark: dark, animated: animated)
    }

    // MARK: Motion

    /// Fades out the motion on screen and sets up each scene's own. In Drift, each scene's motion
    /// fades in and out with its colors.
    private func showMotion(of scenes: [Scenery], dark: Bool, animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for item in moving { retire(item.holder, animated: animated) }
        moving = []
        for (index, scene) in scenes.enumerated() {
            guard let motion = scene.motion else { continue }
            let holder = CALayer()
            holder.frame = wash.bounds
            holder.opacity = index == 0 ? 1 : 0
            wash.addSublayer(holder)
            if scenes.count > 1 {
                let (values, times) = Self.driftOpacity(index: index, count: scenes.count)
                loop(holder, "opacity", values: values, times: times, delay: animated ? Self.crossfade : 0)
            }
            if animated, index == 0 { crossfade(holder, "opacity", from: 0, to: 1) }
            moving.append(Moving(holder: holder, motion: motion, dark: dark))
        }
        CATransaction.commit()
        motionMayHaveChanged()
    }

    /// Puts motion in while it can be seen and Reduce Motion is off, and takes it out otherwise.
    @objc func motionMayHaveChanged() {
        let allowed = !reducesMotion() && isOnScreen()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for item in moving {
            let playing = !(item.holder.sublayers ?? []).isEmpty
            if allowed, !playing {
                let layer = item.motion.makeLayer(dark: item.dark)
                item.motion.layout(layer, in: item.holder.bounds)
                layer.beginTime = item.holder.convertTime(CACurrentMediaTime(), from: nil) - item.motion.warmUp
                item.holder.addSublayer(layer)
            } else if !allowed, playing {
                item.holder.sublayers?.forEach { $0.removeFromSuperlayer() }
            }
        }
        CATransaction.commit()
    }

    /// Fades a scene's motion away and then removes it.
    private func retire(_ holder: CALayer, animated: Bool) {
        let from = holder.presentation()?.opacity ?? holder.opacity
        holder.removeAllAnimations()
        holder.opacity = 0
        guard animated, from > 0 else { return holder.removeFromSuperlayer() }
        CATransaction.begin()
        CATransaction.setCompletionBlock { holder.removeFromSuperlayer() }
        crossfade(holder, "opacity", from: from, to: 0)
        CATransaction.commit()
    }

    // MARK: Animations

    private func crossfade(_ layer: CALayer, _ keyPath: String, from: Any, to: Any) {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = Self.crossfade
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "crossfade")
    }

    /// One endless Drift loop, through every scene and back to the first.
    private func loop(_ layer: CALayer, _ keyPath: String, values: [Any], times: [NSNumber], delay: CFTimeInterval) {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = times
        animation.duration = (Self.driftHold + Self.driftMove) * Double(times.count - 1) / 2
        animation.repeatCount = .infinity
        animation.calculationMode = .linear
        animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + delay
        animation.fillMode = .backwards
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: "drift")
    }

    /// Drift's key times: each scene is held, then eased into the next, and the last returns to the first.
    static func driftTimes(count: Int) -> [NSNumber] {
        let step = driftHold + driftMove, total = step * Double(count)
        var times: [NSNumber] = []
        for index in 0..<count {
            times += [NSNumber(value: Double(index) * step / total), NSNumber(value: (Double(index) * step + driftHold) / total)]
        }
        return times + [1]
    }

    /// Each value held, then the first again at the end, to go with `driftTimes`.
    static func driftValues(_ values: [Any]) -> [Any] {
        values.flatMap { [$0, $0] } + [values[0]]
    }

    /// One scene's motion in Drift: fully there while its colors are held, fading in and out
    /// while they move.
    static func driftOpacity(index: Int, count: Int) -> (values: [Any], times: [NSNumber]) {
        let values: [Float] = (0..<count).flatMap { $0 == index ? [1, 1] : [0, 0] as [Float] } + [index == 0 ? 1 : 0]
        return (values, driftTimes(count: count))
    }
}
