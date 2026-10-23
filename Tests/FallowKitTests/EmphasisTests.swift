import AppKit
import Testing
@testable import FallowCore
@testable import FallowKit

@Suite struct EmphasisTests {
    /// Applies a toggle to text whose selection is marked with `[` and `]` (or `|` for an
    /// insertion point), and returns the result marked the same way.
    func toggle(_ emphasis: Emphasis, _ marked: String) -> String {
        var text = marked
        let selection: NSRange
        if let bar = text.range(of: "|") {
            selection = NSRange(location: text.distance(from: text.startIndex, to: bar.lowerBound), length: 0)
            text.removeSubrange(bar)
        } else {
            let open = text.range(of: "[")!
            let start = text.distance(from: text.startIndex, to: open.lowerBound)
            text.removeSubrange(open)
            let close = text.range(of: "]")!
            let end = text.distance(from: text.startIndex, to: close.lowerBound)
            text.removeSubrange(close)
            selection = NSRange(location: start, length: end - start)
        }
        let edit = emphasis.toggle(in: text as NSString, selection: selection)
        let result = (text as NSString).replacingCharacters(in: edit.range, with: edit.text) as NSString
        if edit.selection.length == 0 {
            return result.replacingCharacters(in: edit.selection, with: "|")
        }
        return result.substring(to: edit.selection.location) + "[" + result.substring(with: edit.selection) + "]"
            + result.substring(from: NSMaxRange(edit.selection))
    }

    @Test func wrapsTheSelection() {
        #expect(toggle(.bold, "a [quiet] place") == "a **[quiet]** place")
        #expect(toggle(.italic, "a [quiet] place") == "a *[quiet]* place")
    }

    @Test func unwrapsWhatsAlreadyMarked() {
        #expect(toggle(.bold, "a **[quiet]** place") == "a [quiet] place")
        #expect(toggle(.italic, "a *[quiet]* place") == "a [quiet] place")
        // The marks selected along with the word.
        #expect(toggle(.bold, "a [**quiet**] place") == "a [quiet] place")
        #expect(toggle(.italic, "a [*quiet*] place") == "a [quiet] place")
    }

    @Test func boldAndItalicCombine() {
        #expect(toggle(.italic, "a **[quiet]** place") == "a ***[quiet]*** place")
        #expect(toggle(.bold, "a *[quiet]* place") == "a ***[quiet]*** place")
        #expect(toggle(.italic, "a ***[quiet]*** place") == "a **[quiet]** place")
        #expect(toggle(.bold, "a ***[quiet]*** place") == "a *[quiet]* place")
    }

    @Test func spacesStayOutsideTheMarks() {
        #expect(toggle(.bold, "a[ quiet ]place") == "a **[quiet]** place")
    }

    @Test func anInsertionPointGetsMarksToTypeBetween() {
        #expect(toggle(.bold, "a | place") == "a **|** place")
        #expect(toggle(.italic, "a | place") == "a *|* place")
        // Pressed again before typing, the marks go.
        #expect(toggle(.bold, "a **|** place") == "a | place")
        #expect(toggle(.italic, "a *|* place") == "a | place")
    }

    /// A test window has no document to give it an undo manager.
    final class UndoKeeper: NSObject, NSWindowDelegate {
        let manager: UndoManager = {
            // Grouped by hand: a test has no event loop to close each group.
            let manager = UndoManager()
            manager.groupsByEvent = false
            return manager
        }()
        func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { manager }
    }

    @Test @MainActor func undoesInOneStep() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let textView = WriterTextView.make(in: scrollView)
        scrollView.documentView = textView
        let window = NSWindow(contentRect: scrollView.frame, styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = scrollView
        let undo = UndoKeeper()
        window.delegate = undo
        textView.string = "a quiet place"
        textView.setSelectedRange(NSRange(location: 2, length: 5))
        undo.manager.beginUndoGrouping()
        textView.toggleBold(nil)
        undo.manager.endUndoGrouping()
        #expect(textView.string == "a **quiet** place")
        #expect(textView.selectedRange() == NSRange(location: 4, length: 5))
        #expect(undo.manager.undoActionName == "Bold")
        undo.manager.undo()
        #expect(textView.string == "a quiet place")
    }
}
