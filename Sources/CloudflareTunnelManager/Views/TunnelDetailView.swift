import SwiftUI

/// Detail pane: controls, metadata, and live logs for one tunnel.
struct TunnelDetailView: View {
    @Environment(AppState.self) private var app
    @Bindable var tunnel: TunnelItem
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            infoGrid
                .padding(16)
            Divider()
            LogsView(tunnelID: tunnel.id)
        }
        .navigationTitle(tunnel.name)
        .navigationSubtitle(tunnel.status.label)
        .toolbar { toolbarContent }
        .confirmationDialog("Delete “\(tunnel.name)”?", isPresented: $showDeleteConfirm) {
            Button("Delete Tunnel", role: .destructive) { app.delete(tunnel) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(tunnel.mode == .named
                 ? "This also attempts to remove the tunnel from your Cloudflare account."
                 : "This removes the tunnel from the app.")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: tunnel.mode.systemImage)
                .font(.title)
                .foregroundStyle(.tint)
                .frame(width: 38)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(tunnel.name).font(.title2).bold()
                    ModeBadge(mode: tunnel.mode)
                }
                StatusBadge(status: tunnel.status)
            }
            Spacer()
            controlButtons
        }
        .padding(16)
    }

    private var controlButtons: some View {
        HStack(spacing: 8) {
            if tunnel.status.isActive {
                Button {
                    app.stop(tunnel)
                } label: { Label("Stop", systemImage: "stop.fill") }
                .disabled(tunnel.status.isBusy)
            } else {
                Button {
                    app.start(tunnel)
                } label: { Label("Start", systemImage: "play.fill") }
                .buttonStyle(.borderedProminent)
                .disabled(!app.isCloudflaredInstalled)
            }
            Button {
                app.restart(tunnel)
            } label: { Label("Restart", systemImage: "arrow.clockwise") }
            .disabled(!app.isCloudflaredInstalled)
        }
    }

    // MARK: Info grid

    private var infoGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
            GridRow {
                Text("Public URL").gridLabel()
                publicURLRow
            }
            GridRow {
                Text("Local Target").gridLabel()
                Text(tunnel.localURL).textSelection(.enabled)
            }
            if tunnel.mode == .named, let host = tunnel.hostname {
                GridRow {
                    Text("Hostname").gridLabel()
                    Text(host).textSelection(.enabled)
                }
            }
            if let cfID = tunnel.cfTunnelID {
                GridRow {
                    Text("Tunnel ID").gridLabel()
                    Text(cfID).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            GridRow {
                Text("Auto-restart").gridLabel()
                Toggle("Restart automatically if it crashes", isOn: $tunnel.autoRestart)
                    .onChange(of: tunnel.autoRestart) { _, _ in app.persistTunnels() }
            }
            if let error = tunnel.status.errorMessage ?? tunnel.lastError {
                GridRow {
                    Text("Last Error").gridLabel()
                    Text(error).foregroundStyle(.red).font(.callout)
                }
            }
        }
    }

    @ViewBuilder
    private var publicURLRow: some View {
        if let url = tunnel.displayURL {
            HStack(spacing: 8) {
                Text(url)
                    .foregroundStyle(.tint)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button { app.copyURL(tunnel) } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless).help("Copy URL")
                Button { app.openInBrowser(tunnel) } label: { Image(systemName: "arrow.up.right.square") }
                    .buttonStyle(.borderless).help("Open in browser")
            }
        } else {
            Text(tunnel.status.isActive ? "Waiting for URL…" : "Not assigned yet")
                .foregroundStyle(.secondary)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .destructiveAction) {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

private extension Text {
    func gridLabel() -> some View {
        self.foregroundStyle(.secondary)
            .font(.callout)
            .gridColumnAlignment(.trailing)
    }
}
