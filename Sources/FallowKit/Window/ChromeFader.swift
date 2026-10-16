import AppKit

/// Fades the window's controls out while you type and back in when you move the mouse,
/// so the text is all there is on screen.
final class ChromeFader {
    /// Mouse travel, in points, that counts as deliberate. Smaller jitters are ignored.
    private static let threshold: CGFloat = 8

    private let views: () -> [NSView]
    private(set) var isHidden = false
    private var travel: CGFloat = 0

    init(views: @escaping () -> [NSView]) {
        self.views = views
    }

    func typed() {
        travel = 0
        guard !isHidden else { return }
        isHidden = true
        fade(to: 0, duration: 0.9)
    }

    func mouseMoved(by delta: CGFloat) {
        guard isHidden else { return }
        travel += delta
        if travel >= Self.threshold { show() }
    }

    func show() {
        travel = 0
        guard isHidden else { return }
        isHidden = false
        fade(to: 1, duration: 0.3)
    }

    private func fade(to alpha: CGFloat, duration: TimeInterval) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for view in views() { view.animator().alphaValue = alpha }
        }
    }
}
