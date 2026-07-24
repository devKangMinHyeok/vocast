import SwiftUI
import Observation

// MARK: - Areas

enum Area: String, CaseIterable, Identifiable, Hashable {
    case studio, voices, denoise, tasks, settings
    var id: String { rawValue }

    /// Area names resolve through the string table so the sidebar and the top bar
    /// follow the interface language like everything else.
    func title(_ st: Strings) -> String {
        switch self {
        case .studio: return st["nStudio"]
        case .voices: return st["nVoices"]
        case .denoise: return st["nDenoise"]
        case .tasks: return st["nTasks"]
        case .settings: return st["settings"]
        }
    }
    func subhead(_ st: Strings) -> String {
        switch self {
        case .studio: return st["subStudio"]
        case .voices: return st["subVoices"]
        case .denoise: return st["subDenoise"]
        case .tasks: return st["subTasks"]
        case .settings: return ""
        }
    }
    func primaryActionLabel(_ st: Strings) -> String {
        switch self {
        case .studio: return st["newNarration"]
        case .voices: return st["newVoice"]
        case .denoise: return st["importAudio"]
        case .tasks: return st["clearFinished"]
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

/// ETA label for a running job. Remaining time floors near zero, so a job that
/// outruns its estimate would read "ETA 0:01" indefinitely. Past that point say
/// it is wrapping up instead of showing a number that stopped moving.
func etaLabel(_ seconds: Double, _ s: Strings) -> String {
    seconds <= 2 ? s["etaFinishing"] : "ETA \(fmtTime(seconds))"
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
    /// String-table key for the localized name; falls back to `name` when empty.
    var key: String = ""
}

/// Why a block did not pass its gate, stored as a code rather than a sentence so the
/// banner resolves it in the current interface language at render time instead of
/// baking English into the model when the scorecard is built.
enum AttentionReason {
    case belowBar
    case subWeak(metricKey: String, metricName: String)
    case simLow
    case speechLoss
}

struct Scorecard {
    var gatePassed: Bool
    var attention: AttentionReason?   // set when not passed
    var headline: [HeadlineMetric]
    var sub: [SubMetric]

    /// The "needs attention" reason in the interface language, or nil when passed.
    func attentionText(_ s: Strings) -> String? {
        switch attention {
        case .belowBar: return s["scReasonBelowBar"]
        case .subWeak(let key, let name):
            let metric = (key.isEmpty ? name : s[key]).lowercased()
            return s.f("scReasonSubWeak", ["metric": metric])
        case .simLow: return s["scReasonSimLow"]
        case .speechLoss: return s["scReasonSpeechLoss"]
        case nil: return nil
        }
    }

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
        func add(_ key: String, _ name: String, _ value: Double?) {
            guard let value else { return }
            sub.append(SubMetric(name: name, value: String(format: "%.2f", value),
                                 pass: value >= 0.8, key: key))
        }
        add("scSubEnding", "Ending style", take?.ending)
        add("scSubStress", "Energy stress", take?.stress)
        add("scSubDrop", "Ending drop", take?.cliff)
        add("scSubClarity", "Word clarity", take?.swallow)

        // Compare the numeric score, not the formatted string (lexicographic order
        // breaks for negative or >= 10 values). value round-trips via Double exactly.
        let weakest = sub.filter { !$0.pass }
            .min { (Double($0.value) ?? 0) < (Double($1.value) ?? 0) }
        let attention: AttentionReason?
        if !meetsBar {
            attention = .belowBar
        } else if let w = weakest {
            attention = .subWeak(metricKey: w.key, metricName: w.name)
        } else {
            attention = nil
        }
        return Scorecard(gatePassed: meetsBar && weakest == nil,
                         attention: attention,
                         headline: [headline], sub: sub)
    }

    /// Build a real scorecard from the denoise engine's report.
    static func fromDenoise(_ r: DenoiseReport) -> Scorecard {
        if let sim = r.sim {   // resynth mode reports voice similarity
            let pass = sim >= 0.85
            return Scorecard(
                gatePassed: pass,
                attention: pass ? nil : .simLow,
                headline: [HeadlineMetric(key: "SIM", value: String(format: "%.2f", sim),
                                          unit: "", name: "Voice similarity", progress: sim, pass: pass)],
                sub: [])
        }
        let preserved = max(0, 100 - r.speechLossPct)
        let pass = r.speechLossPct < 15
        return Scorecard(
            gatePassed: pass,
            attention: pass ? nil : .speechLoss,
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
    /// Absolute start (seconds) of this block in the composed narration, taken from
    /// the paragraph's `start`. This includes the silent gaps the engine inserts
    /// between paragraphs, so it is the real seek target. Summing durations would
    /// drop those gaps and drift the playhead early.
    var start: Double = 0
    var version: Int
    var peaks: [Double]
    var scorecard: Scorecard?   // nil when the engine reported no metrics for this block
}

enum StudioPhase { case empty, rendering, rendered }
enum StudioViewMode { case blocks, karaoke }

/// Which of the three Studio surfaces is showing. The library is the default: it
/// lists saved narrations; the composer writes and renders a new one; the editor
/// opens a saved narration for playback, block edits, and export.
enum StudioNav { case library, composer, editor }

/// What an export covers. From a library row it is always the whole narration;
/// only the open editor can narrow it to the currently selected blocks.
enum ExportScope { case whole, selected }

/// What a rename dialog is renaming: a specific saved narration, or the one open
/// in the editor.
enum RenameTarget: Equatable { case project(String), editor }

// MARK: - Narration library

/// One saved narration in the library. Backed by the engine's persisted history:
/// `id` is the head of a regeneration chain (the newest job that holds the current
/// audio), and `chainIDs` is every history id in that chain so deleting the project
/// removes all of them. Everything here is derived from the history document, so it
/// survives an app restart without the app keeping its own copy.
struct NarrationProject: Identifiable {
    let id: String            // head job id (current audio lives here)
    var title: String
    var voiceID: String?      // profile_id at render time; nil when made from an upload
    var voiceName: String
    var duration: Double
    var blockCount: Int
    var created: String       // engine timestamp, e.g. "2026-07-20 08:26"
    var chainIDs: [String]    // all history ids in this project's regen chain
    var version: Int

    /// A stable dot color per voice, so rows made with the same voice read together.
    /// Missing voices are resolved to stone by the row, not here.
    var voiceColor: Color {
        let palette: [Color] = [Palette.accent, Palette.accentBlue, Palette.good]
        guard let v = voiceID else { return Palette.stone }
        // Reduce first, then abs: abs(v.hashValue) alone traps on Int.min.
        return palette[abs(v.hashValue % palette.count)]
    }
}

@MainActor @Observable
final class StudioModel {
    var scriptText: String = StarterContent.script
    var phase: StudioPhase = .empty
    var blocks: [Block] = []
    var selectedBlockID: Block.ID?
    var viewMode: StudioViewMode = .blocks

    // MARK: Library (default surface)
    /// Which of the three surfaces is showing. Studio opens on the library.
    var nav: StudioNav = .library
    /// Saved narrations, newest first, already collapsed to one row per project.
    var projects: [NarrationProject] = []
    /// The saved narration open in the editor (the head job id).
    var activeProjectID: String?
    var libSearch: String = ""
    var libLoading = false
    /// Real per-narration waveform thumbnails, keyed by head job id. Loaded lazily
    /// so the list draws immediately and fills its waveforms as they decode.
    var libPeaks: [String: [Double]] = [:]

    // Library overlays / row menu
    var openRowMenu: String?          // id of the row whose ⋯ menu is open
    var renameTarget: RenameTarget?   // rename dialog target
    var renameValue: String = ""
    var exportOpen = false
    var exportSource: String?         // head job id being exported
    var exportScope: ExportScope = .whole
    var deleteConfirm: String?        // project id awaiting delete confirmation

    /// Rows filtered by the search box (title substring, case-insensitive). The
    /// engine already returns newest-first, which is the only sort for now.
    var filteredProjects: [NarrationProject] {
        let q = libSearch.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return projects }
        return projects.filter { $0.title.lowercased().contains(q) }
    }
    /// Whether the voice-picker dropdown in the sub-toolbar is open, and which
    /// row the keyboard has highlighted while it is.
    var voiceMenuOpen = false
    var voiceMenuHighlight = 0

    // Transport
    var playing = false
    var currentTime: Double = 0
    /// The block whose play button started the current playback, so that block's
    /// button shows a pause glyph. nil when the bottom transport drives playback.
    var playingBlockID: Block.ID?

    /// Start offset (seconds) of a block in the composed narration. Uses the block's
    /// absolute `start` (which includes inter-paragraph gaps) so a "play from here"
    /// seek lands on the block's real audio, not summed-duration drift.
    func startOffset(of id: Block.ID) -> Double {
        blocks.first(where: { $0.id == id })?.start ?? 0
    }

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

    /// The saved narration currently open in the editor, when it is in the library.
    var activeProject: NarrationProject? {
        activeProjectID.flatMap { id in projects.first { $0.id == id } }
    }

    /// Editor title: the saved project's title, or the script's first line for a
    /// freshly rendered narration not yet reflected in the library list.
    var editorTitle: String {
        if let p = activeProject { return p.title }
        let firstLine = scriptText.split(separator: "\n").first.map(String.init) ?? ""
        return firstLine.trimmingCharacters(in: .whitespaces)
    }

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

/// `pickLang` is a step of its own because a voice's language is the one thing
/// that cannot be changed later. Choosing it inside the recording screen would
/// invite starting a take first and deciding after, which the model forbids.
enum VoicesPhase { case library, pickLang, record, building, result, detail }

@MainActor @Observable
final class VoicesModel {
    var phase: VoicesPhase = .library
    var openedProfileID: String?

    // Guided recording flow
    /// Guided script from the engine (/api/guide), with its per-line coaching.
    var guide: [GuideLine] = []
    /// Language the voice being created will speak. Chosen in the pickLang step,
    /// then locked: the guided lines and the transcription that trains the clone
    /// are both written for it, so it cannot change once a take exists.
    var lang: VoiceLanguage = .ko
    /// True from the moment recording begins. The pick step is the only window.
    var langLocked = false
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

    /// Open the language pick. Recording starts only after a language is chosen.
    func startFlow(suggesting lang: VoiceLanguage) {
        phase = .pickLang
        self.lang = lang
        langLocked = false
        resetTakes()
    }

    /// Leave the pick step and begin recording. The language is now fixed.
    func beginRecording() {
        phase = .record
        langLocked = true
        resetTakes()
    }

    /// Reinforcing an existing profile reuses its language and skips the pick.
    func startReinforcing(lang: VoiceLanguage) {
        phase = .record
        self.lang = lang
        langLocked = true
        resetTakes()
    }

    private func resetTakes() {
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
    func title(_ s: Strings) -> String { s[self == .standard ? "dnModeStandard" : "dnModeResynth"] }
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
    var scorecard = Scorecard(gatePassed: true, attention: nil, headline: [], sub: [])
    var recentJobs: [DenoiseJob] = []      // filled from /api/dnjobs

    // Filled from the real audio once a cleanup finishes; empty until then.
    var originalPeaks: [Double] = []
    var cleanedPeaks: [Double] = []
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
    func typeLabel(_ s: Strings) -> String {
        switch self {
        case .narrationRender: return s["jobKindNarration"]
        case .denoise: return s["jobKindDenoise"]
        case .voiceBuild: return s["jobKindVoiceBuild"]
        }
    }
}

enum JobState { case running, queued, done, failed }

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
    /// Human-readable current stage (e.g. "Generating speech"). Shown by the
    /// top-bar indicator once the percentage pins at its cap, so a slow job reads
    /// as working rather than frozen.
    var stage: String
    // Job-detail facts
    var target: String
    var profile: String
    var throughput: String

    init(kind: JobKind, title: String, subtitle: String, state: JobState,
         progress: Double = 0, eta: Double = 0, timeLabel: String = "", stage: String = "",
         target: String = "", profile: String = "", throughput: String = "4.1x realtime") {
        self.kind = kind; self.title = title; self.subtitle = subtitle
        self.state = state; self.progress = progress; self.eta = eta
        self.timeLabel = timeLabel; self.stage = stage; self.target = target
        self.profile = profile; self.throughput = throughput
    }
}

@MainActor @Observable
final class TasksModel {
    var jobs: [Job] = []                   // filled from /api/tasks
    var selectedJobID: Job.ID?

    var running: [Job] { jobs.filter { $0.state == .running } }
    var queued: [Job] { jobs.filter { $0.state == .queued } }
    var done: [Job] { jobs.filter { $0.state == .done } }
    var failed: [Job] { jobs.filter { $0.state == .failed } }

    var runningCount: Int { running.count }

    var selectedJob: Job? {
        jobs.first { $0.id == selectedJobID } ?? running.first
    }

    // "Finished" covers both terminal states, so clearing sweeps failures too.
    func clearFinished() { jobs.removeAll { $0.state == .done || $0.state == .failed } }
}

// MARK: - Settings

/// A tool the local MCP server exposes, read from the engine. There is no
/// per-tool switch: the MCP server is either on or off, so the row reflects
/// the server state rather than a per-action flag the app cannot honour.
struct MCPAction: Identifiable {
    let id = UUID()
    let name: String
    let desc: String
}

enum SettingsSection: String, CaseIterable, Identifiable {
    // Language sits second, right after General: it is the setting a user is most
    // likely to look for first, and the one that changes everything else on screen.
    case general = "General", language = "Language", models = "Models", audio = "Audio",
         privacy = "Privacy", mcp = "MCP server", about = "About"
    var id: String { rawValue }

    /// The section name in the interface language. Values not in the spec's string
    /// table (Privacy) keep their English label.
    func label(_ st: Strings) -> String {
        switch self {
        case .general:  return st["setGeneral"]
        case .language: return st["setLanguage"]
        case .models:   return st["setModels"]
        case .audio:    return st["setAudio"]
        case .privacy:  return st["setPrivacy"]
        case .mcp:      return st["setMcp"]
        case .about:    return st["setAbout"]
        }
    }
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
    var mcpActions: [MCPAction] = []       // filled from /api/mcp/tools
}

// MARK: - Sample content

/// Example script the Studio starts with, so the first screen is not blank.
/// This is placeholder copy the user is expected to replace, not data.
enum StarterContent {
    static let script = """
    Noise canceling headphones feel like magic, but the idea is simple. A tiny microphone listens to the sound around you, and the headphone plays back the exact opposite of that sound.

    When two opposite waves meet, they cancel out. The low hum of an engine, the drone of an air conditioner, the rumble of a train: all of it gets quieter before it ever reaches your ear.

    This works best on steady, predictable sound. Sudden noises, like a voice or a door slamming, are harder to predict, so a little always slips through.

    That is why the newest headphones do the math thousands of times a second, adjusting to the room as it changes around you.
    """
}
