import QuartzCore

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

    package static func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
    }

    /// The wash for a CAGradientLayer, whose y runs upward on macOS: bottom color first.
    package var washColors: [CGColor] { [bottom, middle, top].map { Self.color($0) } }
    package var glowColors: [CGColor] { [Self.color(glow, alpha: glowAlpha), Self.color(glow, alpha: 0)] }
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
