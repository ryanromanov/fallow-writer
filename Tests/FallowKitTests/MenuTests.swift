import AppKit
import Testing
@testable import FallowCore
@testable import FallowKit

@Suite @MainActor struct MenuTests {
    func settings() -> WriterSettings {
        let name = "FallowMenus-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return WriterSettings(defaults: defaults)
    }

    func mainMenu(_ library: Library = Library(), settings: WriterSettings? = nil) -> (NSMenu, AppDelegate) {
        _ = NSApplication.shared
        let delegate = AppDelegate(settings: settings ?? self.settings(), library: library)
        return (delegate.makeMainMenu(), delegate)
    }

    func submenu(_ title: String, in menu: NSMenu) throws -> NSMenu {
        let found = menu.items.lazy.compactMap(\.submenu).first { $0.title == title }
            ?? menu.items.lazy.compactMap(\.submenu).compactMap { $0.items.first { $0.submenu?.title == title }?.submenu }.first
        return try #require(found)
    }

    @Test func scenesAreUngroupedWithOnlyFallowsOwn() throws {
        let scenes = try submenu("Scene", in: mainMenu().0)
        #expect(scenes.items.map(\.title) == ["Paper", "Dusk", "Mist", "Meadow", "", "Drift (Chromotherapy)", "", "Next Scene", "Previous Scene"])
        #expect(scenes.items.allSatisfy { $0.indentationLevel == 0 })
    }

    @Test func scenesAreGroupedByPack() throws {
        let library = Library()
        library.register(LibraryTests.extra)
        let scenes = try submenu("Scene", in: mainMenu(library).0)
        #expect(scenes.items.map(\.title) == ["Fallow", "Paper", "Dusk", "Mist", "Meadow", "", "Extra", "Sample", "", "Drift (Chromotherapy)", "", "Next Scene", "Previous Scene"])
        let headings = scenes.items.filter { $0.title == "Fallow" || $0.title == "Extra" }
        #expect(headings.allSatisfy { !$0.isEnabled && $0.action == nil })
        #expect(scenes.items.filter { $0.title == "Sample" || $0.title == "Paper" }.allSatisfy { $0.indentationLevel == 1 })
    }

    /// The panel calls it Off; so does the menu.
    @Test func soundIsTurnedOffWithOff() throws {
        let sound = try submenu("Sound", in: mainMenu().0)
        #expect(sound.items.filter { $0.title == "Off" }.count == 2)
        #expect(!sound.items.contains { $0.title == "None" })
        let panel = try #require(sound.items.first { $0.title == "Scene and Sound…" })
        #expect(panel.keyEquivalent == "s" && panel.keyEquivalentModifierMask == [.command, .control])
    }

    @Test func fontHasBoldAndItalic() throws {
        let font = try submenu("Font", in: mainMenu().0)
        let bold = try #require(font.items.first { $0.title == "Bold" })
        let italic = try #require(font.items.first { $0.title == "Italic" })
        #expect(bold.keyEquivalent == "b" && italic.keyEquivalent == "i")
        #expect(bold.action == #selector(WriterTextView.toggleBold) && bold.target == nil)
    }

    @Test func helpComesLast() throws {
        let menu = mainMenu().0
        let help = try #require(menu.items.last?.submenu)
        #expect(help.title == "Help" && help.items.map(\.title) == ["Fallow Help"])
        #expect(help.items[0].keyEquivalent == "?")
    }

    /// No two items share a shortcut.
    @Test func shortcutsAreUnique() {
        var seen: [String: String] = [:]
        func walk(_ menu: NSMenu) {
            for item in menu.items {
                if let submenu = item.submenu { walk(submenu) }
                guard !item.keyEquivalent.isEmpty else { continue }
                var mask = item.keyEquivalentModifierMask
                if item.keyEquivalent != item.keyEquivalent.lowercased() { mask.insert(.shift) }
                let key = "\(item.keyEquivalent.lowercased()) \(mask.rawValue)"
                #expect(seen[key] == nil, "\(item.title) has the same shortcut as \(seen[key] ?? "")")
                seen[key] = item.title
            }
        }
        walk(mainMenu().0)
        #expect(seen.count > 20)
    }

    func press(_ characters: String, keyCode: UInt16, _ modifiers: NSEvent.ModifierFlags, in menu: NSMenu) -> Bool {
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
        return menu.performKeyEquivalent(with: event)
    }

    /// ⌃⌘→ and ⌃⌘← step through the scenes, ⌃⌘↓ and ⌃⌘↑ through the ambient sounds.
    @Test func arrowsCycleScenesAndSounds() {
        let settings = settings()
        let (menu, delegate) = mainMenu(settings: settings)
        func arrow(_ key: Int, _ code: UInt16) -> Bool {
            press(String(Character(UnicodeScalar(key)!)), keyCode: code, [.command, .control, .function, .numericPad], in: menu)
        }
        settings.sceneChoice = "paper"
        #expect(arrow(NSRightArrowFunctionKey, 124))
        #expect(settings.sceneChoice == "dusk")
        #expect(arrow(NSLeftArrowFunctionKey, 123))
        #expect(settings.sceneChoice == "paper")
        settings.ambientChoice = "lowField"
        settings.ambientSound = true
        #expect(arrow(NSDownArrowFunctionKey, 125))
        #expect(settings.ambientChoice == "wind" && settings.ambientSound)
        #expect(arrow(NSDownArrowFunctionKey, 125))
        #expect(!settings.ambientSound)
        #expect(arrow(NSUpArrowFunctionKey, 126))
        #expect(settings.ambientChoice == "wind" && settings.ambientSound)
        withExtendedLifetime(delegate) {}
    }

    /// ⌘= makes the text bigger, as does ⌘+ (⌘⇧= on most keyboards).
    @Test func commandEqualsMakesTextBigger() {
        let settings = settings()
        let (menu, delegate) = mainMenu(settings: settings)
        let size = settings.fontSize
        #expect(press("=", keyCode: 24, [.command], in: menu))
        #expect(settings.fontSize == size + 1)
        #expect(press("+", keyCode: 24, [.command, .shift], in: menu))
        #expect(settings.fontSize == size + 2)
        withExtendedLifetime(delegate) {}
    }
}
