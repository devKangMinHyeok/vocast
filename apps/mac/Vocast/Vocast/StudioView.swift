import SwiftUI
import AppKit

struct StudioView: View {
    @Environment(AppModel.self) private var app
    @State private var voiceKeyMonitor: Any?

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                if app.studio.nav != .library { subToolbar }
                switch app.studio.nav {
                case .library:  StudioLibraryView()
                case .composer: ComposingStudio()
                case .editor:   RenderedStudio()
                }
            }
            // Voice-picker dropdown: a full-pane catcher (a click anywhere closes
            // it) sits beneath the panel, which floats just under the trigger.
            if app.studio.voiceMenuOpen {
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { app.studio.voiceMenuOpen = false }
                VoiceMenuPanel()
                    .padding(.leading, Space.xl)
                    .padding(.top, 46)
                    .transition(.opacity)
            }
            // Library overlays: export sheet, rename, and delete confirmation.
            overlays
        }
        .animation(Motion.calm, value: app.studio.voiceMenuOpen)
        .animation(Motion.calm, value: app.studio.exportOpen)
        .animation(Motion.calm, value: app.studio.renameTarget)
        .animation(Motion.calm, value: app.studio.deleteConfirm)
        // Keyboard for the voice dropdown lives here, on a view that is always
        // present, driving the observable highlight so there is no stale state.
        .onAppear { installVoiceKeys() }
        .onDisappear { removeVoiceKeys() }
    }

    private func installVoiceKeys() {
        guard voiceKeyMonitor == nil else { return }
        voiceKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard app.studio.voiceMenuOpen else { return event }
            let profiles = app.backendProfiles
            let last = max(0, profiles.count - 1)
            switch event.keyCode {
            case 53:                                              // esc
                app.studio.voiceMenuOpen = false; return nil
            case 126:                                             // up arrow
                app.studio.voiceMenuHighlight = max(0, app.studio.voiceMenuHighlight - 1); return nil
            case 125:                                             // down arrow
                app.studio.voiceMenuHighlight = min(last, app.studio.voiceMenuHighlight + 1); return nil
            case 36, 76:                                          // return / enter
                if profiles.indices.contains(app.studio.voiceMenuHighlight) {
                    app.selectedProfileID = profiles[app.studio.voiceMenuHighlight].id
                }
                app.studio.voiceMenuOpen = false; return nil
            default:
                return event
            }
        }
    }
    private func removeVoiceKeys() {
        if let m = voiceKeyMonitor { NSEvent.removeMonitor(m); voiceKeyMonitor = nil }
    }

    // Sub-toolbar changes with the Studio surface (the library has its own bar).
    @ViewBuilder private var subToolbar: some View {
        if app.studio.nav == .editor { editorToolbar } else { composerToolbar }
    }

    /// The saved narration the editor's exports and renames act on.
    private var editorSourceID: String? { app.studio.activeProjectID ?? app.studio.renderJobID }

    @ViewBuilder private var editorToolbar: some View {
        @Bindable var studio = app.studio
        VStack(spacing: 0) {
            // Row 1: back to library, project title + rename, voice, counters.
            HStack(spacing: 12) {
                BackToLibraryButton()
                EditorTitleLabel()
                Rectangle().fill(Palette.hairline).frame(width: 1, height: 16)
                VoiceTrigger()
                Spacer()
                Text("\(app.studio.charCount) / 20,000").font(.mono(12)).foregroundStyle(Palette.mute)
                if let speed = app.rates?.narrationSpeedLabel {
                    Rectangle().fill(Palette.hairline).frame(width: 1, height: 16)
                    Text(speed).font(.mono(12)).foregroundStyle(Palette.ash)
                }
            }
            .padding(.horizontal, Space.xl).frame(height: kBarHeight)
            .overlay(alignment: .bottom) { Hairline() }

            // Row 2: block/karaoke toggle, totals, export.
            HStack(spacing: 14) {
                Segmented(options: [(StudioViewMode.blocks, app.s["blocks"]), (.karaoke, app.s["karaoke"])],
                          selection: $studio.viewMode)
                Text("\(app.studio.blocks.count) \(app.s["blocksTotal"]) · \(fmtTime(app.studio.totalDuration)) \(app.s["totalSuffix"])")
                    .font(.mono(12)).foregroundStyle(Palette.mute)
                Spacer()
                SecondaryButton(title: app.s["exportSel"]) {
                    if let id = editorSourceID { app.openExport(source: id, scope: .selected) }
                }
                PrimaryButton(title: app.s["exportNarration"]) {
                    if let id = editorSourceID { app.openExport(source: id, scope: .whole) }
                }
            }
            .padding(.horizontal, Space.xl).frame(height: kBarHeight)
            .overlay(alignment: .bottom) { Hairline() }
        }
    }

    @ViewBuilder private var composerToolbar: some View {
        HStack(spacing: 14) {
            VoiceTrigger()
            DotLabel(text: app.currentProfileFacts, color: Palette.good, mono: true)
            Spacer()
            Text("\(app.studio.charCount) / 20,000").font(.mono(12)).foregroundStyle(Palette.mute)
            if let speed = app.rates?.narrationSpeedLabel {
                Rectangle().fill(Palette.hairline).frame(width: 1, height: 16)
                Text(speed).font(.mono(12)).foregroundStyle(Palette.ash)
                    .help(app.s["stuScorecardNote"])
            }
        }
        .padding(.horizontal, Space.xl).frame(height: kBarHeight)
        .overlay(alignment: .bottom) { Hairline() }
    }

    @ViewBuilder private var overlays: some View {
        if app.studio.exportOpen { StudioExportSheet() }
        if let t = app.studio.renameTarget { StudioRenameDialog(target: t) }
        if let id = app.studio.deleteConfirm { StudioDeleteDialog(projectID: id) }
    }
}

// MARK: - Editor sub-toolbar deltas

struct BackToLibraryButton: View {
    @Environment(AppModel.self) private var app
    @State private var hovering = false
    var body: some View {
        Button { app.backToLibrary() } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                Text(app.s["backToLibrary"]).font(.ui(13, .medium))
            }
            .foregroundStyle(Palette.body)
            .padding(.horizontal, 10).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(hovering ? Palette.surfaceElevated : .clear))
            .hairline(Radius.control, color: Palette.hairline)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
    }
}

struct EditorTitleLabel: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        HStack(spacing: 8) {
            Text(app.studio.editorTitle.isEmpty ? app.s["untitledNarration"] : app.studio.editorTitle)
                .font(.ui(14, .semibold)).foregroundStyle(Palette.ink)
                .lineLimit(1).truncationMode(.tail).frame(maxWidth: 280, alignment: .leading)
            Button {
                app.studio.renameValue = app.studio.editorTitle
                app.studio.renameTarget = .editor
            } label: {
                Image(systemName: "pencil").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.mute)
                    .frame(width: 22, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(app.s["rowRename"])
        }
    }
}

// MARK: - Composing (empty / editor)

struct ComposingStudio: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        @Bindable var studio = app.studio
        VStack(spacing: Space.md) {
            ScriptAdviceBanner()
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
                        Text(app.s["scriptPlaceholder"])
                            .font(.ui(16)).foregroundStyle(Palette.ash)
                            .padding(.top, Space.xl + 2).padding(.leading, Space.xl + 5)
                        Spacer()
                        SecondaryButton(title: app.s["pasteSample"]) {
                            app.studio.scriptText = StarterContent.script
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
                Text(app.s["renderBlurb"])
                    .font(.ui(13)).foregroundStyle(Palette.mute)
                    .frame(maxWidth: 520, alignment: .leading)
                Spacer()
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small).tint(Palette.accent)
                    Text("\(app.studio.renderStage.isEmpty ? app.s["stageRendering"] : app.studio.renderStage) · \(Int(app.studio.renderProgress * 100))%")
                        .font(.mono(12)).foregroundStyle(Palette.body)
                    SecondaryButton(title: app.s["btnCancel"]) { }
                }
                .padding(.horizontal, 14).frame(height: 44)
                .card(Palette.surfaceElevated, radius: Radius.control)
            } else {
                Text(app.s["renderBlurb"])
                    .font(.ui(13)).foregroundStyle(Palette.mute)
                    .frame(maxWidth: 520, alignment: .leading)
                Spacer()
                PrimaryButton(title: app.s["renderNarration"], systemImage: "play.fill",
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
    private var voiceGone: Bool { app.studio.activeProject.map { app.voiceMissing($0) } ?? false }
    var body: some View {
        VStack(spacing: 0) {
            if voiceGone {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .font(.system(size: 13)).foregroundStyle(Palette.mute)
                    Text(app.s["editorVoiceGone"]).font(.ui(12.5)).foregroundStyle(Palette.mute)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Space.xl).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surface)
                .overlay(alignment: .bottom) { Hairline() }
            }
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
                PlayCircle(playing: app.studio.playing && app.studio.playingBlockID == block.id,
                           size: 34, filled: false, help: app.s["tipPlayBlock"]) {
                    app.studioPlayBlock(block.id)
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
                // The block-level echo of the script banner: this paragraph is in a
                // language the voice does not speak. It rendered anyway.
                if ScriptLanguage.mismatches(block.text, voice: app.currentVoiceLanguage) {
                    DifferentLanguageTag()
                }
                HStack(spacing: 7) {
                    StatusDot(color: rerendering ? Palette.accent : Palette.good, size: 7, blink: rerendering)
                    Text(app.s[rerendering ? "stageRerendering" : "stageRendered"])
                        .font(.mono(12)).foregroundStyle(rerendering ? Palette.accent : Palette.body)
                }
                Text(fmtTime(block.duration)).font(.mono(12)).foregroundStyle(Palette.mute)
                VersionPill(text: "v\(block.version)")
                IconButton(systemImage: "arrow.triangle.2.circlepath",
                           help: app.s["tipRegen"]) { app.regenerateBlock(block.id) }
                IconButton(systemImage: "chart.bar.xaxis", help: app.s["tipScorecard"]) {
                    app.studio.selectedBlockID = block.id
                    app.inspectorVisible = true
                }
            }
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .fill(selected ? Palette.surfaceElevated : Palette.surface))
        .hairline(Radius.card,
                  color: ScriptLanguage.mismatches(block.text, voice: app.currentVoiceLanguage)
                      ? Palette.accent.opacity(0.45)
                      : (selected ? Palette.hairlineStrong : Palette.hairline))
        .contentShape(Rectangle())
        .onTapGesture { app.studio.selectedBlockID = block.id }
    }
}

// MARK: - Karaoke

struct KaraokeView: View {
    @Environment(AppModel.self) private var app

    private var words: [String] { app.studio.karaokeWords }

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
                        .onTapGesture {
                            if i < app.studio.words.count { app.studioSeek(to: app.studio.words[i].s) }
                            app.studio.karaokeWordIndex = i
                        }
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
            PlayCircle(playing: app.studio.playing, size: 42, filled: true,
                       help: app.s["tipPlayPause"]) {
                app.studioPlayToggle()
            }
            Text(fmtTime(app.studio.currentTime)).font(.mono(13)).foregroundStyle(Palette.body)
                .frame(width: 40, alignment: .leading)
            GeometryReader { geo in
                WaveBars(peaks: app.studio.transportPeaks,
                         color: Palette.stone, activeColor: Palette.accent,
                         progress: app.studio.currentTime / total, height: 34)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                        let frac = min(1, max(0, v.location.x / geo.size.width))
                        app.studioSeek(to: frac * total)
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
