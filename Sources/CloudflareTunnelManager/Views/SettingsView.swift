import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
            AccountSettingsView()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
            AdvancedSettingsView()
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 520, height: 420)
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Section("Defaults") {
                TextField("Default local port", value: $settings.defaultLocalPort, format: .number.grouping(.never))
                    .onChange(of: settings.defaultLocalPort) { _, _ in app.persistSettings() }
                TextField("Default domain suffix", text: $settings.defaultDomainSuffix,
                          prompt: Text("dev.example.com"))
                    .onChange(of: settings.defaultDomainSuffix) { _, _ in app.persistSettings() }
                    .help("Used to pre-fill the hostname for new named tunnels.")
            }
            Section("Startup") {
                Toggle("Launch at login", isOn: $settings.autoStartOnLogin)
                    .onChange(of: settings.autoStartOnLogin) { _, _ in
                        app.updateLoginItem()
                        app.persistSettings()
                    }
                Toggle("Restore running tunnels on launch", isOn: $settings.restoreRunningTunnelsOnLaunch)
                    .onChange(of: settings.restoreRunningTunnelsOnLaunch) { _, _ in app.persistSettings() }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Advanced

private struct AdvancedSettingsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Section("cloudflared") {
                LabeledContent("Status") {
                    if app.isCloudflaredInstalled {
                        Label(app.installation.version ?? "Installed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not found", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
                if let path = app.installation.path {
                    LabeledContent("Path") {
                        Text(path).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
                TextField("Binary path override", text: $settings.cloudflaredPathOverride,
                          prompt: Text("/opt/homebrew/bin/cloudflared"))
                    .onChange(of: settings.cloudflaredPathOverride) { _, _ in app.persistSettings() }

                HStack {
                    if app.isHomebrewAvailable {
                        Button(app.isCloudflaredInstalled ? "Reinstall via Homebrew" : "Install via Homebrew") {
                            Task { await app.installCloudflared() }
                        }
                        .disabled(app.isInstalling)
                    }
                    Button("Download…") { app.openDownloadPage() }
                    if app.isInstalling { ProgressView().controlSize(.small) }
                }

                if !app.installLog.isEmpty {
                    ScrollView {
                        Text(app.installLog.joined(separator: "\n"))
                            .font(.system(.caption2, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(height: 90)
                    .background(Color(nsColor: .textBackgroundColor))
                }
            }
            Section("Logs") {
                Stepper("Log buffer: \(settings.logBufferSize) lines",
                        value: $settings.logBufferSize, in: 200...20000, step: 200)
                    .onChange(of: settings.logBufferSize) { _, _ in app.persistSettings() }
            }
        }
        .formStyle(.grouped)
    }
}
