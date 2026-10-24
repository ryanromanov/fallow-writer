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

    /// A file in iCloud that hasn't downloaded is only a placeholder, but its name is still taken.
    @Test func filesNotYetDownloadedAreTaken() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data().write(to: folder.appendingPathComponent(".Untitled.txt.icloud"))
        #expect(DocumentPlace.newFileURL(in: folder).lastPathComponent == "Untitled 2.txt")
    }

    /// Another device's version of a file, kept beside it after a conflict.
    @Test func conflictCopiesAreNamedForTheirDevice() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = DocumentPlace.freeURL(in: folder, named: "Notes (iPad)", extension: "md")
        #expect(first.lastPathComponent == "Notes (iPad).md")
        try Data().write(to: first)
        #expect(DocumentPlace.freeURL(in: folder, named: "Notes (iPad)", extension: "md").lastPathComponent == "Notes (iPad) 2.md")
    }

    /// iCloud Drive shows the container's Documents folder, which is made if it's missing.
    @Test func iCloudDocumentsGoInTheContainersDocumentsFolder() throws {
        let container = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: container) }
        let folder = try #require(DocumentPlace.documentsFolder(in: container))
        #expect(folder.lastPathComponent == "Documents")
        var isFolder: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: folder.path, isDirectory: &isFolder) && isFolder.boolValue)
        #expect(DocumentPlace.documentsFolder(in: nil) == nil)
    }

    /// Without iCloud, documents stay on the device.
    @Test func withoutICloudDocumentsStayOnTheDevice() async {
        guard FileManager.default.ubiquityIdentityToken == nil else { return }
        await withCheckedContinuation { done in DocumentPlace.findCloudFolder { done.resume() } }
        #expect(DocumentPlace.cloudFolder == nil)
        #expect(DocumentPlace.folder == DocumentPlace.localFolder)
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
