import SwiftUI
import AppKit
import Observation
import UserNotifications
import AVFoundation

// MARK: - Toast

struct Toast: Identifiable, Equatable {
    let id = UUID()
    var message: String
}

// MARK: - Onboarding

enum OnboardingStep: Int, CaseIterable { case welcome, download, mic, ready }

@MainActor @Observable
final class OnboardingModel {
    var step: OnboardingStep = .welcome
    var tier: String = "balanced"   // balanced | advanced
}

// MARK: - AppModel (root) + job engine
//
// One @Observable graph injected into the environment. The job methods here are
// the "job engine": they run heavy work as async-timer jobs that publish a live
// progress + ETA, post a completion notification, and raise an in-app toast.

@MainActor @Observable
final class AppModel {
    // Sub-models
    let studio = StudioModel()
    let voices = VoicesModel()
    let denoise = DenoiseModel()
    let tasks = TasksModel()
    let settings = SettingsModel()
    let onboarding = OnboardingModel()

    // Local Python engine (HTTP sidecar)
    let engine = EngineClient()
    let sidecar = Sidecar()
    var engineReady = false
    var engineStarting = true
    var resynthAvailable = false
    var backendProfiles: [EngineProfile] = []
    var selectedProfileID: String?
    var modelStatus: ModelStatus?
    private var modelPollTask: Task<Void, Never>?
    private var dnPollTask: Task<Void, Never>?
    private var dnPlayer: AVPlayer?
    private var renderTask: Task<Void, Never>?
    private var regenTask: Task<Void, Never>?
    private var studioPlayer: AVPlayer?
    private var studioTimeObserver: Any?

    init() {
        // Launch the local engine as a child process and point the client at it.
        if let url = sidecar.start() { engine.base = url }
        Task { await checkEngine() }

        // Terminate the sidecar when the app quits.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.sidecar.stop()
        }

        // Dev/test hook: preload a denoise file so the pipeline can be exercised
        // without driving the native open panel. Only active when the env var is set.
        if let f = ProcessInfo.processInfo.environment["VOCAST_TEST_FILE"], !f.isEmpty {
            let url = URL(fileURLWithPath: f)
            denoise.importedFileURL = url
            denoise.fileName = url.lastPathComponent
            denoise.phase = .modeSelect
            area = .denoise
        }
    }

    func checkEngine() async {
        engineStarting = true
        // Spawning Python + importing the engine takes a few seconds.
        if let h = await engine.waitUntilReady(timeout: 40) {
            engineReady = true
            resynthAvailable = h.resynth
            backendProfiles = (try? await engine.listProfiles()) ?? []
            if selectedProfileID == nil { selectedProfileID = backendProfiles.first?.id }
            modelStatus = try? await engine.modelStatus()
        } else {
            engineReady = false
            resynthAvailable = false
        }
        engineStarting = false
    }

    // MARK: Model download (first run)

    func refreshModelStatus() async {
        modelStatus = try? await engine.modelStatus()
    }

    func downloadModels(tier: String) {
        modelPollTask?.cancel()
        modelPollTask = Task { @MainActor in
            do {
                try await engine.startModelDownload(tier: tier)
            } catch {
                notify("Could not start the model download. Is the engine running?")
                return
            }
            while !Task.isCancelled {
                if let s = try? await engine.modelStatus() {
                    modelStatus = s
                    if s.ready { return }
                    if let e = s.error, !e.isEmpty { notify("Download error: \(e)"); return }
                }
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
        }
    }

    // Shell UI state
    var area: Area = .studio
    var inspectorVisible = true
    var search = ""
    var firstRunComplete = ProcessInfo.processInfo.environment["VOCAST_SKIP_ONBOARDING"] == "1"
    var offline = true
    var toast: Toast?

    private var notifAuthAsked = false

    // MARK: Notifications + toast

    private func requestNotifAuthIfNeeded() {
        guard !notifAuthAsked else { return }
        notifAuthAsked = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func complete(_ message: String) {
        // In-app toast
        let t = Toast(message: message)
        toast = t
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_200_000_000)
            if self.toast?.id == t.id { withAnimation(Motion.calm) { self.toast = nil } }
        }
        // System notification
        if ProcessInfo.processInfo.environment["VOCAST_QUIET"] == "1" { return }
        requestNotifAuthIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = "Vocast"
        content.body = message
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: Generic async progress driver

    @discardableResult
    private func drive(_ duration: Double, eta: Double,
                       tick: @escaping (_ progress: Double, _ eta: Double) -> Void,
                       done: @escaping () -> Void) -> Task<Void, Never> {
        Task { @MainActor in
            let steps = max(1, Int(duration / 0.08))
            for i in 0...steps {
                if Task.isCancelled { return }
                let p = Double(i) / Double(steps)
                tick(p, eta * (1 - p))
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
            done()
        }
    }

    // MARK: Studio render

    func renderNarration() {
        guard !studio.scriptText.isEmpty, studio.phase != .rendering else { return }
        studio.phase = .rendering
        studio.rendering = true
        studio.renderStage = "Preparing"
        stopStudioPlayback()
        let text = studio.scriptText
        let start = Date()

        let job = Job(kind: .narrationRender, title: "Narration render",
                      subtitle: "\(currentProfileName) · TTS on this Mac", state: .running,
                      target: "narration", profile: currentProfileName)
        tasks.jobs.insert(job, at: 0)

        renderTask?.cancel()
        renderTask = Task { @MainActor in
            do {
                let jid = try await engine.createNarration(text: text, profileID: selectedProfileID)
                studio.renderJobID = jid
                while !Task.isCancelled {
                    let st = try await engine.narrationStatus(jid)
                    let eta = st.eta_sec ?? 30
                    let elapsed = Date().timeIntervalSince(start)
                    studio.renderStage = narrationStageText(st.stage)
                    // Prefer real take progress ("take n/m") over the time estimate.
                    if let frac = takeFraction(st.stage) {
                        studio.renderProgress = 0.05 + frac * 0.9
                    } else {
                        studio.renderProgress = min(0.9, elapsed / max(eta, 1))
                    }
                    studio.renderETA = max(1, eta - elapsed)
                    job.progress = studio.renderProgress
                    job.eta = studio.renderETA

                    if st.status == "done" {
                        studio.words = st.words ?? []
                        studio.audioDuration = narrationDuration(st)
                        studio.audioURL = engine.narrationAudioURL(jid)
                        // Real waveform from the composed audio, sliced per block.
                        let full = await RealWaveform.peaks(from: engine.narrationAudioURL(jid), count: 240) ?? []
                        studio.transportPeaks = full.isEmpty ? Waveform.peaks(90, seed: 500) : full
                        studio.blocks = makeRealBlocks(st, text: text, fullPeaks: full)
                        studio.selectedBlockID = studio.blocks.first?.id
                        studio.karaokeWordIndex = 0
                        studio.currentTime = 0
                        studio.phase = .rendered
                        studio.rendering = false
                        job.state = .done
                        job.timeLabel = "just now"
                        complete("Narration is ready.")
                        return
                    }
                    if st.status == "error" {
                        studio.phase = .empty
                        studio.rendering = false
                        tasks.jobs.removeAll { $0.id == job.id }
                        notify("Narration failed: \(st.error ?? "unknown error")")
                        return
                    }
                    try await Task.sleep(nanoseconds: 700_000_000)
                }
            } catch let e as EngineError {
                studio.phase = .empty; studio.rendering = false
                tasks.jobs.removeAll { $0.id == job.id }
                notify(engineMessage(e))
            } catch {
                studio.phase = .empty; studio.rendering = false
                tasks.jobs.removeAll { $0.id == job.id }
                notify("Could not reach the local engine. Is it running?")
            }
        }
    }

    /// Total narration length. The word timeline is the finest source, but it can come
    /// back short or empty when transcription struggles, so fall back to the paragraph
    /// boundaries the engine composed the audio from.
    private func narrationDuration(_ st: NJob) -> Double {
        let fromParas = st.paragraphs?.compactMap { $0.end }.max() ?? 0
        let fromWords = st.words?.last?.e ?? 0
        return max(fromParas, fromWords)
    }

    private func narrationStageText(_ stage: String?) -> String {
        switch stage {
        case "reference": return "Preparing the voice"
        case "takes": return "Generating speech"
        case "post": return "Composing"
        case "done": return "Done"
        default:
            if let s = stage, s.hasPrefix("take ") { return "Generating speech (\(s.dropFirst(5)))" }
            return "Generating"
        }
    }

    private func takeFraction(_ stage: String?) -> Double? {
        guard let s = stage, s.hasPrefix("take ") else { return nil }
        let parts = s.dropFirst(5).split(separator: "/")
        guard parts.count == 2, let n = Double(parts[0]), let m = Double(parts[1]), m > 0 else { return nil }
        return n / m
    }

    private func makeRealBlocks(_ st: NJob, text: String, fullPeaks: [Double]) -> [Block] {
        let metas = st.paragraphs ?? []
        let paras: [String]
        if !metas.isEmpty {
            paras = metas.map { $0.text }
        } else {
            paras = text.components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        let total = st.words?.last?.e ?? 0
        let count = max(1, paras.count)
        let per = total / Double(count)
        return paras.enumerated().map { i, t in
            let meta = i < metas.count ? metas[i] : nil
            // Real paragraph boundaries when the engine reported them.
            let span: (Double, Double)? = {
                guard let s = meta?.start, let e = meta?.end, e > s else { return nil }
                return (s, e)
            }()
            let duration = span.map { $0.1 - $0.0 } ?? (per > 0 ? per : Double(6 + i))

            // Slice the real composed waveform for this block's time range.
            let slice: [Double]
            if !fullPeaks.isEmpty {
                let a: Int, b: Int
                if let (s, e) = span, total > 0 {
                    a = min(fullPeaks.count - 1, max(0, Int(Double(fullPeaks.count) * s / total)))
                    b = min(fullPeaks.count, max(a + 1, Int(Double(fullPeaks.count) * e / total)))
                } else {
                    a = fullPeaks.count * i / count
                    b = min(fullPeaks.count, max(a + 1, fullPeaks.count * (i + 1) / count))
                }
                slice = Array(fullPeaks[a..<b])
            } else {
                slice = Waveform.peaks(34, seed: UInt64(100 + i * 13))
            }
            return Block(text: t, status: .rendered,
                         duration: duration,
                         version: 1, peaks: slice,
                         scorecard: .fromNarration(para: meta,
                                                   take: bestTake(st.takes, paragraph: i,
                                                                  paragraphPNS: meta?.pns ?? st.pns),
                                                   fallbackPNS: st.pns))
        }
    }

    /// The take the engine kept for a paragraph. Multi-paragraph jobs tag takes with
    /// a 1-based `para`; single-paragraph jobs leave it out.
    ///
    /// Note the `best` flag marks "best so far" while scoring, so several takes carry
    /// it and the first one is not the winner. The paragraph's own PNS is the winning
    /// take's PNS, so match on that; otherwise mirror the engine's rule (highest
    /// selection score among takes within PNS_DOMINANCE of the best PNS).
    private func bestTake(_ takes: [NTake]?, paragraph i: Int, paragraphPNS: Double?) -> NTake? {
        guard let takes, !takes.isEmpty else { return nil }
        let tagged = takes.contains { $0.para != nil }
        let pool = tagged ? takes.filter { $0.para == i + 1 } : takes
        guard !pool.isEmpty else { return nil }

        if let target = paragraphPNS,
           let match = pool.first(where: { abs(($0.pns ?? .infinity) - target) < 0.05 }) {
            return match
        }
        let dominance = 8.0   // PNS_DOMINANCE in the engine
        let maxPNS = pool.compactMap { $0.pns }.max() ?? 0
        let contenders = pool.filter { ($0.pns ?? 0) >= maxPNS - dominance }
        return (contenders.isEmpty ? pool : contenders)
            .max { ($0.sel ?? -.greatestFiniteMagnitude) < ($1.sel ?? -.greatestFiniteMagnitude) }
    }

    // MARK: Studio transport playback (real composed audio)

    func studioPlayToggle() {
        guard let url = studio.audioURL else { return }
        if studio.playing {
            studioPlayer?.pause()
            studio.playing = false
            return
        }
        if studioPlayer == nil {
            let player = AVPlayer(url: url)
            studioTimeObserver = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.08, preferredTimescale: 600), queue: .main
            ) { [weak self] time in
                guard let self else { return }
                let sec = time.seconds
                self.studio.currentTime = sec
                if let idx = self.studio.words.lastIndex(where: { $0.s <= sec }) {
                    self.studio.karaokeWordIndex = idx
                }
            }
            studioPlayer = player
        }
        studioPlayer?.play()
        studio.playing = true
    }

    func stopStudioPlayback() {
        studioPlayer?.pause()
        if let obs = studioTimeObserver { studioPlayer?.removeTimeObserver(obs); studioTimeObserver = nil }
        studioPlayer = nil
        studio.playing = false
    }

    func studioSeek(to sec: Double) {
        studio.currentTime = sec
        studioPlayer?.seek(to: CMTime(seconds: sec, preferredTimescale: 600))
        if let idx = studio.words.lastIndex(where: { $0.s <= sec }) { studio.karaokeWordIndex = idx }
    }

    func regenerateBlock(_ id: Block.ID) {
        guard let idx = studio.blocks.firstIndex(where: { $0.id == id }) else { return }
        guard let parentJob = studio.renderJobID else {
            notify("This narration cannot regenerate single blocks. Render it again first.")
            return
        }
        // Re-render just this paragraph on the engine; it recomposes the full audio.
        studio.blocks[idx].status = .rerendering
        stopStudioPlayback()
        let text = studio.scriptText
        let versions = studio.blocks.map { $0.version }   // preserve per-block versions
        let start = Date()

        let job = Job(kind: .narrationRender, title: "Narration render, block \(idx + 1)",
                      subtitle: "\(currentProfileName) · TTS on this Mac", state: .running,
                      target: "block \(idx + 1) of \(studio.blocks.count)", profile: currentProfileName)
        tasks.jobs.insert(job, at: 0)

        regenTask?.cancel()
        regenTask = Task { @MainActor in
            do {
                let jid = try await engine.regenerateParagraph(jobID: parentJob, paragraph: idx)
                while !Task.isCancelled {
                    let st = try await engine.narrationStatus(jid)
                    let eta = st.eta_sec ?? 12
                    let elapsed = Date().timeIntervalSince(start)
                    if let frac = takeFraction(st.stage) {
                        job.progress = 0.05 + frac * 0.9
                    } else {
                        job.progress = min(0.9, elapsed / max(eta, 1))
                    }
                    job.eta = max(1, eta - elapsed)

                    if st.status == "done" {
                        // The regen job is now the current narration (recomposed audio).
                        studio.renderJobID = jid
                        studio.words = st.words ?? []
                        studio.audioDuration = narrationDuration(st)
                        studio.audioURL = engine.narrationAudioURL(jid)
                        let full = await RealWaveform.peaks(from: engine.narrationAudioURL(jid), count: 240) ?? []
                        studio.transportPeaks = full.isEmpty ? Waveform.peaks(90, seed: 500) : full
                        var blocks = makeRealBlocks(st, text: text, fullPeaks: full)
                        // Keep prior versions, bump the one we just regenerated.
                        for i in blocks.indices where i < versions.count { blocks[i].version = versions[i] }
                        if idx < blocks.count { blocks[idx].version += 1 }
                        studio.blocks = blocks
                        studio.selectedBlockID = idx < blocks.count ? blocks[idx].id : blocks.first?.id
                        studio.currentTime = 0
                        studio.karaokeWordIndex = 0
                        job.state = .done
                        job.timeLabel = "just now"
                        complete("Block \(idx + 1) re-rendered.")
                        return
                    }
                    if st.status == "error" {
                        if let i = studio.blocks.firstIndex(where: { $0.id == id }) {
                            studio.blocks[i].status = .rendered
                        }
                        tasks.jobs.removeAll { $0.id == job.id }
                        notify("Block \(idx + 1) could not be re-rendered: \(st.error ?? "unknown error")")
                        return
                    }
                    try await Task.sleep(nanoseconds: 700_000_000)
                }
            } catch let e as EngineError {
                if let i = studio.blocks.firstIndex(where: { $0.id == id }) { studio.blocks[i].status = .rendered }
                tasks.jobs.removeAll { $0.id == job.id }
                notify(engineMessage(e))
            } catch {
                if let i = studio.blocks.firstIndex(where: { $0.id == id }) { studio.blocks[i].status = .rendered }
                tasks.jobs.removeAll { $0.id == job.id }
                notify("Could not reach the local engine. Is it running?")
            }
        }
    }

    // MARK: Guided recording (real microphone capture)

    let recorder = AudioRecorder()
    private var recSessionDir: URL?
    private var buildTask: Task<Void, Never>?

    private func recordingDir() -> URL {
        if let d = recSessionDir { return d }
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("vocast-rec-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        recSessionDir = d
        return d
    }

    func startRecordingLine() {
        let url = recordingDir().appendingPathComponent(String(format: "%02d.wav", voices.recStep))
        do {
            try recorder.start(to: url)
            voices.recording = true
            voices.clipURLs[voices.recStep] = url
        } catch {
            notify("Could not start the microphone. Allow microphone access and try again.")
        }
    }

    func stopRecordingLine() {
        recorder.stop()
        voices.recording = false
        if voices.recStep < voices.captured.count { voices.captured[voices.recStep] = true }
    }

    func retakeLine() {
        if voices.recStep < voices.captured.count { voices.captured[voices.recStep] = false }
        voices.clipURLs[voices.recStep] = nil
    }

    func nextLine() {
        if voices.recStep < 9 { voices.recStep += 1 }
    }

    // MARK: Voice profile build (real)

    func buildVoiceProfile() {
        let clips = voices.captured.indices
            .filter { voices.captured[$0] }
            .compactMap { voices.clipURLs[$0] }
        guard !clips.isEmpty else { notify("Record at least one line first."); return }

        voices.phase = .building
        voices.buildProgress = 0
        voices.buildStage = "Preparing"
        let start = Date()

        let job = Job(kind: .voiceBuild, title: "Voice profile build",
                      subtitle: "\(clips.count) clips · analyzing", state: .running,
                      target: "\(clips.count) clips")
        tasks.jobs.insert(job, at: 0)

        buildTask?.cancel()
        buildTask = Task { @MainActor in
            do {
                let pid = try await engine.createProfile(name: "My voice")
                for (i, url) in clips.enumerated() {
                    try await engine.addRecording(pid: pid, fileURL: url, idx: i)
                }
                let jobID = try await engine.buildProfile(pid: pid)
                voices.buildJobID = jobID
                while !Task.isCancelled {
                    let st = try await engine.narrationStatus(jobID)   // build job on /api/jobs
                    let eta = st.eta_sec ?? 20
                    let elapsed = Date().timeIntervalSince(start)
                    voices.buildStage = buildStageText(st.stage)
                    voices.buildProgress = min(0.95, elapsed / max(eta, 1))
                    voices.buildETA = max(1, eta - elapsed)
                    job.progress = voices.buildProgress; job.eta = voices.buildETA
                    if st.status == "done" {
                        voices.builtProfileID = pid
                        selectedProfileID = pid
                        backendProfiles = (try? await engine.listProfiles()) ?? backendProfiles
                        voices.phase = .result
                        job.state = .done; job.timeLabel = "just now"; job.subtitle = "\(clips.count) clips"
                        complete("Voice profile ready.")
                        return
                    }
                    if st.status == "error" {
                        voices.phase = .record; job.state = .done
                        notify("Build failed: \(st.error ?? "unknown error")")
                        return
                    }
                    try await Task.sleep(nanoseconds: 600_000_000)
                }
            } catch let e as EngineError {
                voices.phase = .record; tasks.jobs.removeAll { $0.id == job.id }; notify(engineMessage(e))
            } catch {
                voices.phase = .record; tasks.jobs.removeAll { $0.id == job.id }
                notify("Could not reach the local engine.")
            }
        }
    }

    private func buildStageText(_ s: String?) -> String {
        switch s {
        case "reference": return "Analyzing your voice"
        case "stats": return "Measuring your style"
        default: return (s?.hasPrefix("prep") == true) ? "Preparing clips" : "Building"
        }
    }

    // MARK: Profile actions (real)

    func deleteProfile(_ id: String) {
        Task { @MainActor in
            try? await engine.deleteProfile(pid: id)
            backendProfiles = (try? await engine.listProfiles()) ?? backendProfiles
            if selectedProfileID == id { selectedProfileID = backendProfiles.first?.id }
            voices.phase = .library
            notify("Profile deleted.")
        }
    }

    func rollbackProfile(_ id: String, version: Int) {
        Task { @MainActor in
            do {
                try await engine.rollbackProfile(pid: id, version: version)
                backendProfiles = (try? await engine.listProfiles()) ?? backendProfiles
                notify("Rolled back to v\(version).")
            } catch { notify("Could not roll back.") }
        }
    }

    func setDefaultProfile(_ id: String) {
        selectedProfileID = id
        if let p = backendProfiles.first(where: { $0.id == id }) { settings.defaultProfile = p.name }
        notify("Set as default.")
    }

    func refreshProfiles() async {
        backendProfiles = (try? await engine.listProfiles()) ?? backendProfiles
    }

    func reinforceProfile(_ id: String, urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task { @MainActor in
            do {
                for u in urls { try await engine.addSource(pid: id, fileURL: u) }
                let jobID = try await engine.buildProfile(pid: id)
                while true {
                    let st = try await engine.narrationStatus(jobID)
                    if st.status == "done" { break }
                    if st.status == "error" { notify("Reinforce failed."); return }
                    try await Task.sleep(nanoseconds: 700_000_000)
                }
                backendProfiles = (try? await engine.listProfiles()) ?? backendProfiles
                complete("Profile reinforced.")
            } catch { notify("Could not reinforce the profile.") }
        }
    }

    // MARK: Denoise (real engine)

    func startDenoise() {
        guard let fileURL = denoise.importedFileURL else {
            notify("Import a file first.")
            return
        }
        denoise.phase = .processing
        denoise.progress = 0
        denoise.stageLabel = "Preparing"
        let mode = denoise.mode.rawValue
        let start = Date()

        let job = Job(kind: .denoise, title: "Denoise, \(denoise.fileName)",
                      subtitle: "\(denoise.mode.title) mode", state: .running,
                      target: denoise.fileName, profile: denoise.mode.title)
        tasks.jobs.insert(job, at: 0)

        dnPollTask?.cancel()
        dnPollTask = Task { @MainActor in
            do {
                let jid = try await engine.createDenoise(fileURL: fileURL, mode: mode)
                denoise.engineJobID = jid
                while !Task.isCancelled {
                    let st = try await engine.denoiseStatus(jid)
                    let eta = st.eta_sec ?? 12
                    let elapsed = Date().timeIntervalSince(start)
                    denoise.stageLabel = stageText(st.stage)
                    denoise.progress = min(0.96, elapsed / max(eta, 1))
                    denoise.eta = max(1, eta - elapsed)
                    job.progress = denoise.progress
                    job.eta = denoise.eta

                    if st.status == "done" {
                        denoise.progress = 1
                        denoise.report = DenoiseReport(from: st.report, mode: mode, engine: st.engine ?? "")
                        denoise.scorecard = .fromDenoise(denoise.report)
                        denoise.abMode = .cleaned
                        // Real A/B waveforms from the preview audio.
                        if let op = await RealWaveform.peaks(from: engine.denoiseAudioURL(jid, kind: "orig"), count: 64) {
                            denoise.originalPeaks = op
                        }
                        if let cp = await RealWaveform.peaks(from: engine.denoiseAudioURL(jid, kind: "clean"), count: 64) {
                            denoise.cleanedPeaks = cp
                        }
                        denoise.phase = .result
                        job.state = .done
                        job.timeLabel = "just now"
                        complete("Cleanup done, \(denoise.mode.title) mode.")
                        return
                    }
                    if st.status == "error" {
                        denoise.phase = .modeSelect
                        job.state = .done
                        job.timeLabel = "failed"
                        notify("Cleanup failed: \(st.error ?? "unknown error")")
                        return
                    }
                    try await Task.sleep(nanoseconds: 500_000_000)
                }
            } catch let e as EngineError {
                denoise.phase = .modeSelect
                tasks.jobs.removeAll { $0.id == job.id }
                notify(engineMessage(e))
            } catch {
                denoise.phase = .modeSelect
                tasks.jobs.removeAll { $0.id == job.id }
                notify("Could not reach the local engine. Is it running?")
            }
        }
    }

    private func stageText(_ stage: String) -> String {
        switch stage {
        case "extract": return "Reading the file"
        case "preview": return "Building preview"
        case "report": return "Measuring quality"
        case "done": return "Done"
        default: return "Cleaning audio"
        }
    }

    private func engineMessage(_ e: EngineError) -> String {
        switch e {
        case .notAvailable(let m): return m
        case .badResponse(_, let m): return m
        case .transport: return "Could not reach the local engine. Is it running?"
        }
    }

    // A/B playback of the real cleaned / original preview.
    func denoisePlayToggle() {
        guard let jid = denoise.engineJobID else { return }
        if denoise.playing {
            dnPlayer?.pause()
            denoise.playing = false
            return
        }
        let kind = denoise.abMode == .cleaned ? "clean" : "orig"
        let url = engine.denoiseAudioURL(jid, kind: kind)
        dnPlayer = AVPlayer(url: url)
        dnPlayer?.play()
        denoise.playing = true
    }

    func denoiseSetAB(_ mode: ABMode) {
        denoise.abMode = mode
        if denoise.playing {   // restart on the newly selected track
            dnPlayer?.pause()
            denoise.playing = false
            denoisePlayToggle()
        }
    }

    func denoiseExport() {
        guard let jid = denoise.engineJobID else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = denoise.fileName.replacingOccurrences(of: ".", with: "_") + "_clean.wav"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        let src = engine.denoiseFileURL(jid)
        Task { @MainActor in
            do {
                let (tmp, _) = try await URLSession.shared.download(from: src)
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: tmp, to: dest)
                complete("Cleaned file exported.")
            } catch {
                notify("Could not export the cleaned file.")
            }
        }
    }

    // MARK: Helpers

    var currentProfileName: String {
        if let id = selectedProfileID, let p = backendProfiles.first(where: { $0.id == id }) {
            return p.name
        }
        return backendProfiles.first?.name ?? "Default voice"
    }

    /// Per-profile SIM is not surfaced by a simple render yet; shown as an example.
    /// Facts about the selected voice. The engine does not score a profile against
    /// the speaker, so this reports what it does know rather than a similarity number.
    var currentProfileFacts: String {
        let p = selectedProfileID.flatMap { id in backendProfiles.first { $0.id == id } }
            ?? backendProfiles.first
        guard let p else { return "no voice profile" }
        let clips = p.clipCount
        return clips > 0 ? "\(p.versionLabel) · \(clips) clips" : p.versionLabel
    }

    var currentProfileInitials: String {
        let name = currentProfileName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "V" : String(name.prefix(2)).uppercased()
    }

    // MARK: Onboarding

    func requestMic() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
    }

    func finishOnboarding(createVoice: Bool = false) {
        firstRunComplete = true
        if createVoice {
            area = .voices
            voices.startFlow()
        } else {
            area = .studio
        }
    }

    // MARK: Export (fake) + lightweight toast

    func exportNarration() { complete("Narration exported to your Downloads folder.") }
    func exportSelection() { complete("Selected blocks exported to your Downloads folder.") }
    func exportCleaned() { complete("Cleaned file exported to your Downloads folder.") }
    func notify(_ message: String) { complete(message) }

    // MARK: New narration / primary actions

    func primaryAction() {
        switch area {
        case .studio:
            studio.resetToEmptyScript()
            studio.scriptText = SampleData.script
        case .voices:
            voices.startFlow()
        case .denoise:
            denoise.phase = .importEmpty
        case .tasks:
            tasks.clearFinished()
        case .settings:
            break
        }
    }
}

// Safe array subscript
extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
