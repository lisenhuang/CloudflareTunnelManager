import SwiftUI

/// Live, auto-scrolling log viewer for a tunnel (or the global feed if nil).
struct LogsView: View {
    @Environment(AppState.self) private var app
    let tunnelID: UUID?
    @State private var autoScroll = true

    private var lines: [LogLine] { app.logStore.lines(for: tunnelID) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            logBody
        }
    }

    private var header: some View {
        HStack {
            Label("Logs", systemImage: "text.alignleft").font(.callout).bold()
            Spacer()
            Toggle("Auto-scroll", isOn: $autoScroll)
                .toggleStyle(.checkbox)
                .font(.caption)
            Button {
                copyAll()
            } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless)
                .help("Copy all logs")
            Button {
                app.logStore.clear(tunnelID: tunnelID)
            } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Clear logs")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var logBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(lines) { line in
                        LogLineRow(line: line)
                            .id(line.id)
                    }
                    Color.clear.frame(height: 1).id(bottomAnchor)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: lines.count) { _, _ in
                guard autoScroll else { return }
                withAnimation(.linear(duration: 0.1)) {
                    proxy.scrollTo(bottomAnchor, anchor: .bottom)
                }
            }
            .overlay(alignment: .center) {
                if lines.isEmpty {
                    Text("No output yet.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }
        }
    }

    private let bottomAnchor = "logs-bottom-anchor"

    private func copyAll() {
        let text = app.logStore.plainText(for: tunnelID)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}

private struct LogLineRow: View {
    let line: LogLine

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(line.date, format: .dateTime.hour().minute().second())
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(line.text)
                .foregroundStyle(color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(.caption, design: .monospaced))
    }

    private var color: Color {
        switch line.level {
        case .info: return .primary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        case .command: return .blue
        }
    }
}
