import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 0) {
            settingsNav
            Rectangle().fill(Palette.hairline).frame(width: 1)
            ScrollView {
                pane.padding(Space.xl).frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var settingsNav: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsSection.allCases) { s in
                let sel = app.settings.section == s
                Button { app.settings.section = s } label: {
                    Text(s.rawValue)
                        .font(.ui(14, sel ? .semibold : .regular))
                        .foregroundStyle(sel ? Palette.ink : Palette.body)
                        .padding(.horizontal, 12).frame(height: 34)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .fill(sel ? Palette.surfaceElevated : .clear))
                }.buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(12)
        .frame(width: 210)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private var pane: some View {
        switch app.settings.section {
        case .general: GeneralPane()
        case .models:  ModelsPane()
        case .audio:   AudioPane()
        case .privacy: PrivacyPane()
        case .mcp:     MCPPane()
        case .about:   AboutPane()
        }
    }
}

// Section scaffolding
struct SettingsHeader: View {
    var title: String
    var blurb: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.ui(20, .semibold)).foregroundStyle(Palette.ink)
            if !blurb.isEmpty {
                Text(blurb).font(.ui(14)).foregroundStyle(Palette.mute).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SettingRow<Trailing: View>: View {
    var label: String
    var sub: String = ""
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.ui(14, .medium)).foregroundStyle(Palette.ink)
                if !sub.isEmpty { Text(sub).font(.mono(12)).foregroundStyle(Palette.mute) }
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16).frame(minHeight: 52)
    }
}

func settingsCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    VStack(spacing: 0) { content() }
        .card(Palette.surface, radius: Radius.card)
}

// MARK: - General

struct GeneralPane: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        @Bindable var settings = app.settings
        VStack(alignment: .leading, spacing: Space.xl) {
            SettingsHeader(title: "General", blurb: "Appearance, startup, and default behavior.")
            settingsCard {
                SettingRow(label: "Appearance", sub: "Dark is the only theme for now.") {
                    Picker("", selection: $settings.appearance) {
                        ForEach(AppearanceChoice.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).fixedSize().labelsHidden()
                }
                Divider().overlay(Palette.hairline)
                SettingRow(label: "Launch at login") {
                    Toggle("", isOn: $settings.launchAtLogin).labelsHidden().toggleStyle(.switch).tint(Palette.accent)
                }
                Divider().overlay(Palette.hairline)
                SettingRow(label: "Default voice profile") {
                    Picker("", selection: $settings.defaultProfile) {
                        ForEach(app.voices.profiles.map(\.name), id: \.self) { Text($0).tag($0) }
                    }.fixedSize().labelsHidden()
                }
            }
        }
    }
}

// MARK: - Models

struct ModelsPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            SettingsHeader(title: "Models", blurb: "Installed models and local storage.")
            settingsCard {
                SettingRow(label: "Vocast voice model", sub: "v1.4 · 1.8 GB") {
                    SecondaryButton(title: "Re-download") { }
                }
                Divider().overlay(Palette.hairline)
                SettingRow(label: "Denoise model", sub: "v2.1 · 240 MB") {
                    SecondaryButton(title: "Re-download") { }
                }
                Divider().overlay(Palette.hairline)
                SettingRow(label: "Storage used", sub: "Example value") {
                    Text("2.1 GB").font(.mono(13)).foregroundStyle(Palette.ink)
                }
            }
        }
    }
}

// MARK: - Audio

struct AudioPane: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        @Bindable var settings = app.settings
        VStack(alignment: .leading, spacing: Space.xl) {
            SettingsHeader(title: "Audio", blurb: "Input device and export format.")
            settingsCard {
                SettingRow(label: "Input device") {
                    Picker("", selection: $settings.inputDevice) {
                        Text("MacBook Pro Microphone").tag("MacBook Pro Microphone")
                        Text("External USB microphone").tag("External USB microphone")
                    }.fixedSize().labelsHidden()
                }
                Divider().overlay(Palette.hairline)
                SettingRow(label: "Export format") {
                    Picker("", selection: $settings.exportFormat) {
                        ForEach(["WAV", "MP3", "M4A"], id: \.self) { Text($0).tag($0) }
                    }.fixedSize().labelsHidden()
                }
                Divider().overlay(Palette.hairline)
                SettingRow(label: "Sample rate") {
                    Picker("", selection: $settings.sampleRate) {
                        ForEach(["44.1 kHz", "48 kHz"], id: \.self) { Text($0).tag($0) }
                    }.fixedSize().labelsHidden()
                }
            }
        }
    }
}

// MARK: - Privacy

struct PrivacyPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            SettingsHeader(title: "Privacy and local status",
                           blurb: "All generation and cleanup happen on device. No account, no server, no telemetry.")
            settingsCard {
                privacyRow("Runs on this Mac", "Generation uses this machine only.")
                Divider().overlay(Palette.hairline)
                privacyRow("Nothing uploaded", "Your audio never leaves the device.")
                Divider().overlay(Palette.hairline)
                privacyRow("Works offline", "After the first-run model download.")
                Divider().overlay(Palette.hairline)
                privacyRow("Where data is stored", "~/Library/Application Support/Vocast")
            }
        }
    }
    private func privacyRow(_ label: String, _ sub: String) -> some View {
        HStack(spacing: 12) {
            StatusDot(color: Palette.good, size: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.ui(14, .medium)).foregroundStyle(Palette.ink)
                Text(sub).font(.mono(12)).foregroundStyle(Palette.mute)
            }
            Spacer()
        }
        .padding(.horizontal, 16).frame(minHeight: 56)
    }
}

// MARK: - MCP

struct MCPPane: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        @Bindable var settings = app.settings
        VStack(alignment: .leading, spacing: Space.xl) {
            SettingsHeader(title: "MCP server",
                           blurb: "Let an AI agent (for example Claude) call Vocast actions on this Mac through a local MCP server. Off by default. Nothing is exposed to the network.")

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable local MCP server").font(.ui(15, .medium)).foregroundStyle(Palette.ink)
                    Text(settings.mcpEnabled ? "Running · localhost only" : "Disabled")
                        .font(.mono(12)).foregroundStyle(settings.mcpEnabled ? Palette.good : Palette.mute)
                }
                Spacer()
                Toggle("", isOn: $settings.mcpEnabled).labelsHidden().toggleStyle(.switch).tint(Palette.accent)
            }
            .padding(Space.lg)
            .card(Palette.surface, radius: Radius.card)

            VStack(alignment: .leading, spacing: 0) {
                Eyebrow(text: "Exposed actions").padding(.bottom, 12)
                settingsCard {
                    ForEach(Array(settings.mcpActions.enumerated()), id: \.element.id) { i, a in
                        HStack(spacing: 14) {
                            Text(a.name).font(.mono(13)).foregroundStyle(Palette.accent).frame(width: 96, alignment: .leading)
                            Text(a.desc).font(.ui(13.5)).foregroundStyle(Palette.body)
                            Spacer()
                            Text(a.enabled && settings.mcpEnabled ? "enabled" : "disabled")
                                .font(.mono(12))
                                .foregroundStyle(a.enabled && settings.mcpEnabled ? Palette.good : Palette.ash)
                        }
                        .padding(.horizontal, 16).frame(minHeight: 52)
                        .opacity(settings.mcpEnabled ? 1 : 0.5)
                        if i < settings.mcpActions.count - 1 {
                            Divider().overlay(Palette.hairline)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - About

struct AboutPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            SettingsHeader(title: "About")
            settingsCard {
                SettingRow(label: "Version", sub: "Vocast 1.0") { Text("build 1").font(.mono(12)).foregroundStyle(Palette.mute) }
                Divider().overlay(Palette.hairline)
                SettingRow(label: "License", sub: "One-time purchase, $49") { EmptyView() }
                Divider().overlay(Palette.hairline)
                SettingRow(label: "Requirements", sub: "macOS 14 or later, Apple Silicon") { EmptyView() }
            }
        }
    }
}
