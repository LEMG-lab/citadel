import SwiftUI
import CitadelCore

@main
struct CitadelApplication: App {
    @State private var appState = AppState()

    init() {
        // This executable is an SPM .executableTarget, not a bundled .app,
        // so macOS defaults to a background activation policy.  Without
        // .regular the process never becomes the frontmost app and the
        // window server won't deliver key events — every keystroke beeps.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("Citadel") {
            ContentView()
                .environment(appState)
                .background(WindowConfigurator())
        }
        .defaultSize(width: 800, height: 600)
        .restorationBehavior(.disabled)
    }
}

/// Applies WindowSecurity settings to the NSWindow backing the SwiftUI view.
private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                WindowSecurity.apply(to: window)
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
