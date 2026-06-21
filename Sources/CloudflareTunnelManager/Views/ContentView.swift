import SwiftUI

/// Root window: sidebar list of tunnels + detail pane for the selected one.
struct ContentView: View {
    @Environment(AppState.self) private var app
    @State private var showingCreate = false

    var body: some View {
        NavigationSplitView {
            SidebarView(showingCreate: $showingCreate)
                .frame(minWidth: 260, idealWidth: 300)
        } detail: {
            if let tunnel = app.selectedTunnel {
                TunnelDetailView(tunnel: tunnel)
            } else {
                EmptyDetailView(showingCreate: $showingCreate)
            }
        }
        .sheet(isPresented: $showingCreate) {
            CreateTunnelSheet()
                .environment(app)
        }
    }
}

// MARK: - Sidebar

private struct SidebarView: View {
    @Environment(AppState.self) private var app
    @Binding var showingCreate: Bool

    var body: some View {
        @Bindable var app = app
        VStack(spacing: 0) {
            if !app.isCloudflaredInstalled {
                InstallBanner()
                Divider()
            }

            if app.tunnels.isEmpty {
                ContentUnavailableView {
                    Label("No Tunnels", systemImage: "cloud")
                } description: {
                    Text("Create a tunnel to expose a local service to the internet.")
                } actions: {
                    Button("Create Tunnel") { showingCreate = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List(selection: $app.selectedTunnelID) {
                    ForEach(app.tunnels) { tunnel in
                        TunnelRowView(tunnel: tunnel)
                            .tag(tunnel.id)
                            .contextMenu { rowMenu(for: tunnel) }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .safeAreaInset(edge: .bottom) { footer }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingCreate = true
                } label: {
                    Label("New Tunnel", systemImage: "plus")
                }
                .help("Create a new tunnel")
            }
        }
        .navigationTitle("Tunnels")
    }

    @ViewBuilder
    private func rowMenu(for tunnel: TunnelItem) -> some View {
        Button(tunnel.status.isActive ? "Stop" : "Start") { app.toggle(tunnel) }
        Button("Restart") { app.restart(tunnel) }
        if tunnel.displayURL != nil {
            Button("Copy URL") { app.copyURL(tunnel) }
            Button("Open in Browser") { app.openInBrowser(tunnel) }
        }
        Divider()
        Button("Delete", role: .destructive) { app.delete(tunnel) }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(app.runningCount > 0 ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)
            Text("\(app.runningCount) running · \(app.tunnels.count) total")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

// MARK: - Empty detail

private struct EmptyDetailView: View {
    @Binding var showingCreate: Bool

    var body: some View {
        ContentUnavailableView {
            Label("Select a Tunnel", systemImage: "sidebar.left")
        } description: {
            Text("Pick a tunnel from the list, or create a new one.")
        } actions: {
            Button("Create Tunnel") { showingCreate = true }
                .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Install banner

private struct InstallBanner: View {
    @Environment(AppState.self) private var app

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("cloudflared not found").font(.callout).bold()
                Text("Required to run tunnels.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if app.isHomebrewAvailable {
                Button("Install") { Task { await app.installCloudflared() } }
                    .disabled(app.isInstalling)
            } else {
                Button("Download") { app.openDownloadPage() }
            }
        }
        .padding(10)
        .background(.orange.opacity(0.12))
    }
}
