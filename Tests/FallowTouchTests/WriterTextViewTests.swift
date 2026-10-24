#if os(iOS)
import UIKit
import Testing
@testable import FallowTouch

/// Bold and italic write Markdown's marks, as on the Mac, and underline is off.
@Suite @MainActor struct WriterTextViewTests {
    func textView(_ text: String, selecting range: NSRange) -> (WriterTextView, UIWindow) {
        let view = WriterTextView()
        let window = onScreen(view)
        view.text = text
        view.selectedRange = range
        return (view, window)
    }

    @Test func boldWrapsTheSelectionAndUnwrapsIt() {
        let (view, window) = textView("a quiet place", selecting: NSRange(location: 2, length: 5))
        view.toggleBoldface(nil)
        #expect(view.text == "a **quiet** place")
        #expect(view.selectedRange == NSRange(location: 4, length: 5))
        view.toggleBoldface(nil)
        #expect(view.text == "a quiet place")
        _ = window
    }

    @Test func italicWrapsTheSelection() {
        let (view, window) = textView("a quiet place", selecting: NSRange(location: 8, length: 5))
        view.toggleItalics(nil)
        #expect(view.text == "a quiet *place*")
        _ = window
    }

    /// The text view's delegate gets a say, as it does for typing, so edits play and save the same way.
    @Test func emphasisAsksTheDelegate() {
        final class Refuses: NSObject, UITextViewDelegate {
            func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool { false }
        }
        let (view, window) = textView("a quiet place", selecting: NSRange(location: 2, length: 5))
        let delegate = Refuses()
        view.delegate = delegate
        view.toggleBoldface(nil)
        #expect(view.text == "a quiet place")
        _ = window
    }

    @Test func underlineIsOffAndTheRestNeedEditing() {
        let (view, window) = textView("text", selecting: NSRange(location: 0, length: 4))
        #expect(!view.canPerformAction(#selector(UIResponderStandardEditActions.toggleUnderline(_:)), withSender: nil))
        #expect(view.canPerformAction(#selector(UIResponderStandardEditActions.toggleBoldface(_:)), withSender: nil))
        view.isEditable = false
        #expect(!view.canPerformAction(#selector(UIResponderStandardEditActions.toggleBoldface(_:)), withSender: nil))
        _ = window
    }

    @Test func noUnderlineButtonShows() {
        let (view, window) = textView("text", selecting: NSRange(location: 0, length: 0))
        view.hideUnderlineButton()
        let shown = view.inputAssistantItem.trailingBarButtonGroups.flatMap(\.barButtonItems).filter { !$0.isHidden }
        #expect(!shown.contains { $0.action.map(NSStringFromSelector)?.contains("Underline") == true })
        _ = window
    }
}
#endif
