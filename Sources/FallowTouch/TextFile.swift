#if os(iOS)
import UIKit

/// A plain-text or Markdown file, as on the Mac. UIDocument autosaves it after edits and when
/// the app goes to the background, and coordinates with other apps and devices editing it.
final class TextFile: UIDocument {
    private(set) var text = ""
    /// Called when the file's text is replaced from outside after it was opened, such as by
    /// iCloud bringing in an edit from another device.
    var onReload: (() -> Void)?
    /// Called when the file can't be edited for a while, and again when it can, such as while
    /// iCloud brings in a newer version.
    var onEditableChange: ((Bool) -> Void)?
    private var isLoaded = false
    /// A save soon after typing pauses. UIDocument's own autosave can wait much longer, and a
    /// crash or a force quit in between would lose the writing.
    private var pendingSave: DispatchWorkItem?
    static let saveDelay: TimeInterval = 1

    override init(fileURL url: URL) {
        super.init(fileURL: url)
        NotificationCenter.default.addObserver(
            self, selector: #selector(stateChanged), name: UIDocument.stateChangedNotification, object: self)
    }

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

    @objc private func stateChanged() {
        if documentState.contains(.inConflict) { resolveConflict() }
        onEditableChange?(!documentState.contains(.editingDisabled))
    }

    /// Two devices edited the file while apart. The version here stays the file, and each other
    /// version is kept beside it, named for the device it came from, so no writing is lost.
    private func resolveConflict() {
        let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: fileURL) ?? []
        for version in versions {
            let device = version.localizedNameOfSavingComputer ?? "Another Device"
            let copy = DocumentPlace.freeURL(in: fileURL.deletingLastPathComponent(),
                                             named: "\(name) (\(device))", extension: fileURL.pathExtension)
            try? FileManager.default.copyItem(at: version.url, to: copy)
            version.isResolved = true
        }
        try? NSFileVersion.removeOtherVersionsOfItem(at: fileURL)
    }

    override func load(fromContents contents: Any, ofType typeName: String?) throws {
        guard let data = contents as? Data else { throw CocoaError(.fileReadCorruptFile) }
        text = try PlainText.decode(data)
        if isLoaded { onReload?() }
        isLoaded = true
    }
}

/// Where documents go, and which one to reopen at launch: Fallow's folder in iCloud Drive, so
/// writing follows you to your other devices and the Mac, or on the device when iCloud is off.
enum DocumentPlace {
    static let containerID = "iCloud.com.ryanromanov.Fallow"

    /// Fallow's folder in iCloud Drive, once found; nil until then, or if iCloud is off.
    private(set) static var cloudFolder: URL?

    /// Fallow's own folder on the device, which the Files app shows under On My iPhone (or
    /// iPad) › Fallow.
    static var localFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Where new documents go.
    static var folder: URL { cloudFolder ?? localFolder }

    /// Looks for Fallow's iCloud Drive folder off the main thread, where it can take a moment,
    /// then calls `done` on the main thread. Until then, and without iCloud, documents go on
    /// the device.
    static func findCloudFolder(then done: @escaping () -> Void = {}) {
        // Quick to ask, and nil when nobody is signed in to iCloud.
        guard FileManager.default.ubiquityIdentityToken != nil else { return done() }
        DispatchQueue.global(qos: .userInitiated).async {
            let folder = documentsFolder(in: FileManager.default.url(forUbiquityContainerIdentifier: containerID))
            DispatchQueue.main.async {
                cloudFolder = folder
                done()
            }
        }
    }

    /// The Documents folder in an iCloud container, made if it isn't there yet. It's the part
    /// the Files app and the Finder show as iCloud Drive › Fallow.
    static func documentsFolder(in container: URL?) -> URL? {
        guard let folder = container?.appendingPathComponent("Documents", isDirectory: true) else { return nil }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        } catch {
            return nil
        }
    }

    /// A new file in Fallow's folder: Untitled.txt, or Untitled 2.txt and so on if that's taken.
    static func newFileURL(in folder: URL = folder) -> URL {
        freeURL(in: folder, named: "Untitled", extension: "txt")
    }

    /// A file named `name`, or `name 2` and so on if that's taken. A file in iCloud that hasn't
    /// downloaded yet is there only as a placeholder, `.name.txt.icloud`, and is taken too.
    static func freeURL(in folder: URL, named name: String, extension fileExtension: String) -> URL {
        var number = 1
        while true {
            let file = (number == 1 ? name : "\(name) \(number)") + "." + fileExtension
            let url = folder.appendingPathComponent(file)
            let placeholder = folder.appendingPathComponent(".\(file).icloud")
            if !FileManager.default.fileExists(atPath: url.path), !FileManager.default.fileExists(atPath: placeholder.path) {
                return url
            }
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
