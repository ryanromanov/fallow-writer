import AppKit
import Testing
@testable import FallowKit

/// The animation's promises: a letter is hidden only while its copy animates, nothing is ever
/// left transparent, and the text, undo and edited state are exactly what typing alone makes.
@Suite @MainActor struct LetterAnimatorTests {
    func makeWindow(animates: Bool = true) -> (TextDocument, WriterTextView) {
        _ = NSApplication.shared
        let name = "FallowLetters-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = WriterSettings(defaults: defaults)
        settings.animatesTyping = animates
        let document = TextDocument()
        let controller = WriterWindowController(settings: settings)
        document.addWindowController(controller)
        controller.show("")
        controller.window!.orderFrontRegardless()
        let textView = controller.writerView.textView
        textView.window?.makeFirstResponder(textView)
        return (document, textView)
    }

    func type(_ text: String, into textView: WriterTextView) {
        for character in text {
            textView.insertText(String(character), replacementRange: textView.selectedRange())
        }
    }

    @Test func typedLetterIsHiddenOnlyWhileItAnimates() {
        let (document, textView) = makeWindow()
        type("a", into: textView)
        #expect(textView.letters.runningCount == 1)
        #expect(textView.letters.hiddenRanges() == [NSRange(location: 0, length: 1)])
        textView.letters.finishAll()
        #expect(textView.letters.runningCount == 0)
        #expect(textView.letters.hiddenRanges().isEmpty)
        #expect(textView.string == "a")
        document.close()
    }

    @Test func animationsEndOnTheirOwn() {
        let (document, textView) = makeWindow()
        type("Fallow", into: textView)
        RunLoop.main.run(until: Date().addingTimeInterval(LetterAnimator.duration + 0.5))
        #expect(textView.letters.runningCount == 0)
        #expect(textView.letters.hiddenRanges().isEmpty)
        document.close()
    }

    @Test func spacesAndNewlinesDoNotAnimate() {
        let (document, textView) = makeWindow()
        type(" \n", into: textView)
        #expect(textView.letters.runningCount == 0)
        document.close()
    }

    @Test func fastTypingAndDeletesLeaveNothingHidden() {
        let (document, textView) = makeWindow()
        type("quick bro", into: textView)
        textView.deleteBackward(nil)
        textView.deleteBackward(nil)
        type("own fox", into: textView)
        textView.letters.finishAll()
        #expect(textView.letters.hiddenRanges().isEmpty)
        #expect(textView.string == "quick bown fox")
        document.close()
    }

    @Test func undoBringsBackNothingInvisible() {
        let (document, textView) = makeWindow()
        type("soil", into: textView)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        textView.undoManager?.undo()
        textView.undoManager?.redo()
        #expect(textView.letters.hiddenRanges().isEmpty)
        #expect(textView.letters.runningCount == 0)
        document.close()
    }

    @Test func animationChangesNeitherTextNorEditedState() throws {
        let (document, textView) = makeWindow()
        type("rest", into: textView)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let undoBefore = textView.undoManager?.canUndo
        textView.letters.finishAll()
        #expect(textView.undoManager?.canUndo == undoBefore)
        #expect(try document.data(ofType: "public.plain-text") == Data("rest".utf8))
        document.close()
    }

    @Test func typingNeverInheritsTheHiddenColor() {
        let (document, textView) = makeWindow()
        type("a", into: textView)
        let color = textView.typingAttributes[.foregroundColor] as? NSColor
        #expect((color?.alphaComponent ?? 1) > 0)
        document.close()
    }

    @Test func turnedOffMeansNoAnimation() {
        let (document, textView) = makeWindow(animates: false)
        type("still", into: textView)
        #expect(textView.letters.runningCount == 0)
        #expect(textView.letters.hiddenRanges().isEmpty)
        document.close()
    }
}
