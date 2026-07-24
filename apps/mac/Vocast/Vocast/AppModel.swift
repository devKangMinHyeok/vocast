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

/// Language comes first: it decides what every later step reads like. The rest of
/// the flow shifts down by one, which the dot row picks up automatically.
enum OnboardingStep: Int, CaseIterable { case language, welcome, download, mic, ready }

@MainActor @Observable
final class OnboardingModel {
    var step: OnboardingStep = .language
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
    var rates: EngineRates?                       // speeds measured on this Mac

    // MARK: Interface language
    //
    // Presentation only. Changing it re-renders every string and touches nothing
    // else: no profile is read, written, or rebuilt. That guarantee is the point
    // of the whole language layer, so it is stated here and surfaced to the user
    // as a transient note whenever the language changes.
    var interfaceLanguage: InterfaceLanguage = AppModel.storedInterfaceLanguage() {
        didSet {
            guard oldValue != interfaceLanguage else { return }
            UserDefaults.standard.set(interfaceLanguage.rawValue, forKey: Self.langKey)
            showLanguageGuarantee()
        }
    }
    /// The reassurance shown for a few seconds after an interface language change.
    var languageNoteVisible = false
    private var languageNoteTask: Task<Void, Never>?
    private static let langKey = "interfaceLanguage"

    /// Strings for the current interface language. Views read copy through this.
    var s: Strings { Strings(interfaceLanguage) }

    private static func storedInterfaceLanguage() -> InterfaceLanguage {
        if let raw = UserDefaults.standard.string(forKey: langKey),
           let l = InterfaceLanguage(rawValue: raw) { return l }
        return .systemDefault
    }

    private func showLanguageGuarantee() {
        languageNoteVisible = true
        languageNoteTask?.cancel()
        languageNoteTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_200_000_000)
            if !Task.isCancelled { withAnimation(Motion.calm) { languageNoteVisible = false } }
        }
    }
    var profilePeaks: [String: [Double]] = [:]    // real waveform per profile id
    private var modelPollTask: Task<Void, Never>?
    private var dnPollTask: Task<Void, Never>?
    private var dnPlayer: AVPlayer?
    private var renderTask: Task<Void, Never>?
    private var regenTask: Task<Void, Never>?
    private var studioPlayer: AVPlayer?
    private var studioTimeObserver: Any?
    private var studioEndObserver: Any?

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
            voices.guide = (try? await engine.guideLines(lang: voices.lang.rawValue)) ?? []
            rates = try? await engine.rates()
            settings.mcpActions = ((try? await engine.mcpTools()) ?? []).map {
                MCPAction(name: $0.name, desc: $0.desc)
            }
            await refreshWork()
            await loadProfilePeaks()
            await loadLibrary()
        } else {
            engineReady = false
            resynthAvailable = false
        }
        engineStarting = false
    }

    // MARK: Work already done on this Mac

    /// Pull the real job history from the engine into the Tasks area and the
    /// Denoise recent list. Called on startup and after anything finishes, so the
    /// app only ever shows work that actually happened.
    func refreshWork() async {
        let s = self.s
        if let items = try? await engine.listTasks() {
            tasks.jobs = items.compactMap { Self.job(from: $0, s: s) }
        }
        if let items = try? await engine.listDenoiseJobs() {
            denoise.recentJobs = items.map { j in
                DenoiseJob(title: j.name ?? j.title ?? j.id,
                           meta: Self.denoiseMeta(j, s),
                           timeLabel: Self.shortDate(j.created))
            }
        }
    }

    /// Decode each profile's reference audio once so the library shows the real
    /// voice rather than a shape derived from its id.
    func loadProfilePeaks() async {
        for p in backendProfiles where profilePeaks[p.id] == nil {
            if let peaks = await RealWaveform.peaks(from: engine.profileAudioURL(p.id), count: 48) {
                profilePeaks[p.id] = peaks
            }
        }
    }

    private static func job(from t: ETask, s: Strings) -> Job? {
        let kind: JobKind
        switch t.kind {
        case "denoise": kind = .denoise
        case "profile_build": kind = .voiceBuild
        default: kind = .narrationRender
        }
        let state: JobState
        switch t.status {
        case "done": state = .done
        case "error": state = .failed
        case "queued": state = .queued
        default: state = .running
        }
        // The engine reports elapsed and eta in seconds; turn them into the
        // fraction the UI shows, and leave it at zero when nothing is known.
        var progress = 0.0
        if state == .done { progress = 1 }
        else if let e = t.elapsed_sec, let eta = t.eta_sec, eta > 0 {
            progress = min(0.95, e / eta)
        }
        var subtitle = [t.stage, t.mode].compactMap { $0 }.joined(separator: " · ")
        if state == .failed, let e = t.error { subtitle = e }
        return Job(kind: kind,
                   title: t.title ?? t.id,
                   subtitle: subtitle,
                   state: state,
                   progress: progress,
                   eta: max(0, (t.eta_sec ?? 0) - (t.elapsed_sec ?? 0)),
                   timeLabel: shortDate(t.created),
                   stage: t.stage ?? "",
                   target: t.stage ?? "",
                   profile: "",
                   throughput: t.elapsed_sec.map { s.f("jobElapsedS", ["n": String(Int($0))]) } ?? "")
    }

    private static func denoiseMeta(_ j: EDenoiseJob, _ s: Strings) -> String {
        var parts: [String] = []
        if let m = j.mode {
            switch m {
            case "standard": parts.append(s["dnModeStandard"])
            case "resynth":  parts.append(s["dnModeResynth"])
            default:         parts.append(m.capitalized)
            }
        }
        if let loss = j.report?.speech_loss_pct {
            parts.append(s.f("jobSpeechPreservedPct", ["n": String(format: "%.0f", max(0, 100 - loss))]))
        }
        if parts.isEmpty, let st = j.status { parts.append(st) }
        return parts.joined(separator: " · ")
    }

    /// The engine formats timestamps as "2026-07-20 08:26"; show just the time part
    /// for today and the date otherwise, rather than inventing "2 hr ago".
    private static func shortDate(_ s: String?) -> String {
        guard let s, s.count >= 16 else { return "" }
        let day = String(s.prefix(10))
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
        return day == today ? String(s.dropFirst(11)) : day
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
                notify(self.s["errDownloadStart"])
                return
            }
            while !Task.isCancelled {
                if let s = try? await engine.modelStatus() {
                    modelStatus = s
                    if s.ready { return }
                    if let e = s.error, !e.isEmpty { notify(self.s.f("errDownloadError", ["detail": e])); return }
                }
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
        }
    }

    // Shell UI state
    var area: Area = .studio
    var inspectorVisible = false   // closed by default; opened with the toolbar toggle
    var search = ""
    // Persisted across launches: once onboarding is finished it stays finished, so
    // the wizard does not reappear every time the app opens. The env var still
    // forces a skip (used by builds/tests).
    static let onboardingKey = "firstRunComplete"
    var firstRunComplete = ProcessInfo.processInfo.environment["VOCAST_SKIP_ONBOARDING"] == "1"
        || UserDefaults.standard.bool(forKey: AppModel.onboardingKey) {
        didSet {
            guard oldValue != firstRunComplete else { return }
            UserDefaults.standard.set(firstRunComplete, forKey: Self.onboardingKey)
        }
    }
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

    // MARK: Studio library (persisted narrations)

    /// Load saved narrations from the engine's history and collapse each
    /// regeneration chain into one project row. Real waveform thumbnails decode
    /// lazily so the list draws right away.
    func loadLibrary() async {
        studio.libLoading = true
        defer { studio.libLoading = false }
        guard let items = try? await engine.listHistory() else { return }
        let projects = Self.collapseChains(items)
        studio.projects = projects
        for p in projects where studio.libPeaks[p.id] == nil {
            Task { @MainActor in
                if let peaks = await RealWaveform.peaks(from: engine.narrationAudioURL(p.id), count: 56) {
                    studio.libPeaks[p.id] = peaks
                }
            }
        }
    }

    /// One row per project: follow each history item's parent link to its chain
    /// root, group by root, and keep the highest-version finished job as the head
    /// (that is where the current audio lives). Non-narration history (profile
    /// builds) is filtered out, and chains with no finished job are dropped.
    static func collapseChains(_ items: [NHistoryItem]) -> [NarrationProject] {
        let narr = items.filter { ($0.kind ?? "clone") == "clone" }
        let byID = Dictionary(narr.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        func root(_ item: NHistoryItem) -> String {
            var cur = item
            var seen: Set<String> = []
            while let pj = cur.parent?.job, let parent = byID[pj], !seen.contains(cur.id) {
                seen.insert(cur.id); cur = parent
            }
            return cur.id
        }

        var groups: [String: [NHistoryItem]] = [:]
        for it in narr { groups[root(it), default: []].append(it) }

        var out: [NarrationProject] = []
        for (_, group) in groups {
            let done = group.filter { $0.status == "done" }
            guard let head = done.max(by: { ($0.version ?? 1) < ($1.version ?? 1) }) else { continue }
            let duration = head.words?.last?.e
                ?? head.paragraphs?.compactMap { $0.end }.max()
                ?? 0
            let blockCount = head.paragraphs?.count ?? Self.paragraphCount(head.text)
            let title: String = {
                if let t = head.title, !t.trimmingCharacters(in: .whitespaces).isEmpty { return t }
                return Self.deriveTitle(head.text)
            }()
            out.append(NarrationProject(
                id: head.id, title: title,
                voiceID: head.profile_id, voiceName: head.profile ?? "",
                duration: duration, blockCount: max(1, blockCount),
                created: head.created ?? "",
                chainIDs: group.map { $0.id }, version: head.version ?? 1))
        }
        // Grouping loses the engine's newest-first order; restore it by timestamp.
        out.sort { $0.created > $1.created }
        return out
    }

    private static func paragraphCount(_ text: String?) -> Int {
        guard let text else { return 1 }
        let n = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.count
        return max(1, n)
    }

    private static func deriveTitle(_ text: String?) -> String {
        let firstLine = (text ?? "").split(separator: "\n").first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Untitled" : String(trimmed.prefix(60))
    }

    /// Whether a project's voice is gone (profile deleted, or it was made from a
    /// one-off upload). Playback and export still work; only re-render needs a voice.
    func voiceMissing(_ p: NarrationProject) -> Bool {
        guard let vid = p.voiceID else { return true }
        return !backendProfiles.contains { $0.id == vid }
    }

    /// A saved narration's relative age, e.g. "2시간 전". Falls back to the date for
    /// anything older than two weeks.
    func relativeDate(_ created: String) -> String {
        guard let date = Self.historyDateFormatter.date(from: created) else {
            return String(created.prefix(10))
        }
        let sec = Date().timeIntervalSince(date)
        if sec < 60 { return s["relJustNow"] }
        if sec < 3600 { return s.f("relMinAgo", ["n": String(max(1, Int(sec / 60)))]) }
        if sec < 86_400 { return s.f("relHourAgo", ["n": String(max(1, Int(sec / 3600)))]) }
        let days = Int(sec / 86_400)
        if days == 1 { return s["relYesterday"] }
        if days < 7 { return s.f("relDayAgo", ["n": String(days)]) }
        if days < 14 { return s["relLastWeek"] }
        return String(created.prefix(10))
    }

    private static let historyDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    /// Open a saved narration in the editor, reconstructing its blocks, word
    /// timeline and audio from the persisted job so it is fully editable again.
    func openProject(_ id: String) {
        studio.openRowMenu = nil
        stopStudioPlayback()
        studio.activeProjectID = id
        Task { @MainActor in
            guard let st = try? await engine.narrationStatus(id) else {
                notify(s["errOpenNarration"]); return
            }
            let text = st.text ?? studio.scriptText
            studio.scriptText = text
            studio.renderJobID = id
            studio.words = st.words ?? []
            studio.audioDuration = narrationDuration(st)
            studio.audioURL = engine.narrationAudioURL(id)
            let full = await RealWaveform.peaks(from: engine.narrationAudioURL(id), count: 240) ?? []
            studio.transportPeaks = full
            studio.blocks = makeRealBlocks(st, text: text, fullPeaks: full)
            studio.selectedBlockID = studio.blocks.first?.id
            studio.karaokeWordIndex = 0
            studio.currentTime = 0
            studio.viewMode = .blocks
            studio.phase = .rendered
            studio.nav = .editor
        }
    }

    /// Start a new narration in the empty composer.
    func newNarration() {
        stopStudioPlayback()
        studio.activeProjectID = nil
        studio.resetToEmptyScript()
        studio.nav = .composer
    }

    /// Return to the library and refresh it (a render or delete may have changed it).
    func backToLibrary() {
        stopStudioPlayback()
        studio.openRowMenu = nil
        studio.nav = .library
        Task { await loadLibrary() }
    }

    /// Rename a saved narration. Updated locally at once, then on the engine.
    func renameProject(_ id: String, title: String) {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        if let i = studio.projects.firstIndex(where: { $0.id == id }) { studio.projects[i].title = t }
        Task { @MainActor in try? await engine.renameHistory(id: id, title: t) }
    }

    /// Delete a saved narration and every job in its regeneration chain.
    func deleteProject(_ id: String) {
        guard let proj = studio.projects.first(where: { $0.id == id }) else { return }
        studio.projects.removeAll { $0.id == id }
        if studio.activeProjectID == id { studio.activeProjectID = nil; studio.nav = .library }
        Task { @MainActor in
            for jid in proj.chainIDs { try? await engine.deleteHistory(id: jid) }
            await loadLibrary()
            complete(s["toNarrationDeleted"])
        }
    }

    // MARK: Studio render

    func renderNarration() {
        guard !studio.scriptText.isEmpty, studio.phase != .rendering else { return }
        studio.phase = .rendering
        studio.rendering = true
        studio.renderStage = s["stPreparing"]
        stopStudioPlayback()
        let text = studio.scriptText
        let start = Date()

        let job = Job(kind: .narrationRender, title: s["jobTitleNarration"],
                      subtitle: s.f("jobSubTts", ["profile": currentProfileName]), state: .running,
                      target: s["jobTargetNarration"], profile: currentProfileName)
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
                    job.stage = studio.renderStage

                    if st.status == "done" {
                        studio.words = st.words ?? []
                        studio.audioDuration = narrationDuration(st)
                        studio.audioURL = engine.narrationAudioURL(jid)
                        // Real waveform from the composed audio, sliced per block.
                        let full = await RealWaveform.peaks(from: engine.narrationAudioURL(jid), count: 240) ?? []
                        studio.transportPeaks = full          // empty if the audio could not be read
                        studio.blocks = makeRealBlocks(st, text: text, fullPeaks: full)
                        studio.selectedBlockID = studio.blocks.first?.id
                        studio.karaokeWordIndex = 0
                        studio.currentTime = 0
                        studio.phase = .rendered
                        studio.rendering = false
                        // The finished render is now a saved project: open it in the
                        // editor and refresh the library so its row appears.
                        studio.activeProjectID = jid
                        studio.nav = .editor
                        Task { await loadLibrary() }
                        job.state = .done
                        job.timeLabel = s["jobTimeJustNow"]
                        complete(s["toNarrationReady"])
                        return
                    }
                    if st.status == "error" {
                        studio.phase = .empty
                        studio.rendering = false
                        tasks.jobs.removeAll { $0.id == job.id }
                        notify(s.f("errNarrationFailed", ["detail": st.error ?? s["errUnknownDetail"]]))
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
                notify(s["errEngineUnreachable"])
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
        case "reference": return s["stPreparingVoice"]
        case "takes": return s["stGeneratingSpeech"]
        case "post": return s["stComposing"]
        case "done": return s["stDone"]
        default:
            if let st = stage, st.hasPrefix("take ") { return "\(s["stGeneratingSpeech"]) (\(st.dropFirst(5)))" }
            return s["stGenerating"]
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
                slice = []            // no invented shape when there is no audio
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

    /// Create the shared studio player (its time observer, and an end-of-playback
    /// observer) on first use.
    private func ensureStudioPlayer() {
        guard studioPlayer == nil, let url = studio.audioURL else { return }
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
        // When playback reaches the end, flip the button back to "play" (not pause)
        // and leave the playhead at the end; the next play restarts from the top.
        studioEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.studio.playing = false
            self.studio.playingBlockID = nil
        }
        studioPlayer = player
    }

    /// True when the playhead is parked at (or past) the end of the narration.
    private var studioAtEnd: Bool {
        studio.totalDuration > 0 && studio.currentTime >= studio.totalDuration - 0.15
    }

    func studioPlayToggle() {
        guard studio.audioURL != nil else { return }
        if studio.playing {
            studioPlayer?.pause()
            studio.playing = false
            return
        }
        ensureStudioPlayer()
        studio.playingBlockID = nil   // bottom transport drives the whole narration
        if studioAtEnd { studioSeek(to: 0) }   // finished → replay from the start
        studioPlayer?.play()
        studio.playing = true
    }

    /// Play from the start of one block (its play button). Toggles to pause if that
    /// same block is already playing. Blocks are concatenated, so this seeks to the
    /// block's offset and plays on through the rest, like clicking the timeline there.
    func studioPlayBlock(_ id: Block.ID) {
        guard studio.audioURL != nil else { return }
        studio.selectedBlockID = id
        if studio.playing, studio.playingBlockID == id {
            studioPlayer?.pause()
            studio.playing = false
            return
        }
        ensureStudioPlayer()
        studioSeek(to: studio.startOffset(of: id))
        studio.playingBlockID = id
        studioPlayer?.play()
        studio.playing = true
    }

    func stopStudioPlayback() {
        studioPlayer?.pause()
        if let obs = studioTimeObserver { studioPlayer?.removeTimeObserver(obs); studioTimeObserver = nil }
        if let obs = studioEndObserver { NotificationCenter.default.removeObserver(obs); studioEndObserver = nil }
        studioPlayer = nil
        studio.playing = false
        studio.playingBlockID = nil
    }

    func studioSeek(to sec: Double) {
        studio.currentTime = sec
        studioPlayer?.seek(to: CMTime(seconds: sec, preferredTimescale: 600))
        if let idx = studio.words.lastIndex(where: { $0.s <= sec }) { studio.karaokeWordIndex = idx }
    }

    func regenerateBlock(_ id: Block.ID) {
        guard let idx = studio.blocks.firstIndex(where: { $0.id == id }) else { return }
        guard let parentJob = studio.renderJobID else {
            notify(s["errNoSingleBlock"])
            return
        }
        // Re-render just this paragraph on the engine; it recomposes the full audio.
        studio.blocks[idx].status = .rerendering
        stopStudioPlayback()
        let text = studio.scriptText
        let versions = studio.blocks.map { $0.version }   // preserve per-block versions
        let start = Date()

        let job = Job(kind: .narrationRender,
                      title: s.f("jobTitleNarrationBlock", ["n": String(idx + 1)]),
                      subtitle: s.f("jobSubTts", ["profile": currentProfileName]), state: .running,
                      target: s.f("jobTargetBlockOf", ["n": String(idx + 1), "total": String(studio.blocks.count)]),
                      profile: currentProfileName)
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
                    job.stage = narrationStageText(st.stage)

                    if st.status == "done" {
                        // The regen job is now the current narration (recomposed audio).
                        studio.renderJobID = jid
                        studio.words = st.words ?? []
                        studio.audioDuration = narrationDuration(st)
                        studio.audioURL = engine.narrationAudioURL(jid)
                        let full = await RealWaveform.peaks(from: engine.narrationAudioURL(jid), count: 240) ?? []
                        studio.transportPeaks = full          // empty if the audio could not be read
                        var blocks = makeRealBlocks(st, text: text, fullPeaks: full)
                        // Keep prior versions, bump the one we just regenerated.
                        for i in blocks.indices where i < versions.count { blocks[i].version = versions[i] }
                        if idx < blocks.count { blocks[idx].version += 1 }
                        studio.blocks = blocks
                        studio.selectedBlockID = idx < blocks.count ? blocks[idx].id : blocks.first?.id
                        studio.currentTime = 0
                        studio.karaokeWordIndex = 0
                        // The regen forked a new head job; make it the open project and
                        // refresh the library so the row points at the current audio.
                        studio.activeProjectID = jid
                        Task { await loadLibrary() }
                        job.state = .done
                        job.timeLabel = s["jobTimeJustNow"]
                        complete(s.f("toBlockRerendered", ["n": String(idx + 1)]))
                        return
                    }
                    if st.status == "error" {
                        if let i = studio.blocks.firstIndex(where: { $0.id == id }) {
                            studio.blocks[i].status = .rendered
                        }
                        tasks.jobs.removeAll { $0.id == job.id }
                        notify(s.f("errBlockRerenderFailed", ["n": String(idx + 1), "detail": st.error ?? s["errUnknownDetail"]]))
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
                notify(s["errEngineUnreachable"])
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
            notify(s["errMicStart"])
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
        guard !clips.isEmpty else { notify(s["errNeedOneLine"]); return }

        voices.phase = .building
        voices.buildProgress = 0
        voices.buildStage = s["stPreparing"]
        let start = Date()

        let job = Job(kind: .voiceBuild, title: s["jobTitleVoiceBuild"],
                      subtitle: s.f("jobSubClipsAnalyzing", ["n": String(clips.count)]), state: .running,
                      target: s.f("jobTargetClips", ["n": String(clips.count)]))
        tasks.jobs.insert(job, at: 0)

        buildTask?.cancel()
        buildTask = Task { @MainActor in
            do {
                let pid = try await engine.createProfile(name: "My voice", lang: voices.lang.rawValue)
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
                    job.stage = voices.buildStage
                    if st.status == "done" {
                        voices.builtProfileID = pid
                        selectedProfileID = pid
                        backendProfiles = (try? await engine.listProfiles()) ?? backendProfiles
                        voices.phase = .result
                        job.state = .done; job.timeLabel = s["jobTimeJustNow"]; job.subtitle = s.f("jobSubClips", ["n": String(clips.count)])
                        complete(s["toVoiceReady"])
                        return
                    }
                    if st.status == "error" {
                        voices.phase = .record; job.state = .done
                        notify(s.f("errBuildFailed", ["detail": st.error ?? s["errUnknownDetail"]]))
                        return
                    }
                    try await Task.sleep(nanoseconds: 600_000_000)
                }
            } catch let e as EngineError {
                voices.phase = .record; tasks.jobs.removeAll { $0.id == job.id }; notify(engineMessage(e))
            } catch {
                voices.phase = .record; tasks.jobs.removeAll { $0.id == job.id }
                notify(s["errEngineUnreachableShort"])
            }
        }
    }

    private func buildStageText(_ stage: String?) -> String {
        switch stage {
        case "reference": return s["stAnalyzingVoice"]
        case "stats": return s["stMeasuringStyle"]
        default: return (stage?.hasPrefix("prep") == true) ? s["stPreparingClips"] : s["stageBuilding"]
        }
    }

    // MARK: Profile actions (real)

    func deleteProfile(_ id: String) {
        Task { @MainActor in
            try? await engine.deleteProfile(pid: id)
            backendProfiles = (try? await engine.listProfiles()) ?? backendProfiles
            if selectedProfileID == id { selectedProfileID = backendProfiles.first?.id }
            voices.phase = .library
            notify(s["toProfileDeleted"])
        }
    }

    func rollbackProfile(_ id: String, version: Int) {
        Task { @MainActor in
            do {
                try await engine.rollbackProfile(pid: id, version: version)
                backendProfiles = (try? await engine.listProfiles()) ?? backendProfiles
                notify(s.f("toRolledBack", ["n": String(version)]))
            } catch { notify(s["errRollback"]) }
        }
    }

    func setDefaultProfile(_ id: String) {
        selectedProfileID = id
        if let p = backendProfiles.first(where: { $0.id == id }) { settings.defaultProfile = p.name }
        notify(s["toSetDefault"])
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
                    if st.status == "error" { notify(s["errReinforce"]); return }
                    try await Task.sleep(nanoseconds: 700_000_000)
                }
                backendProfiles = (try? await engine.listProfiles()) ?? backendProfiles
                complete(s["toProfileReinforced"])
            } catch { notify(s["errReinforceProfile"]) }
        }
    }

    // MARK: Denoise (real engine)

    func startDenoise() {
        guard let fileURL = denoise.importedFileURL else {
            notify(s["errImportFirst"])
            return
        }
        denoise.phase = .processing
        denoise.progress = 0
        denoise.stageLabel = s["stPreparing"]
        let mode = denoise.mode.rawValue
        let start = Date()

        let job = Job(kind: .denoise, title: s.f("jobTitleDenoise", ["file": denoise.fileName]),
                      subtitle: s.f("jobSubMode", ["mode": denoise.mode.title(s)]), state: .running,
                      target: denoise.fileName, profile: denoise.mode.title(s))
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
                    job.stage = denoise.stageLabel

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
                        job.timeLabel = s["jobTimeJustNow"]
                        complete(s.f("toCleanupDone", ["mode": denoise.mode.title(s)]))
                        return
                    }
                    if st.status == "error" {
                        denoise.phase = .modeSelect
                        job.state = .done
                        job.timeLabel = s["jobTimeFailed"]
                        notify(s.f("errCleanupFailed", ["detail": st.error ?? s["errUnknownDetail"]]))
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
                notify(s["errEngineUnreachable"])
            }
        }
    }

    private func stageText(_ stage: String) -> String {
        switch stage {
        case "extract": return s["stReadingFile"]
        case "preview": return s["stBuildingPreview"]
        case "report": return s["stMeasuringQuality"]
        case "done": return s["stDone"]
        default: return s["stCleaningAudio"]
        }
    }

    private func engineMessage(_ e: EngineError) -> String {
        switch e {
        case .notAvailable(let m): return m
        case .badResponse(_, let m): return m
        case .transport: return s["errEngineUnreachable"]
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
                complete(s["toCleanedExported"])
            } catch {
                notify(s["errExportCleaned"])
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
        guard let p else { return s["vNoProfileFacts"] }
        let clips = p.clipCount
        return clips > 0 ? s.f("vCardClips", ["version": p.versionLabel, "n": String(clips)]) : p.versionLabel
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
            voices.startFlow(suggesting: VoiceLanguage(rawValue: interfaceLanguage.rawValue) ?? .ko)
        } else {
            area = .studio
        }
    }

    // MARK: Export (real, to the Downloads folder)

    /// Open the export sheet for a saved narration. From a library row the scope is
    /// always the whole narration; the editor can pass `.selected`.
    func openExport(source id: String, scope: ExportScope = .whole) {
        studio.openRowMenu = nil
        studio.exportSource = id
        studio.exportScope = scope
        studio.exportOpen = true
    }

    /// Export the narration audio. WAV is a straight copy of the composed output;
    /// MP3 and selected-block export need engine transcoding and land in a later step.
    func exportAudio(format: String) {
        guard let id = studio.exportSource else { return }
        if format == "mp3" { notify(s["libSoon"]); return }
        if studio.exportScope == .selected { notify(s["libSoon"]); return }
        studio.exportOpen = false
        downloadToDownloads(from: engine.narrationAudioURL(id), as: exportBaseName(id) + ".wav")
    }

    /// Export subtitles timed to the narration's blocks, as SRT or VTT.
    func exportSubtitle(format: String) {
        guard let id = studio.exportSource else { return }
        studio.exportOpen = false
        Task { @MainActor in
            guard let st = try? await engine.narrationStatus(id) else { notify(s["errExport"]); return }
            let cues = Self.subtitleCues(st)
            guard !cues.isEmpty else { notify(s["errExport"]); return }
            let body = format == "vtt" ? Self.vtt(cues) : Self.srt(cues)
            let name = exportBaseName(id) + "." + format
            do {
                let dest = try uniqueDownloadsURL(name)
                try body.data(using: .utf8)?.write(to: dest)
                exportedToast(name)
            } catch { notify(s["errExport"]) }
        }
    }

    /// Export the whole project as a `.vocast` bundle (manifest + audio) for backup
    /// or moving to another Mac. Importing one arrives with the engine step.
    func exportProjectFile() {
        guard let id = studio.exportSource else { return }
        studio.exportOpen = false
        let name = exportBaseName(id) + ".vocast"
        Task { @MainActor in
            do {
                let manifest = try await engine.rawJob(id)
                let (audioTmp, _) = try await URLSession.shared.download(from: engine.narrationAudioURL(id))
                let bundle = FileManager.default.temporaryDirectory
                    .appendingPathComponent("vocast-export-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
                try manifest.write(to: bundle.appendingPathComponent("manifest.json"))
                try FileManager.default.moveItem(at: audioTmp, to: bundle.appendingPathComponent("output.wav"))
                let zip = try Self.zipForUpload(bundle)
                let dest = try uniqueDownloadsURL(name)
                try FileManager.default.moveItem(at: zip, to: dest)
                try? FileManager.default.removeItem(at: bundle)
                exportedToast(name)
            } catch { notify(s["errExport"]) }
        }
    }

    /// Importing a `.vocast` file registers it back into the engine's history, which
    /// arrives with the engine step.
    func importProjectFile() { studio.exportOpen = false; notify(s["libSoon"]) }

    /// Duplicating copies a saved job to a new history entry, an engine operation
    /// that arrives with the engine step.
    func duplicateProject(_ id: String) { studio.openRowMenu = nil; notify(s["libSoon"]) }

    func notify(_ message: String) { complete(message) }

    // Export helpers

    private func exportedToast(_ filename: String) {
        complete(s.f("exportedBody", ["file": filename]))
    }

    private func exportBaseName(_ id: String) -> String {
        let title = studio.projects.first { $0.id == id }?.title ?? studio.editorTitle
        let source = title.trimmingCharacters(in: .whitespaces).isEmpty ? "narration" : title
        let unsafe = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        let cleaned = String(source.unicodeScalars.map { unsafe.contains($0) ? "_" : Character($0) })
        return String(cleaned.prefix(60)).trimmingCharacters(in: .whitespaces)
    }

    private func uniqueDownloadsURL(_ filename: String) throws -> URL {
        let dir = try FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask,
                                              appropriateFor: nil, create: true)
        let ext = (filename as NSString).pathExtension
        let base = (filename as NSString).deletingPathExtension
        var dest = dir.appendingPathComponent(filename)
        var n = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            let candidate = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
            dest = dir.appendingPathComponent(candidate)
            n += 1
        }
        return dest
    }

    private func downloadToDownloads(from src: URL, as filename: String) {
        Task { @MainActor in
            do {
                let (tmp, _) = try await URLSession.shared.download(from: src)
                let dest = try uniqueDownloadsURL(filename)
                try FileManager.default.moveItem(at: tmp, to: dest)
                exportedToast(filename)
            } catch { notify(s["errExport"]) }
        }
    }

    /// Zip a directory into a single archive using the file coordinator's upload
    /// packaging (no third-party zip dependency). The coordinated copy is deleted
    /// when the block returns, so it is copied out first.
    private static func zipForUpload(_ dir: URL) throws -> URL {
        let coordinator = NSFileCoordinator()
        var coordErr: NSError?
        var moved: URL?
        var moveErr: Error?
        coordinator.coordinate(readingItemAt: dir, options: [.forUploading], error: &coordErr) { zipURL in
            let out = FileManager.default.temporaryDirectory
                .appendingPathComponent("vocast-\(UUID().uuidString).zip")
            do { try FileManager.default.copyItem(at: zipURL, to: out); moved = out }
            catch { moveErr = error }
        }
        if let coordErr { throw coordErr }
        if let moveErr { throw moveErr }
        guard let moved else { throw EngineError.transport("zip failed") }
        return moved
    }

    // Subtitle building (block-timed cues)

    private static func subtitleCues(_ st: NJob) -> [(Double, Double, String)] {
        let paras: [(String, Double?, Double?)]
        if let ps = st.paragraphs, !ps.isEmpty {
            paras = ps.map { ($0.text, $0.start, $0.end) }
        } else {
            let split = (st.text ?? "").components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            paras = split.map { ($0, nil, nil) }
        }
        guard !paras.isEmpty else { return [] }
        let total = st.words?.last?.e ?? paras.compactMap { $0.2 }.max() ?? Double(paras.count) * 4
        var cues: [(Double, Double, String)] = []
        var cursor = 0.0
        let even = total / Double(max(1, paras.count))
        for (text, start, end) in paras {
            let s0 = start ?? cursor
            let e0 = end ?? (s0 + even)
            cues.append((s0, max(e0, s0 + 0.5), text))
            cursor = e0
        }
        return cues
    }

    private static func srtStamp(_ t: Double) -> String {
        let ms = Int((max(0, t) * 1000).rounded())
        let h = ms / 3_600_000, m = (ms / 60_000) % 60, sec = (ms / 1000) % 60, milli = ms % 1000
        return String(format: "%02d:%02d:%02d,%03d", h, m, sec, milli)
    }
    private static func vttStamp(_ t: Double) -> String {
        srtStamp(t).replacingOccurrences(of: ",", with: ".")
    }
    private static func srt(_ cues: [(Double, Double, String)]) -> String {
        cues.enumerated().map { i, c in
            "\(i + 1)\n\(srtStamp(c.0)) --> \(srtStamp(c.1))\n\(c.2)\n"
        }.joined(separator: "\n")
    }
    private static func vtt(_ cues: [(Double, Double, String)]) -> String {
        "WEBVTT\n\n" + cues.map { c in
            "\(vttStamp(c.0)) --> \(vttStamp(c.1))\n\(c.2)\n"
        }.joined(separator: "\n")
    }

    // MARK: New narration / primary actions

    /// The profile Studio will narrate with.
    var currentProfile: EngineProfile? {
        selectedProfileID.flatMap { id in backendProfiles.first { $0.id == id } }
            ?? backendProfiles.first
    }

    /// The language the active voice speaks. Everything language-aware in Studio
    /// keys off this, not off the interface language.
    var currentVoiceLanguage: VoiceLanguage {
        VoiceLanguage(profileCode: currentProfile?.lang)
    }

    /// What, if anything, to say about the script against the active voice.
    /// Quiet by default: mixed script never raises anything.
    var scriptAdvice: ScriptAdvice {
        ScriptAdvice.of(script: studio.scriptText, voice: currentVoiceLanguage)
    }

    /// Profiles grouped by the language they speak, Korean first, with empty
    /// groups omitted. The library renders a section per entry.
    var profilesByLanguage: [(VoiceLanguage, [EngineProfile])] {
        VoiceLanguage.allCases.compactMap { lang in
            let group = backendProfiles.filter { VoiceLanguage(profileCode: $0.lang) == lang }
            return group.isEmpty ? nil : (lang, group)
        }
    }

    /// Open the new voice flow at the language pick. The interface language is a
    /// suggestion only: it seeds the selection and nothing more, because the voice
    /// language is a property of the recording, not of the UI.
    func startNewVoice() {
        area = .voices
        voices.startFlow(suggesting: VoiceLanguage(rawValue: interfaceLanguage.rawValue) ?? .ko)
        loadGuide()
    }

    /// Leave the pick step and start recording. The language is fixed from here.
    func beginVoiceRecording() {
        voices.beginRecording()
        loadGuide()
    }

    /// Reinforce an existing profile. It keeps its own language, so there is no
    /// pick step: changing language means creating a new voice, not editing one.
    func reinforceRecording(for profile: EngineProfile) {
        area = .voices
        voices.startReinforcing(lang: VoiceLanguage(profileCode: profile.lang))
        loadGuide()
    }

    /// Load the guided script for whichever language the new voice will speak.
    func loadGuide() {
        Task { @MainActor in
            voices.guide = (try? await engine.guideLines(lang: voices.lang.rawValue)) ?? []
        }
    }

    func primaryAction() {
        switch area {
        case .studio:
            newNarration()
        case .voices:
            voices.startFlow(suggesting: VoiceLanguage(rawValue: interfaceLanguage.rawValue) ?? .ko)
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
