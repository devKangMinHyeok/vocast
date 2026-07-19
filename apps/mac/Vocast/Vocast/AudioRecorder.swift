import AVFoundation
import Observation

/// Real microphone capture via AVAudioEngine. Writes the take to a WAV file and
/// publishes a live input level (for the meter and waveform) during recording.
@MainActor @Observable
final class AudioRecorder {
    var level: Double = 0      // 0...1 for the meter
    var db: Double = -60       // input level in dB
    var recording = false
    var elapsed: Double = 0

    private let engine = AVAudioEngine()
    // Written from the audio-tap thread; the tap is installed after this is set and
    // removed before it is cleared, so there is a single writer at a time.
    nonisolated(unsafe) private var file: AVAudioFile?
    private var timer: Timer?
    private var startedAt: Date?

    /// Begin capturing to `url` (.wav). Throws if the engine cannot start.
    func start(to url: URL) throws {
        let input = engine.inputNode
        let fmt = input.outputFormat(forBus: 0)
        try? FileManager.default.removeItem(at: url)
        file = try AVAudioFile(forWriting: url, settings: fmt.settings)

        input.installTap(onBus: 0, bufferSize: 2048, format: fmt) { [weak self] buffer, _ in
            self?.handle(buffer)
        }
        engine.prepare()
        try engine.start()

        startedAt = Date()
        elapsed = 0
        recording = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let s = self.startedAt else { return }
            self.elapsed = Date().timeIntervalSince(s)
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        file = nil
        timer?.invalidate(); timer = nil
        recording = false
        level = 0
        db = -60
    }

    private nonisolated func handle(_ buffer: AVAudioPCMBuffer) {
        // Write on the audio thread (the supported pattern).
        try? file?.write(from: buffer)

        guard let ch = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += ch[i] * ch[i] }
        let rms = sqrt(sum / Float(max(1, n)))
        let dbValue = 20 * log10(max(rms, 1e-7))

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.db = Double(dbValue)
            self.level = min(1, max(0, (Double(dbValue) + 60) / 60))  // -60..0 dB → 0..1
        }
    }
}
