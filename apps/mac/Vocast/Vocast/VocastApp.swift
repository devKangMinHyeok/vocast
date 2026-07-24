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
            Button(app.s["menuNewNarration"]) { app.area = .studio; app.primaryAction() }
                .keyboardShortcut("n", modifiers: .command)
            Button(app.s["menuNewVoice"]) { app.area = .voices; app.startNewVoice() }
                .keyboardShortcut("v", modifiers: [.command, .option])
        }

        // App settings (Cmd ,)
        CommandGroup(replacing: .appSettings) {
            Button(app.s["menuSettings"]) { app.area = .settings }
                .keyboardShortcut(",", modifiers: .command)
        }

        // Voice menu
        CommandMenu(app.s["menuGroupVoice"]) {
            Button(app.s["menuNewVoice"]) { app.area = .voices; app.startNewVoice() }
                .keyboardShortcut("v", modifiers: [.command, .option])
            Button(app.s["menuImportToClean"]) { app.area = .denoise; app.denoise.phase = .importEmpty }
        }

        // Render menu
        CommandMenu(app.s["menuRender"]) {
            Button(app.s["menuRenderNarration"]) { app.area = .studio; app.renderNarration() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(app.studio.scriptText.isEmpty)
            Button(app.s["menuRegenerateBlock"]) {
                if let id = app.studio.selectedBlockID { app.regenerateBlock(id) }
            }
            .keyboardShortcut("r", modifiers: .command)
            Divider()
            Button(app.studio.playing ? app.s["menuPause"] : app.s["menuPlay"]) { app.studio.playing.toggle() }
                .keyboardShortcut(.space, modifiers: [])
        }

        // View menu: inspector toggle. (A global search command was removed here: it
        // was wired to a no-op and there is no search surface for it to drive yet.)
        CommandGroup(after: .sidebar) {
            Button(app.s["menuToggleInspector"]) { app.inspectorVisible.toggle() }
                .keyboardShortcut("i", modifiers: .command)
        }
    }
}
