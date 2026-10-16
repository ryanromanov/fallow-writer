import AppKit

/// The speaker button's popover: which ambient scene and keystroke sounds play, and how loud.
/// Every change is saved at once, and the panel follows changes made from the Sound menu.
///
/// The controls are native (so VoiceOver, the keyboard and accessibility settings all work),
/// styled in Fallow's own colors and in the writing font's family rather than as a settings window.
final class SoundPanel: NSViewController {
    private let settings: WriterSettings
    let ambientChoices: ChoiceRow
    let keysChoices: ChoiceRow
    let ambientSlider = NSSlider(value: 1, minValue: 0, maxValue: 1, target: nil, action: nil)
    let keysSlider = NSSlider(value: 1, minValue: 0, maxValue: 1, target: nil, action: nil)
    private var headings: [(label: NSTextField, title: String)] = []
    private let note = NSTextField(labelWithString: "Sounds best with headphones")

    init(settings: WriterSettings) {
        self.settings = settings
        ambientChoices = ChoiceRow(
            settings: settings, label: "Ambient sound",
            options: AmbientChoice.allCases.map { ($0.title, $0.rawValue) } + [("Off", nil)])
        keysChoices = ChoiceRow(settings: settings, label: "Keystroke sounds", options: [("Marimba", "marimba"), ("Off", nil)])
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        ambientChoices.onChoose = { [weak self] id in
            guard let self else { return }
            if let id, let choice = AmbientChoice(rawValue: id) {
                settings.ambientChoice = choice
                settings.ambientSound = true
            } else {
                settings.ambientSound = false
            }
        }
        keysChoices.onChoose = { [weak self] id in self?.settings.keystrokeSounds = id != nil }

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
    }

    /// The system's serif (New York), for Fallow's own name and artwork.
    static func serif(size: CGFloat, italic: Bool = false) -> NSFont {
        let base = NSFont.systemFont(ofSize: size).fontDescriptor
        var descriptor = base.withDesign(.serif) ?? base
        if italic { descriptor = descriptor.withSymbolicTraits(.italic) }
        return NSFont(descriptor: descriptor, size: size) ?? .systemFont(ofSize: size)
    }

    /// A small letter-spaced heading over a row of choices and its volume slider.
    private func section(_ title: String, _ choices: ChoiceRow, _ volume: NSView) -> NSView {
        let heading = NSTextField(labelWithString: "")
        headings.append((heading, title))
        let stack = NSStackView(views: [heading, choices, volume])
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
        for (label, title) in headings {
            label.attributedStringValue = NSAttributedString(string: title.uppercased(), attributes: [
                .font: settings.chromeFont(size: 10, weight: .semibold), .kern: 1.2, .foregroundColor: Palette.secondary,
            ])
        }
        note.font = settings.chromeFont(size: 12, italic: true)
        ambientChoices.selected = settings.ambientSound ? settings.ambientChoice.rawValue : nil
        keysChoices.selected = settings.keystrokeSounds ? "marimba" : nil
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
/// rest faded. Each word is a real button that VoiceOver reads as a radio button.
final class ChoiceRow: NSStackView {
    /// Called with the chosen option's id, or nil for "Off".
    var onChoose: ((String?) -> Void)?
    private(set) var buttons: [ChoiceButton] = []
    private let ids: [String?]
    private let settings: WriterSettings
    private var dots: [NSTextField] = []

    /// Setting this also picks up a change of writing font.
    var selected: String? {
        didSet { restyle() }
    }

    init(settings: WriterSettings, label: String, options: [(title: String, id: String?)]) {
        self.settings = settings
        ids = options.map(\.id)
        super.init(frame: .zero)
        spacing = 7
        setAccessibilityRole(.radioGroup)
        setAccessibilityLabel(label)
        for (index, option) in options.enumerated() {
            if index > 0 {
                let dot = NSTextField(labelWithString: "·")
                dot.textColor = Palette.secondary
                dots.append(dot)
                dot.setAccessibilityElement(false)
                addArrangedSubview(dot)
            }
            let button = ChoiceButton(title: option.title, target: self, action: #selector(chose))
            button.tag = index
            buttons.append(button)
            addArrangedSubview(button)
        }
        restyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func chose(_ sender: NSButton) {
        selected = ids[sender.tag]
        onChoose?(selected)
    }

    private func restyle() {
        let font = settings.chromeFont(size: 14)
        for dot in dots { dot.font = font }
        for (index, button) in buttons.enumerated() {
            button.font = font
            button.isChosen = ids[index] == selected
        }
    }
}

/// One word in a ChoiceRow.
final class ChoiceButton: NSButton {
    var isChosen = false {
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
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: font ?? NSFont.systemFont(ofSize: 14),
            .foregroundColor: isChosen ? Palette.text : Palette.secondary,
        ])
        setAccessibilityValue(isChosen ? 1 : 0)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
