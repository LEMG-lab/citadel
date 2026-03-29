import SwiftUI

/// Top-level view that switches between lock screen and main vault UI.
struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var showCloudWarning = false

    var body: some View {
        Group {
            if appState.isLocked {
                LockScreenView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                MainView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: appState.isLocked)
        .onAppear {
            if appState.cloudSyncWarning != nil {
                showCloudWarning = true
            }
        }
        .alert("Cloud Sync Detected", isPresented: $showCloudWarning) {
            Button("I Understand") {
                appState.cloudSyncWarning = nil
            }
        } message: {
            Text(appState.cloudSyncWarning ?? "")
        }
    }
}
