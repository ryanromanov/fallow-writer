import AppKit
import Testing
@testable import FallowKit

@Suite @MainActor struct SceneTests {
    /// WCAG relative luminance of an sRGB color.
    func luminance(_ color: CGColor) -> Double {
        let c = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)!.components!
        func channel(_ v: CGFloat) -> Double { let v = Double(v); return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(c[0]) + 0.7152 * channel(c[1]) + 0.0722 * channel(c[2])
    }

    func contrast(_ a: CGColor, _ b: CGColor) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// Text stays easy to read on every scene, day and night: at least 7:1, WCAG's AAA level.
    @Test(arguments: SceneChoice.scenes)
    func textIsReadable(scene: SceneChoice) {
        for dark in [false, true] {
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
            var ink = CGColor(gray: 0, alpha: 1)
            appearance.performAsCurrentDrawingAppearance { ink = Palette.text.cgColor }
            let palette = scene.palette(dark: dark)!
            for hex in [palette.top, palette.middle, palette.bottom] {
                #expect(contrast(ink, ScenePalette.color(hex)) >= 7, "\(scene.title), dark: \(dark)")
            }
        }
    }

    @Test func everySceneHasDayAndNight() {
        for scene in SceneChoice.scenes {
            #expect(scene.palette(dark: false) != scene.palette(dark: true))
        }
        #expect(SceneChoice.drift.palette(dark: false) == nil)
    }

    @Test func driftRunsOnlyWhenChosen() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        let view = BackgroundView()
        view.frame = window.contentView!.bounds
        window.contentView!.addSubview(view)
        #expect(!view.isDrifting)
        view.choice = .drift
        #expect(view.isDrifting)
        view.choice = .mist
        #expect(!view.isDrifting)
    }

    @Test func panelChoosesScenes() {
        let name = "FallowScenes-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = WriterSettings(defaults: defaults)
        #expect(settings.sceneChoice == .paper)

        let panel = AtmospherePanel(settings: settings)
        _ = panel.view
        #expect(panel.sceneChoices.buttons.map(\.title) == ["Paper", "Dusk", "Mist", "Meadow", "Drift"])
        panel.sceneChoices.buttons.first { $0.title == "Mist" }!.performClick(nil)
        #expect(settings.sceneChoice == .mist)
        #expect(panel.sceneChoices.buttons.filter(\.isChosen).map(\.title) == ["Mist"])
    }
}
