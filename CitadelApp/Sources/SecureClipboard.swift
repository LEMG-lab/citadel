import AppKit
import Foundation

/// Secure clipboard manager that auto-clears passwords after a timeout.
///
/// - Copies password as UTF-8 string to `NSPasteboard`
/// - Sets ConcealedType/TransientType to signal clipboard managers
/// - Auto-clears after 15 seconds (only if the pasteboard still holds our data)
/// - Clears on deinit and app termination
@MainActor
public final class SecureClipboard {

    /// Default duration before auto-clearing the clipboard.
    public static let defaultClearInterval: TimeInterval = 15.0

    /// Duration before auto-clearing the clipboard.
    public var clearInterval: TimeInterval = defaultClearInterval

    /// Pasteboard types that signal sensitive content to clipboard managers.
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    /// The changeCount from our last write, used to detect if
    /// another app has since written to the pasteboard.
    private var trackedChangeCount: Int = 0

    /// Timer for auto-clear.
    /// nonisolated(unsafe) allows access from deinit, which is nonisolated in Swift 6.
    /// Safe because deinit has exclusive access to the instance.
    nonisolated(unsafe) private var clearTimer: Timer?

    /// Observer for app termination.
    nonisolated(unsafe) private var terminationObserver: (any NSObjectProtocol)?

    public init() {
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.forceClear()
            }
        }
    }

    deinit {
        clearTimer?.invalidate()
        if let obs = terminationObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        NSPasteboard.general.clearContents()
    }

    /// Copy password bytes to the general pasteboard as a UTF-8 string.
    /// Sets concealed/transient types so clipboard managers ignore the entry.
    /// Starts a 15-second auto-clear timer.
    public func copyPassword(_ password: Data) {
        let pb = NSPasteboard.general
        pb.clearContents()

        let item = NSPasteboardItem()
        // Signal clipboard managers that this is sensitive, transient content
        item.setString("", forType: Self.concealedType)
        item.setString("", forType: Self.transientType)
        // Set the password as a UTF-8 string
        item.setString(String(decoding: password, as: UTF8.self), forType: .string)
        pb.writeObjects([item])

        trackedChangeCount = pb.changeCount

        // Cancel any existing timer and start a new one.
        // Use .common mode so the timer fires during modal dialogs and menu tracking.
        clearTimer?.invalidate()
        let timer = Timer(timeInterval: clearInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.autoClear()
            }
        }
        RunLoop.current.add(timer, forMode: .common)
        clearTimer = timer
    }

    /// Copy a non-password string (username, URL, custom field) with concealment markers
    /// and auto-clear after the configured interval.
    public func copySecure(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()

        let item = NSPasteboardItem()
        item.setString("", forType: Self.concealedType)
        item.setString("", forType: Self.transientType)
        item.setString(text, forType: .string)
        pb.writeObjects([item])

        trackedChangeCount = pb.changeCount

        clearTimer?.invalidate()
        let timer = Timer(timeInterval: clearInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.autoClear()
            }
        }
        RunLoop.current.add(timer, forMode: .common)
        clearTimer = timer
    }

    /// Clear the clipboard only if it still contains what we put there.
    private func autoClear() {
        let pb = NSPasteboard.general
        if pb.changeCount == trackedChangeCount {
            pb.clearContents()
        }
        clearTimer?.invalidate()
        clearTimer = nil
        trackedChangeCount = 0
    }

    /// Unconditionally clear the clipboard.
    /// Call on lock, quit, or when the vault is closed.
    public func forceClear() {
        clearTimer?.invalidate()
        clearTimer = nil
        NSPasteboard.general.clearContents()
        trackedChangeCount = 0
    }
}
