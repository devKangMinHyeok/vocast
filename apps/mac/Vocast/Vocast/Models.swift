import SwiftUI
import Observation

// MARK: - Areas

enum Area: String, CaseIterable, Identifiable, Hashable {
    case studio, voices, denoise, tasks, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .studio: return "Studio"
        case .voices: return "Voices"
        case .denoise: return "Denoise"
        case .tasks: return "Tasks"
        case .settings: return "Settings"
        }
    }
    var subhead: String {
        switch self {
        case .studio: return "Write, render, and narrate"
        case .voices: return "Clone and manage your voice"
        case .denoise: return "Clean up audio and video"
        case .tasks: return "Running, queued, and done"
        case .settings: return ""
        }
    }
    var symbol: String {
        switch self {
        case .studio: return "sparkles"
        case .voices: return "waveform"
        case .denoise: return "waveform.path"
        case .tasks: return "clock"
        case .settings: return "gearshape"
        }
    }
    var primaryActionLabel: String {
        switch self {
        case .studio: return "New narration"
        case .voices: return "New voice"
        case .denoise: return "Import audio"
        case .tasks: return "Clear finished"
        case .settings: return ""
        }
    }
}

// MARK: - Waveform sample data

enum Waveform {
    /// Deterministic pseudo-random peaks (0...1) so a bar strip looks organic but stable.
    static func peaks(_ count: Int, seed: UInt64, floor: Double = 0.12) -> [Double] {
        var state = seed &* 2862933555777941757 &+ 3037000493
        var out: [Double] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let r = Double((state >> 33) & 0xFFFF) / 65535.0
            // A gentle envelope so the middle is livelier than the edges.
            let env = 0.55 + 0.45 * sin(Double(i) / Double(count) * .pi)
            out.append(floor + (1 - floor) * r * env)
        }
        return out
    }
}

func fmtTime(_ seconds: Double) -> String {
    let s = max(0, Int(seconds.rounded()))
    return String(format: "%d:%02d", s / 60, s % 60)
}

// MARK: - Quality scorecard

struct HeadlineMetric: Identifiable {
    let id = UUID()
    let key: String        // SIM / CER / MOS / PNS
    let value: String      // 0.94
    let unit: String       // "" / % / /5
    let name: String       // Speaker similarity
    let progress: Double   // 0...1 bar fill
    let pass: Bool
}

struct SubMetric: Identifiable {
    let id = UUID()
    let name: String
    let value: String
    let pass: Bool
}

struct Scorecard {
    var gatePassed: Bool
    var attentionReason: String?   // shown when not passed
    var headline: [HeadlineMetric]
    var sub: [SubMetric]

    static let footnote = "PNS is the prosody north-star: rhythm, emphasis, and phrasing scored against your own voice. Sub-scores run 0 to 1, higher is better. Blocks at 82 or above meet the quality bar. Measured on this Mac."

    /// Real scorecard for one narration block, from the engine's own scores.
    /// `para` carries the paragraph's PNS, `take` the winning take's sub-scores.
    /// Returns nil when the engine reported no prosody metrics for this block, so
    /// the UI can say so instead of showing invented numbers.
    static func fromNarration(para: NPara?, take: NTake?, fallbackPNS: Double?) -> Scorecard? {
        guard let pns = para?.pns ?? fallbackPNS else { return nil }
        let meetsBar = pns >= 82   // GATES["pns"] in the engine
        let headline = HeadlineMetric(
            key: "PNS", value: String(format: "%.1f", pns), unit: "/100",
            name: "Prosody north-star",
            progress: min(1, max(0, pns / 100)), pass: meetsBar)

        // Sub-scores enter the engine's selection score as -PENALTY * (1 - value),
        // so 1.0 is ideal. Only include the ones the engine actually reported.
        var sub: [SubMetric] = []
        func add(_ name: String, _ value: Double?) {
            guard let value else { return }
            sub.append(SubMetric(name: name, value: String(format: "%.2f", value),
                                 pass: value >= 0.8))
        }
        add("Ending style", take?.ending)
        add("Energy stress", take?.stress)
        add("Ending drop", take?.cliff)
        add("Word clarity", take?.swallow)

        let weakest = sub.filter { !$0.pass }.min { $0.value < $1.value }
        let reason: String?
        if !meetsBar {
            reason = "prosody below the 82 quality bar"
        } else if let w = weakest {
            reason = "\(w.name.lowercased()) below target"
        } else {
            reason = nil
        }
        return Scorecard(gatePassed: meetsBar && weakest == nil,
                         attentionReason: reason,
                         headline: [headline], sub: sub)
    }

    static let denoiseFootnote = "Speech preserved is how much of your voice energy was kept. Pause suppression is how much noise was removed from the silences. Measured on this Mac."

    /// Build a real scorecard from the denoise engine's report.
    static func fromDenoise(_ r: DenoiseReport) -> Scorecard {
        if let sim = r.sim {   // resynth mode reports voice similarity
            let pass = sim >= 0.85
            return Scorecard(
                gatePassed: pass,
                attentionReason: pass ? nil : "voice similarity below target",
                headline: [HeadlineMetric(key: "SIM", value: String(format: "%.2f", sim),
                                          unit: "", name: "Voice similarity", progress: sim, pass: pass)],
                sub: [])
        }
        let preserved = max(0, 100 - r.speechLossPct)
        let pass = r.speechLossPct < 15
        return Scorecard(
            gatePassed: pass,
            attentionReason: pass ? nil : "speech loss above target",
            headline: [
                HeadlineMetric(key: "SPEECH", value: String(format: "%.0f", preserved), unit: "%",
                               name: "Speech preserved", progress: preserved / 100, pass: pass),
                HeadlineMetric(key: "PAUSE", value: String(format: "%.0f", abs(r.pauseSuppDb)), unit: "dB",
                               name: "Pause suppression", progress: min(1, abs(r.pauseSuppDb) / 40), pass: true),
            ],
            sub: [])
    }
}

// MARK: - Studio

enum BlockStatus { case rendered, rerendering }

struct Block: Identifiable {
    let id = UUID()
    var text: String
    var status: BlockStatus
    var duration: Double     // seconds
    var version: Int
    var peaks: [Double]
    var scorecard: Scorecard?   // nil when the engine reported no metrics for this block
}

enum StudioPhase { case empty, rendering, rendered }
enum StudioViewMode { case blocks, karaoke }

@MainActor @Observable
final class StudioModel {
    var scriptText: String = SampleData.script
    var phase: StudioPhase = .empty
    var blocks: [Block] = []
    var selectedBlockID: Block.ID?
    var viewMode: StudioViewMode = .blocks

    // Transport
    var playing = false
    var currentTime: Double = 0

    // Render job progress mirror (for footer chip)
    var rendering = false
    var renderProgress: Double = 0
    var renderETA: Double = 0

    // Karaoke
    var karaokeWordIndex: Int = 0

    // Real engine render
    var renderJobID: String?
    var renderStage: String = ""
    var audioURL: URL?
    var words: [NWord] = []
    var audioDuration: Double = 0
    var transportPeaks: [Double] = []

    var charCount: Int { scriptText.count }
    var totalDuration: Double {
        audioDuration > 0 ? audioDuration : blocks.reduce(0) { $0 + $1.duration }
    }
    var selectedBlock: Block? { blocks.first { $0.id == selectedBlockID } }

    /// Real word timeline (from the engine) drives karaoke when present.
    var karaokeWords: [String] {
        if !words.isEmpty { return words.map(\.w) }
        return (blocks.first { $0.id == selectedBlockID } ?? blocks.dropFirst().first ?? blocks.first)?
            .text.split(separator: " ").map(String.init) ?? []
    }

    func resetToEmptyScript() {
        scriptText = ""
        phase = .empty
        blocks = []
        selectedBlockID = nil
        currentTime = 0
        playing = false
    }
}

// MARK: - Voices

struct VoiceVersion: Identifiable {
    let id = UUID()
    let label: String      // v3
    let note: String
    let date: String
    let sim: String
    let isCurrent: Bool
}

struct VoiceProfile: Identifiable {
    let id = UUID()
    var name: String
    var initials: String
    var sim: String
    var version: String    // v3
    var lastUsed: String
    var isDefault: Bool
    var clipCount: Int
    var totalDuration: String
    var peaks: [Double]
    var versions: [VoiceVersion]
}

enum VoicesPhase { case library, record, building, result, detail }

@MainActor @Observable
final class VoicesModel {
    var phase: VoicesPhase = .library
    var openedProfileID: String?

    // Guided recording flow
    let prompts = SampleData.prompts
    var recStep = 0
    var recording = false
    var captured: [Bool] = Array(repeating: false, count: 10)
    var clipURLs: [Int: URL] = [:]

    // Build job mirror
    var buildJobID: String?
    var buildStage: String = ""
    var buildProgress: Double = 0
    var buildETA: Double = 0
    var builtProfileID: String?

    var capturedCount: Int { captured.filter { $0 }.count }
    var capturedSeconds: Int { min(90, capturedCount * 9) }
    var currentLineCaptured: Bool { recStep < captured.count && captured[recStep] }

    func startFlow() {
        phase = .record
        recStep = 0
        recording = false
        captured = Array(repeating: false, count: 10)
        clipURLs = [:]
    }
}

// MARK: - Denoise

enum DenoiseMode: String, CaseIterable, Identifiable {
    case standard, resynth
    var id: String { rawValue }
    var title: String { self == .standard ? "Standard" : "Resynth" }
    var blurb: String {
        self == .standard
            ? "Fast filtering. Removes steady background noise and hum with light touch."
            : "Full resynthesis. Higher effort, rebuilds the voice for the cleanest result."
    }
}

enum DenoisePhase { case importEmpty, modeSelect, processing, result }
enum ABMode { case original, cleaned }

struct DenoiseReport {
    var speechLossPct: Double = 0
    var pauseSuppDb: Double = 0
    var sim: Double? = nil
    var engine: String = ""
    var isResynth: Bool = false

    var speechPreservedText: String { String(format: "%.0f%%", max(0, 100 - speechLossPct)) }
    var pauseSuppText: String { String(format: "%.0f dB", abs(pauseSuppDb)) }
    var simText: String { sim.map { String(format: "%.2f", $0) } ?? "-" }

    init() {}
    init(from r: DNReport?, mode: String, engine: String) {
        self.engine = engine
        self.isResynth = (mode == "resynth")
        self.speechLossPct = r?.speech_loss_pct ?? 0
        self.pauseSuppDb = r?.pause_supp_db ?? 0
        self.sim = r?.sim
    }
}

struct DenoiseJob: Identifiable {
    let id = UUID()
    let title: String
    let meta: String
    let timeLabel: String
}

@MainActor @Observable
final class DenoiseModel {
    var phase: DenoisePhase = .importEmpty
    var fileName: String = ""
    var importedFileURL: URL?
    var engineJobID: String?
    var mode: DenoiseMode = .standard
    var progress: Double = 0
    var eta: Double = 0
    var stageLabel: String = ""
    var playing = false
    var abMode: ABMode = .cleaned
    var report = DenoiseReport()
    // Placeholder until a run finishes; the inspector only shows it once the real
    // report arrives (phase == .result), where fromDenoise replaces it.
    var scorecard = Scorecard(gatePassed: true, attentionReason: nil, headline: [], sub: [])
    var recentJobs: [DenoiseJob] = SampleData.denoiseJobs

    var originalPeaks: [Double] = Waveform.peaks(64, seed: 42, floor: 0.35)
    var cleanedPeaks: [Double] = Waveform.peaks(64, seed: 42, floor: 0.12)
}

// MARK: - Tasks

enum JobKind { case narrationRender, denoise, voiceBuild
    var symbol: String {
        switch self {
        case .narrationRender: return "play.fill"
        case .denoise: return "waveform.path"
        case .voiceBuild: return "waveform"
        }
    }
    var typeLabel: String {
        switch self {
        case .narrationRender: return "Narration render"
        case .denoise: return "Denoise"
        case .voiceBuild: return "Voice profile build"
        }
    }
}

enum JobState { case running, queued, done }

@Observable
final class Job: Identifiable {
    let id = UUID()
    var kind: JobKind
    var title: String
    var subtitle: String
    var state: JobState
    var progress: Double
    var eta: Double
    var timeLabel: String
    // Job-detail facts
    var target: String
    var profile: String
    var throughput: String

    init(kind: JobKind, title: String, subtitle: String, state: JobState,
         progress: Double = 0, eta: Double = 0, timeLabel: String = "",
         target: String = "", profile: String = "", throughput: String = "4.1x realtime") {
        self.kind = kind; self.title = title; self.subtitle = subtitle
        self.state = state; self.progress = progress; self.eta = eta
        self.timeLabel = timeLabel; self.target = target; self.profile = profile
        self.throughput = throughput
    }
}

@MainActor @Observable
final class TasksModel {
    var jobs: [Job] = SampleData.jobs
    var selectedJobID: Job.ID?

    var running: [Job] { jobs.filter { $0.state == .running } }
    var queued: [Job] { jobs.filter { $0.state == .queued } }
    var done: [Job] { jobs.filter { $0.state == .done } }

    var runningCount: Int { running.count }

    var selectedJob: Job? {
        jobs.first { $0.id == selectedJobID } ?? running.first
    }

    func clearFinished() { jobs.removeAll { $0.state == .done } }
}

// MARK: - Settings

struct MCPAction: Identifiable {
    let id = UUID()
    let name: String
    let desc: String
    var enabled: Bool
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General", models = "Models", audio = "Audio",
         privacy = "Privacy", mcp = "MCP server", about = "About"
    var id: String { rawValue }
}

enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system = "System", light = "Light", dark = "Dark"
    var id: String { rawValue }
}

@MainActor @Observable
final class SettingsModel {
    var section: SettingsSection = .mcp

    // General
    var appearance: AppearanceChoice = .dark
    var launchAtLogin = false
    var defaultProfile = "Ava, narration"

    // Audio
    var inputDevice = "MacBook Pro Microphone"
    var exportFormat = "WAV"
    var sampleRate = "48 kHz"

    // MCP
    var mcpEnabled = true
    var mcpActions: [MCPAction] = SampleData.mcpActions
}

// MARK: - Sample content

enum SampleData {
    static let script = """
    Noise canceling headphones feel like magic, but the idea is simple. A tiny microphone listens to the sound around you, and the headphone plays back the exact opposite of that sound.

    When two opposite waves meet, they cancel out. The low hum of an engine, the drone of an air conditioner, the rumble of a train: all of it gets quieter before it ever reaches your ear.

    This works best on steady, predictable sound. Sudden noises, like a voice or a door slamming, are harder to predict, so a little always slips through.

    That is why the newest headphones do the math thousands of times a second, adjusting to the room as it changes around you.
    """

    static let prompts = [
        "The quick brown fox jumps over the lazy dog near the river.",
        "I usually record my videos late in the evening when it is quiet.",
        "Numbers like fourteen, ninety, and two thousand should sound natural.",
        "Please remember to save your project before you close the app.",
        "She sells seashells by the seashore on a bright summer morning.",
        "This is how I sound when I am calm and reading at a steady pace.",
        "Sometimes I get excited and my voice speeds up just a little.",
        "A good microphone makes a real difference in the final recording.",
        "We are almost done, just a couple more lines to go from here.",
        "Thank you for reading these lines, your voice profile is ready to build.",
    ]

    static var profiles: [VoiceProfile] {
        [
            VoiceProfile(
                name: "Ava, narration", initials: "AR", sim: "0.94", version: "v3",
                lastUsed: "used 2 hours ago", isDefault: true, clipCount: 12,
                totalDuration: "1m 48s", peaks: Waveform.peaks(48, seed: 7),
                versions: [
                    VoiceVersion(label: "v3", note: "Reinforced with 4 new clips", date: "Today", sim: "SIM 0.94", isCurrent: true),
                    VoiceVersion(label: "v2", note: "Re-recorded 3 noisy lines", date: "Yesterday", sim: "SIM 0.91", isCurrent: false),
                    VoiceVersion(label: "v1", note: "Initial 10-line profile", date: "Last week", sim: "SIM 0.87", isCurrent: false),
                ]
            ),
            VoiceProfile(
                name: "Ava, energetic", initials: "AR", sim: "0.91", version: "v2",
                lastUsed: "used yesterday", isDefault: false, clipCount: 10,
                totalDuration: "1m 32s", peaks: Waveform.peaks(48, seed: 19),
                versions: [
                    VoiceVersion(label: "v2", note: "Added excited takes", date: "Yesterday", sim: "SIM 0.91", isCurrent: true),
                    VoiceVersion(label: "v1", note: "Initial 10-line profile", date: "Last week", sim: "SIM 0.86", isCurrent: false),
                ]
            ),
            VoiceProfile(
                name: "Ava, calm read", initials: "AR", sim: "0.89", version: "v1",
                lastUsed: "used last week", isDefault: false, clipCount: 10,
                totalDuration: "1m 40s", peaks: Waveform.peaks(48, seed: 31),
                versions: [
                    VoiceVersion(label: "v1", note: "Initial 10-line profile", date: "Last week", sim: "SIM 0.89", isCurrent: true),
                ]
            ),
        ]
    }

    static var jobs: [Job] {
        [
            Job(kind: .narrationRender, title: "Narration render, block 2",
                subtitle: "Ava, narration · 4x realtime", state: .running,
                progress: 0.62, eta: 14, target: "block 2 of 4", profile: "Ava, narration",
                throughput: "4.1x realtime"),
            Job(kind: .denoise, title: "Denoise, interview-raw-take2.wav",
                subtitle: "Resynth mode", state: .queued),
            Job(kind: .voiceBuild, title: "Voice profile build, Ava narration",
                subtitle: "10 clips · SIM 0.94", state: .done, timeLabel: "2 hr ago"),
            Job(kind: .narrationRender, title: "Narration render, block 1",
                subtitle: "11 seconds · MOS 4.3", state: .done, timeLabel: "2 hr ago"),
            Job(kind: .denoise, title: "Denoise, podcast-ep12-room.wav",
                subtitle: "Resynth · -49 dB residual", state: .done, timeLabel: "Yesterday"),
        ]
    }

    static var denoiseJobs: [DenoiseJob] {
        [
            DenoiseJob(title: "podcast-ep12-room.wav", meta: "Resynth · -49 dB residual", timeLabel: "Yesterday"),
            DenoiseJob(title: "voiceover-draft.m4a", meta: "Standard · -46 dB residual", timeLabel: "3 days ago"),
        ]
    }

    static var mcpActions: [MCPAction] {
        [
            MCPAction(name: "clone_voice", desc: "Build a voice profile from clips", enabled: true),
            MCPAction(name: "narrate", desc: "Render a script with a chosen profile", enabled: true),
            MCPAction(name: "denoise", desc: "Clean an audio or video file", enabled: true),
            MCPAction(name: "list_voices", desc: "List available voice profiles", enabled: true),
        ]
    }
}
