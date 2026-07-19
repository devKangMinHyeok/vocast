import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    private var o: OnboardingModel { app.onboarding }

    var body: some View {
        ZStack {
            Palette.canvas.ignoresSafeArea()
            // Soft orange radial glow at the top.
            RadialGradient(colors: [Palette.accent.opacity(0.16), .clear],
                           center: .top, startRadius: 0, endRadius: 480)
                .ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()
                stepContent
                    .frame(maxWidth: 560)
                Spacer()
                stepDots
                    .padding(.bottom, 40)
            }
            .padding(40)
        }
        .transition(.opacity)
    }

    @ViewBuilder private var stepContent: some View {
        switch o.step {
        case .welcome:  welcome
        case .download: download
        case .mic:      mic
        case .ready:    ready
        }
    }

    // 1. Welcome
    private var welcome: some View {
        VStack(spacing: 20) {
            LogoMark(size: 60)
            Text("Your voice, on your Mac").font(.ui(30, .semibold)).foregroundStyle(Palette.ink)
            Text("Clone your voice, narrate any script, and clean up audio. No account, no server. It all runs on this Mac and works offline after a one-time model download.")
                .font(.ui(15)).foregroundStyle(Palette.mute)
                .multilineTextAlignment(.center).lineSpacing(4)
            HStack(spacing: 10) {
                pill("Runs on this Mac")
                pill("Nothing uploaded")
                pill("Works offline")
            }
            .padding(.top, 4)
            PrimaryButton(title: "Get started") {
                withAnimation(Motion.calm) { o.step = .download }
                app.startModelDownload()
            }
            .padding(.top, 8)
        }
    }

    // 2. Model download
    private var download: some View {
        VStack(spacing: 24) {
            Text("Downloading the voice model").font(.ui(30, .semibold)).foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Vocast voice model").font(.ui(15, .medium)).foregroundStyle(Palette.ink)
                    Spacer()
                    Text("\(gb(o.downloadProgress)) / 1.8 GB").font(.mono(12)).foregroundStyle(Palette.mute)
                }
                ThinProgress(value: o.downloadProgress, height: 8, gradient: true)
                HStack {
                    Text("\(Int(o.downloadProgress * 100))%").font(.mono(12)).foregroundStyle(Palette.mute)
                    Spacer()
                    Text(o.downloadComplete ? "Done" : "ETA \(fmtTime(o.downloadETA))")
                        .font(.mono(12)).foregroundStyle(Palette.mute)
                }
            }
            .padding(Space.xl)
            .frame(maxWidth: 440)
            .card(Palette.surface, radius: Radius.card)

            PrimaryButton(title: "Continue", enabled: o.downloadComplete) {
                withAnimation(Motion.calm) { o.step = .mic }
            }
        }
    }

    // 3. Microphone access
    private var mic: some View {
        VStack(spacing: 20) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Palette.surfaceElevated).frame(width: 60, height: 60)
                .hairline(16, color: Palette.hairline)
                .overlay(Image(systemName: "mic").font(.system(size: 26)).foregroundStyle(Palette.mute))
            Text("Microphone access").font(.ui(30, .semibold)).foregroundStyle(Palette.ink)
            Text("Vocast needs your microphone to record voice samples. Recordings stay on this device and are never uploaded.")
                .font(.ui(15)).foregroundStyle(Palette.mute)
                .multilineTextAlignment(.center).lineSpacing(4)
            HStack(spacing: 12) {
                SecondaryButton(title: "Not now") { withAnimation(Motion.calm) { o.step = .ready } }
                PrimaryButton(title: "Allow microphone") {
                    app.requestMic()
                    withAnimation(Motion.calm) { o.step = .ready }
                }
            }
            .padding(.top, 4)
        }
    }

    // 4. Ready
    private var ready: some View {
        VStack(spacing: 20) {
            Circle().fill(Palette.good.opacity(0.14)).frame(width: 72, height: 72)
                .overlay(Image(systemName: "checkmark").font(.system(size: 28, weight: .semibold)).foregroundStyle(Palette.good))
            Text("You are set up").font(.ui(30, .semibold)).foregroundStyle(Palette.ink)
            Text("Create a voice profile to start narrating, or explore the studio first.")
                .font(.ui(15)).foregroundStyle(Palette.mute)
                .multilineTextAlignment(.center).lineSpacing(4)
            HStack(spacing: 12) {
                SecondaryButton(title: "Explore the studio") {
                    withAnimation(Motion.calm) { app.finishOnboarding(createVoice: false) }
                }
                PrimaryButton(title: "Create first voice") {
                    withAnimation(Motion.calm) { app.finishOnboarding(createVoice: true) }
                }
            }
            .padding(.top, 4)
        }
    }

    private var stepDots: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { s in
                Circle()
                    .fill(s.rawValue == o.step.rawValue ? Palette.accent : Palette.stone)
                    .frame(width: 7, height: 7)
            }
        }
    }

    private func pill(_ text: String) -> some View {
        HStack(spacing: 7) {
            StatusDot(color: Palette.good, size: 7)
            Text(text).font(.ui(12.5, .medium)).foregroundStyle(Palette.body)
        }
        .padding(.horizontal, 12).frame(height: 30)
        .background(Capsule().fill(Palette.surface))
        .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
    }

    private func gb(_ p: Double) -> String {
        String(format: "%.1f", 0.1 + p * 1.7)
    }
}
