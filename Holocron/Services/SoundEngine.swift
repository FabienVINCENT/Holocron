import AVFoundation

/// Synthesizes chiptune-style alert sounds with an AVAudioSourceNode square
/// wave — no audio files shipped, negligible memory, engine stopped when idle.
final class SoundEngine {
    enum Alert {
        case permissionRequested
        case questionAsked
        case sessionDone
        case error

        /// (frequency Hz, duration s) steps played back-to-back.
        var steps: [(Double, Double)] {
            switch self {
            case .permissionRequested:  // urgent two-tone up
                return [(660, 0.09), (0, 0.03), (990, 0.12)]
            case .questionAsked:        // curious triad
                return [(523, 0.08), (659, 0.08), (784, 0.14)]
            case .sessionDone:          // success arpeggio
                return [(523, 0.07), (659, 0.07), (784, 0.07), (1047, 0.16)]
            case .error:                // descending buzz
                return [(330, 0.12), (0, 0.02), (220, 0.18)]
            }
        }
    }

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private let sampleRate: Double = 44_100
    private let stateQueue = DispatchQueue(label: "fr.fabien-vincent.holocron.sound")
    // Playback state, guarded by stateQueue (the render thread reads it).
    private var script: [(Double, Double)] = []
    private var stepIndex = 0
    private var samplesIntoStep = 0
    private var playing = false
    private var stopWorkItem: DispatchWorkItem?

    var volume: Double = 0.5

    func play(_ alert: Alert) {
        let steps = alert.steps
        let totalDuration = steps.reduce(0) { $0 + $1.1 }
        stateQueue.sync {
            script = steps
            stepIndex = 0
            samplesIntoStep = 0
            playing = true
        }
        startEngineIfNeeded()

        // Stop the engine shortly after the jingle so idle CPU stays at zero.
        stopWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.stopEngine() }
        stopWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration + 0.3, execute: work)
    }

    private func startEngineIfNeeded() {
        if sourceNode == nil {
            let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList in
                self?.render(frameCount: frameCount, audioBufferList: audioBufferList) ?? noErr
            }
            engine.attach(node)
            let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            sourceNode = node
        }
        engine.mainMixerNode.outputVolume = Float(max(0, min(1, volume)))
        if !engine.isRunning {
            try? engine.start()
        }
    }

    private func stopEngine() {
        engine.stop()
    }

    private func render(frameCount: AVAudioFrameCount, audioBufferList: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        guard let out = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }

        var localScript: [(Double, Double)] = []
        var localStep = 0
        var localSamples = 0
        var localPlaying = false
        stateQueue.sync {
            localScript = script
            localStep = stepIndex
            localSamples = samplesIntoStep
            localPlaying = playing
        }

        for frame in 0..<Int(frameCount) {
            var sample: Float = 0
            if localPlaying, localStep < localScript.count {
                let (frequency, duration) = localScript[localStep]
                let stepSampleCount = Int(duration * sampleRate)
                if frequency > 0 {
                    // Square wave with a short decay envelope: the 8-bit voice.
                    let phase = Double(localSamples) * frequency / sampleRate
                    let square: Float = phase.truncatingRemainder(dividingBy: 1.0) < 0.5 ? 1 : -1
                    let progress = Float(localSamples) / Float(max(stepSampleCount, 1))
                    let envelope = 1.0 - progress * 0.6
                    sample = square * 0.22 * envelope
                }
                localSamples += 1
                if localSamples >= stepSampleCount {
                    localSamples = 0
                    localStep += 1
                    if localStep >= localScript.count { localPlaying = false }
                }
            }
            out[frame] = sample
        }

        stateQueue.sync {
            stepIndex = localStep
            samplesIntoStep = localSamples
            playing = localPlaying
        }
        return noErr
    }
}
