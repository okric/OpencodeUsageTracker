import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var model: AppModel

    @State private var cookieInput = ""
    @State private var cookieMessage: String?
    @State private var isSavingCookie = false
    @State private var workspaceInput = ""
    @State private var workspaceMessage: String?
    @State private var importMessage: String?
    @State private var isImporting = false

    var body: some View {
        Form {
            Section {
                cookieContent
            } header: {
                Text("Session Cookie")
            }

            Section {
                workspaceContent
            } header: {
                Text("Workspace")
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
        .frame(width: 540, height: 620)
        .onAppear {
            model.refreshLaunchAtLoginStatus()
            if workspaceInput.isEmpty {
                workspaceInput = model.workspacePath
            }
        }
    }

    // MARK: Cookie

    @ViewBuilder
    private var cookieContent: some View {
        if model.hasCookie {
            Label("Cookie saved in Keychain", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .font(.callout)
        } else {
            Text("The app reads your OpenCode usage from opencode.ai with the session cookie used by your browser. Cookies expire; paste a new one whenever usage stalls on “expired”.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("To get it: browser DevTools → Network → open any opencode.ai request → copy the value of the `Cookie:` request header.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }

        SecureField(model.hasCookie ? "Paste a new cookie to replace" : "Paste your Cookie header value", text: $cookieInput)
            .textFieldStyle(.roundedBorder)
            .onSubmit { saveCookie() }

        HStack(spacing: 10) {
            Button(model.hasCookie ? "Replace Cookie" : "Save Cookie") {
                saveCookie()
            }
            .disabled(cookieInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSavingCookie)

            if isSavingCookie {
                ProgressView().controlSize(.small)
            }

            Button("Import from .env…") {
                pickEnvFile()
            }
            .disabled(isImporting || isSavingCookie)

            Spacer()

            if model.hasCookie {
                Button("Remove", role: .destructive) {
                    model.removeCookie()
                    cookieMessage = nil
                }
            }
        }

        HStack {
            Button("Refresh Now") {
                model.refreshNow()
            }
            .disabled(model.needsSetup || model.isLoading)

            if model.isLoading {
                ProgressView().controlSize(.small)
            }
        }

        if let importMessage {
            Text(importMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if let cookieMessage {
            Text(cookieMessage)
                .font(.caption)
                .foregroundStyle(cookieMessageHasError ? .red : .primary)
                .lineLimit(3)
        }
    }

    private var cookieMessageHasError: Bool {
        model.snapshot.error != nil && cookieMessage == model.snapshot.error
    }

    // MARK: Workspace

    @ViewBuilder
    private var workspaceContent: some View {
        Text("The workspace page URL you open in the browser (it contains the wrk_… id). A bare wrk_… id also works.")
            .font(.caption)
            .foregroundStyle(.secondary)

        TextField("https://opencode.ai/workspace/wrk_…/go", text: $workspaceInput)
            .textFieldStyle(.roundedBorder)

        HStack {
            Button(workspaceInput == model.workspacePath ? "Up to date" : "Save Workspace") {
                saveWorkspace()
            }
            .disabled(trimmedWorkspace == model.workspacePath || trimmedWorkspace.isEmpty)

            Button("Open Workspace Page") {
                model.openWorkspacePage()
            }

            Spacer()
        }

        if let workspaceMessage {
            Text(workspaceMessage)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    private var trimmedWorkspace: String {
        workspaceInput.trimmingCharacters(in: .whitespacesAndNewlines)
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

        if let updated = model.snapshot.updatedAt {
            Text("Last updated \(updated.formatted(date: .omitted, time: .standard))")
                .font(.caption)
                .foregroundStyle(.secondary)
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
        Text("The OpenCode session cookie is stored as a generic password in the macOS Keychain with `AfterFirstUnlockThisDeviceOnly`. Nothing is written to `.env`, plists, or logs, and there is no telemetry.")
            .font(.caption)
            .foregroundStyle(.secondary)

        Text("Migration: on first launch the app reads `OPENCODE_COOKIE` from the old Node project's `.env` file once, verifies it, and moves it into the Keychain. You can delete that `.env` afterwards.")
            .font(.caption2)
            .foregroundStyle(.tertiary)

        Text("Usage data is scraped from the workspace page you browse; the cookie you paste is what your browser already sends there.")
            .font(.caption2)
            .foregroundStyle(.tertiary)

        Link("Open OpenCode workspace page", destination: URL(string: "https://opencode.ai")!)
    }

    // MARK: Actions

    private func saveCookie() {
        let value = cookieInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        isSavingCookie = true
        cookieMessage = nil
        Task {
            do {
                try await model.saveCookie(value)
                cookieInput = ""
                cookieMessage = "Cookie verified and saved."
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                cookieMessage = "Cookie rejected: \(message)"
            }
            isSavingCookie = false
        }
    }

    private func saveWorkspace() {
        do {
            try model.setWorkspacePath(trimmedWorkspace)
            workspaceMessage = nil
        } catch {
            workspaceMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func pickEnvFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose the old project's .env file"
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.plainText, .init(filenameExtension: "env") ?? .plainText]
        panel.directoryURL = EnvImporter.legacyPath.deletingLastPathComponent()
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            isImporting = true
            importMessage = nil
            Task {
                do {
                    let imported = try await model.importFromEnvFile(at: url)
                    importMessage = imported
                        ? "Cookie imported from \(url.lastPathComponent)."
                        : "No OPENCODE_COOKIE found in that file."
                } catch {
                    importMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
                isImporting = false
            }
        }
    }
}


#if DEBUG
#Preview("Settings") {
    SettingsView(model: AppModel.preview())
}
#endif
