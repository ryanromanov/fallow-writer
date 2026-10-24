#if os(iOS)
import UIKit
import Testing
@testable import FallowTouch

/// Which keystroke sound each edit plays, and which way a two-finger swipe went.
@Suite struct InputTests {
    func kind(_ location: Int, _ length: Int, _ text: String) -> KeyClass? {
        KeyClass(replacing: NSRange(location: location, length: length), with: text)
    }

    @Test func singleKeysHaveSounds() {
        #expect(kind(3, 0, "a") == .letter)
        #expect(kind(3, 0, "é") == .letter)
        #expect(kind(3, 0, " ") == .space)
        #expect(kind(3, 0, "\t") == .space)
        #expect(kind(3, 0, "\n") == .newline)
        #expect(kind(3, 1, "") == .delete)
    }

    /// Pastes, autocorrections and typing over a selection aren't one key, so they're silent.
    @Test func otherEditsAreSilent() {
        #expect(kind(3, 0, "") == nil)
        #expect(kind(3, 0, "pasted") == nil)
        #expect(kind(0, 4, "Their") == nil)
        #expect(kind(3, 2, "a") == nil)
    }

    @Test func swipesGoAlongTheLongerAxis() {
        let far = TwoFingerSwipe.distance
        #expect(TwoFingerSwipe.direction(dx: -far, dy: 5) == .left)
        #expect(TwoFingerSwipe.direction(dx: far, dy: -10) == .right)
        #expect(TwoFingerSwipe.direction(dx: 12, dy: -far) == .up)
        #expect(TwoFingerSwipe.direction(dx: -3, dy: far + 20) == .down)
    }

    @Test func shortMovesAreNoSwipe() {
        let near = TwoFingerSwipe.distance - 1
        #expect(TwoFingerSwipe.direction(dx: near, dy: 0) == nil)
        #expect(TwoFingerSwipe.direction(dx: 0, dy: -near) == nil)
        #expect(TwoFingerSwipe.direction(dx: 0, dy: 0) == nil)
    }
}
#endif
