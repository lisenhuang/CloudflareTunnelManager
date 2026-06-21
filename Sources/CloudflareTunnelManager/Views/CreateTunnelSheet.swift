import SwiftUI

/// Modal for creating a Quick or Named tunnel.
struct CreateTunnelSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var mode: TunnelMode = .quick
    @State private var name = ""
    @State private var localInput = ""
    @State private var hostnameInput = ""
    @State private var startNow = true
    @State private var isCreating = false
    @State private var errorText: String?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case name, local, hostname }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("New Tunnel").font(.title2).bold().padding([.horizontal, .top], 20)

            Picker("Mode", selection: $mode) {
                ForEach(TunnelMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Text(mode.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 6)

            Form {
                TextField("Name (optional)", text: $name, prompt: Text(defaultName))
                    .focused($focusedField, equals: .name)

                TextField("Local target", text: $localInput, prompt: Text("3000 or http://localhost:3000"))
                    .help("A port, host:port, or full URL of your local service.")
                    .focused($focusedField, equals: .local)
                // Always render this preview row. If it were conditional, inserting/
                // removing a sibling next to the focused TextField (when `localInput`
                // toggles empty↔non-empty) tears down the field's NSTextField on macOS
                // and drops first-responder — which made the field reject typed input.
                Text(TunnelInputParsing.normalizeLocalURL(localInput).map { "→ \($0)" } ?? " ")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if mode == .named {
                    TextField("Public hostname", text: $hostnameInput, prompt: Text("app.dev.example.com"))
                        .help("A hostname on a domain you've added to Cloudflare.")
                        .focused($focusedField, equals: .hostname)
                    if !app.hasAPIToken {
                        Label("Add a Cloudflare API token in Settings → Account first.",
                              systemImage: "key.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Toggle("Start immediately", isOn: $startNow)
            }
            .formStyle(.grouped)

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
            }

            Divider()
            HStack {
                if isCreating { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid || isCreating)
            }
            .padding(16)
        }
        .frame(width: 460)
        .onAppear(perform: applyDefaults)
    }

    // MARK: Logic

    private var defaultName: String {
        switch mode {
        case .quick: return "Quick Tunnel"
        case .named: return hostnameInput.isEmpty ? "Named Tunnel" : hostnameInput
        }
    }

    private var isValid: Bool {
        guard TunnelInputParsing.normalizeLocalURL(localInput) != nil else { return false }
        switch mode {
        case .quick:
            return true
        case .named:
            return app.hasAPIToken && TunnelInputParsing.isValidHostname(hostnameInput)
        }
    }

    private func applyDefaults() {
        if localInput.isEmpty { localInput = String(app.settings.defaultLocalPort) }
        if hostnameInput.isEmpty, !app.settings.defaultDomainSuffix.isEmpty {
            hostnameInput = "app." + app.settings.defaultDomainSuffix
        }
        focusedField = .local
    }

    private func create() {
        errorText = nil
        switch mode {
        case .quick:
            app.createQuickTunnel(name: name, localURL: localInput, start: startNow)
            dismiss()
        case .named:
            isCreating = true
            Task {
                do {
                    try await app.createNamedTunnel(
                        name: name,
                        localURL: localInput,
                        hostname: hostnameInput,
                        start: startNow
                    )
                    isCreating = false
                    dismiss()
                } catch {
                    errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    isCreating = false
                }
            }
        }
    }
}
