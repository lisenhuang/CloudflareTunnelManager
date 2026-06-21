import SwiftUI

/// Compact control panel shown from the menu-bar icon.
struct MenuBarView: View {
    @Environment(AppState.self) private var app
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if app.tunnels.isEmpty {
                Text("No tunnels yet.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .padding(12)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(app.tunnels) { tunnel in
                            MenuBarRow(tunnel: tunnel)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 280)
            }

            Divider()
            footer
        }
        .frame(width: 320)
    }

    private var header: some View {
        HStack {
            Image(systemName: "cloud.fill").foregroundStyle(.tint)
            Text("Cloudflare Tunnels").font(.headline)
            Spacer()
            Text("\(app.runningCount) running")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private var footer: some View {
        HStack {
            Button {
                openMainWindow()
            } label: {
                Label("Open Manager", systemImage: "macwindow")
            }
            Spacer()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
        }
        .buttonStyle(.borderless)
        .padding(12)
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

private struct MenuBarRow: View {
    @Environment(AppState.self) private var app
    @Bindable var tunnel: TunnelItem

    var body: some View {
        HStack(spacing: 8) {
            StatusBadge(status: tunnel.status, compact: true)
            VStack(alignment: .leading, spacing: 1) {
                Text(tunnel.name).font(.callout).lineLimit(1)
                Text(tunnel.displayURL ?? tunnel.localURL)
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if tunnel.displayURL != nil {
                Button { app.copyURL(tunnel) } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless).help("Copy URL")
            }
            Button { app.toggle(tunnel) } label: {
                Image(systemName: tunnel.status.isActive ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.borderless)
            .disabled(tunnel.status.isBusy)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
