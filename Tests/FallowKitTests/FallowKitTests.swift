import AppKit
import Foundation
import Testing
@testable import FallowKit

@Suite struct WordCounterTests {
    @Test(arguments: [
        ("", 0),
        ("   \n\n  ", 0),
        ("Hello, world.", 2),
        ("don't stop", 2),
        ("one\ntwo\n\nthree", 3),
        ("A field — left to rest.", 5),
    ])
    func countsWords(text: String, expected: Int) {
        #expect(WordCounter.words(in: text) == expected)
    }

    @Test func statusLine() {
        #expect(WordCounter.status(name: "Untitled", words: 1) == "Untitled · 1 word")
        #expect(WordCounter.status(name: "Notes", words: 0) == "Notes · 0 words")
    }
}

@Suite @MainActor struct TextDocumentTests {
    func read(_ bytes: [UInt8]) throws -> String {
        let document = TextDocument()
        try document.read(from: Data(bytes), ofType: "public.plain-text")
        return document.text
    }

    @Test func roundTripsUTF8() throws {
        let text = "Fallow — héllo 🌱\r\nline two\n"
        let document = TextDocument()
        try document.read(from: Data(text.utf8), ofType: "net.daringfireball.markdown")
        #expect(document.text == text)
        #expect(try document.data(ofType: "net.daringfireball.markdown") == Data(text.utf8))
    }

    @Test func dropsUTF8ByteOrderMark() throws {
        #expect(try read([0xEF, 0xBB, 0xBF] + Array("hi".utf8)) == "hi")
    }

    @Test func readsUTF16WithByteOrderMark() throws {
        #expect(try read([0xFF, 0xFE, 0x68, 0x00, 0x69, 0x00]) == "hi")
    }

    @Test func fallsBackToWindows1252() throws {
        // "café" and a curly apostrophe, as an old Windows text file would have them.
        #expect(try read([0x63, 0x61, 0x66, 0xE9, 0x20, 0x92]) == "café \u{2019}")
    }

    @Test func savesUTF8() throws {
        let document = TextDocument()
        try document.read(from: Data([0x63, 0x61, 0x66, 0xE9]), ofType: "public.plain-text")
        #expect(try document.data(ofType: "public.plain-text") == Data("café".utf8))
    }
}

@Suite struct WriterSettingsTests {
    func makeSettings() -> WriterSettings {
        let name = "FallowTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return WriterSettings(defaults: defaults)
    }

    @Test func defaults() {
        let settings = makeSettings()
        #expect(settings.fontStyle == .serif)
        #expect(settings.fontSize == WriterSettings.defaultFontSize)
        #expect(settings.lineSpacing == .normal)
        #expect(settings.typewriterScrolling)
        #expect(settings.keystrokeSounds && settings.ambientSound)
        #expect(settings.ambientChoice == .lowField)
        #expect(settings.keystrokeVolume == WriterSettings.defaultKeystrokeVolume)
        #expect(settings.ambientVolume == 1)
    }

    @Test func monospacedLinesAreShorter() {
        #expect(FontStyle.mono.measure < FontStyle.serif.measure)
        #expect(FontStyle.sans.measure == FontStyle.serif.measure)
    }

    @Test func clampsFontSize() {
        let settings = makeSettings()
        settings.fontSize = 200
        #expect(settings.fontSize == WriterSettings.fontSizes.upperBound)
        settings.fontSize = 2
        #expect(settings.fontSize == WriterSettings.fontSizes.lowerBound)
    }

    @Test func remembersChoices() {
        let settings = makeSettings()
        settings.fontStyle = .mono
        settings.lineSpacing = .double
        settings.typewriterScrolling = false
        #expect(settings.fontStyle == .mono)
        #expect(settings.lineSpacing == .double)
        #expect(!settings.typewriterScrolling)
        #expect(settings.paragraphStyle.lineHeightMultiple == 2.0)
    }
}

/// Guards against losing work: typing must reach the document, its undo manager and the file.
@Suite @MainActor struct EditingTests {
    @Test func typingMarksDocumentEditedAndSaves() throws {
        _ = NSApplication.shared
        let document = TextDocument()
        try document.read(from: Data("first".utf8), ofType: "public.plain-text")
        document.makeWindowControllers()
        let controller = try #require(document.windowControllers.first as? WriterWindowController)
        let textView = controller.writerView.textView
        textView.setSelectedRange(NSRange(location: 5, length: 0))
        textView.insertText(" hello", replacementRange: textView.selectedRange())
        // AppKit closes the undo group, which is what marks the document edited, after the event.
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        #expect(document.isDocumentEdited)
        #expect(document.undoManager?.canUndo == true)
        #expect(try document.data(ofType: "public.plain-text") == Data("first hello".utf8))

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fallow-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try document.write(to: url, ofType: "public.plain-text")
        let reopened = TextDocument()
        try reopened.read(from: url, ofType: "public.plain-text")
        #expect(reopened.text == "first hello")

        try Data("changed on disk".utf8).write(to: url)
        try document.revert(toContentsOf: url, ofType: "public.plain-text")
        #expect(textView.string == "changed on disk")
        document.close()
    }
}
