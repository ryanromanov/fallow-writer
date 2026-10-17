import AppKit

/// One document's window. The title bar is transparent and untitled; the document's name and
/// word count live in the status line, and both fade away while you type.
final class WriterWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    private let settings: WriterSettings
    let writerView: WriterView
    private(set) var fader: ChromeFader!
    private var pendingCount: DispatchWorkItem?

    private let sound: SoundEngine?
    private var soundPopover: NSPopover?

    /// `sound` is nil in tests, which must never start the real audio engine.
    init(settings: WriterSettings = .shared, sound: SoundEngine? = nil) {
        self.settings = settings
        self.sound = sound
        writerView = WriterView(settings: settings)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: true)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.collectionBehavior = [.fullScreenPrimary]
        window.minSize = NSSize(width: 480, height: 360)
        window.contentView = writerView
        window.center()
        super.init(window: window)

        window.delegate = self
        shouldCascadeWindows = true
        windowFrameAutosaveName = "WriterWindow"
        fader = ChromeFader { [weak self] in self?.chromeViews ?? [] }
        writerView.textView.delegate = self
        writerView.onMouseMoved = { [weak self] in self?.fader.mouseMoved(by: $0) }
        writerView.textView.apply(settings)
        writerView.textView.onKeystroke = { [weak self] in self?.sound?.keystroke($0, isRepeat: $1) }
        writerView.textView.animatesTyping = { [weak self] in self?.settings.animatesTyping ?? false }
        writerView.soundButton.target = self
        writerView.soundButton.action = #selector(showAtmospherePanel)
        updateSoundButton()
        sound?.windowOpened()
        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsDidChange), name: WriterSettings.didChange, object: settings)
        NotificationCenter.default.addObserver(
            self, selector: #selector(libraryDidChange), name: Library.didChange, object: writerView.backgroundView.library)
    }

    /// A pack was added or unlocked: Drift may have new scenes, or a saved choice may now show.
    @objc private func libraryDidChange() { writerView.backgroundView.libraryChanged() }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var currentText: String { writerView.textView.string }

    /// Replaces the text, as when the document is opened or reverted.
    func show(_ text: String) {
        let textView = writerView.textView
        textView.string = text
        textView.apply(settings)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        writerView.layoutSubtreeIfNeeded()
        updateStatus()
    }

    /// The status line and the whole title bar container: the buttons, plus the tab bar and its
    /// background when there are tabs. In full screen the tab bar stays on screen, so it fades there too.
    private var chromeViews: [NSView] {
        var views: [NSView] = [writerView.statusLabel, writerView.soundButton]
        if let titlebar = window?.standardWindowButton(.closeButton)?.superview {
            views.append(titlebar.superview ?? titlebar)
        }
        return views
    }

    private func updateStatus() {
        let name = (document as? NSDocument)?.displayName ?? "Untitled"
        writerView.statusLabel.stringValue = WordCounter.status(name: name, words: WordCounter.words(in: currentText))
    }

    override func synchronizeWindowTitleWithDocumentName() {
        super.synchronizeWindowTitleWithDocumentName()
        updateStatus()
    }

    /// Shows the sound panel under the speaker button. Also the Sound › Volume… menu item.
    @objc func showAtmospherePanel(_ sender: Any?) {
        if let popover = soundPopover, popover.isShown {
            popover.performClose(sender)
            return
        }
        fader.show()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = AtmospherePanel(settings: settings)
        popover.show(relativeTo: writerView.soundButton.bounds, of: writerView.soundButton, preferredEdge: .maxY)
        soundPopover = popover
    }

    /// The speaker shows waves while any sound is on, and a slash when it's all off.
    private func updateSoundButton() {
        let on = settings.ambientSound || settings.keystrokeSounds
        let name = on ? "speaker.wave.2" : "speaker.slash"
        writerView.soundButton.image = NSImage(systemSymbolName: name, accessibilityDescription: on ? "Sound on" : "Sound off")
    }

    @objc private func settingsDidChange() {
        updateSoundButton()
        writerView.statusLabel.font = settings.chromeFont(size: 11)
        writerView.backgroundView.choice = settings.sceneChoice
        writerView.textView.apply(settings)
        writerView.layoutColumn()
        if settings.typewriterScrolling { writerView.centerInsertionPoint(animated: false) }
    }

    // MARK: NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        // Writing again means you're done with the sound panel.
        if let popover = soundPopover, popover.isShown { popover.performClose(nil) }
        if window?.isKeyWindow == true { fader.typed() }
        if settings.typewriterScrolling { writerView.centerInsertionPoint(animated: true) }
        // Counting words reads the whole text, so wait for a pause in typing.
        pendingCount?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.updateStatus() }
        pendingCount = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        // Follow the arrow keys, but leave the text where it is when the mouse moves the caret.
        guard settings.typewriterScrolling, NSApp.currentEvent?.type == .keyDown else { return }
        writerView.centerInsertionPoint(animated: true)
    }

    // MARK: NSWindowDelegate

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        (document as? NSDocument)?.undoManager
    }

    override var document: AnyObject? {
        didSet {
            if let undoManager = (document as? NSDocument)?.undoManager {
                writerView.textView.letters.watch(undoManager)
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        sound?.windowClosed()
    }

    func windowDidResignKey(_ notification: Notification) {
        writerView.textView.letters.finishAll()
        fader.show()
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        writerView.textView.letters.finishAll()
        fader.show()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        // AppKit moves the title bar back from full screen; make sure it isn't left faded.
        fader.show()
        chromeViews.forEach { $0.alphaValue = 1 }
    }

    func windowDidResize(_ notification: Notification) {
        writerView.textView.letters.finishAll()
        guard settings.typewriterScrolling else { return }
        writerView.layoutColumn()
        writerView.centerInsertionPoint(animated: false)
    }
}
