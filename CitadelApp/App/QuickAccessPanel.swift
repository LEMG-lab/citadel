import AppKit
import Carbon
import SwiftUI
import CitadelCore

// MARK: - Carbon Hotkey Handler

/// Singleton that bridges Carbon hotkey events to QuickAccessPanel.
/// Carbon RegisterEventHotKey is the only reliable way to register a system-wide
/// hotkey without addGlobalMonitorForEvents (which causes code signature issues).
private final class HotkeyHandler: @unchecked Sendable {
    static let shared = HotkeyHandler()
    private var hotkeyRef: EventHotKeyRef?
    var callback: (() -> Void)?

    func register() {
        // Already registered
        guard hotkeyRef == nil else { return }

        // Cmd+Shift+Space: keyCode 49 = Space
        let hotkeyID = EventHotKeyID(signature: OSType(0x43544431) /* CTD1 */, id: 1)
        let modifiers: UInt32 = UInt32(cmdKey | shiftKey)

        // Install Carbon event handler
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, event, _) -> OSStatus in
            HotkeyHandler.shared.callback?()
            return noErr
        }, 1, &eventType, nil, nil)

        let status = RegisterEventHotKey(49, modifiers, hotkeyID, GetApplicationEventTarget(), 0, &hotkeyRef)
        if status != noErr {
            print("QUICK ACCESS: Carbon hotkey registration failed: \(status)")
        } else {
            print("QUICK ACCESS: Carbon hotkey registered (Cmd+Shift+Space)")
        }
    }

    func unregister() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
        callback = nil
    }
}

// MARK: - Quick Access Panel

/// Global quick-access search panel (Cmd+Shift+Space).
/// Floating NSPanel that fuzzy-searches vault entries and copies credentials.
@MainActor
final class QuickAccessPanel {

    private var panel: NSPanel?
    private var localMonitor: Any?
    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    func registerGlobalShortcut() {
        // Carbon hotkey for system-wide Cmd+Shift+Space
        HotkeyHandler.shared.callback = { [weak self] in
            Task { @MainActor in
                self?.toggle()
            }
        }
        HotkeyHandler.shared.register()

        // Local monitor for when app is active (catches the keyDown before Carbon)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.contains([.command, .shift]),
                  event.keyCode == 49 else { return event }
            Task { @MainActor in
                self?.toggle()
            }
            return nil
        }
    }

    func toggle() {
        if let panel, panel.isVisible {
            close()
        } else {
            open()
        }
    }

    func open() {
        guard let appState, !appState.isLocked else { return }

        let hostingView = NSHostingView(
            rootView: QuickAccessView(appState: appState) { [weak self] in
                self?.close()
            }
        )

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.contentView = hostingView
        panel.center()
        panel.makeKeyAndOrderFront(nil)

        NSApplication.shared.activate(ignoringOtherApps: true)

        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }

    func tearDown() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        HotkeyHandler.shared.unregister()
        close()
    }
}

/// SwiftUI view for the quick access search panel.
struct QuickAccessView: View {
    let appState: AppState
    let onDismiss: () -> Void

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var results: [VaultEntrySummary] {
        guard !query.isEmpty else {
            return Array(appState.entries.prefix(10))
        }
        return appState.entries
            .compactMap { entry -> (entry: VaultEntrySummary, score: Int)? in
                let result = FuzzyMatch.bestMatch(
                    query: query,
                    fields: [entry.title, entry.username, entry.url]
                )
                guard result.score > 0 else { return nil }
                return (entry, result.score)
            }
            .sorted { $0.score > $1.score }
            .prefix(10)
            .map(\.entry)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("Search vault entries\u{2026}", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($searchFocused)

                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(Color.fieldBackground)

            Divider()

            // Results
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results) { entry in
                        quickResultRow(entry)
                    }
                }
            }
            .frame(maxHeight: 340)

            if !results.isEmpty {
                Divider()
                HStack(spacing: 16) {
                    Text("Enter: copy password")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("\u{2318}Enter: copy username")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("Esc: close")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
        }
        .frame(width: 520)
        .background(Color.contentBackground)
        .onAppear { searchFocused = true }
        .onExitCommand { onDismiss() }
    }

    @ViewBuilder
    private func quickResultRow(_ entry: VaultEntrySummary) -> some View {
        Button {
            copyPassword(entry)
        } label: {
            HStack(spacing: 10) {
                EntryIcon(title: entry.title, entryType: entry.entryType, size: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title.isEmpty ? "(Untitled)" : entry.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if !entry.username.isEmpty {
                        Text(entry.username)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if let host = URL(string: entry.url)?.host {
                    Text(host)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.clear)
    }

    private func copyPassword(_ entry: VaultEntrySummary) {
        guard let detail = try? appState.engine.getEntry(uuid: entry.id) else { return }
        appState.clipboard.copyPassword(detail.password)
        onDismiss()
    }
}
