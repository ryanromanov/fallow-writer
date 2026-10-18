import Foundation

/// A small, fast random number generator (xorshift64*), safe to use on the audio thread.
public struct FastRandom {
    private var state: UInt64

    public init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }

    public mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545_F491_4F6C_DD1D
    }

    /// Uniform in -1...1.
    public mutating func bipolar() -> Float {
        Float(Double(next() >> 11) / Double(1 << 53)) * 2 - 1
    }

    /// Uniform in 0..<1.
    public mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}

/// A state-variable filter (Zavalishin's topology-preserving form), stable while its
/// frequency moves, which plain biquads aren't. Safe to use on the audio thread.
public struct StateVariableFilter {
    private var g = 0.0, k = 1.0, a1 = 0.0, a2 = 0.0, a3 = 0.0
    private var ic1 = 0.0, ic2 = 0.0

    public init() {}

    public mutating func tune(frequency: Double, q: Double, sampleRate: Double) {
        g = tan(Double.pi * min(frequency, sampleRate * 0.45) / sampleRate)
        k = 1 / q
        a1 = 1 / (1 + g * (g + k))
        a2 = g * a1
        a3 = g * a2
    }

    /// Returns (low-pass, band-pass, high-pass).
    public mutating func process(_ x: Double) -> (low: Double, band: Double, high: Double) {
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
