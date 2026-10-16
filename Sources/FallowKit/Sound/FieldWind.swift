import Foundation

/// "Wind": gusts moving across an open field, with no tones at all. Four layers of filtered
/// noise follow one slowly wandering gust strength: a low body, a whoosh whose pitch rises as a
/// gust builds, grass rustling that comes up only in gusts, and a faint whistle on the strongest.
/// Each ear gets its own noise and slightly different filters, so the wind feels wide.
///
/// `render` runs on the audio thread: all state is allocated up front, and it never allocates,
/// locks or touches the main thread.
final class FieldWind: AmbientScene {
    /// Gusts and filter settings change slowly, so they're updated once per block of this many
    /// samples and interpolated in between.
    static let blockSize = 64
    /// Overall level, set so the wind sits at the same loudness as Low Field.
    static let level = 0.36

    /// A state-variable filter (Zavalishin's topology-preserving form), stable while its
    /// frequency moves, which plain biquads aren't.
    struct Filter {
        private var g = 0.0, k = 1.0, a1 = 0.0, a2 = 0.0, a3 = 0.0
        private var ic1 = 0.0, ic2 = 0.0

        mutating func tune(frequency: Double, q: Double, sampleRate: Double) {
            g = tan(Double.pi * min(frequency, sampleRate * 0.45) / sampleRate)
            k = 1 / q
            a1 = 1 / (1 + g * (g + k))
            a2 = g * a1
            a3 = g * a2
        }

        /// Returns (low-pass, band-pass, high-pass).
        mutating func process(_ x: Double) -> (low: Double, band: Double, high: Double) {
            let v3 = x - ic2
            let v1 = a1 * ic1 + a2 * v3
            let v2 = ic2 + a2 * ic1 + a3 * v3
            ic1 = 2 * v1 - ic1
            ic2 = 2 * v2 - ic2
            // Keep denormals out of the integrators.
            if abs(ic1) < 1e-20 { ic1 = 0 }
            if abs(ic2) < 1e-20 { ic2 = 0 }
            return (v2, v1, x - k * v1 - v2)
        }
    }

    /// One ear's noise and filters.
    struct Channel {
        var random: FastRandom
        var brown = 0.0
        var body = Filter(), whoosh = Filter(), rustle = Filter(), whistle = Filter()
        var flutter = 0.0              // fast random flicker for the grass
        /// This ear's filters sit a little apart from the other's.
        let offset: Double
    }

    /// Gust strength wanders smoothly between calm (0) and a strong gust (1).
    private struct Gust {
        var random = FastRandom(seed: 0x6057)
        var drift = 0.0, target = 0.0, slow = 0.0
        var phases = (0.0, 1.3, 2.9)
        var value = 0.0, next = 0.0
    }

    private let sampleRate: Double
    private let channels: UnsafeMutableBufferPointer<Channel>
    private var gust = Gust()
    private var blockRemaining = 0

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        channels = .allocate(capacity: 2)
        channels.baseAddress!.initialize(to: Channel(random: FastRandom(seed: 0xA1C0_57E5), offset: 0.94))
        channels.baseAddress!.advanced(by: 1).initialize(to: Channel(random: FastRandom(seed: 0x7E57_BEEF), offset: 1.07))
        // Settle the gust so the wind starts mid-breeze, not from silence.
        for _ in 0..<2_000 { stepGust() }
        gust.value = gust.next
    }

    deinit {
        channels.baseAddress!.deinitialize(count: 2)
        channels.deallocate()
    }

    func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) {
        var n = 0
        while n < frames {
            if blockRemaining == 0 { startBlock() }
            let count = min(blockRemaining, frames - n)
            let done = Self.blockSize - blockRemaining
            let slope = (gust.next - gust.value) / Double(Self.blockSize)
            for c in 0..<2 {
                let output = c == 0 ? left : right
                var channel = channels[c]
                var strength = gust.value + slope * Double(done)
                for k in 0..<count {
                    output[n + k] = Float(sample(&channel, strength: strength))
                    strength += slope
                }
                channels[c] = channel
            }
            n += count
            blockRemaining -= count
        }
    }

    private func sample(_ channel: inout Channel, strength: Double) -> Double {
        let white = Double(channel.random.bipolar())
        // Brown noise (leaky integrated white): the deep, soft part of the wind.
        channel.brown = channel.brown * 0.995 + white * 0.04
        let body = channel.body.process(channel.brown).low
        let whoosh = channel.whoosh.process(white).band
        let rustleNoise = channel.rustle.process(white).high
        let whistle = channel.whistle.process(white).band

        // Grass flickers quickly and unevenly, louder the stronger the gust.
        channel.flutter += 0.002 * (abs(Double(channel.random.bipolar())) - channel.flutter)
        let rustle = rustleNoise * channel.flutter * 2

        let calm = 1 - strength
        return Self.level * (body * (0.55 + 0.6 * strength)
            + whoosh * (0.05 + 0.33 * strength)
            + rustle * (0.004 + 0.05 * strength * strength)
            + whistle * 0.02 * max(0, strength - 0.6) * calm.magnitude.squareRoot())
    }

    /// Moves the gust on one block and retunes the filters to follow it.
    private func startBlock() {
        gust.value = gust.next
        stepGust()
        let strength = gust.next
        for c in channels.indices {
            let offset = channels[c].offset
            channels[c].body.tune(frequency: (180 + 220 * strength) * offset, q: 0.6, sampleRate: sampleRate)
            channels[c].whoosh.tune(frequency: (320 + 900 * strength * strength) * offset, q: 0.9, sampleRate: sampleRate)
            channels[c].rustle.tune(frequency: 3_200 * offset, q: 0.7, sampleRate: sampleRate)
            channels[c].whistle.tune(frequency: (620 + 380 * strength) * offset, q: 18, sampleRate: sampleRate)
        }
        blockRemaining = Self.blockSize
    }

    /// Gust strength: three slow, unrelated cycles plus a random drift that now and then picks a
    /// new target, so the pattern of gusts never repeats.
    private func stepGust() {
        let blockSeconds = Double(Self.blockSize) / sampleRate
        let twoPi = 2 * Double.pi
        gust.phases.0 += twoPi * blockSeconds / 11.3
        gust.phases.1 += twoPi * blockSeconds / 7.1
        gust.phases.2 += twoPi * blockSeconds / 23.7
        if gust.phases.0 > twoPi { gust.phases.0 -= twoPi }
        if gust.phases.1 > twoPi { gust.phases.1 -= twoPi }
        if gust.phases.2 > twoPi { gust.phases.2 -= twoPi }
        // About every four seconds on average, the drift heads somewhere new.
        if Double(gust.random.next() % 10_000) / 10_000 < blockSeconds / 4 {
            gust.target = Double(gust.random.bipolar())
        }
        gust.drift += (gust.target - gust.drift) * blockSeconds / 2.5
        let cycles = 0.45 * sin(gust.phases.0) + 0.3 * sin(gust.phases.1) + 0.25 * sin(gust.phases.2)
        let raw = 0.45 + 0.3 * cycles + 0.3 * gust.drift
        // Smooth once more so even a new drift target arrives gently.
        gust.slow += (raw - gust.slow) * blockSeconds / 0.8
        gust.next = min(1, max(0, gust.slow))
    }
}
