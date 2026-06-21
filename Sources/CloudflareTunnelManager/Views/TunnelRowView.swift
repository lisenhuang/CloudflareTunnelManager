import SwiftUI

/// One row in the sidebar tunnel list.
struct TunnelRowView: View {
    @Environment(AppState.self) private var app
    @Bindable var tunnel: TunnelItem

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(tunnel.name)
                        .font(.body)
                        .lineLimit(1)
                    ModeBadge(mode: tunnel.mode)
                }
                Text(tunnel.displayURL ?? tunnel.localURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                StatusBadge(status: tunnel.status)
            }
            Spacer()
            Button {
                app.toggle(tunnel)
            } label: {
                Image(systemName: tunnel.status.isActive ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.borderless)
            .disabled(tunnel.status.isBusy)
            .help(tunnel.status.isActive ? "Stop" : "Start")
        }
        .padding(.vertical, 4)
    }
}
