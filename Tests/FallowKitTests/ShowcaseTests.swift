import AppKit
import Testing
@testable import FallowKit

/// Renders the README's screenshots and the repository's social preview into the folder
/// FALLOW_SHOWCASE names (see scripts/screenshots.sh). Only Fallow's own windows are captured.
@Suite(.serialized) @MainActor struct ShowcaseTests {
    static let passage = """
        A field left fallow is not an empty field. Under the surface the soil is doing quiet work: last season's roots break down, worms turn the ground, and the rain settles in where it's needed.

        Writing is like that too. Some days the page fills easily. Other days you sit with it, and nothing seems to happen, and that is part of the work.

        This is a place for both kinds of days.
        """

    var folder: URL? {
        ProcessInfo.processInfo.environment["FALLOW_SHOWCASE"].map { URL(fileURLWithPath: $0) }
    }

    func settings() -> WriterSettings {
        let name = "FallowShowcase-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = WriterSettings(defaults: defaults)
        settings.typewriterScrolling = false
        return settings
    }

    /// A window showing the passage in a document called "Field Notes".
    func window(_ settings: WriterSettings, dark: Bool) -> (TextDocument, WriterWindowController) {
        _ = NSApplication.shared
        let document = TextDocument()
        document.displayName = "Field Notes"
        let controller = WriterWindowController(settings: settings)
        document.addWindowController(controller)
        controller.window!.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        controller.window!.setFrame(NSRect(x: 120, y: 120, width: 1000, height: 640), display: true)
        controller.show(Self.passage)
        controller.window!.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        return (document, controller)
    }

    func capture(_ window: NSWindow, to url: URL, shadow: Bool = true) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x"] + (shadow ? [] : ["-o"]) + ["-l\(window.windowNumber)", url.path]
        try process.run()
        process.waitUntilExit()
    }

    @Test func screenshots() throws {
        guard let folder else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for dark in [false, true] {
            let (document, controller) = window(settings(), dark: dark)
            try capture(controller.window!, to: folder.appendingPathComponent(dark ? "writing-dark.png" : "writing-light.png"))
            document.close()
        }

        // The panel reaches past the window's edge, and its glass shows whatever is behind it.
        // A plain backdrop window of Fallow's own covers that area, so the shot holds nothing
        // but Fallow, and the capture is limited to the backdrop's frame.
        let (document, controller) = window(settings(), dark: false)
        let writing = controller.window!.frame
        let area = NSRect(x: writing.minX - 36, y: writing.minY - 36, width: writing.width + 290, height: writing.height + 72)
        let backdrop = NSWindow(contentRect: area, styleMask: [.borderless], backing: .buffered, defer: false)
        backdrop.backgroundColor = NSColor(srgbRed: 0.80, green: 0.77, blue: 0.71, alpha: 1)
        backdrop.orderFrontRegardless()
        controller.window!.orderFrontRegardless()
        controller.showSoundPanel(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        let screen = NSScreen.screens[0].frame
        // Stay a few points inside the backdrop, so rounding can't reach past its edge.
        let inner = area.insetBy(dx: 4, dy: 4)
        let region = "\(Int(inner.minX.rounded(.up))),\(Int((screen.height - inner.maxY).rounded(.up))),\(Int(inner.width.rounded(.down))),\(Int(inner.height.rounded(.down)))"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-R\(region)", folder.appendingPathComponent("sound-panel.png").path]
        try process.run()
        process.waitUntilExit()
        document.close()
        backdrop.orderOut(nil)
    }

    /// 1280×640, GitHub's social preview size: the icon, name and tagline on the light
    /// background. The icon comes from docs/images/icon.png, which screenshots.sh draws first.
    @Test func socialPreview() throws {
        guard let folder else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = NSApplication.shared
        let size = NSSize(width: 640, height: 320)   // points; 2× on a Retina screen
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: 120, y: 120), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        let content = NSView(frame: NSRect(origin: .zero, size: size))
        let background = BackgroundView(background: GradientBackground())
        background.frame = content.bounds
        content.addSubview(background)

        let icon = NSImageView(image: try #require(NSImage(contentsOf: folder.appendingPathComponent("icon.png"))))
        icon.imageScaling = .scaleProportionallyUpOrDown
        // The icon's sky is the card's own color, so a soft shadow, as in the Dock, outlines it.
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(srgbRed: 0.24, green: 0.16, blue: 0.1, alpha: 0.28)
        shadow.shadowOffset = NSSize(width: 0, height: -3)
        shadow.shadowBlurRadius = 9
        icon.shadow = shadow
        icon.widthAnchor.constraint(equalToConstant: 68).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 68).isActive = true
        let title = NSTextField(labelWithString: "Fallow")
        title.font = SoundPanel.serif(size: 64)
        title.textColor = Palette.text
        let tagline = NSTextField(labelWithString: "A quiet place to write")
        tagline.font = SoundPanel.serif(size: 21, italic: true)
        tagline.textColor = Palette.secondary
        let platform = NSTextField(labelWithAttributedString: NSAttributedString(
            string: "FOR MACOS · OPEN SOURCE",
            attributes: [.font: NSFont.systemFont(ofSize: 10, weight: .semibold), .kern: 1.6, .foregroundColor: Palette.secondary]))
        let stack = NSStackView(views: [icon, title, tagline, platform])
        stack.orientation = .vertical
        stack.spacing = 4
        stack.setCustomSpacing(14, after: icon)
        stack.setCustomSpacing(22, after: tagline)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        window.contentView = content
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        try capture(window, to: folder.appendingPathComponent("social-preview.png"), shadow: false)
        window.orderOut(nil)
    }
}
