import AppKit
import Foundation

/// Manages automatic vault locking on inactivity and system events.
///
/// Monitors:
/// - User inactivity (default 5 minutes, configurable)
/// - App losing focus (`didResignActiveNotification`) — prevents Mission Control thumbnail exposure
/// - System sleep (`willSleepNotification`)
/// - Fast user switch (`sessionDidResignActiveNotification`)
/// - Screen saver activation (`screensaversDidBecomeActiveNotification`)
///
/// On lock: calls the provided `lockAction` closure which should:
/// - Call `vault_close` via VaultEngine
/// - Clear all view model data
/// - Clear clipboard
/// - Show the lock screen
@MainActor
public final class AutoLockManager {

    /// Default inactivity timeout.
    public static let defaultTimeout: TimeInterval = 300 // 5 minutes

    /// Current inactivity timeout.
    public var timeout: TimeInterval {
        didSet { resetInactivityTimer() }
    }

    /// Called when the vault should be locked.
    private let lockAction: @MainActor () -> Void

    private var inactivityTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var eventMonitor: Any?

    /// Create an auto-lock manager.
    ///
    /// - Parameters:
    ///   - timeout: Inactivity timeout in seconds (default 5 minutes).
    ///   - lockAction: Closure to execute when the vault should be locked.
    public init(timeout: TimeInterval = defaultTimeout, lockAction: @MainActor @escaping () -> Void) {
        self.timeout = timeout
        self.lockAction = lockAction
    }

    /// Start monitoring for lock triggers.
    public func start() {
        let ws = NSWorkspace.shared.notificationCenter

        observers.append(
            ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) {
                [weak self] _ in
                Task { @MainActor in self?.lock() }
            }
        )
        observers.append(
            ws.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) {
                [weak self] _ in
                Task { @MainActor in self?.lock() }
            }
        )

        // Screen saver activation — distributed notification from the system.
        let dc = DistributedNotificationCenter.default()
        observers.append(
            dc.addObserver(forName: .init("com.apple.screensaver.didstart"), object: nil, queue: .main) {
                [weak self] _ in
                Task { @MainActor in self?.lock() }
            }
        )

        // Lock immediately when the app loses focus (Mission Control, Cmd+Tab,
        // clicking another window). This ensures the lock screen is visible in
        // Mission Control thumbnails — sharingType alone does not prevent the
        // WindowServer from compositing vault content into thumbnails.
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.lock() }
            }
        )

        // Global event monitor for user activity tracking
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel, .mouseMoved]
        ) { [weak self] _ in
            Task { @MainActor in self?.recordActivity() }
        }

        resetInactivityTimer()
    }

    /// Stop monitoring and invalidate timers.
    public func stop() {
        inactivityTimer?.invalidate()
        inactivityTimer = nil
        let ws = NSWorkspace.shared.notificationCenter
        let dc = DistributedNotificationCenter.default()
        let nc = NotificationCenter.default
        for observer in observers {
            ws.removeObserver(observer)
            dc.removeObserver(observer)
            nc.removeObserver(observer)
        }
        observers.removeAll()
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    /// Call this on any user interaction to reset the inactivity timer.
    public func recordActivity() {
        resetInactivityTimer()
    }

    /// Trigger a lock immediately.
    public func lock() {
        inactivityTimer?.invalidate()
        inactivityTimer = nil
        lockAction()
    }

    // MARK: - Internal

    private func resetInactivityTimer() {
        inactivityTimer?.invalidate()
        inactivityTimer = Timer.scheduledTimer(
            withTimeInterval: timeout,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in self?.lock() }
        }
    }
}
