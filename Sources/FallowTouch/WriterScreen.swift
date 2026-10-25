#if os(iOS)
import SwiftUI

/// The writing screen, for a SwiftUI app's window.
public struct WriterScreen: UIViewControllerRepresentable {
    let panelLinks: [PanelLink]

    /// `panelLinks` go under the choices in the Scene and Sound panel.
    public init(panelLinks: [PanelLink] = []) {
        self.panelLinks = panelLinks
    }

    public func makeUIViewController(context: Context) -> WriterViewController {
        WriterViewController(panelLinks: panelLinks)
    }

    public func updateUIViewController(_ controller: WriterViewController, context: Context) {}
}
#endif
