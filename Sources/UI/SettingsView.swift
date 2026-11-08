import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    @State private var hasBeenVisible = false

    var body: some View {
        Form {
            Section {
                accountContent
            } header: {
                Text("Account")
            }

            Section {
                refreshContent
            } header: {
                Text("Refresh")
            }

            Section {
                launchAtLoginContent
            } header: {
                Text("Startup")
            }

            Section {
                privacyContent
            } header: {
                Text("Privacy & Security")
            }
        }
        .formStyle(.grouped)
        .frame(width: 540)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            guard !hasBeenVisible else { return }
            hasBeenVisible = true
            model.refreshLaunchAtLoginStatus()
            model.refreshNow()
        }
    }

    // MARK: Account

    @ViewBuilder
    private var accountContent: some View {
        if let name = model.connectionInfo {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.headline)
                    Text("read live from the OpenCode CLI's local store — nothing is copied or stored")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        } else {
            Label("OpenCode CLI not linked", systemImage: "xmark.seal")
                .foregroundStyle(.orange)
                .font(.callout)

            Text("Install the OpenCode CLI, sign in, and connect this device (`opencode`, then /connect or web pairing). This app reads the CLI's linked-workspace credential—no browser cookie needed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if model.workspaces.count > 1 {
            Picker("Workspace", selection: Binding(
                get: { model.selectedOrgID },
            set: { model.selectWorkspace($0 ?? "") }
            )) {
                ForEach(model.workspaces) { workspace in
                    Text(workspace.label).tag(Optional(workspace.orgID))
                }
            }
            .pickerStyle(.menu)
        }

        if let statusError = model.snapshot.error {
            Text(statusError)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(3)
        }
    }

    // MARK: Refresh

    @ViewBuilder
    private var refreshContent: some View {
        Picker("Refresh every", selection: Binding(
            get: { model.refreshInterval },
            set: { model.setRefreshInterval($0) }
        )) {
            Text("1 minute").tag(TimeInterval(60))
            Text("5 minutes").tag(TimeInterval(300))
            Text("15 minutes").tag(TimeInterval(900))
            Text("30 minutes").tag(TimeInterval(1800))
        }
        .pickerStyle(.menu)

        HStack {
            if let updated = model.snapshot.updatedAt {
                Text("Last updated \(updated.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer()
            }

            Button("Refresh Now") {
                model.refreshNow()
            }
            .disabled(model.isLoading)

            if model.isLoading {
                ProgressView().controlSize(.small)
            }
        }
    }

    // MARK: Startup

    @ViewBuilder
    private var launchAtLoginContent: some View {
        Toggle("Launch at login", isOn: Binding(
            get: { model.launchAtLogin },
            set: { model.setLaunchAtLogin($0) }
        ))
        .disabled(model.isChangingLaunchAtLogin)

        if model.isChangingLaunchAtLogin {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Updating login item…")
                    .font(.caption)
            }
        }

        if model.launchAtLoginNeedsApproval {
            Label(
                "Approval is needed in System Settings → General → Login Items.",
                systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
            Button("Open Login Items Settings") {
                model.openLoginItemsSettings()
            }
        }

        if let error = model.launchAtLoginError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
        }

        Text("Starts the menu bar app when you log in. The app must be signed and installed in Applications.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: Privacy

    @ViewBuilder
    private var privacyContent: some View {
        Text("This app stores no secrets of its own. The OpenCode CLI login is read live from the CLI's local credential store only at request time; there are no Keychain items, no `.env`, no plist secrets, no logging of credentials, and no telemetry.")
            .font(.caption)
            .foregroundStyle(.secondary)

        Text("The CLI's credential store is never watched or written. Renew the login from the OpenCode CLI itself and refresh here. Usage comes from the same console endpoints the CLI uses (zen/go/v1/usage and workspace budget policies); the sk- API keys in the CLI's auth file are not used and never leave your machine.")
            .font(.caption2)
            .foregroundStyle(.tertiary)

        Link("Project page: github.com/okric/OpencodeUsageTracker", destination: URL(string: "https://github.com/okric/OpencodeUsageTracker")!)
    }
}


#if DEBUG
#Preview("Settings") {
    SettingsView(model: AppModel.preview())
}
#endif
