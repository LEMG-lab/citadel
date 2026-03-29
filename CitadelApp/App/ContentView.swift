import SwiftUI

/// Top-level view that switches between lock screen and main vault UI.
struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.isLocked {
                LockScreenView()
            } else {
                MainView()
            }
        }
    }
}
