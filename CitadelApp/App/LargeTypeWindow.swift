import AppKit
import SwiftUI

/// Shows a password in large monospace type on a dark overlay.
/// Click anywhere or press any key to dismiss. Auto-dismisses after 30 seconds.
@MainActor
final class LargeTypeWindow {

    private var window: NSWindow?
    private var autoDismissTimer: Timer?

    func show(password: String) {
        close()

        let hostingView = NSHostingView(
            rootView: LargeTypeView(password: password) { [weak self] in
                self?.close()
            }
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

        let window = NSWindow(
            contentRect: rect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.contentView = hostingView
        window.center()
        window.makeKeyAndOrderFront(nil)

        self.window = window

        // Auto-dismiss after 30 seconds
        autoDismissTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.close()
            }
        }

        // Key press listener
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in
                self?.close()
            }
            return event
        }
    }

    func close() {
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil
        window?.close()
        window = nil
    }
}

struct LargeTypeView: View {
    let password: String
    let onDismiss: () -> Void

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
        .onTapGesture { onDismiss() }
    }
}
