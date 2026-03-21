import AVFoundation

class SqueakAudioEngine {
    private var engine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private var varispeed = AVAudioUnitVarispeed()
    private var audioBuffer: AVAudioPCMBuffer?
    private var isPlaying = false
    private var isFadingOut = false
    private var fadeWorkItem: DispatchWorkItem?

    var volume: Float = 0.7 {
        didSet {
            guard isPlaying, !isFadingOut else { return }
            engine.mainMixerNode.outputVolume = volume
        }
    }

    init() {
        loadSound(named: "crack2")
        setupEngine()
    }

    func loadSound(named name: String) {
        let extensions = ["m4a", "wav", "mp3", "aiff"]
        var url: URL?
        for ext in extensions {
            if let found = Bundle.main.url(forResource: name, withExtension: ext) {
                url = found
                break
            }
        }

        guard let soundURL = url else {
            NSLog("[Crack] Sound file '%@' not found in bundle", name)
            return
        }

        do {
            let file = try AVAudioFile(forReading: soundURL)
            let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(file.length)
            )
            guard let buffer = buffer else { return }
            try file.read(into: buffer)
            self.audioBuffer = buffer

            // Full teardown and rebuild
            fadeWorkItem?.cancel()
            fadeWorkItem = nil
            playerNode.stop()
            engine.stop()
            engine.detach(playerNode)
            engine.detach(varispeed)
            isPlaying = false
            isFadingOut = false

            // Create fresh nodes
            playerNode = AVAudioPlayerNode()
            varispeed = AVAudioUnitVarispeed()
            setupEngine()

            NSLog("[Crack] Loaded sound: %@ (%d frames)", name, buffer.frameLength)
        } catch {
            NSLog("[Crack] Failed to load sound: %@", error.localizedDescription)
        }
    }

    private func setupEngine() {
        engine.attach(playerNode)
        engine.attach(varispeed)

        let format = audioBuffer?.format
            ?? AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        engine.connect(playerNode, to: varispeed, format: format)
        engine.connect(varispeed, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
        } catch {
            NSLog("[Crack] Audio engine failed to start: %@", error.localizedDescription)
        }
    }

    private var targetRate: Float = 1.0
    private(set) var currentRate: Float = 1.0
    private let smoothing: Float = 0.3

    func tick() {
        guard isPlaying else { return }
        currentRate += (targetRate - currentRate) * smoothing
        varispeed.rate = currentRate
    }

    func play(rate: Float, volume: Float) {
        self.volume = volume
        fadeWorkItem?.cancel()
        fadeWorkItem = nil
        isFadingOut = false

        targetRate = rate
        engine.mainMixerNode.outputVolume = volume

        if !engine.isRunning {
            do { try engine.start() } catch {
                NSLog("[Crack] Engine restart failed: %@", error.localizedDescription)
                return
            }
        }

        if !isPlaying, let buffer = audioBuffer {
            playerNode.stop()
            currentRate = rate
            varispeed.rate = currentRate
            playerNode.scheduleBuffer(buffer, at: nil, options: .loops)
            playerNode.play()
            isPlaying = true
        }
    }

    func fadeOut() {
        guard isPlaying, !isFadingOut else { return }
        isFadingOut = true

        let steps = 8
        let interval = 0.025
        let savedVolume = volume

        for i in 0..<steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * interval) { [weak self] in
                guard let self = self, self.isFadingOut else { return }
                let progress = Float(i + 1) / Float(steps)
                self.engine.mainMixerNode.outputVolume = savedVolume * (1.0 - progress)
            }
        }

        let stopItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.playerNode.stop()
            self.isPlaying = false
            self.isFadingOut = false
        }
        fadeWorkItem = stopItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Double(steps) * interval,
            execute: stopItem
        )
    }

    func stop() {
        fadeWorkItem?.cancel()
        fadeWorkItem = nil
        playerNode.stop()
        isPlaying = false
        isFadingOut = false
        engine.mainMixerNode.outputVolume = 0
    }

    static func availableSounds() -> [String] {
        let extensions = ["m4a", "wav", "mp3", "aiff"]
        var sounds: Set<String> = []
        for ext in extensions {
            if let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) {
                for url in urls {
                    sounds.insert(url.deletingPathExtension().lastPathComponent)
                }
            }
        }
        return sounds.sorted()
    }
}
