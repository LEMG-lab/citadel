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
}

// MARK: - App

@main
struct CitadelApplication: App {
    @State private var appState = AppState()
    @FocusedValue(\.appState) private var focusedAppState

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("Citadel") {
            ContentView()
                .environment(appState)
                .focusedValue(\.appState, appState)
                .background(WindowConfigurator())
        }
        .defaultSize(width: 800, height: 600)
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

        // App settings
        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                NotificationCenter.default.post(name: .citadelShowSettings, object: nil)
            }
            .keyboardShortcut(",")
            .disabled(appState?.isLocked ?? true)
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
            }
            WindowSecurity.startMonitoringNewWindows()
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
