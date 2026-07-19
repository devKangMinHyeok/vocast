import SwiftUI

@main
struct VocastApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .frame(minWidth: 1040, minHeight: 680)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1280, height: 832)
        .commands { VocastCommands(app: app) }
    }
}

struct VocastCommands: Commands {
    var app: AppModel

    var body: some Commands {
        // File / new
        CommandGroup(replacing: .newItem) {
            Button("New narration") { app.area = .studio; app.primaryAction() }
                .keyboardShortcut("n", modifiers: .command)
            Button("New voice") { app.area = .voices; app.voices.startFlow() }
                .keyboardShortcut("v", modifiers: [.command, .option])
        }

        // App settings (Cmd ,)
        CommandGroup(replacing: .appSettings) {
            Button("Settings") { app.area = .settings }
                .keyboardShortcut(",", modifiers: .command)
        }

        // Voice menu
        CommandMenu("Voice") {
            Button("New voice") { app.area = .voices; app.voices.startFlow() }
                .keyboardShortcut("v", modifiers: [.command, .option])
            Button("Import audio to clean") { app.area = .denoise; app.denoise.phase = .importEmpty }
        }

        // Render menu
        CommandMenu("Render") {
            Button("Render narration") { app.area = .studio; app.renderNarration() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(app.studio.scriptText.isEmpty)
            Button("Regenerate block") {
                if let id = app.studio.selectedBlockID { app.regenerateBlock(id) }
            }
            .keyboardShortcut("r", modifiers: .command)
            Divider()
            Button(app.studio.playing ? "Pause" : "Play") { app.studio.playing.toggle() }
                .keyboardShortcut(.space, modifiers: [])
        }

        // View menu: inspector + search
        CommandGroup(after: .sidebar) {
            Button("Toggle inspector") { app.inspectorVisible.toggle() }
                .keyboardShortcut("i", modifiers: .command)
            Button("Search") { app.area = app.area }
                .keyboardShortcut("k", modifiers: .command)
        }
    }
}
