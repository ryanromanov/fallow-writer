#if os(iOS)
import UIKit

/// Fades the screen's controls out while you type and back in when you touch the screen or
/// scroll, as the Mac app does with the mouse, so the text is all there is.
///
/// Faded controls can't be tapped (UIKit skips views that are nearly transparent), so a tap
/// where one was brings the controls back instead of choosing something unseen.
final class ChromeFader {
    private let views: () -> [UIView]
    private(set) var isHidden = false

    init(views: @escaping () -> [UIView]) {
        self.views = views
    }

    func typed() {
        guard !isHidden else { return }
        isHidden = true
        fade(to: 0, duration: 0.9)
    }

    func show() {
        guard isHidden else { return }
        isHidden = false
        fade(to: 1, duration: 0.3)
    }

    private func fade(to alpha: CGFloat, duration: TimeInterval) {
        UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction]) {
            for view in self.views() { view.alpha = alpha }
        }
    }
}
#endif
