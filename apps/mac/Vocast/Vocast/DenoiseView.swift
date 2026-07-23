import SwiftUI
import UniformTypeIdentifiers

struct DenoiseView: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        switch app.denoise.phase {
        case .importEmpty: DenoiseImport()
        case .modeSelect:  DenoiseModeSelect()
        case .processing:  DenoiseProcessing()
        case .result:      DenoiseResult()
        }
    }
}

// MARK: - Import (empty)

struct DenoiseImport: View {
    @Environment(AppModel.self) private var app
    @State private var targeted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                dropzone
                HStack(alignment: .top, spacing: 16) {
                    modeCard(.standard)
                    modeCard(.resynth)
                }
                recentJobs
            }
            .padding(Space.xl)
        }
    }

    private var dropzone: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.path").font(.system(size: 26)).foregroundStyle(Palette.mute)
            Text(app.s["dnDropTitle"]).font(.ui(16, .medium)).foregroundStyle(Palette.ink)
            Text(app.s["dnFormats"]).font(.mono(12)).foregroundStyle(Palette.mute)
            SecondaryButton(title: app.s["dnChooseFile"]) { pickFile() }.padding(.top, 4)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding(Space.xl)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .fill(targeted ? Palette.accent.opacity(0.06) : Color.clear))
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
            .foregroundStyle(targeted ? Palette.accent : Palette.hairline))
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            loadFile(providers)
            return true
        }
        .contentShape(Rectangle())
        .onTapGesture { pickFile() }
    }

    private func modeCard(_ m: DenoiseMode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(app.s[m == .standard ? "dnModeStandard" : "dnModeResynth"])
                .font(.ui(15, .semibold)).foregroundStyle(Palette.ink)
            Text(app.s[m == .standard ? "dnModeStandardBody" : "dnModeResynthBody"])
                .font(.ui(13)).foregroundStyle(Palette.mute).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(Palette.surface, radius: Radius.card)
    }

    private var recentJobs: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: app.s["dnRecentJobs"]).padding(.bottom, 12)
            VStack(spacing: 0) {
                ForEach(Array(app.denoise.recentJobs.enumerated()), id: \.element.id) { i, j in
                    HStack {
                        Image(systemName: "waveform.path").font(.system(size: 14)).foregroundStyle(Palette.good)
                            .frame(width: 34, height: 34)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Palette.surfaceElevated))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(j.title).font(.ui(14, .medium)).foregroundStyle(Palette.ink)
                            Text(j.meta).font(.mono(12)).foregroundStyle(Palette.mute)
                        }
                        Spacer()
                        Text(j.timeLabel).font(.mono(12)).foregroundStyle(Palette.ash)
                    }
                    .padding(.vertical, 12).padding(.horizontal, 14)
                    if i < app.denoise.recentJobs.count - 1 {
                        Rectangle().fill(Palette.hairline).frame(height: 1).padding(.horizontal, 14)
                    }
                }
            }
            .card(Palette.surface, radius: Radius.card)
        }
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .movie, .mpeg4Movie, .wav, .mp3]
        if panel.runModal() == .OK, let url = panel.url {
            app.denoise.importedFileURL = url
            app.denoise.fileName = url.lastPathComponent
            app.denoise.phase = .modeSelect
        }
    }

    private func loadFile(_ providers: [NSItemProvider]) {
        guard let p = providers.first else { return }
        _ = p.loadObject(ofClass: URL.self) { url, _ in
            Task { @MainActor in
                app.denoise.importedFileURL = url
                app.denoise.fileName = url?.lastPathComponent ?? "audio-file.wav"
                app.denoise.phase = .modeSelect
            }
        }
    }
}

// MARK: - Mode select

struct DenoiseModeSelect: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                FileChip(name: app.denoise.fileName)
                HStack(alignment: .top, spacing: 16) {
                    selectableMode(.standard)
                    selectableMode(.resynth)
                }
                PrimaryButton(title: app.s["dnStartCleanup"], systemImage: "sparkles") { app.startDenoise() }
            }
            .padding(Space.xl)
        }
    }

    private func selectableMode(_ m: DenoiseMode) -> some View {
        let sel = app.denoise.mode == m
        let disabled = (m == .resynth && !app.resynthAvailable)
        return Button { if !disabled { app.denoise.mode = m } } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(app.s[m == .standard ? "dnModeStandard" : "dnModeResynth"])
                        .font(.ui(15, .semibold)).foregroundStyle(Palette.ink)
                    if disabled { Text(app.s["dnNotInstalled"]).font(.mono(11)).foregroundStyle(Palette.ash) }
                    Spacer()
                    if sel {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 16)).foregroundStyle(Palette.accent)
                    }
                }
                Text(app.s[m == .standard ? "dnModeStandardBody" : "dnModeResynthBody"])
                    .font(.ui(13)).foregroundStyle(Palette.mute).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(sel ? Palette.accent.opacity(0.06) : Palette.surface))
            .hairline(Radius.card, color: sel ? Palette.accent : Palette.hairline)
            .opacity(disabled ? 0.5 : 1)
            .fullClickArea()
        }.buttonStyle(.plain)
    }
}

struct FileChip: View {
    var name: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.fill").font(.system(size: 13)).foregroundStyle(Palette.mute)
            Text(name).font(.mono(13)).foregroundStyle(Palette.ink)
        }
        .padding(.horizontal, 12).frame(height: 36)
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Palette.surfaceElevated))
        .hairline(Radius.control, color: Palette.hairline)
    }
}

// MARK: - Processing

struct DenoiseProcessing: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            ProgressView().controlSize(.large).tint(Palette.accent)
            Text(app.s["dnCleaning"]).font(.ui(20, .semibold)).foregroundStyle(Palette.ink)
            Text("\(app.denoise.stageLabel.isEmpty ? app.denoise.mode.title + " mode" : app.denoise.stageLabel), on this Mac.")
                .font(.ui(14)).foregroundStyle(Palette.mute)
            VStack(spacing: 8) {
                ThinProgress(value: app.denoise.progress, height: 6)
                HStack {
                    Text("\(Int(app.denoise.progress * 100))%").font(.mono(12)).foregroundStyle(Palette.mute)
                    Spacer()
                    Text(etaLabel(app.denoise.eta)).font(.mono(12)).foregroundStyle(Palette.mute)
                }
            }.frame(maxWidth: 420)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - A/B result

struct DenoiseResult: View {
    @Environment(AppModel.self) private var app
    private var d: DenoiseModel { app.denoise }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                HStack(spacing: 12) {
                    Text(d.fileName).font(.ui(20, .semibold)).foregroundStyle(Palette.ink)
                    Text(app.s["dnCleanedStatus"].replacingOccurrences(
                        of: "{mode}", with: app.s[d.mode == .standard ? "dnModeStandard" : "dnModeResynth"]))
                        .font(.mono(12)).foregroundStyle(Palette.good)
                    Spacer()
                    PrimaryButton(title: app.s["dnExport"]) { app.denoiseExport() }
                }

                HStack(spacing: 16) {
                    Segmented(options: [(ABMode.original, app.s["dnOriginal"]), (.cleaned, app.s["dnCleaned"])],
                              selection: Binding(get: { d.abMode }, set: { app.denoiseSetAB($0) }))
                    PlayCircle(playing: d.playing, size: 42, filled: true,
                               help: app.s["tipPlayPause"]) { app.denoisePlayToggle() }
                    Text(app.s["dnNow"].replacingOccurrences(
                        of: "{side}", with: app.s[d.abMode == .cleaned ? "dnCleaned" : "dnOriginal"]))
                        .font(.mono(13)).foregroundStyle(Palette.mute)
                    Spacer()
                }

                wavePanel(title: app.s["dnOriginal"], peaks: d.originalPeaks, color: Palette.stone, active: d.abMode == .original)
                wavePanel(title: app.s["dnCleaned"], peaks: d.cleanedPeaks, color: Palette.accent, active: d.abMode == .cleaned)

                reportCard
            }
            .padding(Space.xl)
        }
    }

    private func wavePanel(title: String, peaks: [Double], color: Color, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: title)
            WaveBars(peaks: peaks, color: color, height: 76, barWidth: 4, gap: 3)
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .fill(active ? Palette.surfaceElevated : Palette.surface))
        .hairline(Radius.card, color: active ? Palette.hairlineStrong : Palette.hairline)
    }

    @ViewBuilder private var reportCard: some View {
        HStack(alignment: .top, spacing: 40) {
            if d.report.isResynth {
                metric(app.s["scVoiceSim"], d.report.simText,
                       "How closely the cleaned voice matches the original.")
            } else {
                metric(app.s["scSpeechPreserved"], d.report.speechPreservedText,
                       "How much of your voice energy was kept.")
                metric(app.s["scPauseSupp"], d.report.pauseSuppText,
                       "Noise removed from the silences.")
            }
            Spacer()
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(Palette.surface, radius: Radius.card)
    }

    private func metric(_ label: String, _ value: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.ui(13)).foregroundStyle(Palette.mute)
            Text(value).font(.mono(28, .semibold)).foregroundStyle(Palette.ink)
            Text(sub).font(.ui(13)).foregroundStyle(Palette.mute)
        }
    }
}
