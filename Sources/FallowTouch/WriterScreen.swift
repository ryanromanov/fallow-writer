#if os(iOS)
import SwiftUI

/// The writing screen, for a SwiftUI app's window.
public struct WriterScreen: UIViewControllerRepresentable {
    public init() {}

    public func makeUIViewController(context: Context) -> WriterViewController {
        WriterViewController()
    }

    public func updateUIViewController(_ controller: WriterViewController, context: Context) {}
}
#endif
