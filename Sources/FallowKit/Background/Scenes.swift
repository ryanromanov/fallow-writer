import AppKit

/// Hosts the scene behind the text (see `SceneLayers`), and tells it about the appearance,
/// Reduce Motion and whether the window can be seen.
final class BackgroundView: NSView {
    /// A scene's id, or Drift's.
    var choice: String = BuiltIn.paper.id {
        didSet { if choice != oldValue { repaint(animated: true) } }
    }
    var library: Library {
        get { scene.library }
        set { scene.library = newValue }
    }
    /// Whether to leave motion out. Replaced in tests.
    var reducesMotion: () -> Bool {
        get { scene.reducesMotion }
        set { scene.reducesMotion = newValue }
    }
    /// Whether the window can be seen at all. Replaced in tests.
    var isOnScreen: () -> Bool {
        get { scene.isOnScreen }
        set { scene.isOnScreen = newValue }
    }

    private let scene = SceneLayers()

    init() {
        super.init(frame: .zero)
        scene.reducesMotion = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
        scene.isOnScreen = { [weak self] in self?.window?.occlusionState.contains(.visible) ?? false }
        wantsLayer = true
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(motionMayHaveChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit { NSWorkspace.shared.notificationCenter.removeObserver(self) }

    override func makeBackingLayer() -> CALayer { scene.root }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if let window {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: window)
        }
        if let newWindow {
            NotificationCenter.default.addObserver(
                self, selector: #selector(motionMayHaveChanged),
                name: NSWindow.didChangeOcclusionStateNotification, object: newWindow)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        repaint(animated: false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        repaint(animated: false)
    }

    override func layout() {
        super.layout()
        scene.layout()
    }

    /// Whether Drift's loop is running, for tests.
    var isDrifting: Bool { scene.isDrifting }
    /// The motion layers playing now, for tests.
    var motionLayers: [CALayer] { scene.motionLayers }

    /// Repaints after packs are added or unlocked, which can change what a choice shows.
    func libraryChanged() {
        scene.forgetPainted()
        repaint(animated: true)
    }

    private func repaint(animated: Bool) {
        scene.paint(choice, dark: effectiveAppearance.isDark, animated: animated)
    }

    @objc func motionMayHaveChanged() {
        scene.motionMayHaveChanged()
    }
}
