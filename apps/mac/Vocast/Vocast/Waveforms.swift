import Foundation
import AVFoundation

/// Computes real waveform peaks by decoding an audio file (local or from the engine's
/// preview URL). Returns `count` normalized peaks (0...1). Used to replace the stylized
/// placeholder bars with the actual audio envelope.
enum RealWaveform {

    /// Decode `url` and reduce it to `count` peak values. Works for local files and
    /// http(s) URLs (the engine's A/B and composed-audio previews).
    static func peaks(from url: URL, count: Int = 64) async -> [Double]? {
        // For remote URLs, download to a temp file first (AVAudioFile needs a local file).
        var localURL = url
        var temp: URL?
        if url.scheme == "http" || url.scheme == "https" {
            guard let downloaded = try? await download(url) else { return nil }
            localURL = downloaded
            temp = downloaded
        }
        defer { if let temp { try? FileManager.default.removeItem(at: temp) } }

        guard let peaks = decode(localURL, count: count) else { return nil }
        return peaks
    }

    private static func download(_ url: URL) async throws -> URL {
        let (tmp, _) = try await URLSession.shared.download(from: url)
        // Give it an extension AVAudioFile can sniff (m4a for the previews).
        let dest = tmp.appendingPathExtension("m4a")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }

    private static func decode(_ url: URL, count: Int) -> [Double]? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        do { try file.read(into: buffer) } catch { return nil }
        guard let ch = buffer.floatChannelData?[0] else { return nil }

        let n = Int(buffer.frameLength)
        guard n > 0 else { return nil }
        let bucket = max(1, n / count)
        var peaks: [Double] = []
        peaks.reserveCapacity(count)
        var maxPeak: Double = 0.0001
        var i = 0
        while i < n {
            let end = min(i + bucket, n)
            var localMax: Float = 0
            var j = i
            while j < end { localMax = max(localMax, abs(ch[j])); j += 1 }
            let v = Double(localMax)
            maxPeak = max(maxPeak, v)
            peaks.append(v)
            i += bucket
        }
        // Normalize to 0...1 with a small floor so silence still shows a hairline.
        return peaks.map { min(1, 0.06 + 0.94 * ($0 / maxPeak)) }
    }
}
