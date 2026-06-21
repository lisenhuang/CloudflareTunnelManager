import SwiftUI

/// Cloudflare account / API-token management.
///
/// Note on "OAuth login": Cloudflare does not provide an end-user OAuth2 flow for
/// REST API access, so the app authenticates with a scoped **API token** that the
/// user pastes here (stored in the Keychain).
struct AccountSettingsView: View {
    @Environment(AppState.self) private var app
    @State private var tokenInput = ""
    @State private var isSaving = false

    var body: some View {
        Form {
            if let account = app.account {
                Section("Signed in") {
                    LabeledContent("Account", value: account.accountName)
                    LabeledContent("Account ID") {
                        Text(account.accountID).font(.caption.monospaced()).textSelection(.enabled)
                    }
                    LabeledContent("Token", value: account.maskedToken)
                    Button("Log out", role: .destructive) { app.logout() }
                }
            } else {
                Section("Connect to Cloudflare") {
                    Text("Paste a scoped API token to create named tunnels with custom hostnames. Quick tunnels work without a token.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    SecureField("API token", text: $tokenInput, prompt: Text("Cloudflare API token"))

                    HStack {
                        Button("Create a token…") {
                            if let url = URL(string: "https://dash.cloudflare.com/profile/api-tokens") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        Spacer()
                        if isSaving || app.isVerifyingAccount { ProgressView().controlSize(.small) }
                        Button("Save & Verify") { save() }
                            .buttonStyle(.borderedProminent)
                            .disabled(tokenInput.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                    }

                    if let error = app.accountError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.red)
                    }
                }

                Section("Required token permissions") {
                    Label("Account · Cloudflare Tunnel · Edit", systemImage: "checkmark")
                    Label("Zone · DNS · Edit", systemImage: "checkmark")
                    Label("Zone · Zone · Read", systemImage: "checkmark")
                }
                .font(.caption)
            }
        }
        .formStyle(.grouped)
    }

    private func save() {
        isSaving = true
        let token = tokenInput
        Task {
            await app.saveAPIToken(token)
            isSaving = false
            if app.account != nil { tokenInput = "" }
        }
    }
}
