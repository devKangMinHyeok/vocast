import SwiftUI
import UniformTypeIdentifiers

struct VoicesView: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        switch app.voices.phase {
        case .library:  VoicesLibrary()
        case .record:   GuidedRecording()
        case .building: VoiceBuilding()
        case .result:   VoiceResult()
        case .detail:   ProfileDetail()
        }
    }
}

// The profile's real waveform, decoded from its reference audio. Empty until the
// audio has been fetched, which the strip renders as a flat line rather than
// inventing a shape from the id.
@MainActor private func peaksFor(_ id: String, _ app: AppModel) -> [Double] {
    app.profilePeaks[id] ?? []
}

// MARK: - Library

struct VoicesLibrary: View {
    @Environment(AppModel.self) private var app
    private let cols = [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                HStack(spacing: 12) {
                    Text("Your voices").font(.ui(20, .semibold)).foregroundStyle(Palette.ink)
                    Text("\(app.backendProfiles.count) profiles · stored on this Mac")
                        .font(.mono(12)).foregroundStyle(Palette.mute)
                }
                LazyVGrid(columns: cols, spacing: 20) {
                    ForEach(app.backendProfiles) { p in ProfileCard(profile: p) }
                    NewVoiceTile()
                }
            }
            .padding(Space.xl)
        }
        .task { await app.refreshProfiles() }
    }
}

struct ProfileCard: View {
    @Environment(AppModel.self) private var app
    var profile: EngineProfile
    private var isDefault: Bool { app.selectedProfileID == profile.id }

    var body: some View {
        Button {
            app.voices.openedProfileID = profile.id
            app.voices.phase = .detail
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    Avatar(initials: profile.initials, size: 52, elevated: !isDefault)
                    // These cards are narrow, so anything sharing a row with text gets
                    // squeezed, and Korean has no word breaks to fall back on: the text
                    // then wraps one character per line. Keep the pill out of the text
                    // column, let the name truncate, and never compress the meta line.
                    VStack(alignment: .leading, spacing: 6) {
                        Text(profile.name).font(.ui(17, .semibold)).foregroundStyle(Palette.ink)
                            .lineLimit(2).truncationMode(.tail)
                            .fixedSize(horizontal: false, vertical: true)
                            .help(profile.name)
                        Text("\(profile.versionLabel) · \(profile.clipCount) clips")
                            .font(.mono(12)).foregroundStyle(Palette.mute)
                            .lineLimit(1).fixedSize()
                    }
                    Spacer(minLength: 0)
                    if isDefault { TagPill(text: "default") }
                }
                WaveBars(peaks: peaksFor(profile.id, app), color: Palette.stone, height: 30)
                Rectangle().fill(Palette.hairline).frame(height: 1)
                HStack {
                    Text("Voice length").font(.mono(12)).foregroundStyle(Palette.mute)
                    Spacer()
                    Text(fmtTime(profile.durationSec)).font(.mono(13)).foregroundStyle(Palette.ink)
                }
            }
            .padding(Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(isDefault ? Palette.surfaceCard : Palette.surface, radius: Radius.card,
                  border: isDefault ? Palette.hairlineStrong : Palette.hairline)
        }
        .buttonStyle(.plain)
    }
}

struct NewVoiceTile: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        Button { app.voices.startFlow() } label: {
            VStack(spacing: 14) {
                Spacer()
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .regular)).foregroundStyle(Palette.mute)
                    .frame(width: 52, height: 52)
                    .overlay(Circle().strokeBorder(Palette.hairline, lineWidth: 1))
                Text("New voice").font(.ui(16, .semibold)).foregroundStyle(Palette.ink)
                Text("Record about 90 seconds of guided lines to clone your voice.")
                    .font(.ui(13)).foregroundStyle(Palette.mute)
                    .multilineTextAlignment(.center).lineSpacing(3)
                    .frame(maxWidth: 220)
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 250)
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(Palette.hairline))
            // The dashed border only paints its outline, so without this the tile's
            // interior was not hit-testable and only the glyph and labels responded.
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Guided recording (real microphone)

struct GuidedRecording: View {
    @Environment(AppModel.self) private var app
    private var v: VoicesModel { app.voices }
    private var rec: AudioRecorder { app.recorder }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                Button { app.recorder.stop(); app.voices.phase = .library } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                        Text("Back to voices").font(.ui(13.5))
                    }.foregroundStyle(Palette.mute)
                }.buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Create a voice profile").font(.ui(22, .semibold)).foregroundStyle(Palette.ink)
                    Text("Read each line aloud in your normal speaking voice. About 90 seconds total.")
                        .font(.ui(14)).foregroundStyle(Palette.mute)
                }

                VStack(spacing: 8) {
                    HStack {
                        Text("Line \(v.recStep + 1) of 10").font(.mono(12)).foregroundStyle(Palette.mute)
                        Spacer()
                        Text("\(v.capturedSeconds)s / ~90s captured").font(.mono(12)).foregroundStyle(Palette.mute)
                    }
                    ThinProgress(value: Double(v.capturedSeconds) / 90.0, height: 4)
                }

                promptCard

                HStack(spacing: 8) {
                    ForEach(0..<10, id: \.self) { i in
                        Capsule()
                            .fill(v.captured[i] ? Palette.accent : (i == v.recStep ? Palette.hairlineStrong : Palette.stone))
                            .frame(width: 34, height: 6)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
            }
            .padding(Space.xl)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
    }

    /// The line to read now, straight from the engine's guided script. Its lines are
    /// chosen to cover greeting tone, breathing, question endings and emphasis, so
    /// the profile hears the range it needs.
    private var line: GuideLine? {
        v.recStep < v.guide.count ? v.guide[v.recStep] : nil
    }

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                Eyebrow(text: "Read this line")
                if let focus = line?.focus, !focus.isEmpty {
                    Text(focus).font(.mono(11)).foregroundStyle(Palette.accent)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Palette.accent.opacity(0.12)))
                }
            }
            Text(line?.text ?? "Waiting for the engine's guided script.")
                .font(.ui(22, .regular)).foregroundStyle(line == nil ? Palette.ash : Palette.ink)
                .lineSpacing(6).fixedSize(horizontal: false, vertical: true)
            if let tip = line?.tip, !tip.isEmpty {
                HStack(spacing: 7) {
                    Image(systemName: "lightbulb").font(.system(size: 11)).foregroundStyle(Palette.mute)
                    Text(tip).font(.ui(13)).foregroundStyle(Palette.mute)
                }
            }

            VStack(spacing: 16) {
                HStack {
                    HStack(spacing: 10) {
                        StatusDot(color: rec.recording ? Palette.danger : Palette.ash, size: 9, blink: rec.recording)
                        Text(rec.recording ? "Recording" : (v.currentLineCaptured ? "Captured" : "Ready to record"))
                            .font(.mono(13)).foregroundStyle(Palette.body)
                    }
                    Spacer()
                    Text(fmtTime(rec.elapsed)).font(.mono(13)).foregroundStyle(Palette.mute)
                }
                LiveWave(active: rec.recording, color: Palette.accent, height: 56)
                HStack(spacing: 12) {
                    Text("LVL").font(.mono(11)).foregroundStyle(Palette.ash)
                    LevelBar(level: rec.recording ? rec.level : 0, height: 8)
                    Text(rec.recording ? "\(Int(rec.db)) dB" : "-∞ dB").font(.mono(12)).foregroundStyle(Palette.mute)
                        .frame(width: 56, alignment: .trailing)
                }
            }
            .padding(20)
            .card(Palette.surface, radius: Radius.card)

            controls
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(Palette.surface, radius: Radius.card)
    }

    @ViewBuilder private var controls: some View {
        HStack(spacing: 12) {
            if rec.recording {
                Button { app.stopRecordingLine() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "stop.fill").font(.system(size: 11))
                        Text("Stop").font(.ui(13.5, .semibold))
                    }
                    .foregroundStyle(Palette.danger)
                    .padding(.horizontal, 18).frame(height: 34)
                    .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(Palette.danger.opacity(0.6), lineWidth: 1))
                }.buttonStyle(.plain)
            } else if v.currentLineCaptured {
                SecondaryButton(title: "Retake") { app.retakeLine() }
                if v.recStep == 9 {
                    PrimaryButton(title: "Build profile", systemImage: "sparkles") { app.buildVoiceProfile() }
                } else {
                    PrimaryButton(title: "Next line", systemImage: "arrow.right") { app.nextLine() }
                }
            } else {
                PrimaryButton(title: "Record", systemImage: "record.circle") { app.startRecordingLine() }
            }
            if !rec.recording && v.capturedCount > 0 && v.recStep < 9 {
                SecondaryButton(title: "Build now (\(v.capturedCount))") { app.buildVoiceProfile() }
            }
        }
    }
}

// MARK: - Building

struct VoiceBuilding: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView().controlSize(.large).tint(Palette.accent)
            Text("Building your voice profile").font(.ui(20, .semibold)).foregroundStyle(Palette.ink)
            Text("\(app.voices.buildStage.isEmpty ? "Analyzing your clips" : app.voices.buildStage) on this Mac. This runs as a background job, you can keep working.")
                .font(.ui(14)).foregroundStyle(Palette.mute)
                .multilineTextAlignment(.center).frame(maxWidth: 420).lineSpacing(3)
            VStack(spacing: 8) {
                ThinProgress(value: app.voices.buildProgress, height: 6)
                HStack {
                    Text("\(Int(app.voices.buildProgress * 100))%").font(.mono(12)).foregroundStyle(Palette.mute)
                    Spacer()
                    Text("ETA \(fmtTime(app.voices.buildETA))").font(.mono(12)).foregroundStyle(Palette.mute)
                }
            }
            .frame(maxWidth: 420)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Result

struct VoiceResult: View {
    @Environment(AppModel.self) private var app
    private var built: EngineProfile? { app.backendProfiles.first { $0.id == app.voices.builtProfileID } }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Circle().fill(Palette.good.opacity(0.14))
                .frame(width: 76, height: 76)
                .overlay(Image(systemName: "checkmark").font(.system(size: 28, weight: .semibold)).foregroundStyle(Palette.good))
            Text("Voice profile ready").font(.ui(24, .semibold)).foregroundStyle(Palette.ink)
            Text("\(built?.name ?? "Your voice") is now in your library and set as default.")
                .font(.ui(14)).foregroundStyle(Palette.mute)

            VStack(spacing: 18) {
                HStack(spacing: 40) {
                    stat("\(built?.clipCount ?? app.voices.capturedCount)", "clips analyzed")
                    stat(fmtTime(built?.durationSec ?? 0), "of your voice")
                    stat(built?.versionLabel ?? "v1", "version")
                }
                WaveDots(count: 56, height: 22)
                Text("Renders will follow the rhythm and tone the app measured from your voice. You can reinforce this profile later by adding more clips.")
                    .font(.ui(13.5)).foregroundStyle(Palette.mute)
                    .multilineTextAlignment(.center).lineSpacing(3).frame(maxWidth: 560)
            }
            .padding(Space.xl)
            .frame(maxWidth: 720)
            .card(Palette.surface, radius: Radius.card)

            HStack(spacing: 12) {
                SecondaryButton(title: "View in library") { app.voices.phase = .library }
                PrimaryButton(title: "Start narrating") { app.area = .studio }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Space.xl)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.mono(24, .semibold)).foregroundStyle(Palette.ink)
            Text(label).font(.ui(12.5)).foregroundStyle(Palette.mute)
        }
    }
}

// MARK: - Profile detail

struct ProfileDetail: View {
    @Environment(AppModel.self) private var app
    private var profile: EngineProfile? { app.backendProfiles.first { $0.id == app.voices.openedProfileID } }
    private var isDefault: Bool { app.selectedProfileID == app.voices.openedProfileID }

    var body: some View {
        ScrollView {
            if let p = profile {
                VStack(alignment: .leading, spacing: Space.xl) {
                    Button { app.voices.phase = .library } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                            Text("Back to voices").font(.ui(13.5))
                        }.foregroundStyle(Palette.mute)
                    }.buttonStyle(.plain)

                    HStack(alignment: .center, spacing: 16) {
                        Avatar(initials: p.initials, size: 56, elevated: !isDefault)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                // Truncate rather than let a long name squeeze itself
                                // into a vertical stack of single characters.
                                Text(p.name).font(.ui(22, .semibold)).foregroundStyle(Palette.ink)
                                    .lineLimit(1).truncationMode(.tail)
                                    .help(p.name)
                                if isDefault { TagPill(text: "default") }
                            }
                            Text("\(p.versionLabel) · \(p.clipCount) source clips · \(fmtTime(p.durationSec))")
                                .font(.mono(12)).foregroundStyle(Palette.mute)
                        }
                        Spacer()
                        SecondaryButton(title: "Reinforce") { pickSources(p.id) }
                        PrimaryButton(title: "Set as default", enabled: !isDefault) { app.setDefaultProfile(p.id) }
                    }

                    HStack(alignment: .top, spacing: 20) {
                        versionHistory(p)
                        sourceClips(p)
                    }
                }
                .padding(Space.xl)
            } else {
                Text("Profile not found.").font(.ui(14)).foregroundStyle(Palette.mute).padding(Space.xl)
            }
        }
    }

    private func versionHistory(_ p: EngineProfile) -> some View {
        let versions = (p.version_log ?? []).sorted { $0.version > $1.version }
        return VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "Version history").padding(.bottom, 16)
            VStack(spacing: 12) {
                if versions.isEmpty {
                    Text("This profile has one version.").font(.ui(13.5)).foregroundStyle(Palette.mute)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                }
                ForEach(versions) { v in
                    let current = v.version == (p.version ?? versions.first?.version)
                    HStack(spacing: 14) {
                        Text("v\(v.version)").font(.mono(13, .semibold)).foregroundStyle(Palette.ink).frame(width: 26, alignment: .leading)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(current ? "Current version" : "Earlier version").font(.ui(14, .medium)).foregroundStyle(Palette.ink)
                            Text(v.built ?? "").font(.mono(12)).foregroundStyle(Palette.mute)
                        }
                        Spacer()
                        if current {
                            Text("current").font(.mono(12)).foregroundStyle(Palette.good)
                        } else {
                            SecondaryButton(title: "Roll back") { app.rollbackProfile(p.id, version: v.version) }
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(current ? Palette.surfaceElevated : Color.clear))
                    .hairline(10, color: current ? Palette.hairline : .clear)
                }
            }
            .padding(Space.md)
            .frame(maxWidth: .infinity)
            .card(Palette.surface, radius: Radius.card)
        }
        .frame(maxWidth: .infinity)
    }

    private func sourceClips(_ p: EngineProfile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "Source clips").padding(.bottom, 16)
            VStack(alignment: .leading, spacing: 16) {
                WaveBars(peaks: peaksFor(p.id, app), color: Palette.stone, height: 30)
                Text("\(p.clipCount) clips, \(fmtTime(p.durationSec)) total. Drag audio files here to reinforce this profile with more of your voice.")
                    .font(.ui(13.5)).foregroundStyle(Palette.mute).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 20)
                Rectangle().fill(Palette.hairline).frame(height: 1)
                HStack {
                    Button { app.deleteProfile(p.id) } label: {
                        Text("Delete profile").font(.ui(13.5, .medium)).foregroundStyle(Palette.danger)
                    }.buttonStyle(.plain)
                    Spacer()
                    if isDefault {
                        HStack(spacing: 6) {
                            Text("Default").font(.mono(13)).foregroundStyle(Palette.mute)
                            Image(systemName: "checkmark").font(.system(size: 11)).foregroundStyle(Palette.good)
                        }
                    }
                }
            }
            .padding(Space.lg)
            .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
            .card(Palette.surface, radius: Radius.card)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                loadDropped(providers, into: p.id)
                return true
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func pickSources(_ pid: String) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .movie]
        if panel.runModal() == .OK { app.reinforceProfile(pid, urls: panel.urls) }
    }

    private func loadDropped(_ providers: [NSItemProvider], into pid: String) {
        var urls: [URL] = []
        let group = DispatchGroup()
        for p in providers {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { urls.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) { app.reinforceProfile(pid, urls: urls) }
    }
}
