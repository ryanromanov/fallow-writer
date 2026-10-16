import AppKit

/// Phase 1's only scene: a soft vertical wash, paper-warm by day and dark loam by night,
/// with a faint glow near the top.
struct GradientBackground: Background {
    func makeLayer() -> CALayer {
        let wash = CAGradientLayer()
        let glow = CAGradientLayer()
        glow.type = .radial
        glow.startPoint = CGPoint(x: 0.5, y: 1.05)
        glow.endPoint = CGPoint(x: 1.25, y: 0.1)
        glow.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        glow.name = "glow"
        wash.addSublayer(glow)
        return wash
    }

    func update(_ layer: CALayer, dark: Bool) {
        guard let wash = layer as? CAGradientLayer else { return }
        let stops: [(CGFloat, CGFloat, CGFloat)] = dark
            ? [(0.15, 0.135, 0.12), (0.115, 0.105, 0.095), (0.085, 0.078, 0.07)]
            : [(0.965, 0.948, 0.915), (0.94, 0.918, 0.875), (0.905, 0.875, 0.82)]
        // Layer y runs upward on macOS, so the first color is the bottom.
        wash.colors = stops.reversed().map { CGColor(srgbRed: $0.0, green: $0.1, blue: $0.2, alpha: 1) }
        wash.locations = [0, 0.55, 1]

        guard let glow = wash.sublayers?.first(where: { $0.name == "glow" }) as? CAGradientLayer else { return }
        glow.frame = wash.bounds
        let light = dark ? CGColor(srgbRed: 1, green: 0.85, blue: 0.7, alpha: 0.05) : CGColor(gray: 1, alpha: 0.45)
        glow.colors = [light, light.copy(alpha: 0)!]
    }
}
