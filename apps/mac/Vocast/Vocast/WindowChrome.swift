import SwiftUI
import AppKit

/// Configures the window so the native unified toolbar raises the titlebar height
/// (which vertically centers the traffic lights on the same row as the custom top bar),
/// while `fullSizeContentView` lets the app content render underneath the transparent
/// toolbar. Paired with a transparent, height-forcing `.toolbar` item on the root view.
struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        context.coordinator.host = v
        DispatchQueue.main.async { context.coordinator.configure() }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { context.coordinator.configure() }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        weak var host: NSView?
        weak var window: NSWindow?

        func configure() {
            guard let window = host?.window, self.window !== window else { return }
            self.window = window
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.toolbar?.showsBaselineSeparator = false
        }
    }
}
