import SwiftUI

@main
struct CloudflareTunnelManagerApp: App {
    @State private var app = AppState()

    var body: some Scene {
        // Main control-panel window.
        WindowGroup("Cloudflare Tunnel Manager") {
            ContentView()
                .environment(app)
                .frame(minWidth: 820, minHeight: 520)
                .task { await app.bootstrap() }
                .onDisappear { app.shutdown() }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}  // no document "New" menu
        }

        // Menu-bar control for an always-running dev tool.
        MenuBarExtra("Cloudflare Tunnels", systemImage: "cloud.fill") {
            MenuBarView()
                .environment(app)
        }
        .menuBarExtraStyle(.window)

        // Settings window (⌘,).
        Settings {
            SettingsView()
                .environment(app)
        }
    }
}
