import SwiftUI

struct TasksView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                group(app.s["taskGroupRunning"], app.tasks.running)
                group(app.s["taskGroupQueued"], app.tasks.queued)
                group(app.s["taskGroupDone"], app.tasks.done)
            }
            .padding(Space.xl)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private func group(_ title: String, _ jobs: [Job]) -> some View {
        if !jobs.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Eyebrow(text: title)
                    Text("\(jobs.count)").font(.mono(11)).foregroundStyle(Palette.ash)
                }
                VStack(spacing: 12) {
                    ForEach(jobs) { job in TaskRow(job: job) }
                }
            }
        }
    }
}

struct TaskRow: View {
    @Environment(AppModel.self) private var app
    var job: Job

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: job.kind.symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(iconColor)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Palette.surfaceElevated))
                VStack(alignment: .leading, spacing: 3) {
                    Text(job.title).font(.ui(15, .medium)).foregroundStyle(Palette.ink)
                    Text(job.subtitle).font(.mono(12)).foregroundStyle(Palette.mute)
                }
                Spacer()
                trailingMeta
                trailingButton
            }
            if job.state == .running {
                ThinProgress(value: job.progress, height: 4)
            }
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity)
        .card(Palette.surface, radius: Radius.card,
              border: app.tasks.selectedJobID == job.id ? Palette.hairlineStrong : Palette.hairline)
        .contentShape(Rectangle())
        .onTapGesture { app.tasks.selectedJobID = job.id }
    }

    private var iconColor: Color {
        switch job.state {
        case .running: return Palette.accent
        case .queued: return Palette.mute
        case .done: return Palette.good
        case .failed: return Palette.danger
        }
    }

    @ViewBuilder private var trailingMeta: some View {
        switch job.state {
        case .running: Text(etaLabel(job.eta)).font(.mono(12)).foregroundStyle(Palette.accent)
        case .queued:  Text(app.s["taskWaiting"]).font(.mono(12)).foregroundStyle(Palette.ash)
        case .done:    Text(job.timeLabel).font(.mono(12)).foregroundStyle(Palette.good)
        case .failed:  Text(app.s["taskFailed"]).font(.mono(12)).foregroundStyle(Palette.danger)
        }
    }

    @ViewBuilder private var trailingButton: some View {
        switch job.state {
        case .running, .queued:
            SecondaryButton(title: app.s["btnCancel"]) { app.tasks.jobs.removeAll { $0.id == job.id } }
        case .done:
            SecondaryButton(title: app.s["taskOpen"]) { openJob() }
        case .failed:
            SecondaryButton(title: app.s["taskDismiss"]) { app.tasks.jobs.removeAll { $0.id == job.id } }
        }
    }

    private func openJob() {
        switch job.kind {
        case .narrationRender: app.area = .studio
        case .denoise: app.area = .denoise
        case .voiceBuild: app.area = .voices
        }
    }
}
