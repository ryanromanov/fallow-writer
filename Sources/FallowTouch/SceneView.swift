#if os(iOS)
import UIKit

/// Hosts the scene behind the text (see `SceneLayers`), and tells it about the appearance and
/// Reduce Motion.
final class SceneView: UIView {
    /// A scene's id, or Drift's.
    var choice: String = BuiltIn.paper.id {
        didSet { if choice != oldValue { repaint(animated: true) } }
    }

    private let scene = SceneLayers()

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        // The scene's layers assume y runs upward, as on the Mac.
        scene.root.isGeometryFlipped = true
        layer.addSublayer(scene.root)
        scene.reducesMotion = { UIAccessibility.isReduceMotionEnabled }
        scene.isOnScreen = { [weak self] in self?.window != nil }
        NotificationCenter.default.addObserver(
            self, selector: #selector(motionMayHaveChanged),
            name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: SceneView, _) in
            view.repaint(animated: false)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        scene.root.frame = bounds
        CATransaction.commit()
        scene.layout()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        repaint(animated: false)
        scene.motionMayHaveChanged()
    }

    /// Repaints after packs are added or unlocked, which can change what a choice shows.
    func libraryChanged() {
        scene.forgetPainted()
        repaint(animated: true)
    }

    private func repaint(animated: Bool) {
        scene.paint(choice, dark: traitCollection.userInterfaceStyle == .dark, animated: animated)
    }

    @objc private func motionMayHaveChanged() {
        scene.motionMayHaveChanged()
    }
}
#endif
