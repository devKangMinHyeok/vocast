import SwiftUI

let kSidebarWidth: CGFloat = 232
let kInspectorWidth: CGFloat = 308
let kBarHeight: CGFloat = 52

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        // Onboarding replaces the main UI rather than covering it. As an overlay the
        // panes underneath still existed, and AppKit resolves cursor rects by view
        // geometry rather than SwiftUI z-order, so the script editor's NSTextView kept
        // showing an I-beam through the onboarding screen.
        main
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.canvas)
            .background(WindowChrome())
            .ignoresSafeArea(.container, edges: .top)
            .toolbar {
                // A transparent, height-forcing item so the unified toolbar (and titlebar)
                // is tall enough to vertically center the traffic lights on the top-bar row.
                ToolbarItem(placement: .principal) {
                    Color.clear.frame(width: 1, height: 30).accessibilityHidden(true)
                }
                // These have to be real toolbar items. The top bar is drawn under the
                // titlebar so the traffic lights can share its row, and AppKit's titlebar
                // takes every click in that strip as a window drag. A SwiftUI button
                // placed there looks right and does nothing. Only the title and subhead
                // stay in the drawn bar, since text does not need to be clicked.
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        ActivityIndicatorBar()
                        if app.firstRunComplete { PrimaryActionButton() }
                        InspectorToggle()
                    }
                    // Sit at the trailing edge of the detail pane, where the design puts
                    // them, rather than out over the inspector.
                    .padding(.trailing, app.inspectorVisible ? kInspectorWidth - 12 : 0)
                }
            }
            .toolbarBackground(.hidden, for: .windowToolbar)
            .preferredColorScheme(.dark)
            .tint(Palette.accent)
    }

    @ViewBuilder private var main: some View {
        if app.firstRunComplete {
            shell
        } else {
            OnboardingView()
        }
    }

    private var shell: some View {
        HStack(spacing: 0) {
            Sidebar().frame(width: kSidebarWidth)
            VHairline()
            DetailPane().frame(maxWidth: .infinity, maxHeight: .infinity)
            if app.inspectorVisible {
                VHairline()
                InspectorPane()
                    .frame(width: kInspectorWidth)
                    .transition(.move(edge: .trailing))
            }
        }
        .overlay(alignment: .bottomTrailing) { ToastView(toast: app.toast) }
    }
}

struct VHairline: View {
    var body: some View { Rectangle().fill(Palette.hairline).frame(width: 1).frame(maxHeight: .infinity) }
}

// MARK: - Top bar (per pane), 52px

struct TopBar<Trailing: View>: View {
    var title: String
    var subhead: String = ""
    var leadingInset: CGFloat = Space.xl
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.ui(18, .semibold)).foregroundStyle(Palette.ink)
            if !subhead.isEmpty {
                Text(subhead).font(.ui(14)).foregroundStyle(Palette.mute)
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.leading, leadingInset).padding(.trailing, Space.md)
        .frame(height: kBarHeight)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(Palette.hairline).frame(height: 1) }
}

// MARK: - Detail pane (top bar + area content)

struct DetailPane: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            // The controls that used to live here are toolbar items now; see the
            // .toolbar in RootView for why. This bar keeps the title and subhead.
            TopBar(title: app.area.title, subhead: app.area.subhead) { EmptyView() }
            areaContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Palette.canvas)
    }

    @ViewBuilder private var areaContent: some View {
        switch app.area {
        case .studio:   StudioView()
        case .voices:   VoicesView()
        case .denoise:  DenoiseView()
        case .tasks:    TasksView()
        case .settings: SettingsView()
        }
    }
}

/// The area's primary action, as a toolbar item so it actually receives clicks.
struct PrimaryActionButton: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        if app.area != .settings {
            PrimaryButton(title: app.area.primaryActionLabel, systemImage: "plus") {
                app.primaryAction()
            }
        }
    }
}

struct InspectorToggle: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        Button { withAnimation(Motion.calm) { app.inspectorVisible.toggle() } } label: {
            Image(systemName: "sidebar.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.mute)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Palette.surfaceElevated))
                .hairline(Radius.control, color: Palette.hairline)
        }
        .buttonStyle(.plain)
        .help("Toggle inspector")
    }
}

// Toolbar activity indicator: spinner + "Rendering 62%", only while a job runs.
struct ActivityIndicatorBar: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        if let job = app.tasks.running.first {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(Palette.accent)
                Text("\(verb(job)) \(Int(job.progress * 100))%")
                    .font(.mono(12)).foregroundStyle(Palette.mute)
            }
            .padding(.trailing, 4)
            .transition(.opacity)
        }
    }
    private func verb(_ job: Job) -> String {
        switch job.kind {
        case .narrationRender: return "Rendering"
        case .denoise: return "Cleaning"
        case .voiceBuild: return "Building"
        }
    }
}

// MARK: - Inspector pane router

struct InspectorPane: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            InspectorHeader(title: headerTitle, meta: headerMeta)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.surface)
    }

    private var headerTitle: String {
        switch app.area {
        case .studio: return app.studio.phase == .rendered ? "Quality scorecard" : "Inspector"
        case .denoise: return app.denoise.phase == .result ? "Quality report" : "Inspector"
        case .tasks: return app.tasks.running.first != nil ? "Job detail" : "Inspector"
        default: return "Inspector"
        }
    }
    private var headerMeta: String {
        switch app.area {
        case .studio:
            if app.studio.phase == .rendered, let id = app.studio.selectedBlockID,
               let idx = app.studio.blocks.firstIndex(where: { $0.id == id }) {
                return "block \(idx + 1)"
            }
            return ""
        case .denoise: return app.denoise.phase == .result ? "cleaned" : ""
        case .tasks: return app.tasks.running.first != nil ? "running" : ""
        default: return ""
        }
    }

    @ViewBuilder private var content: some View {
        switch app.area {
        case .studio:
            if app.studio.phase == .rendered, let block = app.studio.selectedBlock {
                if let card = block.scorecard {
                    ScorecardView(card: card)
                } else {
                    InspectorEmpty(text: "The engine reported no quality scores for this block.")
                }
            } else {
                InspectorEmpty(text: "Render your script to see a quality scorecard for each block here.")
            }
        case .denoise:
            if app.denoise.phase == .result {
                ScorecardView(card: app.denoise.scorecard, footnote: Scorecard.denoiseFootnote)
            } else {
                InspectorEmpty(text: "Import a file and run a cleanup to see the quality report here.")
            }
        case .tasks:
            if let job = app.tasks.selectedJob, job.state == .running {
                JobDetailInspector(job: job)
            } else {
                InspectorEmpty(text: "Select a running job to see its progress and details.")
            }
        case .voices:
            InspectorEmpty(text: "Select a voice, or open a profile to see its versions and source clips.")
        case .settings:
            InspectorEmpty(text: "Contextual detail appears here.")
        }
    }
}

struct InspectorHeader: View {
    var title: String
    var meta: String = ""
    var body: some View {
        HStack {
            Text(title).font(.ui(15, .semibold)).foregroundStyle(Palette.ink)
            Spacer()
            if !meta.isEmpty { Text(meta).font(.mono(11)).foregroundStyle(Palette.ash) }
        }
        .padding(.horizontal, Space.lg)
        .frame(height: 44)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

struct InspectorEmpty: View {
    var text: String
    var body: some View {
        VStack {
            Spacer()
            Text(text)
                .font(.ui(14)).foregroundStyle(Palette.mute)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, Space.xl)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct JobDetailInspector: View {
    var job: Job
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(job.kind.typeLabel).font(.ui(15, .semibold)).foregroundStyle(Palette.ink)
                    ThinProgress(value: job.progress, height: 6)
                    HStack {
                        Text("\(Int(job.progress * 100))%").font(.mono(12)).foregroundStyle(Palette.mute)
                        Spacer()
                        Text("ETA \(fmtTime(job.eta))").font(.mono(12)).foregroundStyle(Palette.mute)
                    }
                }
                .padding(16).card(Palette.surfaceCard, radius: 10)

                VStack(spacing: 12) {
                    factRow("Type", job.kind.typeLabel)
                    factRow("Target", job.target)
                    factRow("Profile", job.profile)
                    if !job.throughput.isEmpty { factRow("Elapsed", job.throughput) }
                }
                Text("ETA comes from how long jobs like this actually took on this Mac.")
                    .font(.ui(12.5)).foregroundStyle(Palette.ash)
                    .fixedSize(horizontal: false, vertical: true).lineSpacing(3)
            }
            .padding(Space.lg)
        }
    }
    private func factRow(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.ui(13.5)).foregroundStyle(Palette.mute)
            Spacer()
            Text(v).font(.mono(12.5)).foregroundStyle(Palette.ink)
        }
    }
}

// MARK: - Toast

struct ToastView: View {
    var toast: Toast?
    var body: some View {
        Group {
            if let toast {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Palette.brandGradient)
                        .frame(width: 34, height: 34)
                        .overlay(Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.onWhite))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Vocast").font(.ui(13, .semibold)).foregroundStyle(Palette.ink)
                        Text(toast.message).font(.ui(12.5)).foregroundStyle(Palette.mute)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Palette.surfaceCard))
                .hairline(Radius.card, color: Palette.hairline)
                .padding(Space.xl)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(Motion.calm, value: toast)
    }
}
