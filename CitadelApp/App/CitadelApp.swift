import SwiftUI
import CitadelCore

// MARK: - FocusedValue for keyboard shortcuts

struct FocusedAppStateKey: FocusedValueKey {
    typealias Value = AppState
}

extension FocusedValues {
    var appState: AppState? {
        get { self[FocusedAppStateKey.self] }
        set { self[FocusedAppStateKey.self] = newValue }
    }
}

// MARK: - Notifications for command actions

extension Notification.Name {
    static let citadelNewEntry = Notification.Name("citadelNewEntry")
    static let citadelShowSettings = Notification.Name("citadelShowSettings")
    static let citadelCopyPassword = Notification.Name("citadelCopyPassword")
    static let citadelCopyUsername = Notification.Name("citadelCopyUsername")
    static let citadelOpenEmergency = Notification.Name("citadelOpenEmergency")
}

// MARK: - Appearance environment key

struct AppearanceModeKey: EnvironmentKey {
    static let defaultValue: Binding<AppearanceMode> = .constant(.system)
}

extension EnvironmentValues {
    var appearanceMode: Binding<AppearanceMode> {
        get { self[AppearanceModeKey.self] }
        set { self[AppearanceModeKey.self] = newValue }
    }
}

// MARK: - App

@main
struct CitadelApplication: App {
    @State private var appState = AppState()
    @State private var appearanceMode: AppearanceMode = .saved
    @FocusedValue(\.appState) private var focusedAppState

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("Citadel") {
            ContentView()
                .environment(appState)
                .environment(\.appearanceMode, $appearanceMode)
                .focusedValue(\.appState, appState)
                .tint(.citadelAccent)
                .preferredColorScheme(appearanceMode.colorScheme)
                .background(WindowConfigurator())
        }
        .defaultSize(width: 1100, height: 700)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .commands {
            CitadelCommands()
        }
    }
}

// MARK: - Commands (keyboard shortcuts)

struct CitadelCommands: Commands {
    @FocusedValue(\.appState) private var appState

    var body: some Commands {
        // Replace "New" with "New Entry"
        CommandGroup(replacing: .newItem) {
            Button("New Entry") {
                NotificationCenter.default.post(name: .citadelNewEntry, object: nil)
            }
            .keyboardShortcut("n")
            .disabled(appState?.isLocked ?? true)
        }

        // File > Open Emergency File
        CommandGroup(after: .newItem) {
            Divider()
            Button("Open Emergency File\u{2026}") {
                NotificationCenter.default.post(name: .citadelOpenEmergency, object: nil)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
        }

        // App settings
        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                NotificationCenter.default.post(name: .citadelShowSettings, object: nil)
            }
            .keyboardShortcut(",")
            .disabled(appState?.isLocked ?? true)
        }

        // Help menu
        CommandGroup(replacing: .help) {
            Button("Citadel User Guide") {
                let guideURL: URL
                // Check repo location first, then bundle
                let repoPath = (ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory())
                    + "/Projects/citadel/GUIDE.md"
                if FileManager.default.fileExists(atPath: repoPath) {
                    guideURL = URL(fileURLWithPath: repoPath)
                } else {
                    let bundlePath = Bundle.main.bundlePath
                    let appSupport = (bundlePath as NSString).deletingLastPathComponent
                    let fallback = (appSupport as NSString).appendingPathComponent("GUIDE.md")
                    guideURL = URL(fileURLWithPath: fallback)
                }
                NSWorkspace.shared.open(guideURL)
            }
            .keyboardShortcut("?", modifiers: [.command])
        }

        // Custom commands
        CommandMenu("Vault") {
            Button("Lock Vault") {
                appState?.lockVault()
            }
            .keyboardShortcut("l")
            .disabled(appState?.isLocked ?? true)

            Divider()

            Button("Copy Password") {
                NotificationCenter.default.post(name: .citadelCopyPassword, object: nil)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(appState?.isLocked ?? true || appState?.selectedEntryID == nil)

            Button("Copy Username") {
                NotificationCenter.default.post(name: .citadelCopyUsername, object: nil)
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
            .disabled(appState?.isLocked ?? true || appState?.selectedEntryID == nil)
        }
    }
}

// MARK: - Window configurator

/// Applies WindowSecurity settings to the NSWindow backing the SwiftUI view
/// and monitors for new windows (sheets, dialogs) to secure them too.
private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                WindowSecurity.apply(to: window)
                window.minSize = NSSize(width: 900, height: 600)
            }
            WindowSecurity.startMonitoringNewWindows()
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
