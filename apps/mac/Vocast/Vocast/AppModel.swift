import SwiftUI
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
    var downloadProgress: Double = 0
    var downloadETA: Double = 8
    var downloading = false

    var downloadComplete: Bool { downloadProgress >= 1 }
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

        let job = Job(kind: .narrationRender, title: "Narration render",
                      subtitle: "\(currentProfileName) · 4x realtime", state: .running,
                      target: "4 blocks", profile: currentProfileName)
        tasks.jobs.insert(job, at: 0)

        drive(4.0, eta: 12, tick: { p, e in
            self.studio.renderProgress = p
            self.studio.renderETA = e
            job.progress = p
            job.eta = e
        }, done: {
            self.studio.blocks = self.makeBlocks()
            self.studio.selectedBlockID = self.studio.blocks.first?.id
            self.studio.phase = .rendered
            self.studio.rendering = false
            job.state = .done
            job.timeLabel = "just now"
            self.complete("Narration is ready, 4 blocks rendered.")
        })
    }

    func regenerateBlock(_ id: Block.ID) {
        guard let idx = studio.blocks.firstIndex(where: { $0.id == id }) else { return }
        studio.blocks[idx].status = .rerendering
        studio.blocks[idx].version += 1

        let job = Job(kind: .narrationRender, title: "Narration render, block \(idx + 1)",
                      subtitle: "\(currentProfileName) · 4x realtime", state: .running,
                      target: "block \(idx + 1) of \(studio.blocks.count)", profile: currentProfileName)
        tasks.jobs.insert(job, at: 0)

        drive(2.6, eta: 8, tick: { _, e in job.eta = e; job.progress = 1 - e / 8 },
              done: {
            if let i = self.studio.blocks.firstIndex(where: { $0.id == id }) {
                self.studio.blocks[i].status = .rendered
            }
            job.state = .done
            job.timeLabel = "just now"
            self.complete("Block \(idx + 1) re-rendered.")
        })
    }

    // MARK: Guided recording (per-line, fake live meter)

    private var recTask: Task<Void, Never>?

    func startRecordingLine() {
        voices.recording = true
        voices.recElapsed = 0
        recTask?.cancel()
        recTask = Task { @MainActor in
            while !Task.isCancelled && voices.recording {
                voices.recElapsed += 0.1
                let base = 0.55 + 0.35 * sin(voices.recElapsed * 4)
                voices.level = min(1, max(0.15, base + Double.random(in: -0.08...0.08)))
                voices.levelDb = -40 + voices.level * 28   // ~ -12 dB at healthy level
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    func stopRecordingLine() {
        voices.recording = false
        recTask?.cancel()
        if voices.recStep < voices.captured.count { voices.captured[voices.recStep] = true }
        voices.level = 0
        voices.levelDb = -60
    }

    func retakeLine() {
        if voices.recStep < voices.captured.count { voices.captured[voices.recStep] = false }
        voices.recElapsed = 0
    }

    func nextLine() {
        if voices.recStep < 9 { voices.recStep += 1; voices.recElapsed = 0 }
    }

    func deleteProfile(_ id: VoiceProfile.ID) {
        voices.profiles.removeAll { $0.id == id }
        voices.phase = .library
        notify("Profile deleted.")
    }

    func setDefault(_ id: VoiceProfile.ID) {
        for i in voices.profiles.indices { voices.profiles[i].isDefault = (voices.profiles[i].id == id) }
        notify("Set as default.")
    }

    // MARK: Voice profile build

    func buildVoiceProfile() {
        voices.phase = .building
        voices.buildProgress = 0

        let job = Job(kind: .voiceBuild, title: "Voice profile build, Ava narration",
                      subtitle: "10 clips · analyzing", state: .running,
                      target: "10 clips", profile: "Ava, narration")
        tasks.jobs.insert(job, at: 0)

        drive(4.0, eta: 10, tick: { p, e in
            self.voices.buildProgress = p
            self.voices.buildETA = e
            job.progress = p; job.eta = e
        }, done: {
            self.voices.phase = .result
            for i in self.voices.profiles.indices { self.voices.profiles[i].isDefault = false }
            job.state = .done
            job.subtitle = "10 clips · SIM 0.94"
            job.timeLabel = "just now"
            self.complete("Voice profile ready, similarity 0.94.")
        })
    }

    // MARK: Denoise

    func startDenoise() {
        denoise.phase = .processing
        denoise.progress = 0

        let job = Job(kind: .denoise, title: "Denoise, \(denoise.fileName)",
                      subtitle: "\(denoise.mode.title) mode", state: .running,
                      target: denoise.fileName, profile: denoise.mode.title)
        tasks.jobs.insert(job, at: 0)

        drive(4.0, eta: 11, tick: { p, e in
            self.denoise.progress = p
            self.denoise.eta = e
            job.progress = p; job.eta = e
        }, done: {
            self.denoise.abMode = .cleaned
            self.denoise.phase = .result
            job.state = .done
            job.timeLabel = "just now"
            self.complete("Cleanup done, residual noise -52 dB.")
        })
    }

    // MARK: Helpers

    var currentProfileName: String {
        voices.profiles.first(where: { $0.isDefault })?.name ?? "Ava, narration"
    }

    var currentProfileSim: String {
        voices.profiles.first(where: { $0.isDefault })?.sim ?? "0.94"
    }

    var currentProfileInitials: String {
        voices.profiles.first(where: { $0.isDefault })?.initials ?? "AR"
    }

    private func makeBlocks() -> [Block] {
        let paras = studio.scriptText
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let durations: [Double] = [11, 12, 9, 7]
        let versions: [Int] = [2, 3, 1, 1]
        return paras.enumerated().map { i, text in
            Block(
                text: text,
                status: .rendered,
                duration: durations[safe: i] ?? Double(6 + i),
                version: versions[safe: i] ?? 1,
                peaks: Waveform.peaks(34, seed: UInt64(100 + i * 13)),
                scorecard: .sample(attention: i == 1)   // block 2 is the "attention" example
            )
        }
    }

    // MARK: Onboarding

    func startModelDownload() {
        guard !onboarding.downloading else { return }
        onboarding.downloading = true
        drive(5.0, eta: 8, tick: { p, e in
            self.onboarding.downloadProgress = p
            self.onboarding.downloadETA = e
        }, done: { })
    }

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
