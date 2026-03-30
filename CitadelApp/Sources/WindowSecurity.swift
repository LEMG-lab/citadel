import AppKit

/// Window security configuration for the vault UI.
///
/// - Sets `sharingType = .none` to prevent screenshots and screen sharing
/// - Ensures no sensitive data appears in window titles
/// - Monitors for new windows (sheets, dialogs) and secures them automatically
@MainActor
public enum WindowSecurity {

    private nonisolated(unsafe) static var observer: NSObjectProtocol?

    /// Apply security settings to a window.
    public static func apply(to window: NSWindow) {
        window.sharingType = .none
        window.title = "Smaug"
    }

    /// Monitor for new windows (sheets, password generator, etc.) and apply
    /// sharingType = .none to all of them. SwiftUI sheets create separate
    /// NSWindow instances that don't inherit the parent's sharingType.
    public static func startMonitoringNewWindows() {
        guard observer == nil else { return }

        // Secure all existing windows first
        for window in NSApplication.shared.windows {
            window.sharingType = .none
        }

        // Watch for new windows becoming visible
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow else { return }
            DispatchQueue.main.async {
                window.sharingType = .none
            }
        }
    }
}
