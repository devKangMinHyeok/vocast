import SwiftUI

struct StudioView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            subToolbar
            if app.studio.phase == .rendered {
                RenderedStudio()
            } else {
                ComposingStudio()
            }
        }
    }

    // Sub-toolbar changes with phase.
    @ViewBuilder private var subToolbar: some View {
        if app.studio.phase == .rendered {
            HStack(spacing: 14) {
                @Bindable var studio = app.studio
                Segmented(options: [(StudioViewMode.blocks, "Blocks"), (.karaoke, "Karaoke")],
                          selection: $studio.viewMode)
                Text("\(app.studio.blocks.count) blocks · \(fmtTime(app.studio.totalDuration)) total")
                    .font(.mono(12)).foregroundStyle(Palette.mute)
                Spacer()
                SecondaryButton(title: "Export selection") { app.exportSelection() }
                PrimaryButton(title: "Export narration") { app.exportNarration() }
            }
            .padding(.horizontal, Space.xl).frame(height: kBarHeight)
            .overlay(alignment: .bottom) { Hairline() }
        } else {
            HStack(spacing: 14) {
                ProfileSelector()
                DotLabel(text: "SIM \(app.currentProfileSim) · default", color: Palette.good, mono: true)
                Spacer()
                Text("\(app.studio.charCount) / 20,000").font(.mono(12)).foregroundStyle(Palette.mute)
                Rectangle().fill(Palette.hairline).frame(width: 1, height: 16)
                Text("~4x realtime").font(.mono(12)).foregroundStyle(Palette.ash)
            }
            .padding(.horizontal, Space.xl).frame(height: kBarHeight)
            .overlay(alignment: .bottom) { Hairline() }
        }
    }
}

// MARK: - Profile selector chip

struct ProfileSelector: View {
    @Environment(AppModel.self) private var app

    private var chip: some View {
        HStack(spacing: 10) {
            Avatar(initials: app.currentProfileInitials, size: 26)
            Text(app.currentProfileName).font(.ui(13.5, .medium)).foregroundStyle(Palette.ink).fixedSize()
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.mute)
        }
        .padding(.leading, 6).padding(.trailing, 12).frame(height: 38)
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Palette.surfaceElevated))
        .hairline(Radius.control, color: Palette.hairline)
    }

    var body: some View {
        // A plain Button hosting the styled chip; a native menu is attached so the
        // full avatar + name + chevron always render (Menu labels can collapse custom views).
        Button { cycleDefault() } label: { chip }
            .buttonStyle(.plain)
            .contextMenu {
                ForEach(app.voices.profiles) { p in
                    Button(p.name) { setDefault(p) }
                }
            }
    }

    private func cycleDefault() {
        let ps = app.voices.profiles
        guard let cur = ps.firstIndex(where: { $0.isDefault }) else { return }
        let next = (cur + 1) % ps.count
        for i in app.voices.profiles.indices { app.voices.profiles[i].isDefault = (i == next) }
    }
    private func setDefault(_ p: VoiceProfile) {
        for i in app.voices.profiles.indices { app.voices.profiles[i].isDefault = (app.voices.profiles[i].id == p.id) }
    }
}

// MARK: - Composing (empty / editor)

struct ComposingStudio: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        @Bindable var studio = app.studio
        VStack(spacing: Space.md) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $studio.scriptText)
                    .font(.ui(16))
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(7)
                    .scrollContentBackground(.hidden)
                    .padding(Space.xl)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .card(Palette.surface, radius: Radius.card)

                if app.studio.scriptText.isEmpty {
                    VStack(alignment: .leading) {
                        Text("Paste or write your script. Up to 20,000 characters.")
                            .font(.ui(16)).foregroundStyle(Palette.ash)
                            .padding(.top, Space.xl + 2).padding(.leading, Space.xl + 5)
                        Spacer()
                        SecondaryButton(title: "Paste a sample script") {
                            app.studio.scriptText = SampleData.script
                        }
                        .padding(Space.xl)
                    }
                    .allowsHitTesting(app.studio.scriptText.isEmpty)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }

            footer
        }
        .padding(Space.xl)
    }

    @ViewBuilder private var footer: some View {
        HStack(alignment: .center) {
            if app.studio.rendering {
                Text("Render turns your script into editable paragraph blocks. Each block can be replayed, re-rendered, and scored on its own.")
                    .font(.ui(13)).foregroundStyle(Palette.mute)
                    .frame(maxWidth: 520, alignment: .leading)
                Spacer()
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small).tint(Palette.accent)
                    Text("Rendering \(Int(app.studio.renderProgress * 100))% · ETA \(fmtTime(app.studio.renderETA))")
                        .font(.mono(12)).foregroundStyle(Palette.body)
                    SecondaryButton(title: "Cancel") { }
                }
                .padding(.horizontal, 14).frame(height: 44)
                .card(Palette.surfaceElevated, radius: Radius.control)
            } else {
                Text("Render turns your script into editable paragraph blocks. Each block can be replayed, re-rendered, and scored on its own.")
                    .font(.ui(13)).foregroundStyle(Palette.mute)
                    .frame(maxWidth: 520, alignment: .leading)
                Spacer()
                PrimaryButton(title: "Render narration", systemImage: "play.fill",
                              enabled: !app.studio.scriptText.isEmpty) {
                    app.renderNarration()
                }
            }
        }
    }
}

// MARK: - Rendered (blocks + karaoke) + transport

struct RenderedStudio: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        VStack(spacing: 0) {
            if app.studio.viewMode == .blocks {
                ScrollView {
                    VStack(spacing: Space.md) {
                        ForEach(app.studio.blocks) { block in
                            BlockCard(block: block)
                        }
                    }
                    .padding(Space.xl)
                }
            } else {
                KaraokeView()
            }
            Transport()
        }
    }
}

struct BlockCard: View {
    @Environment(AppModel.self) private var app
    var block: Block

    private var selected: Bool { app.studio.selectedBlockID == block.id }
    private var rerendering: Bool { block.status == .rerendering }
    private var index: Int { (app.studio.blocks.firstIndex { $0.id == block.id } ?? 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                PlayCircle(playing: false, size: 34, filled: false) {
                    app.studio.selectedBlockID = block.id
                }
                Text(block.text)
                    .font(.ui(16))
                    .foregroundStyle(rerendering ? Palette.mute : Palette.ink)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 14) {
                WaveBars(peaks: block.peaks,
                         color: rerendering ? Palette.accent : Palette.stone,
                         height: 24)
                    .frame(maxWidth: 520)
                Spacer(minLength: 12)
                HStack(spacing: 7) {
                    StatusDot(color: rerendering ? Palette.accent : Palette.good, size: 7, blink: rerendering)
                    Text(rerendering ? "Re-rendering" : "Rendered")
                        .font(.mono(12)).foregroundStyle(rerendering ? Palette.accent : Palette.body)
                }
                Text(fmtTime(block.duration)).font(.mono(12)).foregroundStyle(Palette.mute)
                VersionPill(text: "v\(block.version)")
                IconButton(systemImage: "arrow.triangle.2.circlepath") { app.regenerateBlock(block.id) }
                IconButton(systemImage: "chart.bar.xaxis") {
                    app.studio.selectedBlockID = block.id
                    app.inspectorVisible = true
                }
            }
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .fill(selected ? Palette.surfaceElevated : Palette.surface))
        .hairline(Radius.card, color: selected ? Palette.hairlineStrong : Palette.hairline)
        .contentShape(Rectangle())
        .onTapGesture { app.studio.selectedBlockID = block.id }
    }
}

// MARK: - Karaoke

struct KaraokeView: View {
    @Environment(AppModel.self) private var app

    private var words: [String] {
        let b = app.studio.selectedBlock ?? app.studio.blocks[safe: 1] ?? app.studio.blocks.first
        return b?.text.split(separator: " ").map(String.init) ?? []
    }

    var body: some View {
        ScrollView {
            FlowLayout(hSpacing: 8, vSpacing: 12) {
                ForEach(Array(words.enumerated()), id: \.offset) { i, word in
                    let state = wordState(i)
                    Text(word)
                        .font(.ui(26, .regular))
                        .foregroundStyle(state == .current ? Palette.onWhite
                                         : state == .played ? Palette.mute : Palette.stone)
                        .padding(.horizontal, state == .current ? 8 : 0)
                        .padding(.vertical, state == .current ? 2 : 0)
                        .background(state == .current
                                    ? RoundedRectangle(cornerRadius: Radius.row).fill(Palette.accent) : nil)
                        .onTapGesture { app.studio.karaokeWordIndex = i }
                }
            }
            .padding(.horizontal, 60).padding(.vertical, 40)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    enum WordState { case played, current, upcoming }
    private func wordState(_ i: Int) -> WordState {
        if i == app.studio.karaokeWordIndex { return .current }
        return i < app.studio.karaokeWordIndex ? .played : .upcoming
    }
}

// MARK: - Global transport

struct Transport: View {
    @Environment(AppModel.self) private var app
    private var total: Double { max(1, app.studio.totalDuration) }

    var body: some View {
        HStack(spacing: 16) {
            PlayCircle(playing: app.studio.playing, size: 46, filled: true) {
                app.studio.playing.toggle()
            }
            Text(fmtTime(app.studio.currentTime)).font(.mono(13)).foregroundStyle(Palette.body)
                .frame(width: 40, alignment: .leading)
            GeometryReader { geo in
                WaveBars(peaks: Waveform.peaks(90, seed: 500, floor: 0.2),
                         color: Palette.stone, activeColor: Palette.accent,
                         progress: app.studio.currentTime / total, height: 34)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                        let frac = min(1, max(0, v.location.x / geo.size.width))
                        app.studio.currentTime = frac * total
                    })
            }
            .frame(height: 34)
            Text(fmtTime(total)).font(.mono(13)).foregroundStyle(Palette.mute)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, Space.xl).frame(height: 72)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Hairline() }
    }
}
