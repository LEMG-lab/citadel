import AppKit
import SwiftUI

/// Shows a password in large monospace type on a dark overlay.
/// Click anywhere or press any key to dismiss. Auto-dismisses after 30 seconds.
@MainActor
final class LargeTypeWindow {

    private var panel: NSPanel?
    private var autoDismissTimer: Timer?
    private var localMonitor: Any?

    func show(password: String) {
        close()

        let hostingView = NSHostingView(
            rootView: LargeTypeView(password: password)
        )

        guard let screen = NSScreen.main else { return }
        let width = min(password.count * 50 + 120, Int(screen.frame.width) - 100)
        let height = 180
        let rect = NSRect(
            x: (Int(screen.frame.width) - width) / 2,
            y: (Int(screen.frame.height) - height) / 2,
            width: width,
            height: height
        )

        let panel = NSPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.sharingType = .none
        panel.contentView = hostingView
        panel.center()
        panel.orderFrontRegardless()

        self.panel = panel

        // Auto-dismiss after 10 seconds
        autoDismissTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.close()
            }
        }

        // Local monitor: key/click within app dismisses
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            DispatchQueue.main.async { [weak self] in
                self?.close()
            }
            return event
        }
    }

    func close() {
        guard panel != nil else { return }

        autoDismissTimer?.invalidate()
        autoDismissTimer = nil

        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }

        panel?.orderOut(nil)
        panel = nil
    }
}

struct LargeTypeView: View {
    let password: String

    var body: some View {
        VStack(spacing: 16) {
            Text(password)
                .font(.system(size: 72, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.3)
                .padding(.horizontal, 40)

            Text("Click or press any key to dismiss")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.black.opacity(0.9))
        )
    }
}
