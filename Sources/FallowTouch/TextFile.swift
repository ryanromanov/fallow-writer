#if os(iOS)
import UIKit

/// A plain-text or Markdown file, as on the Mac. UIDocument autosaves it after edits and when
/// the app goes to the background, and coordinates with other apps and devices editing it.
final class TextFile: UIDocument {
    private(set) var text = ""
    /// Called when the file's text is replaced from outside after it was opened, such as by
    /// iCloud bringing in an edit from another device.
    var onReload: (() -> Void)?
    private var isLoaded = false
    /// A save soon after typing pauses. UIDocument's own autosave can wait much longer, and a
    /// crash or a force quit in between would lose the writing.
    private var pendingSave: DispatchWorkItem?
    static let saveDelay: TimeInterval = 1

    /// The file's name, without its extension.
    var name: String { fileURL.deletingPathExtension().lastPathComponent }

    /// Markdown documents export formatted; plain text exports as typed.
    var isMarkdown: Bool { ["md", "markdown"].contains(fileURL.pathExtension.lowercased()) }

    /// Records an edit, to be saved soon.
    func edit(_ text: String) {
        guard text != self.text else { return }
        self.text = text
        updateChangeCount(.done)
        pendingSave?.cancel()
        let save = DispatchWorkItem { [weak self] in self?.autosave(completionHandler: nil) }
        pendingSave = save
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDelay, execute: save)
    }

    override func contents(forType typeName: String) throws -> Any {
        Data(text.utf8)
    }

    override func load(fromContents contents: Any, ofType typeName: String?) throws {
        guard let data = contents as? Data else { throw CocoaError(.fileReadCorruptFile) }
        text = try PlainText.decode(data)
        if isLoaded { onReload?() }
        isLoaded = true
    }
}

/// Where documents go, and which one to reopen at launch.
enum DocumentPlace {
    /// Fallow's own folder, which the Files app shows under On My iPhone (or iPad) › Fallow.
    static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// A new file in Fallow's folder: Untitled.txt, or Untitled 2.txt and so on if that's taken.
    static func newFileURL() -> URL {
        var number = 1
        while true {
            let name = number == 1 ? "Untitled" : "Untitled \(number)"
            let url = folder.appendingPathComponent(name).appendingPathExtension("txt")
            if !FileManager.default.fileExists(atPath: url.path) { return url }
            number += 1
        }
    }

    private static let lastKey = "lastDocument"

    /// Remembers the open document, or nil for a blank page, to reopen at the next launch.
    /// A bookmark keeps working for files outside Fallow's folder, and if the file is moved.
    static func remember(_ url: URL?, defaults: UserDefaults = .standard) {
        if let url, let bookmark = try? url.bookmarkData() {
            defaults.set(bookmark, forKey: lastKey)
        } else {
            defaults.removeObject(forKey: lastKey)
        }
    }

    static func lastDocument(defaults: UserDefaults = .standard) -> URL? {
        guard let bookmark = defaults.data(forKey: lastKey) else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale) else { return nil }
        if isStale { remember(url, defaults: defaults) }
        return url
    }
}
#endif
