import AppKit
import Testing
@testable import FallowKit

/// Locks every pack but Fallow's own until it's unlocked, and records what was offered.
final class TestAccess: PackAccess {
    var unlocked: Set<String> = ["fallow"]
    var requested: [String] = []

    func isUnlocked(_ pack: Pack) -> Bool { unlocked.contains(pack.id) }
    func requestUnlock(_ pack: Pack) { requested.append(pack.id) }
}

@Suite @MainActor struct LibraryTests {
    static let sample = Scenery(
        id: "sample", title: "Sample",
        light: ScenePalette(top: 0xF4F6F8, middle: 0xEAEEF2, bottom: 0xDDE3EA, glow: 0xFFFFFF, glowAlpha: 0.4),
        dark: ScenePalette(top: 0x1C2128, middle: 0x161A20, bottom: 0x101318, glow: 0xC8DCFF, glowAlpha: 0.08))
    static let hum = Ambience(id: "hum", title: "Hum") { LowField(sampleRate: $0) }
    static let click = KeystrokeSet(id: "click", title: "Click") { _ in [[0.1, 0.05, 0]] }
    static let extra = Pack(id: "extra", title: "Extra", scenes: [sample], ambiences: [hum], keystrokeSets: [click])

    func settings() -> WriterSettings {
        let name = "FallowLibrary-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return WriterSettings(defaults: defaults)
    }

    func lockedLibrary() -> (Library, TestAccess) {
        let library = Library()
        let access = TestAccess()
        library.access = access
        library.register(Self.extra)
        return (library, access)
    }

    /// Earlier versions saved these ids; they must keep meaning the same things.
    @Test func builtInIDsNeverChange() {
        let library = Library()
        #expect(library.scenes.map(\.id) == ["paper", "dusk", "mist", "meadow"])
        #expect(library.ambiences.map(\.id) == ["lowField", "wind"])
        #expect(library.keystrokeSets.map(\.id) == ["marimba"])
        #expect(Library.driftID == "drift")
    }

    @Test func scenesCycleThroughWhatCanBeChosenThenDrift() {
        let (library, access) = lockedLibrary()
        #expect(library.scene(after: "meadow", by: 1) == Library.driftID)
        #expect(library.scene(after: Library.driftID, by: 1) == "paper")
        #expect(library.scene(after: "paper", by: -1) == Library.driftID)
        access.unlocked.insert("extra")
        #expect(library.scene(after: "meadow", by: 1) == "sample")
        #expect(library.scene(after: "sample", by: -1) == "meadow")
    }

    @Test func ambiencesCycleThroughOff() {
        let (library, access) = lockedLibrary()
        #expect(library.ambience(after: "lowField", by: 1) == "wind")
        #expect(library.ambience(after: "wind", by: 1) == nil)
        #expect(library.ambience(after: nil, by: 1) == "lowField")
        #expect(library.ambience(after: nil, by: -1) == "wind")
        access.unlocked.insert("extra")
        #expect(library.ambience(after: "wind", by: 1) == "hum")
    }

    @Test func everythingIsOpenByDefault() {
        let library = Library()
        library.register(Self.extra)
        #expect(library.isAvailable("sample") && library.isAvailable("hum") && library.isAvailable("click"))
        #expect(library.driftScenes.map(\.id) == ["paper", "dusk", "mist", "meadow", "sample"])
    }

    @Test func lockedChoicesFallBack() {
        let (library, _) = lockedLibrary()
        #expect(!library.isAvailable("sample"))
        #expect(library.scene(for: "sample")?.id == "paper")
        #expect(library.ambience(for: "hum").id == "lowField")
        #expect(library.keystrokeSet(for: "click").id == "marimba")
        #expect(library.scene(for: "gone")?.id == "paper")
        #expect(library.scene(for: Library.driftID) == nil)
        #expect(!library.driftScenes.contains { $0.id == "sample" })
    }

    @Test func choosingLockedOffersThePack() {
        let (library, access) = lockedLibrary()
        let settings = settings()
        library.chooseScene("sample", in: settings)
        library.chooseAmbience("hum", in: settings)
        #expect(settings.sceneChoice == "paper" && settings.ambientChoice == "lowField")
        #expect(access.requested == ["extra", "extra"])

        access.unlocked.insert("extra")
        library.changed()
        library.chooseScene("sample", in: settings)
        library.chooseKeystrokes("click", in: settings)
        #expect(settings.sceneChoice == "sample" && settings.keystrokeChoice == "click")
        #expect(library.driftScenes.last?.id == "sample")
    }

    @Test func takenIDsAreSkipped() {
        let library = Library()
        library.register(Pack(id: "copy", title: "Copy", scenes: [
            Scenery(id: "paper", title: "Other Paper", light: Self.sample.light, dark: Self.sample.dark),
            Scenery(id: Library.driftID, title: "Fake Drift", light: Self.sample.light, dark: Self.sample.dark),
        ]))
        #expect(library.scenes.map(\.title) == ["Paper", "Dusk", "Mist", "Meadow"])
    }

    @Test func panelMarksLockedChoicesAndUpdatesOnUnlock() {
        let (library, access) = lockedLibrary()
        let settings = settings()
        let panel = AtmospherePanel(settings: settings, library: library)
        _ = panel.view
        let sample = panel.sceneChoices.buttons[4]
        #expect(sample.isLocked && !sample.isChosen)
        sample.performClick(nil)
        #expect(access.requested == ["extra"])
        #expect(settings.sceneChoice == "paper")
        #expect(panel.sceneChoices.buttons.filter(\.isChosen).count == 1 && panel.sceneChoices.buttons[0].isChosen)

        access.unlocked.insert("extra")
        library.changed()
        let unlocked = panel.sceneChoices.buttons[4]
        #expect(!unlocked.isLocked)
        unlocked.performClick(nil)
        #expect(settings.sceneChoice == "sample" && panel.sceneChoices.buttons[4].isChosen)
    }

    @Test func soundEngineLoadsTheChosenKeystrokeSet() throws {
        let library = Library()
        library.register(Self.extra)
        let settings = settings()
        settings.ambientSound = false
        settings.keystrokeChoice = "click"
        let sound = SoundEngine(settings: settings, library: library, offline: true)
        #expect(sound.keystrokeSetID == "click")
        settings.keystrokeChoice = "marimba"
        #expect(sound.keystrokeSetID == "marimba")
    }
}
