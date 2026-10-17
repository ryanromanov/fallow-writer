import Foundation

/// A scene behind the text: a light and a dark palette, so Fallow keeps following the Mac's
/// appearance.
public struct Scenery {
    /// Stable and saved in user defaults: never change one once it has shipped.
    public let id: String
    public let title: String
    public let light: ScenePalette
    public let dark: ScenePalette

    public init(id: String, title: String, light: ScenePalette, dark: ScenePalette) {
        self.id = id
        self.title = title
        self.light = light
        self.dark = dark
    }

    public func palette(dark isDark: Bool) -> ScenePalette { isDark ? dark : light }
}

/// An ambient soundscape, made fresh each time it starts playing.
public struct Ambience {
    public let id: String
    public let title: String
    /// Makes the generator for a sample rate. It renders on the audio thread (see `AmbientScene`).
    public let make: (_ sampleRate: Double) -> AmbientScene

    public init(id: String, title: String, make: @escaping (_ sampleRate: Double) -> AmbientScene) {
        self.id = id
        self.title = title
        self.make = make
    }
}

/// A set of keystroke sounds.
public struct KeystrokeSet {
    /// Every sound is mono, at this rate.
    public static let sampleRate = 44_100.0

    public let id: String
    public let title: String
    /// Every variant for one kind of key, as mono samples at `sampleRate`. A different variant
    /// plays each time, so a few slight variations keep repeated keys from sounding mechanical.
    public let sounds: (KeyClass) -> [[Float]]

    public init(id: String, title: String, sounds: @escaping (KeyClass) -> [[Float]]) {
        self.id = id
        self.title = title
        self.sounds = sounds
    }
}

/// A bundle of scenes and sounds. Fallow's own content is a pack too, and goes through the same
/// path as any other.
public struct Pack {
    public let id: String
    public let title: String
    public let scenes: [Scenery]
    public let ambiences: [Ambience]
    public let keystrokeSets: [KeystrokeSet]

    public init(id: String, title: String, scenes: [Scenery] = [], ambiences: [Ambience] = [], keystrokeSets: [KeystrokeSet] = []) {
        self.id = id
        self.title = title
        self.scenes = scenes
        self.ambiences = ambiences
        self.keystrokeSets = keystrokeSets
    }
}

/// Decides which packs can be used. By default every pack is open.
public protocol PackAccess: AnyObject {
    func isUnlocked(_ pack: Pack) -> Bool
    /// Someone chose something from a locked pack.
    func requestUnlock(_ pack: Pack)
}

/// Every pack is open.
final class OpenAccess: PackAccess {
    func isUnlocked(_ pack: Pack) -> Bool { true }
    func requestUnlock(_ pack: Pack) {}
}

/// Every scene and sound Fallow knows about, from every registered pack, in order. Choices are
/// saved by id; one that's missing or locked falls back to Fallow's default, so a saved choice
/// can never leave the window without a background or the sound without a scene.
public final class Library {
    public static let shared = Library()
    /// Posted when packs are added or something is unlocked.
    public static let didChange = Notification.Name("FallowLibraryDidChange")
    /// Drift isn't a scene of its own: it moves through every available scene.
    public static let driftID = "drift"

    public private(set) var packs: [Pack]
    public var access: PackAccess = OpenAccess() {
        didSet { changed() }
    }

    init(packs: [Pack] = [BuiltIn.pack]) {
        self.packs = packs
    }

    /// Adds a pack after Fallow's own, keeping ids unique: an id that's already taken is skipped.
    /// Main thread only.
    public func register(_ pack: Pack) {
        var taken = Set(packs.flatMap { $0.scenes.map(\.id) + $0.ambiences.map(\.id) + $0.keystrokeSets.map(\.id) })
        taken.insert(Self.driftID)
        func fresh<Item>(_ items: [Item], _ id: KeyPath<Item, String>) -> [Item] {
            items.filter { taken.insert($0[keyPath: id]).inserted }
        }
        packs.append(Pack(
            id: pack.id, title: pack.title, scenes: fresh(pack.scenes, \.id),
            ambiences: fresh(pack.ambiences, \.id), keystrokeSets: fresh(pack.keystrokeSets, \.id)))
        changed()
    }

    /// Call when something is unlocked, so menus, panels and backgrounds update. Main thread only.
    public func changed() {
        dispatchPrecondition(condition: .onQueue(.main))
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    // MARK: Lookup

    public func isUnlocked(_ pack: Pack) -> Bool { access.isUnlocked(pack) }

    /// The pack an item id belongs to.
    public func pack(containing id: String) -> Pack? {
        packs.first { pack in
            pack.scenes.contains { $0.id == id } || pack.ambiences.contains { $0.id == id }
                || pack.keystrokeSets.contains { $0.id == id }
        }
    }

    /// Whether an item can be chosen: it exists and its pack is unlocked. Drift always can.
    public func isAvailable(_ id: String) -> Bool {
        if id == Self.driftID { return true }
        return pack(containing: id).map(isUnlocked) ?? false
    }

    /// Every scene, ambience and keystroke set, locked ones included, for menus.
    public var scenes: [Scenery] { packs.flatMap(\.scenes) }
    public var ambiences: [Ambience] { packs.flatMap(\.ambiences) }
    public var keystrokeSets: [KeystrokeSet] { packs.flatMap(\.keystrokeSets) }

    /// The scenes Drift moves through: every unlocked one.
    var driftScenes: [Scenery] {
        let available = scenes.filter { isAvailable($0.id) }
        return available.isEmpty ? [BuiltIn.paper] : available
    }

    /// The scene to show for a saved id, or Fallow's default. Nil means Drift.
    func scene(for id: String) -> Scenery? {
        if id == Self.driftID { return nil }
        return scenes.first { $0.id == id && isAvailable(id) } ?? BuiltIn.paper
    }

    func ambience(for id: String) -> Ambience {
        ambiences.first { $0.id == id && isAvailable(id) } ?? BuiltIn.lowField
    }

    func keystrokeSet(for id: String) -> KeystrokeSet {
        keystrokeSets.first { $0.id == id && isAvailable(id) } ?? BuiltIn.marimba
    }

    /// The id a saved choice actually plays as, after falling back.
    func resolvedSceneID(_ id: String) -> String { scene(for: id)?.id ?? Self.driftID }
}

// MARK: Choosing

extension Library {
    /// Chooses a scene, or Drift. One from a locked pack isn't chosen; its pack is offered instead.
    func chooseScene(_ id: String, in settings: WriterSettings) {
        guard unlockIfNeeded(id) else { return }
        settings.sceneChoice = id
    }

    /// Chooses an ambient sound and turns ambient sound on, or turns it off for nil.
    func chooseAmbience(_ id: String?, in settings: WriterSettings) {
        guard let id else { settings.ambientSound = false; return }
        guard unlockIfNeeded(id) else { return }
        settings.ambientChoice = id
        settings.ambientSound = true
    }

    /// Chooses keystroke sounds and turns them on, or turns them off for nil.
    func chooseKeystrokes(_ id: String?, in settings: WriterSettings) {
        guard let id else { settings.keystrokeSounds = false; return }
        guard unlockIfNeeded(id) else { return }
        settings.keystrokeChoice = id
        settings.keystrokeSounds = true
    }

    /// True if the item can be used now; otherwise asks for its pack to be unlocked.
    private func unlockIfNeeded(_ id: String) -> Bool {
        if isAvailable(id) { return true }
        if let pack = pack(containing: id) { access.requestUnlock(pack) }
        return false
    }
}
