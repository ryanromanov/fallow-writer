#if os(iOS)
import AVFoundation
import UIKit

/// The writing screen: the scene, the centered writing column, the status line, and the
/// scene and sound menu.
public final class WriterViewController: UIViewController, UITextViewDelegate {
    static let minimumMargin: CGFloat = 24

    let sceneView = SceneView()
    let textView = UITextView()
    let statusLabel = UILabel()
    let soundButton = UIButton(type: .system)

    private let settings: WriterSettings
    private let library: Library
    private let sound: SoundEngine
    /// Whether this screen has told the sound engine it's open.
    private var isOpen = false
    /// Settles each typed letter into place.
    private(set) var letters: LetterAnimator!
    /// The letter being typed, between the text view asking to change and changing.
    private var typedLetter: NSRange?

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
        letters = LetterAnimator(textView: textView)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (controller: WriterViewController, _) in
            controller.letters.finishAll()
        }

        statusLabel.textColor = Palette.secondary
        statusLabel.textAlignment = .center

        soundButton.setImage(UIImage(systemName: "speaker.wave.2"), for: .normal)
        soundButton.tintColor = Palette.secondary
        soundButton.accessibilityLabel = "Scene and sound"
        soundButton.showsMenuAsPrimaryAction = true
        soundButton.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] done in
            done(self?.menuItems() ?? [])
        }])

        for subview in [sceneView, textView, statusLabel, soundButton] as [UIView] {
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
        ])

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
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        try? AVAudioSession.sharedInstance().setActive(true)
        sound.windowOpened()
    }

    @objc private func close() {
        guard isOpen else { return }
        isOpen = false
        sound.windowClosed()
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
        if let range = typedLetter {
            typedLetter = nil
            letters.animate(range)
        }
        updateStatus()
        if settings.typewriterScrolling { centerInsertionPoint(animated: true) }
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
        statusLabel.text = WordCounter.status(name: "Untitled", words: WordCounter.words(in: textView.text))
    }

    @objc private func settingsDidChange() { applySettings() }

    @objc private func libraryDidChange() { sceneView.libraryChanged() }

    #if DEBUG
    /// Types `FALLOW_DEMO_TEXT` a letter at a time, the way the keyboard does (asking the
    /// delegate first, which `insertText` alone doesn't), for checking the letter animation and
    /// making screenshots in the simulator.
    /// `FALLOW_LETTER_DURATION` slows the animation down.
    private func typeDemoText() {
        let environment = ProcessInfo.processInfo.environment
        guard let text = environment["FALLOW_DEMO_TEXT"] else { return }
        if let duration = environment["FALLOW_LETTER_DURATION"].flatMap(Double.init) { LetterAnimator.duration = duration }
        var remaining = Array(text)
        Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] timer in
            guard let self, !remaining.isEmpty else { return timer.invalidate() }
            let letter = String(remaining.removeFirst())
            if self.textView(textView, shouldChangeTextIn: textView.selectedRange, replacementText: letter) {
                textView.insertText(letter)
            }
        }
    }
    #endif

    // MARK: Scene and sound menu

    private func menuItems() -> [UIMenuElement] {
        let scenes = library.scenes.map { scene in
            UIAction(title: scene.title, state: library.resolvedSceneID(settings.sceneChoice) == scene.id ? .on : .off) { [self] _ in
                library.chooseScene(scene.id, in: settings)
            }
        } + [UIAction(title: "Drift", state: library.resolvedSceneID(settings.sceneChoice) == Library.driftID ? .on : .off) { [self] _ in
            library.chooseScene(Library.driftID, in: settings)
        }]

        let playing = settings.ambientSound ? library.ambience(for: settings.ambientChoice).id : nil
        let ambiences = library.ambiences.map { ambience in
            UIAction(title: ambience.title, state: playing == ambience.id ? .on : .off) { [self] _ in
                library.chooseAmbience(ambience.id, in: settings)
            }
        } + [UIAction(title: "Off", state: playing == nil ? .on : .off) { [self] _ in
            library.chooseAmbience(nil, in: settings)
        }]

        let typing = settings.keystrokeSounds ? library.keystrokeSet(for: settings.keystrokeChoice).id : nil
        let keystrokes = library.keystrokeSets.map { set in
            UIAction(title: set.title, state: typing == set.id ? .on : .off) { [self] _ in
                library.chooseKeystrokes(set.id, in: settings)
            }
        } + [UIAction(title: "Off", state: typing == nil ? .on : .off) { [self] _ in
            library.chooseKeystrokes(nil, in: settings)
        }]

        return [
            UIMenu(title: "Scene", image: UIImage(systemName: "photo"), children: scenes),
            UIMenu(title: "Ambient Sound", image: UIImage(systemName: "wind"), children: ambiences),
            UIMenu(title: "Keystrokes", image: UIImage(systemName: "keyboard"), children: keystrokes),
        ]
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
