#if os(iOS)
import UIKit
@testable import FallowTouch

/// Settings of their own, starting from the defaults, so tests don't touch the app's.
func freshSettings() -> WriterSettings {
    let name = "FallowTouchTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return WriterSettings(defaults: defaults)
}

/// Puts a view in a phone-sized window, so it lays out and its text gets laid out.
@MainActor func onScreen(_ view: UIView, size: CGSize = CGSize(width: 390, height: 844)) -> UIWindow {
    let window = UIWindow(frame: CGRect(origin: .zero, size: size))
    view.frame = window.bounds
    window.addSubview(view)
    window.isHidden = false
    view.layoutIfNeeded()
    return window
}

/// A folder of its own in the temporary directory.
func temporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}
#endif
