import AppKit

/// A window's content: the background, the centered writing column, and the status line.
final class WriterView: NSView {
    static let minimumMargin: CGFloat = 32

    let scrollView = NSScrollView()
    let textView: WriterTextView
    let backgroundView = BackgroundView()
    let statusLabel = NSTextField(labelWithString: "")
    /// Opens the sound panel. It sits in the bottom-right corner and fades with the other chrome.
    let soundButton = NSButton()
    var onMouseMoved: ((CGFloat) -> Void)?

    /// Text starts to dissolve this far above the bottom edge and is gone by `clearHeight`,
    /// just above the status line, so the two never overlap.
    static let fadeHeight: CGFloat = 110
    static let clearHeight: CGFloat = 34
    private let fadeMask = CAGradientLayer()

    private let settings: WriterSettings

    init(settings: WriterSettings) {
        self.settings = settings
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        textView = WriterTextView.make(in: scrollView)
        scrollView.documentView = textView
        super.init(frame: NSRect(x: 0, y: 0, width: 900, height: 700))

        backgroundView.choice = settings.sceneChoice
        for view in [backgroundView, scrollView] as [NSView] {
            view.frame = bounds
            view.autoresizingMask = [.width, .height]
            addSubview(view)
        }

        scrollView.wantsLayer = true
        let opaque = CGColor(gray: 0, alpha: 1), clear = CGColor(gray: 0, alpha: 0)
        fadeMask.colors = [opaque, opaque, clear, clear]
        scrollView.layer?.mask = fadeMask

        statusLabel.font = settings.chromeFont(size: 11)
        statusLabel.textColor = Palette.secondary
        statusLabel.alignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)
        soundButton.isBordered = false
        soundButton.bezelStyle = .regularSquare
        soundButton.imagePosition = .imageOnly
        soundButton.contentTintColor = Palette.secondary
        soundButton.setAccessibilityLabel("Scene and sound")
        soundButton.toolTip = "Scene and sound"
        soundButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(soundButton)

        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            soundButton.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            soundButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            soundButton.widthAnchor.constraint(equalToConstant: 24),
            soundButton.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        layoutColumn()
        layoutFade()
    }

    /// Fades the text out toward the bottom edge. AppKit flips the scroll view's layer geometry,
    /// so the gradient runs top to bottom and its last color is at the bottom.
    private func layoutFade() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fadeMask.frame = scrollView.bounds
        let height = max(scrollView.bounds.height, 1)
        let start = max(1 - Self.fadeHeight / height, 0), end = max(1 - Self.clearHeight / height, start)
        fadeMask.locations = [0, NSNumber(value: Double(start)), NSNumber(value: Double(end)), 1]
        CATransaction.commit()
    }

    /// Centers a column as many characters wide as the font style's `measure`. With typewriter
    /// scrolling, the text gets half a window of space above and below so any line can sit in
    /// the middle.
    func layoutColumn() {
        let font = settings.font
        let sample = "the quick brown fox jumps over the lazy dog" as NSString
        let characterWidth = sample.size(withAttributes: [.font: font]).width / CGFloat(sample.length)
        let padding = textView.textContainer?.lineFragmentPadding ?? 0
        let size = scrollView.contentSize
        let side = max(Self.minimumMargin, (size.width - characterWidth * settings.fontStyle.measure) / 2 - padding)
        let lineHeight = font.ascender - font.descender + font.leading
        let vertical = settings.typewriterScrolling ? max(80, size.height / 2 - lineHeight) : 96
        let inset = NSSize(width: side.rounded(), height: vertical.rounded())
        if textView.textContainerInset != inset { textView.textContainerInset = inset }
    }

    /// Scrolls so the insertion point sits in the middle of the window.
    func centerInsertionPoint(animated: Bool) {
        guard let caret = textView.insertionRect else { return }
        let clip = scrollView.contentView
        let maxY = max(0, textView.frame.height - clip.bounds.height)
        let y = min(max(0, (caret.midY - clip.bounds.height / 2).rounded()), maxY)
        guard abs(y - clip.bounds.origin.y) >= 1 else { return }
        let origin = NSPoint(x: clip.bounds.origin.x, y: y)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                clip.animator().setBoundsOrigin(origin)
            } completionHandler: { [scrollView] in
                scrollView.reflectScrolledClipView(clip)
            }
        } else {
            clip.setBoundsOrigin(origin)
            scrollView.reflectScrolledClipView(clip)
        }
    }

    // MARK: Mouse movement, which brings the chrome back

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        onMouseMoved?(hypot(event.deltaX, event.deltaY))
    }
}
