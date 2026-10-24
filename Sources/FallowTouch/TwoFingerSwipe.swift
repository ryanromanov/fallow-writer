#if os(iOS)
import UIKit

/// A swipe with two fingers on the text view, in one of four directions.
///
/// The text view starts scrolling or selecting as soon as one finger is down, and the second
/// finger of a swipe always lands a moment later. So when it does, this stops whatever the text
/// view started and puts the scroll position and the selection back as they were.
final class TwoFingerSwipe: UIGestureRecognizer {
    enum Direction { case left, right, up, down }

    /// Set when the swipe is recognized.
    private(set) var direction: Direction?
    /// How far the fingers travel before it counts as a swipe.
    static let distance: CGFloat = 40

    private var start: CGPoint?
    private var offsetBefore: CGPoint?
    private var selectionBefore: NSRange?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let textView = view as? UITextView else { return state = .failed }
        let count = numberOfTouches
        if count == touches.count {
            // The first fingers down: remember how things were before the text view acts on them.
            offsetBefore = textView.contentOffset
            selectionBefore = textView.selectedRange
        }
        if count > 2 {
            state = state == .possible ? .failed : .cancelled
        } else if count == 2, state == .possible {
            start = centroid
            stopTextView(textView)
            state = .began
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let start, state == .began || state == .changed, numberOfTouches == 2 else { return }
        let point = centroid
        guard let direction = Self.direction(dx: point.x - start.x, dy: point.y - start.y) else { return state = .changed }
        self.direction = direction
        state = .ended
    }

    /// The way fingers that moved this far went, along whichever axis they moved more; nil until
    /// they've gone far enough.
    static func direction(dx: CGFloat, dy: CGFloat) -> Direction? {
        guard max(abs(dx), abs(dy)) >= distance else { return nil }
        return abs(dx) > abs(dy) ? (dx < 0 ? .left : .right) : (dy < 0 ? .up : .down)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        finish()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        finish()
    }

    /// Lifting a finger before the fingers have gone far enough means it wasn't a swipe.
    private func finish() {
        switch state {
        case .possible: state = .failed
        case .began, .changed: state = .cancelled
        default: break
        }
    }

    override func reset() {
        direction = nil
        start = nil
        offsetBefore = nil
        selectionBefore = nil
    }

    /// Cancels the text view's own gestures (switching one off and on cancels it) and undoes any
    /// scrolling or selecting they did with the first finger.
    private func stopTextView(_ textView: UITextView) {
        for recognizer in textView.gestureRecognizers ?? [] where recognizer !== self && recognizer.isEnabled {
            recognizer.isEnabled = false
            recognizer.isEnabled = true
        }
        if let offsetBefore { textView.setContentOffset(offsetBefore, animated: false) }
        if let selectionBefore, textView.selectedRange != selectionBefore { textView.selectedRange = selectionBefore }
    }

    private var centroid: CGPoint {
        // In the window, since putting the text view's scroll position back moves its own coordinates.
        let points = (0..<numberOfTouches).map { location(ofTouch: $0, in: nil) }
        return CGPoint(x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
                       y: points.map(\.y).reduce(0, +) / CGFloat(points.count))
    }
}
#endif
