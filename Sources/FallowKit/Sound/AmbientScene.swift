/// A generated ambient soundscape. `render` runs on the audio thread, so a scene allocates
/// everything up front and never allocates, locks or touches the main thread while rendering.
public protocol AmbientScene: AnyObject {
    /// Fills `frames` samples of each channel, at the sample rate the scene was made for.
    func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int)
}
