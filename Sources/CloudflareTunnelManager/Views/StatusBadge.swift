import SwiftUI

/// A small colored status pill (● Running, ● Stopped, …).
struct StatusBadge: View {
    let status: TunnelStatus
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            if status.isBusy {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Circle()
                    .fill(status.color)
                    .frame(width: 7, height: 7)
            }
            if !compact {
                Text(status.label)
                    .font(.caption)
                    .foregroundStyle(status.color)
            }
        }
        .help(status.errorMessage ?? status.label)
    }
}

/// A pill describing the tunnel mode.
struct ModeBadge: View {
    let mode: TunnelMode

    var body: some View {
        Label(mode.shortLabel, systemImage: mode.systemImage)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
    }
}
