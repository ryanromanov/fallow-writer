import Foundation

/// "Low Field": a warm drone. Tones of a D chord swell and fade on their own slow cycles, so the
/// harmony keeps shifting without ever changing key, over a faint breath of air.
///
/// `render` runs on the audio thread: all state is allocated up front, and it never allocates,
/// locks or touches the main thread.
final class LowField: AmbientScene {
    /// Swells change over tens of seconds, so they're computed once per block of this many
    /// samples and interpolated in between.
    static let blockSize = 64

    /// Each tone is a point turning around a circle: rotating it one step per sample traces the
    /// sine with two multiplications, where calling sin() costs far more on the audio thread.
    private struct Oscillator {
        var x = 1.0, y = 0.0          // cos and sin of the current phase
        let stepCos: Double, stepSin: Double

        init(frequency: Double, sampleRate: Double) {
            let step = 2 * Double.pi * frequency / sampleRate
            stepCos = cos(step)
            stepSin = sin(step)
        }

        mutating func advance() {
            (x, y) = (x * stepCos - y * stepSin, x * stepSin + y * stepCos)
        }

        /// Rounding slowly changes the circle's radius; pull it back to 1 (one Newton step).
        mutating func renormalize() {
            let scale = (3 - (x * x + y * y)) / 2
            x *= scale
            y *= scale
        }
    }

    private struct Voice {
        var tone: Oscillator
        var twin: Oscillator           // detuned slightly sharp, so the pair beats slowly
        var amplitude: Double
        var pan: Double                // 0 left … 1 right
        var swellStep: Double          // swell phase advance per block
        var swellPhase: Double
        var swell = 0.0                // level at the start of the current block
    }

    private let sampleRate: Double
    private let voices: UnsafeMutableBufferPointer<Voice>
    private var random = FastRandom(seed: 0x10F1_E1D)
    private var air = (b0: Float(0), b1: Float(0), b2: Float(0), lowpass: Float(0), right: Float(0))
    /// Detuning for the chorus: each tone has a twin this many hertz sharp, so they beat slowly.
    private let detune = 0.18
    /// Samples left in the current block.
    private var blockRemaining = 0
    private var started = false
    /// Tests turn the air off to compare the tones alone.
    private let includesAir: Bool

    init(sampleRate: Double, air: Bool = true) {
        self.sampleRate = sampleRate
        includesAir = air
        let tones: [(midi: Int, amplitude: Double, pan: Double, period: Double)] = [
            (38, 0.30, 0.50, 23),   // D2
            (45, 0.22, 0.35, 17),   // A2
            (50, 0.18, 0.65, 29),   // D3
            (54, 0.12, 0.25, 13),   // F#3
            (57, 0.11, 0.75, 19),   // A3
            (64, 0.06, 0.40, 31),   // E4, the ninth
            (69, 0.04, 0.60, 37),   // A4
        ]
        voices = .allocate(capacity: tones.count)
        for (i, tone) in tones.enumerated() {
            let frequency = 440 * pow(2, Double(tone.midi - 69) / 12)
            // Stagger the swells so the field starts already in motion.
            let phase = Double(i) * 0.37
            let voice = Voice(
                tone: Oscillator(frequency: frequency, sampleRate: sampleRate),
                twin: Oscillator(frequency: frequency + detune, sampleRate: sampleRate),
                amplitude: tone.amplitude, pan: tone.pan,
                swellStep: 2 * Double.pi * Double(Self.blockSize) / (tone.period * sampleRate),
                swellPhase: phase, swell: Self.swell(at: phase))
            voices.baseAddress!.advanced(by: i).initialize(to: voice)
        }
    }

    deinit {
        voices.baseAddress!.deinitialize(count: voices.count)
        voices.deallocate()
    }

    /// Swell between 15% and 100% of the voice's level.
    private static func swell(at phase: Double) -> Double {
        0.15 + 0.85 * (0.5 - 0.5 * cos(phase))
    }

    func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) {
        var n = 0
        while n < frames {
            if blockRemaining == 0 { startBlock() }
            let count = min(blockRemaining, frames - n)
            // How far through the block the first sample of this run is.
            let done = Self.blockSize - blockRemaining
            for i in voices.indices {
                var voice = voices[i]
                let next = Self.swell(at: voice.swellPhase + voice.swellStep)
                let slope = (next - voice.swell) / Double(Self.blockSize)
                var gain = (voice.swell + slope * Double(done)) * voice.amplitude * 0.16
                let leftGain = 1 - voice.pan, rightGain = voice.pan
                for k in 0..<count {
                    // A sine with a little second harmonic (sin 2φ = 2 sin φ cos φ), and its twin.
                    let s = voice.tone.y
                    let value = (s + 0.5 * s * voice.tone.x + voice.twin.y) * gain
                    let index = n + k
                    if i == 0 {
                        left[index] = Float(value * leftGain)
                        right[index] = Float(value * rightGain)
                    } else {
                        left[index] += Float(value * leftGain)
                        right[index] += Float(value * rightGain)
                    }
                    voice.tone.advance()
                    voice.twin.advance()
                    gain += slope * voice.amplitude * 0.16
                }
                voices[i] = voice
            }
            for k in n..<(n + count) where includesAir {
                let breath = nextAir()
                left[k] += breath.0
                right[k] += breath.1
            }
            n += count
            blockRemaining -= count
        }
    }

    /// Moves every voice's swell on by one block (except before the first) and keeps the
    /// oscillators on their circles.
    private func startBlock() {
        for i in voices.indices {
            if started {
                voices[i].swellPhase += voices[i].swellStep
                if voices[i].swellPhase > 2 * Double.pi { voices[i].swellPhase -= 2 * Double.pi }
            }
            voices[i].swell = Self.swell(at: voices[i].swellPhase)
            voices[i].tone.renormalize()
            voices[i].twin.renormalize()
        }
        blockRemaining = Self.blockSize
        started = true
    }

    /// Faint pink noise, low-passed so it reads as air rather than hiss. The right channel is
    /// a slightly delayed blend so the two sides aren't identical.
    private func nextAir() -> (Float, Float) {
        let white = random.bipolar()
        // Paul Kellet's economy pink-noise filter.
        air.b0 = 0.99765 * air.b0 + white * 0.0990460
        air.b1 = 0.96300 * air.b1 + white * 0.2965164
        air.b2 = 0.57000 * air.b2 + white * 1.0526913
        let pink = air.b0 + air.b1 + air.b2 + white * 0.1848
        air.lowpass += 0.04 * (pink - air.lowpass)
        air.right += 0.3 * (air.lowpass - air.right)
        // Keep denormals out of the filters.
        if abs(air.lowpass) < 1e-15 { air.lowpass = 0 }
        if abs(air.right) < 1e-15 { air.right = 0 }
        return (air.lowpass * 0.05, air.right * 0.05)
    }
}
