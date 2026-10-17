/// Fallow's own scenes and sounds, free in every build. Their ids were saved by earlier versions
/// of Fallow, so they must never change.
enum BuiltIn {
    static let paper = Scenery(
        id: "paper", title: "Paper",
        light: ScenePalette(top: 0xF6F2EA, middle: 0xF0EADF, bottom: 0xE7DFD1, glow: 0xFFFFFF, glowAlpha: 0.45),
        dark: ScenePalette(top: 0x26221F, middle: 0x1D1B18, bottom: 0x161412, glow: 0xFFD9B3, glowAlpha: 0.05))
    static let dusk = Scenery(
        id: "dusk", title: "Dusk",
        light: ScenePalette(top: 0xF9E1CF, middle: 0xF2CDC3, bottom: 0xE0C3D4, glow: 0xFFF0DC, glowAlpha: 0.5),
        dark: ScenePalette(top: 0x3A2420, middle: 0x2C1B19, bottom: 0x201414, glow: 0xFF8A55, glowAlpha: 0.12))
    static let mist = Scenery(
        id: "mist", title: "Mist",
        light: ScenePalette(top: 0xE5EEE7, middle: 0xD7E3DB, bottom: 0xC6D6CF, glow: 0xFFFFFF, glowAlpha: 0.45),
        dark: ScenePalette(top: 0x1F2542, middle: 0x181C34, bottom: 0x121528, glow: 0x9FB1FF, glowAlpha: 0.1))
    static let meadow = Scenery(
        id: "meadow", title: "Meadow",
        light: ScenePalette(top: 0xF4EFD0, middle: 0xE6E8C2, bottom: 0xD3DCAD, glow: 0xFFFCE0, glowAlpha: 0.45),
        dark: ScenePalette(top: 0x23311F, middle: 0x1A2518, bottom: 0x131B12, glow: 0xB8E08A, glowAlpha: 0.09))

    static let lowField = Ambience(id: "lowField", title: "Low Field") { LowField(sampleRate: $0) }
    static let wind = Ambience(id: "wind", title: "Wind") { FieldWind(sampleRate: $0) }

    static let marimba = KeystrokeSet(id: "marimba", title: "Marimba", sounds: MarimbaKeystrokes.sounds(for:))

    static let pack = Pack(
        id: "fallow", title: "Fallow",
        scenes: [paper, dusk, mist, meadow], ambiences: [lowField, wind], keystrokeSets: [marimba])
}
