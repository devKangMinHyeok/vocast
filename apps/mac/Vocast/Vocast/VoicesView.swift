import SwiftUI

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

// MARK: - Library

struct VoicesLibrary: View {
    @Environment(AppModel.self) private var app
    private let cols = [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                HStack(spacing: 12) {
                    Text("Your voices").font(.ui(20, .semibold)).foregroundStyle(Palette.ink)
                    Text("\(app.voices.profiles.count) profiles · stored on this Mac")
                        .font(.mono(12)).foregroundStyle(Palette.mute)
                }
                LazyVGrid(columns: cols, spacing: 20) {
                    ForEach(app.voices.profiles) { p in
                        ProfileCard(profile: p)
                    }
                    NewVoiceTile()
                }
            }
            .padding(Space.xl)
        }
    }
}

struct ProfileCard: View {
    @Environment(AppModel.self) private var app
    var profile: VoiceProfile

    var body: some View {
        Button {
            app.voices.openedProfileID = profile.id
            app.voices.phase = .detail
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    Avatar(initials: profile.initials, size: 52, elevated: !profile.isDefault)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(profile.name).font(.ui(17, .semibold)).foregroundStyle(Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            if profile.isDefault { TagPill(text: "default") }
                        }
                        Text("\(profile.version) · \(profile.lastUsed)")
                            .font(.mono(12)).foregroundStyle(Palette.mute)
                    }
                    Spacer(minLength: 0)
                }
                WaveBars(peaks: profile.peaks, color: Palette.stone, height: 30)
                Rectangle().fill(Palette.hairline).frame(height: 1)
                HStack {
                    Text("Similarity").font(.mono(12)).foregroundStyle(Palette.mute)
                    Spacer()
                    HStack(spacing: 7) {
                        StatusDot(color: Palette.good, size: 7)
                        Text(profile.sim).font(.mono(13)).foregroundStyle(Palette.ink)
                    }
                }
            }
            .padding(Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(profile.isDefault ? Palette.surfaceCard : Palette.surface, radius: Radius.card,
                  border: profile.isDefault ? Palette.hairlineStrong : Palette.hairline)
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
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Guided recording (signature)

struct GuidedRecording: View {
    @Environment(AppModel.self) private var app
    private var v: VoicesModel { app.voices }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                Button { app.voices.phase = .library } label: {
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

                // Progress row
                VStack(spacing: 8) {
                    HStack {
                        Text("Line \(v.recStep + 1) of 10").font(.mono(12)).foregroundStyle(Palette.mute)
                        Spacer()
                        Text("\(v.capturedSeconds)s / ~90s captured").font(.mono(12)).foregroundStyle(Palette.mute)
                    }
                    ThinProgress(value: Double(v.capturedSeconds) / 90.0, height: 4)
                }

                promptCard

                // Line dots
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

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            Eyebrow(text: "Read this line")
            Text(v.prompts[v.recStep]).font(.ui(22, .regular)).foregroundStyle(Palette.ink)
                .lineSpacing(6).fixedSize(horizontal: false, vertical: true)

            // Capture panel
            VStack(spacing: 16) {
                HStack {
                    HStack(spacing: 10) {
                        StatusDot(color: v.recording ? Palette.danger : Palette.ash, size: 9, blink: v.recording)
                        Text(v.recording ? "Recording" : (v.currentLineCaptured ? "Captured" : "Ready to record"))
                            .font(.mono(13)).foregroundStyle(Palette.body)
                    }
                    Spacer()
                    Text(fmtTime(v.recElapsed)).font(.mono(13)).foregroundStyle(Palette.mute)
                }
                LiveWave(active: v.recording, color: Palette.accent, height: 56)
                HStack(spacing: 12) {
                    Text("LVL").font(.mono(11)).foregroundStyle(Palette.ash)
                    LevelBar(level: v.recording ? v.level : 0, height: 8)
                    Text(v.recording ? "\(Int(v.levelDb)) dB" : "-∞ dB").font(.mono(12)).foregroundStyle(Palette.mute)
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
            if v.recording {
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
            Text("Analyzing 10 clips on this Mac. This runs as a background job, you can keep working.")
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
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Circle().fill(Palette.good.opacity(0.14))
                .frame(width: 76, height: 76)
                .overlay(Image(systemName: "checkmark").font(.system(size: 28, weight: .semibold)).foregroundStyle(Palette.good))
            Text("Voice profile ready").font(.ui(24, .semibold)).foregroundStyle(Palette.ink)
            Text("Ava, narration is now in your library and set as default.")
                .font(.ui(14)).foregroundStyle(Palette.mute)

            VStack(spacing: 18) {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text("0.94").font(.mono(46, .semibold)).foregroundStyle(Palette.ink)
                    Text("similarity").font(.mono(14)).foregroundStyle(Palette.mute)
                }
                WaveDots(count: 56, height: 22)
                Text("A high score means renders will closely match your voice. You can reinforce this profile later by adding more source clips.")
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
}

// MARK: - Profile detail

struct ProfileDetail: View {
    @Environment(AppModel.self) private var app
    private var profile: VoiceProfile? { app.voices.openedProfile }

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
                        Avatar(initials: p.initials, size: 56, elevated: !p.isDefault)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text(p.name).font(.ui(22, .semibold)).foregroundStyle(Palette.ink)
                                if p.isDefault { TagPill(text: "default") }
                            }
                            Text("\(p.version) · SIM \(p.sim) · \(p.clipCount) source clips · \(p.lastUsed)")
                                .font(.mono(12)).foregroundStyle(Palette.mute)
                        }
                        Spacer()
                        SecondaryButton(title: "Rename") { app.notify("Renaming is a demo action.") }
                        PrimaryButton(title: "Reinforce") { app.voices.startFlow() }
                    }

                    HStack(alignment: .top, spacing: 20) {
                        versionHistory(p)
                        sourceClips(p)
                    }
                }
                .padding(Space.xl)
            }
        }
    }

    private func versionHistory(_ p: VoiceProfile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "Version history").padding(.bottom, 16)
            VStack(spacing: 12) {
                ForEach(p.versions) { v in
                    HStack(spacing: 14) {
                        Text(v.label).font(.mono(13, .semibold)).foregroundStyle(Palette.ink).frame(width: 26, alignment: .leading)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(v.note).font(.ui(14, .medium)).foregroundStyle(Palette.ink)
                            Text("\(v.date) · \(v.sim)").font(.mono(12)).foregroundStyle(Palette.mute)
                        }
                        Spacer()
                        if v.isCurrent {
                            Text("current").font(.mono(12)).foregroundStyle(Palette.good)
                        } else {
                            SecondaryButton(title: "Roll back") { app.notify("Rolled back to \(v.label).") }
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(v.isCurrent ? Palette.surfaceElevated : Color.clear))
                    .hairline(10, color: v.isCurrent ? Palette.hairline : .clear)
                }
            }
            .padding(Space.md)
            .frame(maxWidth: .infinity)
            .card(Palette.surface, radius: Radius.card)
        }
        .frame(maxWidth: .infinity)
    }

    private func sourceClips(_ p: VoiceProfile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "Source clips").padding(.bottom, 16)
            VStack(alignment: .leading, spacing: 16) {
                WaveBars(peaks: p.peaks, color: Palette.stone, height: 30)
                Text("\(p.clipCount) clips, \(p.totalDuration) total. Drag audio files here to reinforce this profile with more of your voice.")
                    .font(.ui(13.5)).foregroundStyle(Palette.mute).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 20)
                Rectangle().fill(Palette.hairline).frame(height: 1)
                HStack {
                    Button { app.deleteProfile(p.id) } label: {
                        Text("Delete profile").font(.ui(13.5, .medium)).foregroundStyle(Palette.danger)
                    }.buttonStyle(.plain)
                    Spacer()
                    Button { app.setDefault(p.id) } label: {
                        HStack(spacing: 6) {
                            Text("Set as default").font(.mono(13)).foregroundStyle(Palette.mute)
                            Image(systemName: "checkmark").font(.system(size: 11)).foregroundStyle(Palette.good)
                        }
                    }.buttonStyle(.plain)
                }
            }
            .padding(Space.lg)
            .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
            .card(Palette.surface, radius: Radius.card)
            .onDrop(of: [.fileURL], isTargeted: nil) { _ in
                app.notify("Added source clips to \(p.name).")
                return true
            }
        }
        .frame(maxWidth: .infinity)
    }
}
