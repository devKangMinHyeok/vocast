import SwiftUI

// MARK: - Studio library
//
// The default Studio surface: a vertical list of saved narrations, backed by the
// engine's persisted history (see AppModel.loadLibrary). A row opens a narration in
// the editor; the ⋯ menu renames, duplicates, exports, or deletes it. The "+ 새
// 나레이션" primary lives in the window's top bar (RootView) and opens the composer.

struct StudioLibraryView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var studio = app.studio
        VStack(spacing: 0) {
            libraryBar($studio.libSearch)
            if app.studio.projects.isEmpty {
                LibraryEmptyState()
            } else if app.studio.filteredProjects.isEmpty {
                LibraryNoResults()   // has projects, but the search matches none
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(app.studio.filteredProjects) { project in
                            LibraryRow(project: project)
                        }
                    }
                    .padding(Space.xl)
                }
            }
        }
    }

    // Search (left, flexible) + sort control (right). 34pt control row.
    @ViewBuilder private func libraryBar(_ search: Binding<String>) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(Palette.ash)
                TextField(app.s["libSearchPlaceholder"], text: search)
                    .textFieldStyle(.plain).font(.ui(13.5)).foregroundStyle(Palette.body)
            }
            .padding(.horizontal, 12).frame(height: 34).frame(maxWidth: 420)
            .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Palette.surfaceElevated))
            .hairline(Radius.control, color: Palette.hairline)

            Spacer(minLength: 12)

            // One sort order for now (newest first), shown as a static control so the
            // affordance is present without offering a choice that does nothing.
            HStack(spacing: 7) {
                Image(systemName: "arrow.up.arrow.down").font(.system(size: 12)).foregroundStyle(Palette.mute)
                Text(app.s["libSortNewest"]).font(.ui(13, .medium)).foregroundStyle(Palette.body)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.ash)
            }
            .padding(.horizontal, 12).frame(height: 34)
            .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Palette.surfaceElevated))
            .hairline(Radius.control, color: Palette.hairline)
        }
        .padding(.horizontal, Space.xl).frame(height: kBarHeight)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

// MARK: - Row

struct LibraryRow: View {
    @Environment(AppModel.self) private var app
    var project: NarrationProject
    @State private var hovering = false

    private var missing: Bool { app.voiceMissing(project) }
    private var peaks: [Double] {
        app.studio.libPeaks[project.id]
            ?? Waveform.peaks(24, seed: UInt64(abs(project.id.hashValue % 100_000)), floor: 0.2)
    }

    var body: some View {
        HStack(spacing: 16) {
            // Waveform thumbnail with a hairline divider on its right.
            WaveBars(peaks: peaks, color: Palette.stone, height: 40, gap: 2)
                .frame(width: 112, height: 40)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(Palette.hairline).frame(width: 1, height: 40).offset(x: 8)
                }
                .padding(.trailing, 8)

            VStack(alignment: .leading, spacing: 8) {
                Text(project.title)
                    .font(.ui(14.5, .semibold)).foregroundStyle(Palette.ink)
                    .lineLimit(1).truncationMode(.tail)
                metaRow
            }

            Spacer(minLength: 12)

            LibraryRowMenuButton(project: project)
        }
        .padding(.horizontal, Space.lg).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Palette.surface))
        .hairline(11, color: hovering ? Palette.hairlineStrong : Palette.hairline)
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .onTapGesture { app.openProject(project.id) }
        .onHover { hovering = $0 }
    }

    private var metaRow: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                Circle().fill(missing ? Palette.stone : project.voiceColor).frame(width: 7, height: 7)
                Text(missing ? app.s["libVoiceNone"] : project.voiceName)
                    .font(.ui(12.5, .medium))
                    .foregroundStyle(missing ? Palette.ash : Palette.body)
                    .lineLimit(1).frame(maxWidth: 200, alignment: .leading).fixedSize()
            }
            metaSep
            Text(fmtTime(project.duration)).font(.mono(12)).foregroundStyle(Palette.mute)
            Text(app.s.f("libBlocksN", ["n": String(project.blockCount)])).font(.mono(12)).foregroundStyle(Palette.mute)
            metaSep
            Text(app.relativeDate(project.created)).font(.mono(12)).foregroundStyle(Palette.stone)
        }
    }
    private var metaSep: some View {
        Rectangle().fill(Palette.hairline).frame(width: 1, height: 12)
    }
}

/// The ⋯ button and its anchored dropdown. A SwiftUI popover keeps the menu a
/// separate presentation from the row, so a menu-item tap never falls through to the
/// row's open gesture (the propagation bug the web build had does not arise here).
struct LibraryRowMenuButton: View {
    @Environment(AppModel.self) private var app
    var project: NarrationProject
    @State private var hovering = false

    private var isOpen: Binding<Bool> {
        Binding(get: { app.studio.openRowMenu == project.id },
                set: { app.studio.openRowMenu = $0 ? project.id : nil })
    }

    var body: some View {
        Button { app.studio.openRowMenu = project.id } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.mute)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(hovering ? Palette.surfaceElevated : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .popover(isPresented: isOpen, arrowEdge: .bottom) {
            LibraryRowMenu(project: project).presentationBackground(Palette.surfaceCard)
        }
    }
}

struct LibraryRowMenu: View {
    @Environment(AppModel.self) private var app
    var project: NarrationProject

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            item("rowOpen", "arrow.right") { app.openProject(project.id) }
            item("rowRename", "pencil") {
                app.studio.openRowMenu = nil
                app.studio.renameValue = project.title
                app.studio.renameTarget = .project(project.id)
            }
            item("rowDuplicate", "plus.square.on.square") { app.duplicateProject(project.id) }
            item("rowExport", "square.and.arrow.up") { app.openExport(source: project.id, scope: .whole) }
            Rectangle().fill(Palette.hairline).frame(height: 1).padding(.vertical, 5)
            item("rowDelete", "trash", destructive: true) {
                app.studio.openRowMenu = nil
                app.studio.deleteConfirm = project.id
            }
        }
        .padding(6)
        .frame(minWidth: 176)
    }

    @ViewBuilder private func item(_ key: String, _ icon: String, destructive: Bool = false,
                                   _ action: @escaping () -> Void) -> some View {
        MenuRow(label: app.s[key], icon: icon, destructive: destructive, action: action)
    }
}

private struct MenuRow: View {
    var label: String
    var icon: String
    var destructive: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 13, weight: .regular))
                    .frame(width: 16)
                Text(label).font(.ui(13, .medium))
                Spacer(minLength: 20)
            }
            .foregroundStyle(destructive ? Palette.danger : Palette.body)
            .padding(.horizontal, 10).frame(height: 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .fill(hovering ? (destructive ? Palette.danger.opacity(0.1) : Palette.surfaceElevated) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Empty state

struct LibraryEmptyState: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Palette.surface)
                .frame(width: 96, height: 96)
                .overlay {
                    // A calm waveform glyph with one accent bar, echoing the app mark.
                    HStack(alignment: .center, spacing: 3) {
                        ForEach(0..<9, id: \.self) { i in
                            Capsule().fill(i == 4 ? Palette.accent : Palette.stone)
                                .frame(width: 3, height: [14, 22, 30, 20, 38, 18, 28, 16, 12][i])
                        }
                    }
                }
                .hairline(22, color: Palette.hairline)
            VStack(spacing: 8) {
                Text(app.s["libEmptyTitle"]).font(.ui(18, .semibold)).foregroundStyle(Palette.ink)
                Text(app.s["libEmptyBody"]).font(.ui(13.5)).foregroundStyle(Palette.mute)
                    .multilineTextAlignment(.center).lineSpacing(3).frame(maxWidth: 360)
            }
            PrimaryButton(title: app.s["libEmptyCta"], systemImage: "plus") { app.newNarration() }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Space.xl)
    }
}

/// Shown when the library has narrations but the current search matches none, so
/// the list area explains itself instead of going blank (which read as "wiped").
struct LibraryNoResults: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "magnifyingglass").font(.system(size: 26)).foregroundStyle(Palette.ash)
            Text(app.s["libNoResults"]).font(.ui(14.5, .medium)).foregroundStyle(Palette.mute)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Space.xl)
    }
}

// MARK: - Overlays (export sheet, rename, delete). Hosted by StudioView.

/// A centered modal over a dimmed backdrop. The backdrop closes on tap.
struct StudioModalBackdrop<Content: View>: View {
    var opacity: Double
    var onDismiss: () -> Void
    @ViewBuilder var content: () -> Content
    var body: some View {
        ZStack {
            Color(hex: 0x06070A, alpha: opacity).ignoresSafeArea()
                .contentShape(Rectangle()).onTapGesture(perform: onDismiss)
            content()
        }
        .transition(.opacity)
    }
}

struct StudioExportSheet: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        @Bindable var studio = app.studio
        StudioModalBackdrop(opacity: 0.55, onDismiss: { app.studio.exportOpen = false }) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.mute)
                    Text(app.s["exportTitle"]).font(.ui(15, .semibold)).foregroundStyle(Palette.ink)
                    Spacer()
                    CloseX { app.studio.exportOpen = false }
                }
                .padding(.horizontal, Space.lg).frame(height: 52)
                .overlay(alignment: .bottom) { Hairline() }

                section(app.s["expAudioH"], app.s["expAudioHint"]) {
                    // Scope segment only applies inside the editor; a row export is whole.
                    if app.studio.exportSource == app.studio.activeProjectID && app.studio.nav == .editor {
                        Segmented(options: [(ExportScope.whole, app.s["expScopeWhole"]),
                                            (.selected, app.s["expScopeSelected"])],
                                  selection: $studio.exportScope)
                        .padding(.bottom, 10)
                    }
                    HStack(spacing: 10) {
                        formatChip("WAV", "24-bit") { app.exportAudio(format: "wav") }
                        formatChip("MP3", "320k") { app.exportAudio(format: "mp3") }
                    }
                }
                Hairline()
                section(app.s["expSubH"], app.s["expSubHint"]) {
                    HStack(spacing: 10) {
                        formatChip("SRT", "") { app.exportSubtitle(format: "srt") }
                        formatChip("VTT", "") { app.exportSubtitle(format: "vtt") }
                    }
                }
                Hairline()
                section(app.s["expProjectH"], app.s["expProjHint"]) {
                    HStack(spacing: 10) {
                        projectRow(app.s["expProjectExport"], "square.and.arrow.up") { app.exportProjectFile() }
                        projectRow(app.s["expProjectImport"], "square.and.arrow.down") { app.importProjectFile() }
                    }
                }
            }
            .frame(width: 440)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.surfaceCard))
            .hairline(14, color: Palette.hairline)
        }
    }

    @ViewBuilder private func section<C: View>(_ title: String, _ hint: String,
                                               @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title).font(.ui(13, .semibold)).foregroundStyle(Palette.ink)
                Text(hint).font(.ui(12)).foregroundStyle(Palette.ash).lineLimit(1)
            }
            content()
        }
        .padding(Space.lg)
    }

    private func formatChip(_ name: String, _ detail: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(name).font(.ui(14, .semibold)).foregroundStyle(Palette.ink)
                Spacer()
                if !detail.isEmpty { Text(detail).font(.mono(11)).foregroundStyle(Palette.ash) }
            }
            .padding(.horizontal, 14).frame(height: 44)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Palette.surfaceElevated))
            .hairline(Radius.control, color: Palette.hairline)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func projectRow(_ label: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.mute)
                Text(label).font(.ui(12.5, .medium)).foregroundStyle(Palette.body).lineLimit(1)
                Spacer(minLength: 6)
            }
            .padding(.horizontal, 12).frame(height: 40)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Palette.surfaceElevated))
            .hairline(Radius.control, color: Palette.hairline)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct StudioRenameDialog: View {
    @Environment(AppModel.self) private var app
    var target: RenameTarget

    var body: some View {
        @Bindable var studio = app.studio
        StudioModalBackdrop(opacity: 0.55, onDismiss: dismiss) {
            VStack(alignment: .leading, spacing: 14) {
                Text(app.s["renameTitle"]).font(.ui(15, .semibold)).foregroundStyle(Palette.ink)
                TextField("", text: $studio.renameValue)
                    .textFieldStyle(.plain).font(.ui(14)).foregroundStyle(Palette.ink)
                    .padding(.horizontal, 12).frame(height: 40)
                    .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Palette.surfaceElevated))
                    .hairline(Radius.control, color: Palette.hairline)
                    .onSubmit(save)
                Text(app.s["renameHint"]).font(.ui(12.5)).foregroundStyle(Palette.ash)
                    .fixedSize(horizontal: false, vertical: true).lineSpacing(3)
                HStack(spacing: 10) {
                    Spacer()
                    SecondaryButton(title: app.s["delCancel"], action: dismiss)
                    PrimaryButton(title: app.s["renameSave"], enabled: !trimmed.isEmpty, action: save)
                }
            }
            .padding(Space.lg)
            .frame(width: 400)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.surfaceCard))
            .hairline(14, color: Palette.hairline)
        }
    }

    private var trimmed: String { app.studio.renameValue.trimmingCharacters(in: .whitespaces) }
    private func dismiss() { app.studio.renameTarget = nil }
    private func save() {
        guard !trimmed.isEmpty else { return }
        switch target {
        case .project(let id): app.renameProject(id, title: trimmed)
        case .editor:
            if let id = app.studio.activeProjectID { app.renameProject(id, title: trimmed) }
        }
        app.studio.renameTarget = nil
    }
}

struct StudioDeleteDialog: View {
    @Environment(AppModel.self) private var app
    var projectID: String

    private var title: String { app.studio.projects.first { $0.id == projectID }?.title ?? "" }

    var body: some View {
        StudioModalBackdrop(opacity: 0.6, onDismiss: dismiss) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Palette.danger.opacity(0.14)).frame(width: 40, height: 40)
                        .overlay(Image(systemName: "trash").font(.system(size: 16, weight: .medium)).foregroundStyle(Palette.danger))
                    Text(app.s["delTitle"]).font(.ui(15, .semibold)).foregroundStyle(Palette.ink)
                    Spacer()
                }
                Text(title).font(.ui(13, .medium)).foregroundStyle(Palette.body)
                    .lineLimit(1).truncationMode(.tail)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Palette.surfaceElevated))
                    .hairline(Radius.control, color: Palette.hairline)
                Text(app.s["delBody"]).font(.ui(12.5)).foregroundStyle(Palette.mute)
                    .fixedSize(horizontal: false, vertical: true).lineSpacing(3)
                HStack(spacing: 10) {
                    Spacer()
                    SecondaryButton(title: app.s["delCancel"], action: dismiss)
                    DangerButton(title: app.s["delConfirm"]) {
                        app.deleteProject(projectID)
                        app.studio.deleteConfirm = nil
                    }
                }
            }
            .padding(Space.lg)
            .frame(width: 420)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.surfaceCard))
            .hairline(14, color: Palette.hairline)
        }
    }
    private func dismiss() { app.studio.deleteConfirm = nil }
}

// MARK: - Small shared controls

struct CloseX: View {
    var action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.mute)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(hovering ? Palette.surfaceElevated : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
    }
}

/// A filled destructive button (red fill, white text) for the delete confirmation.
struct DangerButton: View {
    var title: String
    var action: () -> Void
    @State private var pressed = false
    var body: some View {
        Button(action: action) {
            Text(title).font(.ui(13, .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 15).frame(height: 28)
                .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Palette.danger.opacity(pressed ? 0.85 : 1)))
                .contentShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)._onPressChange { pressed = $0 }
    }
}
