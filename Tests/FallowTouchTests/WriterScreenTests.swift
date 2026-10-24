#if os(iOS)
import UIKit
import Testing
@testable import FallowTouch

/// The writing screen: its layout, status line, fading controls, letters and shortcuts.
@Suite @MainActor struct WriterScreenTests {
    func screen(_ settings: WriterSettings = freshSettings()) -> (WriterViewController, UIWindow) {
        let controller = WriterViewController(settings: settings)
        let window = onScreen(controller.view)
        return (controller, window)
    }

    /// The column is centered, and with typewriter scrolling there's room for any line to sit
    /// in the middle.
    @Test func columnIsCenteredWithRoomAboveAndBelow() {
        let settings = freshSettings()
        let (controller, window) = screen(settings)
        let textView = controller.textView
        let inset = textView.textContainerInset
        #expect(inset.left == inset.right)
        #expect(inset.left >= WriterViewController.minimumMargin)
        #expect(inset.top >= textView.bounds.height / 2 - settings.font.lineHeight - 1)
        #expect(inset.top == inset.bottom)
        _ = window
    }

    @Test func withoutTypewriterScrollingTheTextStartsAtTheTop() {
        let settings = freshSettings()
        settings.typewriterScrolling = false
        let (controller, window) = screen(settings)
        #expect(controller.textView.textContainerInset.top == 48)
        _ = window
    }

    @Test func statusCountsWords() {
        let (controller, window) = screen()
        #expect(controller.statusLabel.text == "Untitled · 0 words")
        controller.textView.text = "A quiet place"
        controller.textViewDidChange(controller.textView)
        #expect(controller.statusLabel.text?.hasSuffix("3 words") == true)
        _ = window
    }

    /// Typing fades the controls; touching the screen brings them back.
    @Test func controlsFadeWhileTyping() {
        let (controller, window) = screen()
        let controls = [controller.statusLabel, controller.soundButton, controller.documentButton] as [UIView]
        controller.fader.typed()
        #expect(controller.fader.isHidden)
        #expect(controls.allSatisfy { $0.alpha == 0 })
        controller.fader.show()
        #expect(!controller.fader.isHidden)
        #expect(controls.allSatisfy { $0.alpha == 1 })
        _ = window
    }

    @Test func shortcutsMatchTheMac() {
        let (controller, window) = screen()
        let commands = controller.keyCommands ?? []
        func command(_ input: String, _ modifiers: UIKeyModifierFlags) -> UIKeyCommand? {
            commands.first { $0.input == input && $0.modifierFlags == modifiers }
        }
        for arrow in [UIKeyCommand.inputLeftArrow, UIKeyCommand.inputRightArrow, UIKeyCommand.inputUpArrow, UIKeyCommand.inputDownArrow] {
            // The arrows would otherwise go to the text view, to move the insertion point.
            #expect(command(arrow, [.command, .control])?.wantsPriorityOverSystemBehavior == true)
        }
        #expect(command("s", [.command, .control])?.title == "Scene and Sound…")
        #expect(command("n", .command) != nil)
        #expect(command("o", .command) != nil)
        #expect(command("p", .command) != nil)
        _ = window
    }

    /// One-finger scrolling only, so a two-finger swipe doesn't move the page.
    @Test func twoFingersSwipeRatherThanScroll() {
        let (controller, window) = screen()
        let textView = controller.textView
        #expect(textView.panGestureRecognizer.maximumNumberOfTouches == 1)
        #expect(textView.gestureRecognizers?.contains { $0 is TwoFingerSwipe } == true)
        _ = window
    }

    /// A typed letter settles into place, and everything settles at once when asked.
    @Test func lettersSettle() {
        let settings = freshSettings()
        let (controller, window) = screen(settings)
        let textView = controller.textView
        textView.text = "Quiet"
        textView.textStorage.setAttributes([.font: settings.font], range: NSRange(location: 0, length: 5))
        textView.layoutIfNeeded()
        controller.letters.animate(NSRange(location: 4, length: 1))
        #expect(controller.letters.runningCount == 1)
        controller.letters.finishAll()
        #expect(controller.letters.runningCount == 0)
        _ = window
    }
}
#endif
