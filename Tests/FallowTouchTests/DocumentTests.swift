#if os(iOS)
import UIKit
import Testing
@testable import FallowTouch

/// Files are plain text, new ones get the next free name, and the last one is remembered.
@Suite @MainActor struct DocumentTests {
    @Test func newFilesTakeTheNextFreeName() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(DocumentPlace.newFileURL(in: folder).lastPathComponent == "Untitled.txt")
        try Data().write(to: folder.appendingPathComponent("Untitled.txt"))
        try Data().write(to: folder.appendingPathComponent("Untitled 2.txt"))
        #expect(DocumentPlace.newFileURL(in: folder).lastPathComponent == "Untitled 3.txt")
    }

    @Test func remembersTheLastDocumentOrABlankPage() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Notes.md")
        try Data("notes".utf8).write(to: url)
        let defaults = UserDefaults(suiteName: "FallowTouchTests-\(UUID().uuidString)")!
        #expect(DocumentPlace.lastDocument(defaults: defaults) == nil)
        DocumentPlace.remember(url, defaults: defaults)
        #expect(DocumentPlace.lastDocument(defaults: defaults)?.standardizedFileURL.path == url.standardizedFileURL.path)
        DocumentPlace.remember(nil, defaults: defaults)
        #expect(DocumentPlace.lastDocument(defaults: defaults) == nil)
    }

    @Test func namesAndKinds() {
        let markdown = TextFile(fileURL: URL(fileURLWithPath: "/tmp/Chapter One.md"))
        #expect(markdown.name == "Chapter One")
        #expect(markdown.isMarkdown)
        #expect(!TextFile(fileURL: URL(fileURLWithPath: "/tmp/notes.txt")).isMarkdown)
        #expect(TextFile(fileURL: URL(fileURLWithPath: "/tmp/README.MARKDOWN")).isMarkdown)
    }

    @Test func writesUTF8AndReadsOlderEncodings() throws {
        let file = TextFile(fileURL: URL(fileURLWithPath: "/tmp/test.txt"))
        file.edit("café ☕︎")
        #expect(try file.contents(forType: "public.plain-text") as? Data == Data("café ☕︎".utf8))
        try file.load(fromContents: Data([0x63, 0x61, 0x66, 0xE9]), ofType: nil)
        #expect(file.text == "café")
    }

    /// Typing the same text again isn't an edit, so there's nothing to save.
    @Test func sameTextIsNoEdit() {
        let file = TextFile(fileURL: URL(fileURLWithPath: "/tmp/test.txt"))
        #expect(!file.hasUnsavedChanges)
        file.edit("")
        #expect(!file.hasUnsavedChanges)
        file.edit("words")
        #expect(file.hasUnsavedChanges)
    }

    @Test func savesAndOpensAgain() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Draft.txt")
        let file = TextFile(fileURL: url)
        file.edit("A quiet place to write.")
        #expect(await file.save(to: url, for: .forCreating))
        #expect(await file.close())
        #expect(try String(contentsOf: url, encoding: .utf8) == "A quiet place to write.")

        let again = TextFile(fileURL: url)
        #expect(await again.open())
        #expect(again.text == "A quiet place to write.")
        _ = await again.close()
    }
}
#endif
