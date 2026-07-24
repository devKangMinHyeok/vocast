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
                    Text(s.label(app.s))
                        .font(.ui(14, sel ? .semibold : .regular))
                        .foregroundStyle(sel ? Palette.ink : Palette.body)
                        .padding(.horizontal, 12).frame(height: 34)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .fill(sel ? Palette.surfaceElevated : .clear))
                        .fullClickArea()
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
        case .language: LanguagePane()
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
            SettingsHeader(title: app.s["setGeneral"], blurb: app.s["setGeneralBlurb"])
            settingsCard {
                SettingRow(label: app.s["setAppearance"], sub: app.s["setAppearanceSub"]) {
                    Picker("", selection: $settings.appearance) {
                        ForEach(AppearanceChoice.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).fixedSize().labelsHidden()
                }
                Divider().overlay(Palette.hairline)
                SettingRow(label: app.s["setLaunchLogin"]) {
                    Toggle("", isOn: $settings.launchAtLogin).labelsHidden().toggleStyle(.switch).tint(Palette.accent)
                }
                Divider().overlay(Palette.hairline)
                SettingRow(label: app.s["setDefaultProfile"]) {
                    Picker("", selection: $settings.defaultProfile) {
                        // Iterate profiles by their unique id, not by name: two profiles
                        // can share a name, and a ForEach keyed on name would produce
                        // duplicate ids and mis-render.
                        ForEach(app.backendProfiles) { p in Text(p.name).tag(p.name) }
                    }.fixedSize().labelsHidden()
                }
            }
        }
    }
}

// MARK: - Models

struct ModelsPane: View {
    @Environment(AppModel.self) private var app

    private var installed: [String: Bool] { app.modelStatus?.installed ?? [:] }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            SettingsHeader(title: app.s["setModels"], blurb: app.s["setModelsBlurb"])
            settingsCard {
                modelRow(app.s["mdlVoiceFast"], "1.9 GB", installed["tts_fast"] ?? false)
                Divider().overlay(Palette.hairline)
                modelRow(app.s["mdlTranscription"], "1.5 GB", installed["whisper"] ?? false)
                Divider().overlay(Palette.hairline)
                modelRow(app.s["mdlVoiceHighQ"], "2.9 GB", installed["tts_best"] ?? false)
                Divider().overlay(Palette.hairline)
                modelRow(app.s["mdlNoiseRemoval"], app.s["setBundled"], true)
            }

            if let s = app.modelStatus, s.downloading {
                VStack(alignment: .leading, spacing: 8) {
                    ThinProgress(value: s.fraction, height: 6, gradient: true)
                    Text(app.s.f("setDownloadingGB", ["a": String(format: "%.1f", s.downloadedGB), "b": String(format: "%.1f", s.totalGB)]))
                        .font(.mono(12)).foregroundStyle(Palette.mute)
                }
            } else if (installed["tts_best"] ?? false) == false {
                SecondaryButton(title: app.s["setDownloadHighQ"]) {
                    app.downloadModels(tier: "advanced")
                }
            }
        }
        .task { await app.refreshModelStatus() }
    }

    private func modelRow(_ name: String, _ size: String, _ isInstalled: Bool) -> some View {
        SettingRow(label: name, sub: size) {
            HStack(spacing: 7) {
                StatusDot(color: isInstalled ? Palette.good : Palette.ash, size: 7)
                Text(app.s[isInstalled ? "setInstalled" : "dnNotInstalled"])
                    .font(.mono(12)).foregroundStyle(isInstalled ? Palette.good : Palette.ash)
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
            SettingsHeader(title: app.s["setAudio"], blurb: app.s["setAudioBlurb"])
            settingsCard {
                SettingRow(label: app.s["setInputDevice"]) {
                    Picker("", selection: $settings.inputDevice) {
                        Text("MacBook Pro Microphone").tag("MacBook Pro Microphone")
                        Text("External USB microphone").tag("External USB microphone")
                    }.fixedSize().labelsHidden()
                }
                Divider().overlay(Palette.hairline)
                SettingRow(label: app.s["setExportFormat"]) {
                    Picker("", selection: $settings.exportFormat) {
                        // Only formats the engine can actually export (WAV/MP3). M4A was
                        // offered but the export endpoint does not support it.
                        ForEach(["WAV", "MP3"], id: \.self) { Text($0).tag($0) }
                    }.fixedSize().labelsHidden()
                }
                Divider().overlay(Palette.hairline)
                SettingRow(label: app.s["setSampleRate"]) {
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
    @Environment(AppModel.self) private var app
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            SettingsHeader(title: app.s["setPrivacyStatus"],
                           blurb: app.s["setPrivacyBlurb"])
            settingsCard {
                privacyRow(app.s["obPillLocal"], app.s["privSubLocal"])
                Divider().overlay(Palette.hairline)
                privacyRow(app.s["obPillNoUpload"], app.s["privSubNoUpload"])
                Divider().overlay(Palette.hairline)
                privacyRow(app.s["obPillOffline"], app.s["privSubOffline"])
                Divider().overlay(Palette.hairline)
                privacyRow(app.s["privWhereStored"], "~/Library/Application Support/Vocast")
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
            SettingsHeader(title: app.s["setMcp"],
                           blurb: app.s["setMcpBlurb"])

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.s["setMcpEnable"]).font(.ui(15, .medium)).foregroundStyle(Palette.ink)
                    Text(app.s[settings.mcpEnabled ? "mcpRunning" : "mcpDisabled"])
                        .font(.mono(12)).foregroundStyle(settings.mcpEnabled ? Palette.good : Palette.mute)
                }
                Spacer()
                Toggle("", isOn: $settings.mcpEnabled).labelsHidden().toggleStyle(.switch).tint(Palette.accent)
            }
            .padding(Space.lg)
            .card(Palette.surface, radius: Radius.card)

            VStack(alignment: .leading, spacing: 0) {
                Eyebrow(text: app.s["setMcpExposed"]).padding(.bottom, 12)
                settingsCard {
                    if settings.mcpActions.isEmpty {
                        Text(app.s["setMcpEmpty"])
                            .font(.ui(13.5)).foregroundStyle(Palette.ash)
                            .padding(.horizontal, 16).frame(minHeight: 52)
                    }
                    ForEach(Array(settings.mcpActions.enumerated()), id: \.element.id) { i, a in
                        HStack(spacing: 14) {
                            Text(a.name).font(.mono(13)).foregroundStyle(Palette.accent).frame(width: 150, alignment: .leading)
                            Text(a.desc).font(.ui(13.5)).foregroundStyle(Palette.body)
                            Spacer()
                            Text(app.s[settings.mcpEnabled ? "mcpActionEnabled" : "mcpActionDisabled"])
                                .font(.mono(12))
                                .foregroundStyle(settings.mcpEnabled ? Palette.good : Palette.ash)
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
    @Environment(AppModel.self) private var app
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            SettingsHeader(title: app.s["setAbout"])
            settingsCard {
                SettingRow(label: app.s["setAbtVersion"], sub: "Vocast 1.0") { Text("build 1").font(.mono(12)).foregroundStyle(Palette.mute) }
                Divider().overlay(Palette.hairline)
                SettingRow(label: app.s["setAbtLicense"], sub: app.s["setAbtLicenseValue"]) { EmptyView() }
                Divider().overlay(Palette.hairline)
                SettingRow(label: app.s["setAbtRequirements"], sub: app.s["setAbtRequirementsValue"]) { EmptyView() }
            }
        }
    }
}

// MARK: - Language
//
// Two rows that say the same thing from opposite directions: this is where the
// interface language lives, and this is not where voice languages live. The blue
// panel states the guarantee outright, because "will this rewrite my voices?" is
// the question a language switch raises.

struct LanguagePane: View {
    @Environment(AppModel.self) private var app
    private var s: Strings { app.s }

    var body: some View {
        @Bindable var model = app
        VStack(alignment: .leading, spacing: Space.xl) {
            SettingsHeader(title: s["setLangTitle"], blurb: s["setLangBlurb"])

            VStack(alignment: .leading, spacing: 10) {
                settingsCard {
                    SettingRow(label: s["interfaceLanguage"], sub: s["interfaceLangDetail"]) {
                        Picker("", selection: $model.interfaceLanguage) {
                            ForEach(InterfaceLanguage.allCases) { l in
                                Text(l.nativeName).tag(l)
                            }
                        }
                        .pickerStyle(.segmented).fixedSize().labelsHidden()
                    }
                }
                HStack(spacing: 7) {
                    StatusDot(color: Palette.good, size: 7)
                    Text(s["applyNow"]).font(.mono(12)).foregroundStyle(Palette.good)
                }
                .padding(.leading, 2)
            }

            // Dimmed on purpose: it is here to point elsewhere, not to be used.
            settingsCard {
                SettingRow(label: s["voiceLangSetting"], sub: s["voiceLangSettingDetail"]) {
                    SecondaryButton(title: s["nVoices"]) { app.area = .voices }
                }
            }
            .opacity(0.85)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle")
                    .font(.system(size: 13)).foregroundStyle(Palette.accentBlue)
                Text(s["guaranteeNote"]).font(.ui(13)).foregroundStyle(Palette.body)
                    .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Palette.accentBlue.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(Palette.accentBlue.opacity(0.3), lineWidth: 1))
        }
    }
}
