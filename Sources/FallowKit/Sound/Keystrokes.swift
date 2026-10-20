import AppKit
import Foundation

/// What kind of key was pressed, for choosing its sound.
public enum KeyClass: CaseIterable {
    case letter, space, newline, delete

    /// Nil for keys that shouldn't make a sound: shortcuts (⌘ or ⌃ held), arrows, function and
    /// navigation keys, and Escape.
    static func classify(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, characters: String?) -> KeyClass? {
        if !modifiers.intersection([.command, .control]).isEmpty { return nil }
        switch keyCode {
        case 49, 48: return .space          // space, tab
        case 36, 76: return .newline        // return, keypad enter
        case 51, 117: return .delete        // delete (backspace), forward delete
        case 53: return nil                 // escape
        default: break
        }
        guard let scalar = characters?.unicodeScalars.first else { return nil }
        // AppKit sends arrows, function and navigation keys as private-use characters.
        if (0xF700...0xF8FF).contains(scalar.value) || scalar.properties.generalCategory == .control { return nil }
        return .letter
    }

    init?(event: NSEvent) {
        guard let kind = Self.classify(
            keyCode: event.keyCode, modifiers: event.modifierFlags, characters: event.charactersIgnoringModifiers)
        else { return nil }
        self = kind
    }
}

/// "Marimba": soft wooden bars struck with a felt mallet. Letters play notes of a D major
/// pentatonic scale, so any run of typing sounds consonant.
enum MarimbaKeystrokes {
    static let sampleRate = 44_100.0
    /// A4 to D6, D major pentatonic.
    static let letterNotes = [69, 71, 74, 76, 78, 81, 83, 86]

    /// Every sound for one key class. Letters get one variant per note; the rest get a few
    /// slight variations so repeated presses don't sound mechanical.
    static func sounds(for kind: KeyClass) -> [[Float]] {
        var random = FastRandom(seed: 0xFA11_0001)
        switch kind {
        case .letter:
            return letterNotes.map { bar(frequency: frequency(midi: $0), gain: 0.22, decay: 0.55, brightness: 0.9, random: &random) }
        case .space:
            return (0..<3).map { i in
                bar(frequency: frequency(midi: 62) * (1 + Double(i - 1) * 0.004), gain: 0.2, decay: 0.7, brightness: 0.6, random: &random)
            }
        case .newline:
            return (0..<2).map { i in
                let root = 50 + i * 2 // D3 or E3
                return chord([root, root + 7, root + 12, root + 16], spread: 0.018, gain: 0.13, random: &random)
            }
        case .delete:
            return (0..<3).map { i in
                bar(frequency: 196 * (1 + Double(i) * 0.03), gain: 0.16, decay: 0.07, brightness: 0.3, noise: 0.5, random: &random)
            }
        }
    }

    static func frequency(midi: Int) -> Double {
        440 * pow(2, Double(midi - 69) / 12)
    }

    /// One struck bar: a fundamental and the marimba's tuned overtones (4× and 10×), each dying away
    /// at its own rate, plus a short felt thump. `decay` is the fundamental's time constant at A4;
    /// higher notes ring shorter.
    static func bar(
        frequency: Double, gain: Float, decay: Double, brightness: Float, noise: Float = 0.15,
        random: inout FastRandom
    ) -> [Float] {
        let tau = decay * pow(440 / frequency, 0.4)
        let length = Int((tau * 6 + 0.02) * sampleRate)
        let partials: [(ratio: Double, amplitude: Float, tau: Double)] = [
            (1, 1, tau),
            (3.93, 0.32 * brightness, tau * 0.22),
            (9.54, 0.1 * brightness, tau * 0.06),
        ]
        var samples = [Float](repeating: 0, count: length)
        var thump: Float = 0
        for n in 0..<length {
            let t = Double(n) / sampleRate
            var value: Float = 0
            for partial in partials where partial.ratio * frequency < sampleRate / 2 {
                value += partial.amplitude * Float(sin(2 * .pi * partial.ratio * frequency * t) * exp(-t / partial.tau))
            }
            // Felt thump: low-passed noise that's gone in a few milliseconds.
            thump += 0.15 * (random.bipolar() - thump)
            value += noise * thump * Float(exp(-t / 0.004))
            samples[n] = value * gain * envelope(n, length)
        }
        return samples
    }

    /// Several bars struck almost together, low to high, as a soft rolled chord.
    static func chord(_ notes: [Int], spread: Double, gain: Float, random: inout FastRandom) -> [Float] {
        let bars = notes.map { bar(frequency: frequency(midi: $0), gain: gain, decay: 0.9, brightness: 0.5, random: &random) }
        let offset = Int(spread * sampleRate)
        var mix = [Float](repeating: 0, count: bars.map(\.count).max()! + offset * (notes.count - 1))
        for (i, bar) in bars.enumerated() {
            for (n, sample) in bar.enumerated() { mix[i * offset + n] += sample }
        }
        return mix
    }

    /// A 3 ms attack (a felt mallet, and no click) and a 20 ms release that lands exactly on zero.
    private static func envelope(_ n: Int, _ length: Int) -> Float {
        let attack = Int(0.003 * sampleRate), release = Int(0.02 * sampleRate)
        if n < attack { return Float(n) / Float(attack) }
        if n >= length - release { return Float(length - 1 - n) / Float(release) }
        return 1
    }
}
