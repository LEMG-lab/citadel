import AppKit

/// Window security configuration for the vault UI.
///
/// - Sets `sharingType = .none` to prevent screenshots and screen sharing
/// - Ensures no sensitive data appears in window titles
public enum WindowSecurity {

    /// Apply security settings to a window.
    /// Call this in the window's lifecycle (e.g., `onAppear` or `NSWindowDelegate`).
    @MainActor
    public static func apply(to window: NSWindow) {
        // Prevent screen capture, screen sharing, and AirPlay mirroring
        // from seeing window content.
        window.sharingType = .none

        // Use a generic title that reveals nothing about vault contents.
        window.title = "Citadel"
    }
}
