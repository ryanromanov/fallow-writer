import AppKit
import AVFoundation
import Foundation
import Testing
@testable import FallowKit

// These tests never start the realtime engine: generators are tested directly, and the graph
// runs in offline manual rendering mode, so nothing plays through the speakers.

func peak(_ samples: [Float]) -> Float { samples.map(abs).max() ?? 0 }
func rms(_ samples: [Float]) -> Float {
    samples.isEmpty ? 0 : (samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
}

@Suite struct KeystrokeTests {
    @Test(arguments: KeyClass.allCases)
    func soundsAreCleanAndQuiet(kind: KeyClass) {
        let sounds = MarimbaKeystrokes.sounds(for: kind)
        #expect(!sounds.isEmpty)
        for samples in sounds {
            #expect(samples.allSatisfy { $0.isFinite })
            #expect(peak(samples) < 0.5)
            #expect(peak(samples) > 0.02)
            // Starts and ends at silence, so there's no click.
            #expect(abs(samples.first!) < 0.01)
            #expect(peak(Array(samples.suffix(Int(0.005 * MarimbaKeystrokes.sampleRate)))) < 0.002)
        }
    }

    @Test func fastTypingDoesNotClip() {
        // Fifteen letters in one second, every one a full-volume hit.
        let letters = MarimbaKeystrokes.sounds(for: .letter)
        let step = Int(MarimbaKeystrokes.sampleRate / 15)
        var mix = [Float](repeating: 0, count: step * 15 + letters.map(\.count).max()!)
        for i in 0..<15 {
            for (n, sample) in letters[i % letters.count].enumerated() { mix[i * step + n] += sample }
        }
        #expect(peak(mix) < 1)
    }

    static let keyCases: [(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, characters: String, expected: KeyClass?)] = [
        (0, [], "a", .letter),
        (49, [], " ", .space),
        (36, [], "\r", .newline),
        (51, [], "\u{7F}", .delete),
        (117, [], "\u{F728}", .delete),
        (0, [.command], "a", nil),
        (0, [.control], "a", nil),
        (123, [], "\u{F702}", nil),       // left arrow
        (122, [], "\u{F704}", nil),       // F1
        (53, [], "\u{1B}", nil),          // escape
        (0, [.shift], "A", .letter),
        (0, [.option], "å", .letter),
    ]

    @Test(arguments: keyCases)
    func classifiesKeys(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, characters: String, expected: KeyClass?) {
        #expect(KeyClass.classify(keyCode: keyCode, modifiers: modifiers, characters: characters) == expected)
    }
}

@Suite struct LowFieldTests {
    @Test func rendersAGentleSteadyDrone() {
        let rate = 44_100.0
        let field = LowField(sampleRate: rate)
        let frames = Int(rate * 10)
        var left = [Float](repeating: 0, count: frames), right = left
        // Render in device-sized chunks, as the audio thread would.
        for start in stride(from: 0, to: frames, by: 512) {
            let count = min(512, frames - start)
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    field.render(left: l.baseAddress! + start, right: r.baseAddress! + start, frames: count)
                }
            }
        }
        #expect(left.allSatisfy { $0.isFinite } && right.allSatisfy { $0.isFinite })
        #expect(peak(left) < 0.8 && peak(right) < 0.8)
        #expect((0.02...0.2).contains(rms(left)))
        #expect((0.02...0.2).contains(rms(right)))
        #expect(left != right)
    }
}

/// Renders `seconds` of a scene in device-sized chunks, as the audio thread would.
func renderScene(_ scene: AmbientScene, seconds: Double, sampleRate: Double = 44_100) -> (left: [Float], right: [Float]) {
    let frames = Int(sampleRate * seconds)
    var left = [Float](repeating: 0, count: frames), right = left
    for start in stride(from: 0, to: frames, by: 512) {
        let count = min(512, frames - start)
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                scene.render(left: l.baseAddress! + start, right: r.baseAddress! + start, frames: count)
            }
        }
    }
    return (left, right)
}

@Suite struct FieldWindTests {
    @Test func rendersGustyWideWind() {
        let (left, right) = renderScene(FieldWind(sampleRate: 44_100), seconds: 40)
        #expect(left.allSatisfy { $0.isFinite } && right.allSatisfy { $0.isFinite })
        #expect(peak(left) < 0.8 && peak(right) < 0.8)
        #expect((0.02...0.2).contains(rms(left)))
        #expect((0.02...0.2).contains(rms(right)))
        #expect(left != right)

        // Gusts: one-second windows should range from lulls to clearly louder stretches.
        let levels = stride(from: 0, to: left.count - 44_100, by: 44_100).map { rms(Array(left[$0..<($0 + 44_100)])) }
        #expect(levels.max()! / levels.min()! > 1.5)
    }
}

/// The drone as first written, with sin() and cos() every sample: slow, but plainly correct.
/// The optimized LowField must sound the same.
func referenceLowField(sampleRate: Double, frames: Int) -> (left: [Float], right: [Float]) {
    let tones: [(midi: Int, amplitude: Double, pan: Double, period: Double)] = [
        (38, 0.30, 0.50, 23), (45, 0.22, 0.35, 17), (50, 0.18, 0.65, 29), (54, 0.12, 0.25, 13),
        (57, 0.11, 0.75, 19), (64, 0.06, 0.40, 31), (69, 0.04, 0.60, 37),
    ]
    var left = [Float](repeating: 0, count: frames), right = left
    for (i, tone) in tones.enumerated() {
        let frequency = 440 * pow(2, Double(tone.midi - 69) / 12)
        for n in 0..<frames {
            let t = Double(n) / sampleRate
            let phase = 2 * Double.pi * frequency * t
            let value = sin(phase) + 0.25 * sin(2 * phase) + sin(2 * Double.pi * (frequency + 0.18) * t)
            let swell = 0.15 + 0.85 * (0.5 - 0.5 * cos(Double(i) * 0.37 + 2 * Double.pi * t / tone.period))
            let sample = value * tone.amplitude * swell * 0.16
            left[n] += Float(sample * (1 - tone.pan))
            right[n] += Float(sample * tone.pan)
        }
    }
    return (left, right)
}

@Suite struct LowFieldMatchesReference {
    @Test func soundsTheSameAsTheReference() {
        let rate = 44_100.0, frames = Int(rate * 10)
        let reference = referenceLowField(sampleRate: rate, frames: frames)
        let field = LowField(sampleRate: rate, air: false)
        var left = [Float](repeating: 0, count: frames), right = left
        for start in stride(from: 0, to: frames, by: 471) {   // an odd chunk size, to cross block edges
            let count = min(471, frames - start)
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    field.render(left: l.baseAddress! + start, right: r.baseAddress! + start, frames: count)
                }
            }
        }
        // Tones only: what's left after subtracting the reference must be far below hearing.
        for (rendered, expected) in [(left, reference.left), (right, reference.right)] {
            let difference = zip(rendered, expected).map { $0 - $1 }
            #expect(rms(difference) < rms(expected) * 0.001)
        }
    }
}

@Suite @MainActor struct SoundEngineTests {
    func makeSettings(keys: Bool, ambient: Bool) -> WriterSettings {
        let name = "FallowSoundTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = WriterSettings(defaults: defaults)
        settings.keystrokeSounds = keys
        settings.ambientSound = ambient
        return settings
    }

    func render(_ engine: AVAudioEngine, seconds: Double) throws -> [Float] {
        let format = engine.manualRenderingFormat
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: engine.manualRenderingMaximumFrameCount)!
        var samples: [Float] = []
        var remaining = Int(seconds * format.sampleRate)
        while remaining > 0 {
            let status = try engine.renderOffline(min(AVAudioFrameCount(remaining), buffer.frameCapacity), to: buffer)
            guard status == .success else { break }
            samples += UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))
            remaining -= Int(buffer.frameLength)
        }
        return samples
    }

    @Test func keystrokeReachesTheOutput() throws {
        let sound = SoundEngine(settings: makeSettings(keys: true, ambient: false), offline: true)
        sound.windowOpened()
        #expect(sound.engine.isRunning)
        let before = try render(sound.engine, seconds: 0.2)
        #expect(rms(before) < 1e-4)
        sound.keystroke(.letter)
        let after = try render(sound.engine, seconds: 0.3)
        #expect(rms(after) > 0.005)
    }

    @Test func ambientPlaysOnlyWhenOn() throws {
        let settings = makeSettings(keys: false, ambient: true)
        let sound = SoundEngine(settings: settings, offline: true)
        sound.windowOpened()
        let ambient = try render(sound.engine, seconds: 1)
        #expect(rms(ambient) > 0.01)
        #expect(peak(ambient) < 1)

        // Ambient off with keys still on: the drone goes, the engine stays.
        settings.keystrokeSounds = true
        settings.ambientSound = false
        #expect(sound.engine.isRunning)
        let silence = try render(sound.engine, seconds: 0.5)
        #expect(rms(silence) < 1e-4)
    }

    /// Both channels off stops the engine; turning keystrokes back on must bring them back.
    @Test func keystrokesReturnAfterEverythingWasOff() throws {
        let settings = makeSettings(keys: true, ambient: true)
        let sound = SoundEngine(settings: settings, offline: true)
        sound.windowOpened()
        settings.keystrokeSounds = false
        settings.ambientSound = false
        #expect(!sound.engine.isRunning)
        settings.keystrokeSounds = true
        #expect(sound.engine.isRunning)
        sound.keystroke(.letter)
        let after = try render(sound.engine, seconds: 0.3)
        #expect(rms(after) > 0.005)
    }

    @Test func switchingScenesKeepsPlaying() throws {
        let settings = makeSettings(keys: false, ambient: true)
        let sound = SoundEngine(settings: settings, offline: true)
        sound.windowOpened()
        let drone = try render(sound.engine, seconds: 0.5)
        settings.ambientChoice = .wind
        let wind = try render(sound.engine, seconds: 0.5)
        #expect(rms(drone) > 0.01)
        #expect(rms(wind) > 0.01)
        #expect(sound.engine.isRunning)
    }

    @Test func engineStopsWhenNothingNeedsIt() {
        let settings = makeSettings(keys: true, ambient: true)
        let sound = SoundEngine(settings: settings, offline: true)
        #expect(!sound.engine.isRunning)
        sound.windowOpened()
        #expect(sound.engine.isRunning)
        sound.windowClosed()
        #expect(!sound.engine.isRunning)
        sound.windowOpened()
        settings.keystrokeSounds = false
        settings.ambientSound = false
        #expect(!sound.engine.isRunning)
    }
}

/// Renders preview WAVs when FALLOW_AUDITION names a folder (see scripts/audition.sh).
@Suite struct Audition {
    @Test func renderPreviews() throws {
        guard let folder = ProcessInfo.processInfo.environment["FALLOW_AUDITION"] else { return }
        let directory = URL(fileURLWithPath: folder)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let rate = MarimbaKeystrokes.sampleRate
        var random = FastRandom(seed: 42)

        // A typed sentence: letters at an unhurried pace, spaces between words, a typo
        // fixed with two backspaces, and a return at the end.
        let script = "a field left to rest isn't empty~~t\n"
        var keys = [Float](repeating: 0, count: Int(rate * 7))
        var time = 0.4
        var last: [KeyClass: Int] = [:]
        for character in script {
            let kind: KeyClass = character == " " ? .space : character == "\n" ? .newline : character == "~" ? .delete : .letter
            let variants = MarimbaKeystrokes.sounds(for: kind)
            var index = Int(random.next() % UInt64(variants.count))
            if index == last[kind], variants.count > 1 { index = (index + 1) % variants.count }
            last[kind] = index
            let gain = 0.85 + 0.15 * (random.bipolar() + 1) / 2
            let start = Int(time * rate)
            for (n, sample) in variants[index].enumerated() where start + n < keys.count { keys[start + n] += sample * gain }
            time += 0.13 + 0.06 * Double(random.bipolar())
        }

        let field = LowField(sampleRate: rate)
        let frames = Int(rate * 20)
        var left = [Float](repeating: 0, count: frames), right = left
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in field.render(left: l.baseAddress!, right: r.baseAddress!, frames: frames) }
        }

        try write(keys, keys, to: directory.appendingPathComponent("1-keystrokes.wav"))
        try write(left, right, to: directory.appendingPathComponent("2-ambient.wav"))
        let together = zip(left, right).enumerated().map { n, pair in
            (pair.0 + (n < keys.count ? keys[n] : 0), pair.1 + (n < keys.count ? keys[n] : 0))
        }
        try write(together.map(\.0), together.map(\.1), to: directory.appendingPathComponent("3-together.wav"))

        let wind = renderScene(FieldWind(sampleRate: rate), seconds: 30)
        try write(wind.left, wind.right, to: directory.appendingPathComponent("4-wind.wav"))
        print("AUDITION levels (RMS): low field \(rms(left)), wind \(rms(wind.left))")
    }

    func write(_ left: [Float], _ right: [Float], to url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: MarimbaKeystrokes.sampleRate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(left.count))!
        buffer.frameLength = AVAudioFrameCount(left.count)
        for (channel, samples) in [left, right].enumerated() {
            samples.withUnsafeBufferPointer { buffer.floatChannelData![channel].update(from: $0.baseAddress!, count: samples.count) }
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: format.sampleRate, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        try file.write(from: buffer)
    }
}
