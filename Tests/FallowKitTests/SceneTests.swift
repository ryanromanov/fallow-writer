import AppKit
import Testing
@testable import FallowKit

/// A motion that makes a plain, named layer.
struct TestMotion: SceneMotion {
    var warmUp: CFTimeInterval { 20 }
    func makeLayer(dark: Bool) -> CALayer {
        let layer = CALayer()
        layer.name = dark ? "dark" : "light"
        return layer
    }
}

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
    @Test(arguments: BuiltIn.pack.scenes.map(\.id))
    func textIsReadable(id: String) {
        let scene = BuiltIn.pack.scenes.first { $0.id == id }!
        for dark in [false, true] {
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
            var ink = CGColor(gray: 0, alpha: 1)
            appearance.performAsCurrentDrawingAppearance { ink = Palette.text.cgColor }
            let palette = scene.palette(dark: dark)
            for hex in [palette.top, palette.middle, palette.bottom] {
                #expect(contrast(ink, ScenePalette.color(hex)) >= 7, "\(scene.title), dark: \(dark)")
            }
        }
    }

    @Test func everySceneHasDayAndNight() {
        for scene in BuiltIn.pack.scenes {
            #expect(scene.palette(dark: false) != scene.palette(dark: true))
        }
    }

    @Test func driftRunsOnlyWhenChosen() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        let view = BackgroundView()
        view.frame = window.contentView!.bounds
        window.contentView!.addSubview(view)
        #expect(!view.isDrifting)
        view.choice = Library.driftID
        #expect(view.isDrifting)
        view.choice = "mist"
        #expect(!view.isDrifting)
    }

    @Test func panelChoosesScenes() {
        let name = "FallowScenes-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = WriterSettings(defaults: defaults)
        #expect(settings.sceneChoice == "paper")

        let panel = AtmospherePanel(settings: settings)
        _ = panel.view
        #expect(panel.sceneChoices.buttons.map(\.title) == ["Paper", "Dusk", "Mist", "Meadow", "Drift"])
        panel.sceneChoices.buttons.first { $0.title == "Mist" }!.performClick(nil)
        #expect(settings.sceneChoice == "mist")
        #expect(panel.sceneChoices.buttons.filter(\.isChosen).map(\.title) == ["Mist"])
    }

    // MARK: Motion

    static let moving = Scenery(id: "moving", title: "Moving", light: BuiltIn.mist.light, dark: BuiltIn.mist.dark, motion: TestMotion())

    func motionView() -> (BackgroundView, NSWindow) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        let library = Library()
        library.register(Pack(id: "extra", title: "Extra", scenes: [Self.moving]))
        let view = BackgroundView()
        view.library = library
        view.isOnScreen = { true }
        view.reducesMotion = { false }
        view.frame = window.contentView!.bounds
        window.contentView!.addSubview(view)
        return (view, window)
    }

    @Test func motionPlaysOnlyForItsScene() {
        let (view, _) = motionView()
        #expect(view.motionLayers.isEmpty)
        view.choice = "moving"
        #expect(view.motionLayers.count == 1)
        let layer = view.motionLayers[0]
        // Started as if it had already been running for its warm-up.
        #expect(layer.beginTime < layer.superlayer!.convertTime(CACurrentMediaTime(), from: nil) - 19)
        #expect(layer.frame == view.bounds)
        view.choice = "paper"
        #expect(view.motionLayers.isEmpty)
    }

    @Test func motionLeavesWithReduceMotionAndWhileHidden() {
        let (view, _) = motionView()
        view.choice = "moving"
        var reduce = true
        view.reducesMotion = { reduce }
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        #expect(view.motionLayers.isEmpty)
        reduce = false
        view.motionMayHaveChanged()
        #expect(view.motionLayers.count == 1)

        var visible = false
        view.isOnScreen = { visible }
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: view.window)
        #expect(view.motionLayers.isEmpty)
        visible = true
        view.motionMayHaveChanged()
        #expect(view.motionLayers.count == 1)
    }

    @Test func motionFollowsAppearanceAndJoinsDrift() {
        let (view, _) = motionView()
        view.appearance = NSAppearance(named: .aqua)
        view.choice = "moving"
        #expect(view.motionLayers.map(\.name) == ["light"])
        view.appearance = NSAppearance(named: .darkAqua)
        #expect(view.motionLayers.map(\.name) == ["dark"])

        view.choice = Library.driftID
        #expect(view.isDrifting && view.motionLayers.count == 1)
        let holder = view.motionLayers[0].superlayer!
        #expect(holder.animation(forKey: "drift") != nil)
    }

    /// In Drift, a scene's motion is there exactly while its colors are.
    @Test func driftOpacityFollowsTheColors() {
        let times = BackgroundView.driftTimes(count: 3).map(\.doubleValue)
        let expected: [Double] = (0...6).map { Double($0) / 6 }
        #expect(zip(times, expected).allSatisfy { abs($0 - $1) < 1e-12 } && times.count == 7)
        let first = BackgroundView.driftOpacity(index: 0, count: 3).values as! [Float]
        let last = BackgroundView.driftOpacity(index: 2, count: 3).values as! [Float]
        #expect(first == [1, 1, 0, 0, 0, 0, 1])
        #expect(last == [0, 0, 0, 0, 1, 1, 0])
    }
}
