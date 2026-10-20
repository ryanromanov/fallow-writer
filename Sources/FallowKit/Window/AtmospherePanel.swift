import AppKit

/// The speaker button's popover: the scene behind the text, which ambient sound and keystroke
/// sounds play, and how loud. Every change is saved at once, and the panel follows changes made
/// from the menus.
///
/// The controls are native (so VoiceOver, the keyboard and accessibility settings all work),
/// styled in Fallow's own colors and in the writing font's family rather than as a settings window.
final class AtmospherePanel: NSViewController {
    private let settings: WriterSettings
    private let library: Library
    let sceneChoices: ChoiceRow
    let ambientChoices: ChoiceRow
    let keysChoices: ChoiceRow
    let ambientSlider = NSSlider(value: 1, minValue: 0, maxValue: 1, target: nil, action: nil)
    let keysSlider = NSSlider(value: 1, minValue: 0, maxValue: 1, target: nil, action: nil)
    private var headings: [(label: NSTextField, title: String)] = []
    private let note = NSTextField(labelWithString: "Sounds best with headphones")

    init(settings: WriterSettings, library: Library = .shared) {
        self.settings = settings
        self.library = library
        sceneChoices = ChoiceRow(settings: settings, label: "Scene")
        ambientChoices = ChoiceRow(settings: settings, label: "Ambient sound")
        keysChoices = ChoiceRow(settings: settings, label: "Keystroke sounds")
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        sceneChoices.onChoose = { [weak self] id in
            guard let self, let id else { return }
            library.chooseScene(id, in: settings)
        }
        ambientChoices.onChoose = { [weak self] id in
            guard let self else { return }
            library.chooseAmbience(id, in: settings)
        }
        keysChoices.onChoose = { [weak self] id in
            guard let self else { return }
            library.chooseKeystrokes(id, in: settings)
        }
        fillChoices()

        for slider in [ambientSlider, keysSlider] {
            slider.isContinuous = true
            slider.controlSize = .small
            slider.trackFillColor = Palette.caret
            slider.target = self
            slider.action = #selector(volumeChanged)
            slider.widthAnchor.constraint(equalToConstant: 190).isActive = true
        }
        ambientSlider.setAccessibilityLabel("Ambient volume")
        keysSlider.setAccessibilityLabel("Keystroke volume")

        note.textColor = Palette.secondary

        let stack = NSStackView(views: [
            section("Scene", sceneChoices, nil),
            section("Ambient", ambientChoices, volume(ambientSlider)),
            section("Keystrokes", keysChoices, volume(keysSlider)),
            note,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        // A stack view's own edge insets are ignored as a popover's root view, so pad it here.
        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
        ])
        view = container

        refresh()
        NotificationCenter.default.addObserver(
            self, selector: #selector(refresh), name: WriterSettings.didChange, object: settings)
        NotificationCenter.default.addObserver(
            self, selector: #selector(libraryChanged), name: Library.didChange, object: library)
    }

    /// Every scene and sound in the library, with those from locked packs marked.
    private func fillChoices() {
        func option(_ title: String, _ id: String) -> ChoiceRow.Option {
            ChoiceRow.Option(title: title, id: id, isLocked: !library.isAvailable(id))
        }
        sceneChoices.options = library.scenes.map { option($0.title, $0.id) } + [option("Drift", Library.driftID)]
        sceneChoices.buttons.last?.toolTip = "Chromotherapy: drifts slowly from scene to scene"
        ambientChoices.options = library.ambiences.map { option($0.title, $0.id) } + [.off]
        keysChoices.options = library.keystrokeSets.map { option($0.title, $0.id) } + [.off]
    }

    @objc private func libraryChanged() {
        fillChoices()
        refresh()
    }

    /// The system's serif (New York), for Fallow's own name and artwork.
    static func serif(size: CGFloat, italic: Bool = false) -> NSFont {
        let base = NSFont.systemFont(ofSize: size).fontDescriptor
        var descriptor = base.withDesign(.serif) ?? base
        if italic { descriptor = descriptor.withSymbolicTraits(.italic) }
        return NSFont(descriptor: descriptor, size: size) ?? .systemFont(ofSize: size)
    }

    /// A small letter-spaced heading over a row of choices and its volume slider.
    private func section(_ title: String, _ choices: ChoiceRow, _ volume: NSView?) -> NSView {
        let heading = NSTextField(labelWithString: "")
        headings.append((heading, title))
        let stack = NSStackView(views: [heading, choices] + (volume.map { [$0] } ?? []))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(4, after: heading)
        return stack
    }

    /// A slider between quiet and loud speaker symbols.
    private func volume(_ slider: NSSlider) -> NSView {
        func symbol(_ name: String) -> NSImageView {
            let view = NSImageView(image: NSImage(systemSymbolName: name, accessibilityDescription: nil)!)
            view.symbolConfiguration = .init(pointSize: 10, weight: .regular)
            view.contentTintColor = Palette.secondary
            return view
        }
        let row = NSStackView(views: [symbol("speaker.fill"), slider, symbol("speaker.wave.3.fill")])
        row.spacing = 6
        return row
    }

    @objc private func refresh() {
        sceneChoices.selected = library.resolvedSceneID(settings.sceneChoice)
        for (label, title) in headings {
            label.attributedStringValue = NSAttributedString(string: title.uppercased(), attributes: [
                .font: settings.chromeFont(size: 10, weight: .semibold), .kern: 1.2, .foregroundColor: Palette.secondary,
            ])
        }
        note.font = settings.chromeFont(size: 12, italic: true)
        ambientChoices.selected = settings.ambientSound ? library.ambience(for: settings.ambientChoice).id : nil
        keysChoices.selected = settings.keystrokeSounds ? library.keystrokeSet(for: settings.keystrokeChoice).id : nil
        ambientSlider.floatValue = settings.ambientVolume
        keysSlider.floatValue = settings.keystrokeVolume
        ambientSlider.isEnabled = settings.ambientSound
        keysSlider.isEnabled = settings.keystrokeSounds
    }

    @objc private func volumeChanged(_ sender: NSSlider) {
        if sender === ambientSlider { settings.ambientVolume = sender.floatValue }
        if sender === keysSlider { settings.keystrokeVolume = sender.floatValue }
    }
}

/// Choices set as words in a line, "Low Field · Wind · Off": the chosen one in full ink, the
/// rest faded. Each word is a real button that VoiceOver reads as a radio button. A row too long
/// for the panel wraps onto further lines, breaking between words, never mid-name, and the dot
/// at a break is left out.
final class ChoiceRow: NSView {
    struct Option {
        let title: String
        /// Nil for "Off".
        let id: String?
        /// From a pack that isn't unlocked: shown with a lock, and choosing it offers the pack.
        var isLocked = false

        static let off = Option(title: "Off", id: nil)
    }

    /// The widest a line of choices gets before wrapping, in points.
    static let maxWidth: CGFloat = 300
    /// Space between a word and a dot, and between lines.
    static let spacing: CGFloat = 7, lineSpacing: CGFloat = 2

    /// Called with the chosen option's id, or nil for "Off".
    var onChoose: ((String?) -> Void)?
    private(set) var buttons: [ChoiceButton] = []
    private let settings: WriterSettings
    /// The dot before each button but the first.
    private var dots: [NSTextField] = []

    var options: [Option] = [] {
        didSet { rebuild() }
    }

    /// Setting this also picks up a change of writing font.
    var selected: String? {
        didSet { restyle() }
    }

    init(settings: WriterSettings, label: String) {
        self.settings = settings
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.radioGroup)
        setAccessibilityLabel(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private func rebuild() {
        for view in subviews { view.removeFromSuperview() }
        buttons = []
        dots = []
        for (index, option) in options.enumerated() {
            if index > 0 {
                let dot = NSTextField(labelWithString: "·")
                dot.textColor = Palette.secondary
                dot.setAccessibilityElement(false)
                dots.append(dot)
                addSubview(dot)
            }
            let button = ChoiceButton(title: option.title, target: self, action: #selector(chose))
            button.tag = index
            button.isLocked = option.isLocked
            buttons.append(button)
            addSubview(button)
        }
        restyle()
    }

    @objc private func chose(_ sender: NSButton) {
        let option = options[sender.tag]
        // A locked choice isn't selected here: the settings change only once it's unlocked.
        if !option.isLocked { selected = option.id }
        onChoose?(option.id)
    }

    private func restyle() {
        let font = settings.chromeFont(size: 14)
        for dot in dots { dot.font = font }
        for (index, button) in buttons.enumerated() {
            button.font = font
            button.isChosen = options[index].id == selected
        }
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    // MARK: Layout

    /// Where each word goes, where each dot goes (nil where a line breaks), and the size of it all.
    private func arrangement() -> (buttons: [NSRect], dots: [NSRect?], size: NSSize) {
        var buttonFrames: [NSRect] = [], dotFrames: [NSRect?] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, width: CGFloat = 0
        for (index, button) in buttons.enumerated() {
            let size = button.intrinsicContentSize
            if index > 0 {
                // A label's fitting size includes its padding; its intrinsic size can leave the dot clipped.
                let dot = dots[index - 1].fittingSize
                let needed = Self.spacing + dot.width + Self.spacing + size.width
                if x + needed <= Self.maxWidth {
                    dotFrames.append(NSRect(x: x + Self.spacing, y: y, width: dot.width, height: dot.height))
                    x += Self.spacing + dot.width + Self.spacing
                } else {
                    dotFrames.append(nil)
                    y += lineHeight + Self.lineSpacing
                    x = 0
                    lineHeight = 0
                }
            }
            buttonFrames.append(NSRect(x: x, y: y, width: size.width, height: size.height))
            x += size.width
            width = max(width, x)
            lineHeight = max(lineHeight, size.height)
        }
        // Center each dot on its line's words.
        dotFrames = dotFrames.enumerated().map { index, frame in
            guard var frame else { return nil }
            frame.origin.y = buttonFrames[index + 1].midY - frame.height / 2
            return frame
        }
        return (buttonFrames, dotFrames, NSSize(width: width, height: buttons.isEmpty ? 0 : y + lineHeight))
    }

    override var intrinsicContentSize: NSSize { arrangement().size }

    override func layout() {
        super.layout()
        let (buttonFrames, dotFrames, _) = arrangement()
        for (button, frame) in zip(buttons, buttonFrames) { button.frame = frame }
        for (dot, frame) in zip(dots, dotFrames) {
            dot.isHidden = frame == nil
            if let frame { dot.frame = frame }
        }
    }
}

/// One word in a ChoiceRow.
final class ChoiceButton: NSButton {
    var isChosen = false {
        didSet { style() }
    }
    var isLocked = false {
        didSet { style() }
    }

    convenience init(title: String, target: AnyObject, action: Selector) {
        self.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        setButtonType(.momentaryChange)
        setAccessibilityRole(.radioButton)
        style()
    }

    private func style() {
        let font = font ?? NSFont.systemFont(ofSize: 14)
        let color = isChosen ? Palette.text : Palette.secondary
        let styled = NSMutableAttributedString(string: title, attributes: [.font: font, .foregroundColor: color])
        if isLocked, let lock = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: font.pointSize * 0.6, weight: .regular)) {
            let attachment = NSTextAttachment()
            attachment.image = lock
            styled.append(NSAttributedString(string: "\u{2009}"))
            styled.append(NSAttributedString(attachment: attachment))
            styled.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: styled.length))
        }
        attributedTitle = styled
        setAccessibilityValue(isChosen ? 1 : 0)
        setAccessibilityHelp(isLocked ? "Locked. Choose to unlock." : nil)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
