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
    static let snow = Scenery(
        id: "snow", title: "Snow",
        light: ScenePalette(top: 0xF4F6F8, middle: 0xEAEEF2, bottom: 0xDDE3EA, glow: 0xFFFFFF, glowAlpha: 0.4),
        dark: ScenePalette(top: 0x1C2128, middle: 0x161A20, bottom: 0x101318, glow: 0xC8DCFF, glowAlpha: 0.08))
    static let rain = Ambience(id: "rain", title: "Rain") { LowField(sampleRate: $0) }
    static let typewriter = KeystrokeSet(id: "typewriter", title: "Typewriter") { _ in [[0.1, 0.05, 0]] }
    static let winter = Pack(id: "winter", title: "Winter", scenes: [snow], ambiences: [rain], keystrokeSets: [typewriter])

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
        library.register(Self.winter)
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

    @Test func everythingIsOpenByDefault() {
        let library = Library()
        library.register(Self.winter)
        #expect(library.isAvailable("snow") && library.isAvailable("rain") && library.isAvailable("typewriter"))
        #expect(library.driftScenes.map(\.id) == ["paper", "dusk", "mist", "meadow", "snow"])
    }

    @Test func lockedChoicesFallBack() {
        let (library, _) = lockedLibrary()
        #expect(!library.isAvailable("snow"))
        #expect(library.scene(for: "snow")?.id == "paper")
        #expect(library.ambience(for: "rain").id == "lowField")
        #expect(library.keystrokeSet(for: "typewriter").id == "marimba")
        #expect(library.scene(for: "gone")?.id == "paper")
        #expect(library.scene(for: Library.driftID) == nil)
        #expect(!library.driftScenes.contains { $0.id == "snow" })
    }

    @Test func choosingLockedOffersThePack() {
        let (library, access) = lockedLibrary()
        let settings = settings()
        library.chooseScene("snow", in: settings)
        library.chooseAmbience("rain", in: settings)
        #expect(settings.sceneChoice == "paper" && settings.ambientChoice == "lowField")
        #expect(access.requested == ["winter", "winter"])

        access.unlocked.insert("winter")
        library.changed()
        library.chooseScene("snow", in: settings)
        library.chooseKeystrokes("typewriter", in: settings)
        #expect(settings.sceneChoice == "snow" && settings.keystrokeChoice == "typewriter")
        #expect(library.driftScenes.last?.id == "snow")
    }

    @Test func takenIDsAreSkipped() {
        let library = Library()
        library.register(Pack(id: "copy", title: "Copy", scenes: [
            Scenery(id: "paper", title: "Other Paper", light: Self.snow.light, dark: Self.snow.dark),
            Scenery(id: Library.driftID, title: "Fake Drift", light: Self.snow.light, dark: Self.snow.dark),
        ]))
        #expect(library.scenes.map(\.title) == ["Paper", "Dusk", "Mist", "Meadow"])
    }

    @Test func panelMarksLockedChoicesAndUpdatesOnUnlock() {
        let (library, access) = lockedLibrary()
        let settings = settings()
        let panel = AtmospherePanel(settings: settings, library: library)
        _ = panel.view
        let snow = panel.sceneChoices.buttons[4]
        #expect(snow.isLocked && !snow.isChosen)
        snow.performClick(nil)
        #expect(access.requested == ["winter"])
        #expect(settings.sceneChoice == "paper")
        #expect(panel.sceneChoices.buttons.filter(\.isChosen).count == 1 && panel.sceneChoices.buttons[0].isChosen)

        access.unlocked.insert("winter")
        library.changed()
        let unlocked = panel.sceneChoices.buttons[4]
        #expect(!unlocked.isLocked)
        unlocked.performClick(nil)
        #expect(settings.sceneChoice == "snow" && panel.sceneChoices.buttons[4].isChosen)
    }

    @Test func soundEngineLoadsTheChosenKeystrokeSet() throws {
        let library = Library()
        library.register(Self.winter)
        let settings = settings()
        settings.ambientSound = false
        settings.keystrokeChoice = "typewriter"
        let sound = SoundEngine(settings: settings, library: library, offline: true)
        #expect(sound.keystrokeSetID == "typewriter")
        settings.keystrokeChoice = "marimba"
        #expect(sound.keystrokeSetID == "marimba")
    }
}
