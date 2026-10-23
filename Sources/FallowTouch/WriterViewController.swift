#if os(iOS)
import AVFoundation
import SwiftUI
import UIKit

/// The writing screen: the scene, the centered writing column, the status line, and the
/// document and the scene and sound menus. It opens on the last document, or a blank page.
public final class WriterViewController: UIViewController, UITextViewDelegate, UIDocumentPickerDelegate,
    UIGestureRecognizerDelegate, UIPopoverPresentationControllerDelegate {
    static let minimumMargin: CGFloat = 24

    let sceneView = SceneView()
    let textView = WriterTextView()
    let statusLabel = UILabel()
    let soundButton = UIButton(type: .system)
    let documentButton = UIButton(type: .system)

    private let settings: WriterSettings
    private let library: Library
    private let sound: SoundEngine
    /// Whether this screen can be heard: on screen, with the app in front.
    private var isOpen = false
    /// Whether this screen has told the sound engine it's open, which waits for the audio session.
    private var isPlaying = false
    /// Settles each typed letter into place.
    private(set) var letters: LetterAnimator!
    /// The letter being typed, between the text view asking to change and changing.
    private var typedLetter: NSRange?
    /// The open document, or nil for a blank page that hasn't been typed on yet.
    private var file: TextFile?
    /// A file outside Fallow's folder, which needs access asked for while it's open.
    private var scopedURL: URL?
    /// Puts the status line back after a choice made from the keyboard was shown in it.
    private var pendingAnnouncement: DispatchWorkItem?
    /// Fades the status line and buttons while typing.
    private(set) lazy var fader = ChromeFader { [unowned self] in [statusLabel, soundButton, documentButton] }

    public init(settings: WriterSettings = .shared, library: Library = .shared, sound: SoundEngine = .shared) {
        self.settings = settings
        self.library = library
        self.sound = sound
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public override func viewDidLoad() {
        super.viewDidLoad()
        sceneView.choice = settings.sceneChoice
        textView.backgroundColor = .clear
        textView.delegate = self
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        // The text view already sits clear of the safe area and the keyboard.
        textView.contentInsetAdjustmentBehavior = .never
        textView.tintColor = Palette.caret
        textView.hideUnderlineButton()
        letters = LetterAnimator(textView: textView)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (controller: WriterViewController, _) in
            controller.letters.finishAll()
        }

        statusLabel.textColor = Palette.secondary
        statusLabel.textAlignment = .center

        soundButton.setImage(UIImage(systemName: "speaker.wave.2"), for: .normal)
        soundButton.tintColor = Palette.secondary
        soundButton.accessibilityLabel = "Scene and sound"
        soundButton.addAction(UIAction { [weak self] _ in self?.showAtmospherePanel() }, for: .primaryActionTriggered)

        documentButton.setImage(UIImage(systemName: "doc.text"), for: .normal)
        documentButton.tintColor = Palette.secondary
        documentButton.accessibilityLabel = "Documents"
        documentButton.showsMenuAsPrimaryAction = true
        documentButton.menu = UIMenu(children: [
            UIAction(title: "New Document", image: UIImage(systemName: "square.and.pencil")) { [weak self] _ in
                self?.newDocument()
            },
            UIAction(title: "Open…", image: UIImage(systemName: "folder")) { [weak self] _ in
                self?.showOpenPicker()
            },
            UIMenu(options: .displayInline, children: [
                UIAction(title: "Share…", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
                    self?.shareDocument()
                },
                UIMenu(title: "Export", image: UIImage(systemName: "arrow.down.doc"), children: [
                    UIAction(title: "PDF") { [weak self] _ in self?.export(as: "pdf") },
                    UIAction(title: "Rich Text") { [weak self] _ in self?.export(as: "rtf") },
                ]),
                UIAction(title: "Print…", image: UIImage(systemName: "printer")) { [weak self] _ in
                    self?.printDocument()
                },
            ]),
        ])

        for subview in [sceneView, textView, statusLabel, soundButton, documentButton] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        let safe = view.safeAreaLayoutGuide, keyboard = view.keyboardLayoutGuide
        NSLayoutConstraint.activate([
            sceneView.topAnchor.constraint(equalTo: view.topAnchor),
            sceneView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sceneView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            textView.topAnchor.constraint(equalTo: safe.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -8),

            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: keyboard.topAnchor, constant: -10),
            soundButton.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            soundButton.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -12),
            soundButton.widthAnchor.constraint(equalToConstant: 44),
            soundButton.heightAnchor.constraint(equalToConstant: 44),
            documentButton.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            documentButton.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 12),
            documentButton.widthAnchor.constraint(equalToConstant: 44),
            documentButton.heightAnchor.constraint(equalToConstant: 44),
        ])

        // Any touch brings the controls back, without getting in the way of the text view's own.
        let tap = UITapGestureRecognizer(target: self, action: #selector(touched))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        view.addGestureRecognizer(tap)

        applySettings()
        updateStatus()
        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsDidChange), name: WriterSettings.didChange, object: settings)
        NotificationCenter.default.addObserver(
            self, selector: #selector(libraryDidChange), name: Library.didChange, object: library)
        NotificationCenter.default.addObserver(
            self, selector: #selector(open), name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(close), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(saveNow), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(audioInterrupted), name: AVAudioSession.interruptionNotification, object: nil)
        openLastDocument()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        open()
        textView.becomeFirstResponder()
        if let undoManager = textView.undoManager { letters.watch(undoManager) }
        #if DEBUG
        typeDemoText()
        #endif
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        close()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutColumn()
    }

    // MARK: Sound

    /// Starts the sound while the screen can be heard. Fallow's sound is ambient: it mixes with
    /// other audio and goes quiet with the Ring/Silent switch.
    @objc private func open() {
        guard !isOpen, viewIfLoaded?.window != nil else { return }
        isOpen = true
        Self.activateAudioSession { [weak self] in
            guard let self, isOpen, !isPlaying else { return }
            isPlaying = true
            sound.windowOpened()
        }
    }

    @objc private func close() {
        guard isOpen else { return }
        isOpen = false
        guard isPlaying else { return }
        isPlaying = false
        sound.windowClosed()
    }

    /// A phone call, Siri or an alarm stops the sound; it comes back when they're done.
    @objc private func audioInterrupted(_ notification: Notification) {
        guard let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: value) == .ended
        else { return }
        Self.activateAudioSession { [weak self] in
            guard let self, isPlaying else { return }
            sound.resume()
        }
    }

    private static let audioQueue = DispatchQueue(label: "Fallow audio session", qos: .userInitiated)

    /// Activates the audio session off the main thread, where it can take a moment, then calls
    /// `ready` on the main thread.
    private static func activateAudioSession(then ready: @escaping () -> Void) {
        audioQueue.async {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.ambient)
            try? session.setActive(true)
            DispatchQueue.main.async(execute: ready)
        }
    }

    public func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let kind = KeyClass(replacing: range, with: text)
        if let kind { sound.keystroke(kind) }
        // Animate one typed letter at a time, and never input-method text (marked text).
        // Anything else, such as a delete, paste or autocorrection, settles every letter first.
        typedLetter = nil
        if kind == .letter, textView.markedTextRange == nil, settings.animatesTyping, !UIAccessibility.isReduceMotionEnabled {
            typedLetter = NSRange(location: range.location, length: (text as NSString).length)
        } else if kind != .space, kind != .newline {
            letters.finishAll()
        }
        return true
    }

    public func textViewDidChange(_ textView: UITextView) {
        fader.typed()
        // Writing again means you're done with the panel.
        if presentedViewController is UIHostingController<AtmospherePanel> { dismiss(animated: true) }
        if let range = typedLetter {
            typedLetter = nil
            letters.animate(range)
        }
        updateStatus()
        if settings.typewriterScrolling { centerInsertionPoint(animated: true) }
        if let file {
            file.edit(textView.text)
        } else if !textView.text.isEmpty {
            createFile()
        }
    }

    // MARK: Controls

    @objc private func touched() { fader.show() }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                  shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        fader.show()
    }

    public func textViewDidEndEditing(_ textView: UITextView) {
        fader.show()
    }

    // MARK: Keyboard shortcuts

    /// A hardware keyboard's shortcuts, as on the Mac. Hold ⌘ to see them listed.
    public override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(title: "New Document", action: #selector(newDocumentCommand), input: "n", modifierFlags: .command),
            UIKeyCommand(title: "Open…", action: #selector(openCommand), input: "o", modifierFlags: .command),
            UIKeyCommand(title: "Print…", action: #selector(printCommand), input: "p", modifierFlags: .command),
            UIKeyCommand(title: "Scene and Sound…", action: #selector(toggleAtmospherePanel), input: "s", modifierFlags: [.command, .control]),
            arrow("Next Scene", #selector(nextScene), UIKeyCommand.inputRightArrow),
            arrow("Previous Scene", #selector(previousScene), UIKeyCommand.inputLeftArrow),
            arrow("Next Ambient Sound", #selector(nextAmbient), UIKeyCommand.inputDownArrow),
            arrow("Previous Ambient Sound", #selector(previousAmbient), UIKeyCommand.inputUpArrow),
        ]
    }

    /// ⌃⌘ and an arrow, which the text view would otherwise take to move the insertion point.
    private func arrow(_ title: String, _ action: Selector, _ input: String) -> UIKeyCommand {
        let command = UIKeyCommand(title: title, action: action, input: input, modifierFlags: [.command, .control])
        command.wantsPriorityOverSystemBehavior = true
        return command
    }

    @objc private func newDocumentCommand() { newDocument() }
    @objc private func openCommand() { showOpenPicker() }
    @objc private func printCommand() { printDocument() }

    @objc private func nextScene() { cycleScene(by: 1) }
    @objc private func previousScene() { cycleScene(by: -1) }
    @objc private func nextAmbient() { cycleAmbient(by: 1) }
    @objc private func previousAmbient() { cycleAmbient(by: -1) }

    private func cycleScene(by step: Int) {
        let id = library.scene(after: settings.sceneChoice, by: step)
        library.chooseScene(id, in: settings)
        announce("Scene · \(library.scene(for: id)?.title ?? "Drift")")
    }

    private func cycleAmbient(by step: Int) {
        let id = library.ambience(after: settings.ambientSound ? settings.ambientChoice : nil, by: step)
        library.chooseAmbience(id, in: settings)
        announce("Ambient · \(id.map { library.ambience(for: $0).title } ?? "Off")")
    }

    /// Names a choice made from the keyboard in the status line for a moment, since there's no
    /// panel to show it, and tells VoiceOver.
    private func announce(_ text: String) {
        pendingAnnouncement?.cancel()
        statusLabel.text = text
        statusLabel.alpha = 1
        UIAccessibility.post(notification: .announcement, argument: text)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            pendingAnnouncement = nil
            updateStatus()
            guard fader.isHidden else { return }
            UIView.animate(withDuration: 0.9, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction]) {
                self.statusLabel.alpha = 0
            }
        }
        pendingAnnouncement = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    // MARK: Documents

    /// Reopens the document that was open last time. Typing waits until it's there.
    private func openLastDocument() {
        guard let url = DocumentPlace.lastDocument() else { return }
        textView.isEditable = false
        openFile(url) { [weak self] opened in
            guard let self else { return }
            if !opened { DocumentPlace.remember(nil) }
            textView.isEditable = true
            if viewIfLoaded?.window != nil { textView.becomeFirstResponder() }
        }
    }

    /// Opens a file in place of the current one.
    private func openFile(_ url: URL, then done: ((Bool) -> Void)? = nil) {
        closeFile()
        let scoped = url.startAccessingSecurityScopedResource()
        let file = TextFile(fileURL: url)
        file.open { [weak self] success in
            guard let self, success else {
                if scoped { url.stopAccessingSecurityScopedResource() }
                done?(false)
                return
            }
            if scoped { scopedURL = url }
            self.file = file
            file.onReload = { [weak self, weak file] in
                guard let self, let file, self.file === file else { return }
                show(file.text)
            }
            DocumentPlace.remember(url)
            show(file.text)
            done?(true)
        }
    }

    /// Saves the blank page as a new file in Fallow's folder, once there's something on it.
    private func createFile() {
        let file = TextFile(fileURL: DocumentPlace.newFileURL())
        file.edit(textView.text)
        self.file = file
        file.save(to: file.fileURL, for: .forCreating) { [weak self] success in
            guard let self, self.file === file else { return }
            guard success else {
                self.file = nil
                return
            }
            DocumentPlace.remember(file.fileURL)
            updateStatus()
        }
    }

    /// Closes the open document, saving any last edits.
    private func closeFile() {
        guard let file else { return }
        self.file = nil
        file.onReload = nil
        file.edit(textView.text)
        let scoped = scopedURL
        scopedURL = nil
        file.close { _ in scoped?.stopAccessingSecurityScopedResource() }
    }

    private func newDocument() {
        closeFile()
        DocumentPlace.remember(nil)
        show("")
        textView.becomeFirstResponder()
    }

    private func showOpenPicker() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.plainText])
        picker.delegate = self
        present(picker, animated: true)
    }

    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        openFile(url) { [weak self] _ in self?.textView.becomeFirstResponder() }
    }

    /// Puts a document's text on the page, with the insertion point at the end.
    private func show(_ text: String) {
        letters.finishAll()
        textView.text = text
        applySettings()
        textView.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        updateStatus()
        if settings.typewriterScrolling { centerInsertionPoint(animated: false) }
    }

    // MARK: Sharing, export and printing

    private var documentName: String { file?.name ?? "Untitled" }

    private func typeset() -> NSAttributedString {
        Typesetter(settings: settings).typeset(textView.text, markdown: file?.isMarkdown ?? false)
    }

    /// Shares the document's own file, saved first. A blank page is shared as its text.
    private func shareDocument() {
        guard let file else { return share([textView.text ?? ""]) }
        file.edit(textView.text)
        file.save(to: file.fileURL, for: .forOverwriting) { [weak self] _ in
            self?.share([file.fileURL])
        }
    }

    /// Typesets the document and offers it as a PDF or Rich Text file.
    private func export(as fileExtension: String) {
        let text = typeset()
        do {
            let data = fileExtension == "pdf" ? Exports.pdf(text) : try Exports.richText(text)
            share([try Exports.file(named: documentName, extension: fileExtension, data: data)])
        } catch {
            let alert = UIAlertController(title: "Couldn't export “\(documentName)”", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }

    private func share(_ items: [Any]) {
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = documentButton
        present(sheet, animated: true)
    }

    private func printDocument() {
        let printer = UIPrintInteractionController.shared
        let info = UIPrintInfo.printInfo()
        info.jobName = documentName
        info.outputType = .general
        printer.printInfo = info
        printer.printFormatter = Exports.formatter(typeset())
        printer.present(from: documentButton.bounds, in: documentButton, animated: true)
    }

    /// Saves now, when the app goes to the background.
    @objc private func saveNow() {
        file?.autosave(completionHandler: nil)
    }

    // MARK: Layout and settings

    /// Centers a column as many characters wide as the font style's `measure`, as on the Mac.
    /// With typewriter scrolling, the text gets half the visible height above and below so any
    /// line can sit in the middle. The text view ends at the keyboard, so that's the middle of
    /// what can be seen.
    private func layoutColumn() {
        let font = settings.font
        let sample = "the quick brown fox jumps over the lazy dog" as NSString
        let characterWidth = sample.size(withAttributes: [.font: font]).width / CGFloat(sample.length)
        let padding = textView.textContainer.lineFragmentPadding
        let width = textView.bounds.width
        let side = max(Self.minimumMargin, (width - characterWidth * settings.fontStyle.measure) / 2 - padding).rounded()
        let vertical = settings.typewriterScrolling ? max(48, textView.bounds.height / 2 - font.lineHeight).rounded() : 48
        let inset = UIEdgeInsets(top: vertical, left: side, bottom: vertical, right: side)
        guard textView.textContainerInset != inset else { return }
        textView.textContainerInset = inset
        if settings.typewriterScrolling { centerInsertionPoint(animated: false) }
    }

    /// Scrolls so the insertion point sits in the middle of what can be seen.
    private func centerInsertionPoint(animated: Bool) {
        guard let position = textView.selectedTextRange?.end else { return }
        textView.layoutIfNeeded()
        let caret = textView.caretRect(for: position)
        guard !caret.isNull, !caret.isInfinite else { return }
        let maxY = max(0, textView.contentSize.height - textView.bounds.height)
        let y = min(max(0, (caret.midY - textView.bounds.height / 2).rounded()), maxY)
        guard abs(y - textView.contentOffset.y) >= 1 else { return }
        let offset = CGPoint(x: 0, y: y)
        if animated {
            UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
                self.textView.contentOffset = offset
            }
        } else {
            textView.contentOffset = offset
        }
    }

    private func applySettings() {
        letters.finishAll()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: settings.font,
            .paragraphStyle: settings.paragraphStyle,
            .foregroundColor: Palette.text,
        ]
        let selection = textView.selectedRange
        textView.textStorage.setAttributes(attributes, range: NSRange(location: 0, length: textView.textStorage.length))
        textView.typingAttributes = attributes
        textView.selectedRange = selection
        statusLabel.font = settings.chromeFont(size: 12)
        sceneView.choice = settings.sceneChoice
        view.setNeedsLayout()
        if settings.typewriterScrolling { centerInsertionPoint(animated: false) }
    }

    private func updateStatus() {
        // A choice being announced keeps the status line until it's done.
        if let pendingAnnouncement, !pendingAnnouncement.isCancelled { return }
        statusLabel.text = WordCounter.status(name: file?.name ?? "Untitled", words: WordCounter.words(in: textView.text))
    }

    @objc private func settingsDidChange() { applySettings() }

    @objc private func libraryDidChange() { sceneView.libraryChanged() }

    #if DEBUG
    /// Types `FALLOW_DEMO_TEXT` a letter at a time, the way the keyboard does (asking the
    /// delegate first, which `insertText` alone doesn't), for checking the letter animation and
    /// making screenshots in the simulator.
    /// `FALLOW_LETTER_DURATION` slows the animation down, `FALLOW_DEMO_PANEL` opens the scene
    /// and sound panel, `FALLOW_DEMO_CYCLE` steps the scene and ambient sound, and `FALLOW_DEMO_BOLD` and `FALLOW_DEMO_EXPORT` try bold and export.
    private func typeDemoText() {
        let environment = ProcessInfo.processInfo.environment
        // FALLOW_DEMO_CYCLE steps the scene and the ambient sound, as ⌃⌘→ and ⌃⌘↓ do.
        if environment["FALLOW_DEMO_CYCLE"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.nextScene() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.nextAmbient() }
        }
        if environment["FALLOW_DEMO_PANEL"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.showAtmospherePanel() }
        }
        guard let text = environment["FALLOW_DEMO_TEXT"] else { return }
        if let duration = environment["FALLOW_LETTER_DURATION"].flatMap(Double.init) { LetterAnimator.duration = duration }
        var remaining = Array(text)
        Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            if remaining.isEmpty {
                timer.invalidate()
                // FALLOW_DEMO_BOLD then makes the last word bold, as ⌘B would.
                if environment["FALLOW_DEMO_BOLD"] != nil, let word = textView.text.split(separator: " ").last {
                    textView.selectedRange = NSRange(word.startIndex..<word.endIndex, in: textView.text)
                    textView.toggleBoldface(nil)
                }
                // FALLOW_DEMO_EXPORT then writes the PDF export next to the document.
                if environment["FALLOW_DEMO_EXPORT"] != nil {
                    try? Exports.pdf(typeset()).write(to: DocumentPlace.folder.appendingPathComponent("Export.pdf"))
                }
                return
            }
            // Wait while the last document opens.
            guard textView.isEditable else { return }
            let letter = String(remaining.removeFirst())
            if self.textView(textView, shouldChangeTextIn: textView.selectedRange, replacementText: letter) {
                textView.insertText(letter)
            }
        }
    }
    #endif

    // MARK: Scene and sound panel

    /// ⌃⌘S shows the panel, or closes it if it's open.
    @objc private func toggleAtmospherePanel() {
        if presentedViewController is UIHostingController<AtmospherePanel> {
            dismiss(animated: true)
        } else if presentedViewController == nil {
            showAtmospherePanel()
        }
    }

    /// Shows the scene and sound panel as a popover from the speaker button, on iPhone too.
    private func showAtmospherePanel() {
        fader.show()
        let panel = UIHostingController(rootView: AtmospherePanel(model: AtmosphereModel(settings: settings, library: library)))
        panel.modalPresentationStyle = .popover
        panel.preferredContentSize = panel.sizeThatFits(in: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude))
        if let popover = panel.popoverPresentationController {
            popover.sourceView = soundButton
            popover.permittedArrowDirections = [.down]
            popover.delegate = self
        }
        present(panel, animated: true)
    }

    public func adaptivePresentationStyle(for controller: UIPresentationController,
                                          traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        .none
    }
}

extension KeyClass {
    /// The kind of key that makes a text view replace `range` with `text`, or nil for edits that
    /// aren't a single key, such as a paste or an autocorrection.
    init?(replacing range: NSRange, with text: String) {
        switch text {
        case "": if range.length > 0 { self = .delete } else { return nil }
        case "\n": self = .newline
        case " ", "\t": self = .space
        default:
            guard text.count == 1, range.length == 0 else { return nil }
            self = .letter
        }
    }
}
#endif
