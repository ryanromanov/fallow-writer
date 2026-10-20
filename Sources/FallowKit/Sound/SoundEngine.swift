import AVFoundation

/// Plays keystroke sounds and the ambient scene.
///
/// Graph: keystroke players → keys mixer ┐
///        ambient source node → ambient mixer ┴→ bus → peak limiter → main mixer → output
///
/// The engine runs only while a window is open and at least one channel is on. If it can't
/// start (no output device, say), Fallow carries on silently.
public final class SoundEngine {
    public static let shared = SoundEngine(settings: .shared)

    /// Voices for overlapping keystrokes. A voice is reused only once its sound has finished.
    static let voiceCount = 14
    /// Auto-repeated keys play this much quieter.
    static let repeatGain: Float = 0.35

    let engine = AVAudioEngine()
    private let settings: WriterSettings
    private let library: Library
    private let offline: Bool
    private let keysMixer = AVAudioMixerNode()
    private let ambientMixer = AVAudioMixerNode()
    private let bus = AVAudioMixerNode()
    private let limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_PeakLimiter,
        componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
    private let keyFormat = AVAudioFormat(standardFormatWithSampleRate: KeystrokeSet.sampleRate, channels: 1)!
    private let ambientFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!

    private var players: [AVAudioPlayerNode] = []
    /// When each voice's current sound ends, in seconds since the reference date.
    private var busyUntil: [TimeInterval]
    private var sounds: [KeyClass: [AVAudioPCMBuffer]] = [:]
    /// The keystroke set `sounds` holds.
    private(set) var keystrokeSetID: String?
    private var lastVariant: [KeyClass: Int] = [:]
    private var ambientNode: AVAudioSourceNode?
    /// The ambience `ambientNode` is playing.
    private var ambienceID: String?
    /// Fades in progress, one per node, so fading a new scene in never strands an old one.
    private var fades: [ObjectIdentifier: Timer] = [:]
    /// Nodes still fading out before they're detached.
    private var fadingOut = 0
    private var openWindows = 0
    private var random = SystemRandomNumberGenerator()

    /// False if the engine failed to start; Fallow then stays silent.
    public private(set) var isAvailable = true

    /// `offline` renders through `engine.renderOffline` instead of the speakers, for tests.
    init(settings: WriterSettings, library: Library = .shared, offline: Bool = false) {
        self.settings = settings
        self.library = library
        self.offline = offline
        busyUntil = Array(repeating: 0, count: Self.voiceCount)

        if offline {
            try? engine.enableManualRenderingMode(.offline, format: ambientFormat, maximumFrameCount: 4096)
        }
        for node in [keysMixer, ambientMixer, bus, limiter] as [AVAudioNode] { engine.attach(node) }
        engine.connect(keysMixer, to: bus, format: nil)
        engine.connect(ambientMixer, to: bus, format: nil)
        engine.connect(bus, to: limiter, format: nil)
        engine.connect(limiter, to: engine.mainMixerNode, format: nil)

        for _ in 0..<Self.voiceCount {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: keysMixer, format: keyFormat)
            players.append(player)
        }
        loadKeystrokes()

        NotificationCenter.default.addObserver(
            self, selector: #selector(configurationChanged), name: .AVAudioEngineConfigurationChange, object: engine)
        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsChanged), name: WriterSettings.didChange, object: settings)
        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsChanged), name: Library.didChange, object: library)
    }

    // MARK: Windows

    public func windowOpened() {
        openWindows += 1
        update()
    }

    public func windowClosed() {
        openWindows = max(0, openWindows - 1)
        update()
    }

    // MARK: Keystrokes

    /// Renders the chosen keystroke set into buffers, unless they're already loaded.
    private func loadKeystrokes() {
        let set = library.keystrokeSet(for: settings.keystrokeChoice)
        guard set.id != keystrokeSetID else { return }
        keystrokeSetID = set.id
        lastVariant = [:]
        for kind in KeyClass.allCases {
            sounds[kind] = set.sounds(kind).filter { !$0.isEmpty }.map(makeBuffer)
        }
    }

    public func keystroke(_ kind: KeyClass, isRepeat: Bool = false) {
        guard settings.keystrokeSounds, engine.isRunning, let variants = sounds[kind], !variants.isEmpty else { return }
        // Never the same variant twice in a row.
        var variant = Int.random(in: 0..<variants.count, using: &random)
        if variants.count > 1, variant == lastVariant[kind] { variant = (variant + 1) % variants.count }
        lastVariant[kind] = variant
        let buffer = variants[variant]

        let now = Date.timeIntervalSinceReferenceDate
        let voice = busyUntil.firstIndex { $0 <= now } ?? busyUntil.indices.min { busyUntil[$0] < busyUntil[$1] }!
        busyUntil[voice] = now + Double(buffer.frameLength) / keyFormat.sampleRate

        let player = players[voice]
        player.volume = (isRepeat ? Self.repeatGain : 1) * Float.random(in: 0.85...1, using: &random)
        player.pan = kind == .letter ? Float.random(in: -0.25...0.25, using: &random) : 0
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
    }

    // MARK: Running and stopping

    @objc private func settingsChanged() { update() }

    private func applyVolumes() {
        keysMixer.outputVolume = settings.keystrokeVolume
        ambientMixer.outputVolume = settings.ambientVolume
    }

    private var wanted: Bool { openWindows > 0 && (settings.keystrokeSounds || settings.ambientSound) }

    /// Starts or stops the engine and the ambient scene to match the settings and open windows.
    private func update() {
        applyVolumes()
        loadKeystrokes()
        if wanted, !engine.isRunning { start() }
        guard engine.isRunning else { return }
        if openWindows > 0, settings.ambientSound {
            // Choosing another scene crossfades: the old one fades out as the new one fades in.
            if ambienceID != library.ambience(for: settings.ambientChoice).id { stopAmbient() }
            startAmbient()
        } else {
            stopAmbient()
        }
        stopIfIdle()
    }

    /// Stops the engine, so it costs no CPU, once nothing is playing or about to.
    private func stopIfIdle() {
        if !wanted, ambientNode == nil, fadingOut == 0, engine.isRunning { engine.stop() }
    }

    private func start() {
        do {
            engine.prepare()
            try engine.start()
            // After the engine has been stopped, a player still reports isPlaying but stays
            // silent until it's stopped and played again.
            players.forEach { $0.stop(); $0.play() }
            isAvailable = true
        } catch {
            isAvailable = false
        }
    }

    /// Plugging in or unplugging headphones stops the engine; start it again.
    @objc private func configurationChanged(_ notification: Notification) {
        DispatchQueue.main.async { [self] in
            guard !engine.isRunning, wanted else { return }
            start()
        }
    }

    // MARK: Ambient

    private func startAmbient() {
        guard ambientNode == nil else { return }
        let ambience = library.ambience(for: settings.ambientChoice)
        let scene = ambience.make(ambientFormat.sampleRate)
        let node = AVAudioSourceNode(format: ambientFormat) { _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard buffers.count >= 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self)
            else { return noErr }
            scene.render(left: left, right: right, frames: Int(frameCount))
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: ambientMixer, format: ambientFormat)
        ambientNode = node
        ambienceID = ambience.id
        fade(node, to: 1, over: offline ? 0 : 2.5)
    }

    private func stopAmbient() {
        guard let node = ambientNode else { return }
        ambientNode = nil
        ambienceID = nil
        fadingOut += 1
        fade(node, to: 0, over: offline ? 0 : 1.5) { [self] in
            engine.detach(node)
            fadingOut -= 1
            stopIfIdle()
        }
    }

    /// Ramps a node's volume on the main thread, replacing any fade already running on that node.
    private func fade(_ node: AVAudioSourceNode, to target: Float, over duration: TimeInterval, then done: (() -> Void)? = nil) {
        let id = ObjectIdentifier(node)
        fades.removeValue(forKey: id)?.invalidate()
        if duration == 0 {
            node.volume = target
            done?()
            return
        }
        if target > 0 { node.volume = 0 }
        let start = node.volume, began = Date()
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] timer in
            let progress = min(1, Float(Date().timeIntervalSince(began) / duration))
            // Ease in and out so the start and end of the fade are both gentle.
            let eased = progress * progress * (3 - 2 * progress)
            node.volume = start + (target - start) * eased
            guard progress >= 1 else { return }
            timer.invalidate()
            self?.fades.removeValue(forKey: id)
            done?()
        }
        // In common modes, so a fade keeps going while a slider is dragged, a menu is open or
        // the window is resized, instead of pausing part-way until the mouse is let go.
        RunLoop.main.add(timer, forMode: .common)
        fades[id] = timer
    }

    private func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: keyFormat, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
        }
        return buffer
    }
}
