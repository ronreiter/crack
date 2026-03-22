import AVFoundation

// MARK: - Protocol for all audio engines

protocol CreakAudioEngine: AnyObject {
    var volume: Float { get set }
    func play(rate: Float, volume: Float)
    func fadeOut()
    func stop()
    func tick()
}

// MARK: - Shared synth state

class SynthState {
    var targetExcitation: Float = 0
    var excitation: Float = 0
    var targetVolume: Float = 0
    var currentVolume: Float = 0
}

// MARK: - Crack Preset Parameters

struct CrackPreset {
    let name: String
    let crackRateMultiplier: Float   // how often cracks fire
    let decayRate: Float             // 0.9 = very short, 0.95 = longer
    let gateThreshold: Float
    let freqs: [Float]               // 5 resonator frequencies
    let qs: [Float]                  // 5 resonator Q values
    let mix: [Float]                 // 5 resonator mix levels
    let freqShift: Float             // how much freq shifts with excitation
    let drive: Float                 // output saturation
    let clickMix: Float              // raw click vs filtered ratio

    // Haunted Door with 2x accelerated frequencies
    static let all: [CrackPreset] = [
        CrackPreset(name: "Haunted Door",
                    crackRateMultiplier: 0.2, decayRate: 0.977, gateThreshold: 0.03,
                    freqs: [140, 320, 800, 2080, 5200], qs: [3, 4, 6, 5, 4],
                    mix: [0.3, 0.3, 0.25, 0.1, 0.05], freqShift: 0.3, drive: 7.0, clickMix: 0.5),
    ]
}

// MARK: - Parameterized Crack Engine

class SynthCrackEngine: CreakAudioEngine {
    private var engine: AVAudioEngine!
    private var srcNode: AVAudioSourceNode!
    private var isPlaying = false
    var volume: Float = 0.7
    private let state = SynthState()

    init(preset: CrackPreset = CrackPreset.all[0]) {
        let sr: Float = 44100
        let synthState = state
        let p = preset

        var burstEnvelope: Float = 0
        var burstPhase: Float = 0

        // 5 resonator states
        var ry: [(Float, Float)] = Array(repeating: (0, 0), count: 5)

        engine = AVAudioEngine()
        srcNode = AVAudioSourceNode { (_, _, frameCount, bufferList) -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(bufferList)
            let frames = Int(frameCount)

            for frame in 0..<frames {
                synthState.excitation += (synthState.targetExcitation - synthState.excitation) * 0.001
                synthState.currentVolume += (synthState.targetVolume - synthState.currentVolume) * 0.002
                let exc = synthState.excitation

                burstPhase += exc * 0.006 * p.crackRateMultiplier + 0.0001
                if burstPhase > 1.0 + Float.random(in: 0...1.0) {
                    burstPhase = 0
                    burstEnvelope = 1.0
                }

                burstEnvelope *= p.decayRate
                if burstEnvelope < p.gateThreshold { burstEnvelope = 0 }

                let excSignal: Float
                if burstEnvelope > 0 {
                    let click = burstEnvelope * burstEnvelope * burstEnvelope
                    excSignal = click * exc * 3.0
                } else {
                    excSignal = 0
                }

                func bp(_ input: Float, _ freq: Float, _ q: Float, _ idx: Int) -> Float {
                    let w0 = 2.0 * Float.pi * freq / sr
                    let alpha = sin(w0) / (2.0 * q)
                    let cosw0 = cos(w0)
                    let b0 = alpha, a0 = 1.0 + alpha
                    let a1 = -2.0 * cosw0, a2 = 1.0 - alpha
                    let out = (b0/a0) * input - (a1/a0) * ry[idx].0 - (a2/a0) * ry[idx].1
                    ry[idx].1 = ry[idx].0; ry[idx].0 = out
                    return out
                }

                var mixed: Float = 0
                for i in 0..<5 {
                    let f = p.freqs[i] + exc * p.freqs[i] * 0.3 * p.freqShift
                    mixed += bp(excSignal, f, p.qs[i], i) * p.mix[i]
                }

                let withClick = mixed + excSignal * p.clickMix
                let output = tanh(withClick * p.drive) * synthState.currentVolume * 0.6

                for buffer in abl { buffer.mData!.assumingMemoryBound(to: Float.self)[frame] = output }
            }
            return noErr
        }

        engine.attach(srcNode)
        engine.connect(srcNode, to: engine.mainMixerNode,
                       format: AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!)
        do { try engine.start() } catch {}
    }

    func play(rate: Float, volume: Float) {
        self.volume = volume; state.targetExcitation = min(rate, 4.0); state.targetVolume = volume
        if !engine.isRunning { do { try engine.start() } catch { return } }; isPlaying = true
    }
    func tick() {}
    func fadeOut() {
        state.targetExcitation = 0; state.targetVolume = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.isPlaying = false }
    }
    func stop() { state.targetExcitation = 0; state.targetVolume = 0; isPlaying = false }
}

// MARK: - FM Preset Parameters

struct FMPreset {
    let name: String
    let carrierBase: Float
    let carrierRange: Float
    let modBase: Float
    let modRange: Float
    let modIndexBase: Float
    let modIndexRange: Float
    let noiseAmount: Float
    let drive: Float

    static let all: [FMPreset] = [
        FMPreset(name: "Cat", carrierBase: 180, carrierRange: 120, modBase: 230, modRange: 80,
                 modIndexBase: 2.0, modIndexRange: 6.0, noiseAmount: 0.3, drive: 1.5),
        FMPreset(name: "Alien Whisper", carrierBase: 80, carrierRange: 40, modBase: 90, modRange: 30,
                 modIndexBase: 1.0, modIndexRange: 3.0, noiseAmount: 0.5, drive: 1.0),
        FMPreset(name: "Whale Song", carrierBase: 40, carrierRange: 20, modBase: 45, modRange: 15,
                 modIndexBase: 1.5, modIndexRange: 4.0, noiseAmount: 0.4, drive: 1.2),
        FMPreset(name: "Warble", carrierBase: 350, carrierRange: 150, modBase: 6, modRange: 4,
                 modIndexBase: 150, modIndexRange: 300, noiseAmount: 0.1, drive: 1.2),
    ]
}

// MARK: - Parameterized FM Engine

class FMSynthEngine: CreakAudioEngine {
    private var engine: AVAudioEngine!
    private var srcNode: AVAudioSourceNode!
    private var isPlaying = false
    var volume: Float = 0.7
    private let state = SynthState()

    init(preset: FMPreset = FMPreset.all[0]) {
        let sr: Float = 44100
        let synthState = state
        let p = preset

        var carrierPhase: Float = 0
        var modPhase: Float = 0
        var nf_y1: Float = 0

        engine = AVAudioEngine()
        srcNode = AVAudioSourceNode { (_, _, frameCount, bufferList) -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(bufferList)
            let frames = Int(frameCount)

            for frame in 0..<frames {
                synthState.excitation += (synthState.targetExcitation - synthState.excitation) * 0.0005
                synthState.currentVolume += (synthState.targetVolume - synthState.currentVolume) * 0.002
                let exc = synthState.excitation

                let cFreq = p.carrierBase + exc * p.carrierRange
                let mFreq = p.modBase + exc * p.modRange
                let mIdx = p.modIndexBase + exc * p.modIndexRange

                modPhase += mFreq / sr
                if modPhase >= 1.0 { modPhase -= 1.0 }
                let modSig = sin(modPhase * 2.0 * Float.pi)

                carrierPhase += (cFreq + modSig * mIdx * mFreq) / sr
                if carrierPhase >= 1.0 { carrierPhase -= 1.0 }
                let carrier = sin(carrierPhase * 2.0 * Float.pi)

                let noise = Float.random(in: -1...1)
                nf_y1 = nf_y1 * 0.95 + noise * 0.05
                let fNoise = nf_y1 * exc * p.noiseAmount

                let amp = exc * 0.4
                let output = tanh((carrier * amp + fNoise) * synthState.currentVolume * p.drive) * 0.5

                for buffer in abl { buffer.mData!.assumingMemoryBound(to: Float.self)[frame] = output }
            }
            return noErr
        }

        engine.attach(srcNode)
        engine.connect(srcNode, to: engine.mainMixerNode,
                       format: AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!)
        do { try engine.start() } catch {}
    }

    func play(rate: Float, volume: Float) {
        self.volume = volume; state.targetExcitation = min(rate, 4.0); state.targetVolume = volume
        if !engine.isRunning { do { try engine.start() } catch { return } }; isPlaying = true
    }
    func tick() {}
    func fadeOut() {
        state.targetExcitation = 0; state.targetVolume = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.isPlaying = false }
    }
    func stop() { state.targetExcitation = 0; state.targetVolume = 0; isPlaying = false }
}

// MARK: - Noise Preset Parameters

struct NoisePreset {
    let name: String
    let freqs: [Float]       // 3 resonator center frequencies
    let qs: [Float]          // 3 resonator Q values
    let freqShifts: [Float]  // how much each shifts with excitation
    let mix: [Float]         // 3 resonator mix levels
    let drive: Float
    let usePink: Bool        // true = pink noise, false = white

    static let all: [NoisePreset] = [
        NoisePreset(name: "Wind", freqs: [320, 680, 1400], qs: [40, 30, 20],
                    freqShifts: [200, 150, 100], mix: [0.5, 0.35, 0.15], drive: 3.0, usePink: true),
        NoisePreset(name: "Arctic Wind", freqs: [1000, 3000, 7000], qs: [25, 30, 20],
                    freqShifts: [300, 500, 800], mix: [0.3, 0.4, 0.3], drive: 3.5, usePink: true),
    ]
}

// MARK: - Parameterized Noise+Filter Engine

class NoiseResonantEngine: CreakAudioEngine {
    private var engine: AVAudioEngine!
    private var srcNode: AVAudioSourceNode!
    private var isPlaying = false
    var volume: Float = 0.7
    private let state = SynthState()

    init(preset: NoisePreset = NoisePreset.all[0]) {
        let sr: Float = 44100
        let synthState = state
        let p = preset

        var bp_y: [(Float, Float)] = Array(repeating: (0, 0), count: 3)
        var pinkState: [Float] = [0, 0, 0, 0, 0, 0, 0]

        engine = AVAudioEngine()
        srcNode = AVAudioSourceNode { (_, _, frameCount, bufferList) -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(bufferList)
            let frames = Int(frameCount)

            for frame in 0..<frames {
                synthState.excitation += (synthState.targetExcitation - synthState.excitation) * 0.001
                synthState.currentVolume += (synthState.targetVolume - synthState.currentVolume) * 0.002
                let exc = synthState.excitation

                let white = Float.random(in: -1...1)
                let noiseSource: Float
                if p.usePink {
                    pinkState[0] = 0.99886 * pinkState[0] + white * 0.0555179
                    pinkState[1] = 0.99332 * pinkState[1] + white * 0.0750759
                    pinkState[2] = 0.96900 * pinkState[2] + white * 0.1538520
                    pinkState[3] = 0.86650 * pinkState[3] + white * 0.3104856
                    pinkState[4] = 0.55000 * pinkState[4] + white * 0.5329522
                    pinkState[5] = -0.7616 * pinkState[5] - white * 0.0168980
                    noiseSource = (pinkState[0] + pinkState[1] + pinkState[2]
                        + pinkState[3] + pinkState[4] + pinkState[5]
                        + pinkState[6] + white * 0.5362) * 0.11
                    pinkState[6] = white * 0.115926
                } else {
                    noiseSource = white
                }

                let noise = noiseSource * exc * 2.0

                func bpf(_ input: Float, _ freq: Float, _ q: Float, _ idx: Int) -> Float {
                    let w0 = 2.0 * Float.pi * freq / sr
                    let alpha = sin(w0) / (2.0 * q)
                    let cosw0 = cos(w0)
                    let b0 = alpha, a0 = 1.0 + alpha
                    let a1 = -2.0 * cosw0, a2 = 1.0 - alpha
                    let out = (b0/a0) * input - (a1/a0) * bp_y[idx].0 - (a2/a0) * bp_y[idx].1
                    bp_y[idx].1 = bp_y[idx].0; bp_y[idx].0 = out
                    return out
                }

                var mixed: Float = 0
                for i in 0..<3 {
                    let f = p.freqs[i] + exc * p.freqShifts[i]
                    mixed += bpf(noise, f, p.qs[i], i) * p.mix[i]
                }

                let output = tanh(mixed * p.drive) * synthState.currentVolume * 0.5

                for buffer in abl { buffer.mData!.assumingMemoryBound(to: Float.self)[frame] = output }
            }
            return noErr
        }

        engine.attach(srcNode)
        engine.connect(srcNode, to: engine.mainMixerNode,
                       format: AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!)
        do { try engine.start() } catch {}
    }

    func play(rate: Float, volume: Float) {
        self.volume = volume; state.targetExcitation = min(rate, 4.0); state.targetVolume = volume
        if !engine.isRunning { do { try engine.start() } catch { return } }; isPlaying = true
    }
    func tick() {}
    func fadeOut() {
        state.targetExcitation = 0; state.targetVolume = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.isPlaying = false }
    }
    func stop() { state.targetExcitation = 0; state.targetVolume = 0; isPlaying = false }
}
