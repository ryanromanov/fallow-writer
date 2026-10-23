import QuartzCore

/// Paints the chosen scene in Core Animation layers, for a view to host. Switching scenes
/// crossfades; Drift is one long Core Animation loop that the render server runs on its own, so
/// it costs no CPU here.
///
/// The layers assume y runs upward, as on the Mac: the wash lists its colors bottom first, the
/// glow comes from the top, and scenes' motion falls toward y = 0. A host where y runs downward
/// (UIKit) sets `isGeometryFlipped` on `root`.
package final class SceneLayers {
    /// Seconds Drift holds each scene, and then spends moving to the next.
    package static let driftHold: CFTimeInterval = 30
    package static let driftMove: CFTimeInterval = 30
    package static let crossfade: CFTimeInterval = 1.2

    /// The layer to host, sized to fill the view. Everything else is inside it.
    package var root: CALayer { wash }
    package var library = Library.shared
    /// Whether to leave motion out, such as when Reduce Motion is on.
    package var reducesMotion: () -> Bool = { false }
    /// Whether the scene can be seen at all.
    package var isOnScreen: () -> Bool = { true }

    private let wash = CAGradientLayer()
    private let glow = CAGradientLayer()
    /// What's painted now, so layout and redisplay don't restart a crossfade or Drift.
    private var painted: (choice: String, dark: Bool)?

    /// A scene's motion, inside a holder layer that fades it with the scene. The holder stays while
    /// the motion itself is taken out, when Reduce Motion is on or the scene is hidden.
    private struct Moving {
        let holder: CALayer
        let motion: SceneMotion
        let dark: Bool
    }
    private var moving: [Moving] = []

    package init() {
        glow.type = .radial
        glow.startPoint = CGPoint(x: 0.5, y: 1.05)
        glow.endPoint = CGPoint(x: 1.25, y: 0.1)
        wash.locations = [0, 0.55, 1]
        wash.addSublayer(glow)
    }

    /// Fits everything to `root`'s bounds. Call after its size changes.
    package func layout() {
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
    package var isDrifting: Bool { wash.animation(forKey: "drift") != nil }
    /// The motion layers playing now, for tests.
    package var motionLayers: [CALayer] { moving.flatMap { $0.holder.sublayers ?? [] } }

    /// Paints a scene's id, or Drift's, in the light or dark palette. Does nothing if that's
    /// what's painted already.
    package func paint(_ choice: String, dark: Bool, animated: Bool) {
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

    /// Forgets what's painted, so the next `paint` paints again even for the same choice. Call
    /// after packs are added or unlocked, which can change what a choice shows.
    package func forgetPainted() {
        painted = nil
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

    /// Puts motion in while it can be seen and isn't reduced, and takes it out otherwise. Call
    /// whenever either may have changed.
    package func motionMayHaveChanged() {
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
    package static func driftTimes(count: Int) -> [NSNumber] {
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
    package static func driftOpacity(index: Int, count: Int) -> (values: [Any], times: [NSNumber]) {
        let values: [Float] = (0..<count).flatMap { $0 == index ? [1, 1] : [0, 0] as [Float] } + [index == 0 ? 1 : 0]
        return (values, driftTimes(count: count))
    }
}
