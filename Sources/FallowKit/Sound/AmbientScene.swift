/// A generated ambient soundscape. `render` runs on the audio thread, so a scene allocates
/// everything up front and never allocates, locks or touches the main thread while rendering.
protocol AmbientScene: AnyObject {
    func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int)
}

/// The ambient scenes you can choose from the Sound menu.
public enum AmbientChoice: String, CaseIterable {
    case lowField, wind

    var title: String {
        switch self {
        case .lowField: return "Low Field"
        case .wind: return "Wind"
        }
    }

    func makeScene(sampleRate: Double) -> AmbientScene {
        switch self {
        case .lowField: return LowField(sampleRate: sampleRate)
        case .wind: return FieldWind(sampleRate: sampleRate)
        }
    }
}
