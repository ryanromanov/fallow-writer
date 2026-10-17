import AppKit

/// Builds the menus (Fallow has no nib) and handles the settings menu items.
public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private let settings: WriterSettings

    /// True once Fallow itself has launched; false under `swift test`, so tests stay silent.
    static var isRunningApp = false

    override public init() {
        settings = .shared
        super.init()
    }

    public func applicationWillFinishLaunching(_ notification: Notification) {
        // Create the shared document controller before anything else asks for one.
        _ = NSDocumentController.shared
        Self.isRunningApp = true
        NSApp.mainMenu = makeMainMenu()
    }

    public func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }

    public func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: Settings actions

    @objc func chooseFontStyle(_ sender: NSMenuItem) {
        if let style = sender.representedObject as? String, let value = FontStyle(rawValue: style) {
            settings.fontStyle = value
        }
    }

    @objc func makeTextBigger(_ sender: Any?) { settings.fontSize += 1 }
    @objc func makeTextSmaller(_ sender: Any?) { settings.fontSize -= 1 }

    @objc func chooseLineSpacing(_ sender: NSMenuItem) {
        if let spacing = sender.representedObject as? String, let value = LineSpacing(rawValue: spacing) {
            settings.lineSpacing = value
        }
    }

    @objc func toggleTypewriterScrolling(_ sender: Any?) {
        settings.typewriterScrolling.toggle()
    }

    @objc func toggleAnimatesTyping(_ sender: Any?) { settings.animatesTyping.toggle() }

    @objc func chooseScene(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let choice = SceneChoice(rawValue: raw) {
            settings.sceneChoice = choice
        }
    }

    @objc func chooseAmbient(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let choice = AmbientChoice(rawValue: raw) {
            settings.ambientChoice = choice
            settings.ambientSound = true
        } else {
            settings.ambientSound = false
        }
    }
    @objc func toggleKeystrokeSounds(_ sender: Any?) { settings.keystrokeSounds.toggle() }

    public func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(chooseFontStyle):
            item.state = item.representedObject as? String == settings.fontStyle.rawValue ? .on : .off
        case #selector(chooseLineSpacing):
            item.state = item.representedObject as? String == settings.lineSpacing.rawValue ? .on : .off
        case #selector(toggleTypewriterScrolling):
            item.state = settings.typewriterScrolling ? .on : .off
        case #selector(chooseScene):
            item.state = item.representedObject as? String == settings.sceneChoice.rawValue ? .on : .off
        case #selector(toggleAnimatesTyping):
            item.state = settings.animatesTyping ? .on : .off
            // Reduce Motion wins; the setting is kept for when it's turned off again.
            return !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        case #selector(chooseAmbient):
            let chosen = settings.ambientSound ? settings.ambientChoice.rawValue : nil
            item.state = item.representedObject as? String == chosen ? .on : .off
            return SoundEngine.shared.isAvailable
        case #selector(toggleKeystrokeSounds):
            item.state = settings.keystrokeSounds ? .on : .off
            return SoundEngine.shared.isAvailable
        case #selector(makeTextBigger):
            return settings.fontSize < WriterSettings.fontSizes.upperBound
        case #selector(makeTextSmaller):
            return settings.fontSize > WriterSettings.fontSizes.lowerBound
        default:
            break
        }
        return true
    }

    // MARK: Menus

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu(appMenu()))
        main.addItem(submenu(fileMenu()))
        main.addItem(submenu(editMenu()))
        main.addItem(submenu(formatMenu()))
        main.addItem(submenu(viewMenu()))
        main.addItem(submenu(soundMenu()))
        let window = windowMenu()
        main.addItem(submenu(window))
        NSApp.windowsMenu = window
        return main
    }

    private func appMenu() -> NSMenu {
        let menu = NSMenu(title: "Fallow")
        menu.addItem(item("About Fallow", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        menu.addItem(.separator())
        let services = NSMenu(title: "Services")
        NSApp.servicesMenu = services
        menu.addItem(submenu(services))
        menu.addItem(.separator())
        menu.addItem(item("Hide Fallow", #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Quit Fallow", #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(item("New", #selector(NSDocumentController.newDocument(_:)), "n"))
        // AppKit adds Open Recent after this item itself.
        menu.addItem(item("Open…", #selector(NSDocumentController.openDocument(_:)), "o"))
        menu.addItem(.separator())
        menu.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w"))
        menu.addItem(item("Save…", #selector(NSDocument.save(_:)), "s"))
        menu.addItem(item("Duplicate", #selector(NSDocument.duplicate(_:)), "S"))
        menu.addItem(item("Rename…", #selector(NSDocument.rename(_:))))
        menu.addItem(item("Move To…", #selector(NSDocument.move(_:))))
        menu.addItem(item("Save As…", #selector(NSDocument.saveAs(_:)), "S", [.command, .option]))
        // Because documents autosave, AppKit turns this into a Revert To submenu (Last Opened,
        // Last Saved, Browse All Versions…), as in TextEdit.
        menu.addItem(item("Revert to Saved", #selector(NSDocument.revertToSaved(_:))))
        menu.addItem(.separator())
        // AppKit adds its Share submenu, with a separator, right after the PDF item, so PDF goes
        // last: the exports stay together and Share follows them.
        menu.addItem(item("Export as Rich Text…", #selector(TextDocument.exportRichText(_:))))
        menu.addItem(item("Export as Word Document…", #selector(TextDocument.exportWordDocument(_:))))
        menu.addItem(item("Export as PDF…", #selector(NSDocument.saveToPDF(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Print…", #selector(NSDocument.printDocument(_:)), "p"))
        return menu
    }

    private func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(item("Undo", Selector(("undo:")), "z"))
        menu.addItem(item("Redo", Selector(("redo:")), "Z"))
        menu.addItem(.separator())
        menu.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        menu.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        menu.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        menu.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        menu.addItem(.separator())

        let find = NSMenu(title: "Find")
        let findItems: [(String, NSTextFinder.Action, String, NSEvent.ModifierFlags)] = [
            ("Find…", .showFindInterface, "f", [.command]),
            ("Find and Replace…", .showReplaceInterface, "f", [.command, .option]),
            ("Find Next", .nextMatch, "g", [.command]),
            ("Find Previous", .previousMatch, "G", [.command]),
            ("Use Selection for Find", .setSearchString, "e", [.command]),
        ]
        for (title, action, key, modifiers) in findItems {
            let entry = item(title, #selector(NSTextView.performTextFinderAction(_:)), key, modifiers)
            entry.tag = action.rawValue
            find.addItem(entry)
        }
        menu.addItem(submenu(find))

        let spelling = NSMenu(title: "Spelling and Grammar")
        spelling.addItem(item("Show Spelling and Grammar", #selector(NSText.showGuessPanel(_:)), ":"))
        spelling.addItem(item("Check Document Now", #selector(NSText.checkSpelling(_:)), ";"))
        spelling.addItem(item("Check Spelling While Typing", #selector(NSTextView.toggleContinuousSpellChecking(_:))))
        spelling.addItem(item("Correct Spelling Automatically", #selector(NSTextView.toggleAutomaticSpellingCorrection(_:))))
        menu.addItem(submenu(spelling))

        let substitutions = NSMenu(title: "Substitutions")
        substitutions.addItem(item("Smart Quotes", #selector(NSTextView.toggleAutomaticQuoteSubstitution(_:))))
        substitutions.addItem(item("Smart Dashes", #selector(NSTextView.toggleAutomaticDashSubstitution(_:))))
        substitutions.addItem(item("Text Replacement", #selector(NSTextView.toggleAutomaticTextReplacement(_:))))
        menu.addItem(submenu(substitutions))
        return menu
    }

    private func formatMenu() -> NSMenu {
        let menu = NSMenu(title: "Format")
        let font = NSMenu(title: "Font")
        for style in FontStyle.allCases {
            let entry = item(style.title, #selector(chooseFontStyle), target: self)
            entry.representedObject = style.rawValue
            font.addItem(entry)
        }
        menu.addItem(submenu(font))
        menu.addItem(item("Bigger", #selector(makeTextBigger), "+", target: self))
        menu.addItem(item("Smaller", #selector(makeTextSmaller), "-", target: self))
        menu.addItem(.separator())
        let spacing = NSMenu(title: "Line Spacing")
        for value in LineSpacing.allCases {
            let entry = item(value.title, #selector(chooseLineSpacing), target: self)
            entry.representedObject = value.rawValue
            spacing.addItem(entry)
        }
        menu.addItem(submenu(spacing))
        return menu
    }

    private func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        menu.addItem(item("Typewriter Scrolling", #selector(toggleTypewriterScrolling), "t", [.command, .option], target: self))
        menu.addItem(item("Animate Typing", #selector(toggleAnimatesTyping), target: self))
        let scenes = NSMenu(title: "Scene")
        for choice in SceneChoice.allCases {
            if choice == .drift { scenes.addItem(.separator()) }
            let entry = item(choice.menuTitle, #selector(chooseScene), target: self)
            entry.representedObject = choice.rawValue
            scenes.addItem(entry)
        }
        menu.addItem(submenu(scenes))
        menu.addItem(.separator())
        menu.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        return menu
    }

    private func soundMenu() -> NSMenu {
        let menu = NSMenu(title: "Sound")
        let heading = NSMenuItem(title: "Ambient", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)
        for choice in AmbientChoice.allCases {
            let entry = item(choice.title, #selector(chooseAmbient), target: self)
            entry.representedObject = choice.rawValue
            entry.indentationLevel = 1
            menu.addItem(entry)
        }
        let none = item("None", #selector(chooseAmbient), target: self)
        none.indentationLevel = 1
        menu.addItem(none)
        menu.addItem(.separator())
        menu.addItem(item("Keystroke Sounds", #selector(toggleKeystrokeSounds), target: self))
        menu.addItem(.separator())
        // Handled by the front window's controller, through the responder chain.
        menu.addItem(item("Scene and Sound…", #selector(WriterWindowController.showAtmospherePanel)))
        return menu
    }

    private func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }

    private func item(
        _ title: String, _ action: Selector, _ key: String = "",
        _ modifiers: NSEvent.ModifierFlags = [.command], target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        if !key.isEmpty { item.keyEquivalentModifierMask = modifiers }
        item.target = target
        return item
    }

    private func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
