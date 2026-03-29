import SwiftUI

/// Top-level view that switches between lock screen and main vault UI.
struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var showCloudWarning = false

    var body: some View {
        Group {
            if appState.isLocked {
                LockScreenView()
            } else {
                MainView()
            }
        }
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
