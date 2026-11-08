import AppKit
import Combine
import Foundation
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot = UsageSnapshot()
    @Published private(set) var isLoading = false
    @Published private(set) var connectionInfo: String?
    @Published private(set) var workspaces: [WorkspaceOption] = []
    @Published private(set) var selectedOrgID: String?
    @Published private(set) var refreshInterval: TimeInterval = 300
    @Published private(set) var launchAtLogin = false
    @Published private(set) var launchAtLoginNeedsApproval = false
    @Published private(set) var launchAtLoginError: String?
    @Published private(set) var isChangingLaunchAtLogin = false

    struct WorkspaceOption: Identifiable, Equatable {
        var orgID: String
        var name: String

        var id: String { orgID }
        var label: String { name.isEmpty ? orgID : name }
    }

    private let store: OpenCodeCLIStore
    private let defaults: UserDefaults

    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?

    private let refreshKey = "refreshInterval"
    private let orgKey = "orgID"
    private let loginConfiguredKey = "didConfigureLoginItem"
    private let loginItemPathKey = "loginItemPath"

    init(store: OpenCodeCLIStore = OpenCodeCLIStore(), defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        let storedInterval = defaults.double(forKey: refreshKey)
        refreshInterval = storedInterval >= 60 ? storedInterval : 300
        selectedOrgID = defaults.string(forKey: orgKey)
    }

    // MARK: Lifecycle

    func start() {
        refreshLaunchAtLoginStatus()
        scheduleTimer()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1_500))
            configureLoginItemOnFirstLaunchIfNeeded()
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        Task { await refresh() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    // MARK: Credentials (read fresh from the CLI every time)

    private func loadConnections() -> [CLIConnection] {
        (try? store.connections()) ?? []
    }

    private func activeConnection(from connections: [CLIConnection]) -> CLIConnection? {
        let usable = connections.filter { $0.isValid }
        guard !usable.isEmpty else { return nil }
        if let preferredOrg = selectedOrgID,
           let match = usable.first(where: { $0.orgID == preferredOrg })
        {
            return match
        }
        return usable.first
    }

    private func recordWorkspaces(_ connections: [CLIConnection]) {
        let seen = connections
            .filter { $0.isValid }
            .reduce(into: [String: WorkspaceOption]()) { map, connection in
                if map[connection.orgID] == nil {
                    map[connection.orgID] = WorkspaceOption(
                        orgID: connection.orgID,
                        name: connection.orgName ?? connection.email ?? "")
                }
            }
        workspaces = seen.values.sorted { $0.orgID < $1.orgID }

        if let connection = activeConnection(from: connections) {
            connectionInfo = connection.accountDescription
        } else {
            connectionInfo = nil
        }
    }

    func selectWorkspace(_ orgID: String) {
        selectedOrgID = orgID
        defaults.set(orgID, forKey: orgKey)
        refreshNow()
    }

    // MARK: Refresh

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let connections = loadConnections()
        recordWorkspaces(connections)

        guard let connection = activeConnection(from: connections) else {
            var newSnapshot = snapshot
            newSnapshot.error = CLIStoreError.notInstalled.errorDescription
            newSnapshot.isStale = newSnapshot.hasItems
            snapshot = newSnapshot
            return
        }

        do {
            let result = try await UsageClient(connection: connection).fetchUsage()
            snapshot = UsageSnapshot(
                items: result.items,
                budgets: result.budgets,
                updatedAt: Date(),
                error: nil,
                isStale: false)
        } catch OpenCodeUsageError.unauthorized {
            // The CLI may have refreshed its device link; re-read once.
            let fresh = loadConnections()
            recordWorkspaces(fresh)
            guard let retry = activeConnection(from: fresh) else {
                var newSnapshot = snapshot
                newSnapshot.error = OpenCodeUsageError.unauthorized.errorDescription
                newSnapshot.isStale = newSnapshot.hasItems
                snapshot = newSnapshot
                return
            }
            retryFetch(connection: retry)
            return
        } catch {
            var newSnapshot = snapshot
            newSnapshot.error = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            newSnapshot.isStale = newSnapshot.hasItems
            snapshot = newSnapshot
        }
    }

    /// One more attempt after a credential re-read; failures land in the snapshot.
    private func retryFetch(connection: CLIConnection) {
        Task {
            do {
                let result = try await UsageClient(connection: connection).fetchUsage()
                await MainActor.run {
                    snapshot = UsageSnapshot(
                        items: result.items,
                        budgets: result.budgets,
                        updatedAt: Date(),
                        error: nil,
                        isStale: false)
                }
            } catch {
                await MainActor.run {
                    var newSnapshot = snapshot
                    newSnapshot.error = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                    newSnapshot.isStale = newSnapshot.hasItems
                    snapshot = newSnapshot
                }
            }
        }
    }

    func refreshNow() {
        Task { await refresh() }
    }

    // MARK: Refresh interval

    func setRefreshInterval(_ interval: TimeInterval) {
        let clamped = min(max(interval, 60), 3600)
        refreshInterval = clamped
        defaults.set(clamped, forKey: refreshKey)
        scheduleTimer()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let newTimer = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    // MARK: Links

    /// Opens the workspace activity page the CLI itself links to.
    @discardableResult
    func openActivityPage() -> Bool {
        let connections = loadConnections()
        guard let connection = activeConnection(from: connections),
              let url = UsageClient(connection: connection).activityPageURL
        else {
            return false
        }
        NSWorkspace.shared.open(url)
        return true
    }

    // MARK: Launch at login

    func refreshLaunchAtLoginStatus() {
        switch SMAppService.mainApp.status {
        case .enabled:
            launchAtLogin = true
            launchAtLoginNeedsApproval = false
        case .requiresApproval:
            launchAtLogin = true
            launchAtLoginNeedsApproval = true
        case .notRegistered, .notFound:
            launchAtLogin = false
            launchAtLoginNeedsApproval = false
        @unknown default:
            launchAtLogin = false
            launchAtLoginNeedsApproval = false
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard !isChangingLaunchAtLogin else { return }
        isChangingLaunchAtLogin = true
        launchAtLoginError = nil
        // Optimistic so the toggle slides immediately; refreshLaunchAtLoginStatus
        // corrects it once the system registers or rejects the login item.
        launchAtLogin = enabled
        Task {
            defer {
                isChangingLaunchAtLogin = false
                refreshLaunchAtLoginStatus()
            }
            do {
                if enabled {
                    if SMAppService.mainApp.status == .notRegistered {
                        try SMAppService.mainApp.register()
                    }
                } else if SMAppService.mainApp.status != .notRegistered {
                    try await SMAppService.mainApp.unregister()
                }
                defaults.set(true, forKey: loginConfiguredKey)
                defaults.set(Bundle.main.bundlePath, forKey: loginItemPathKey)
            } catch {
                launchAtLoginError = error.localizedDescription
            }
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private var isInApplicationsFolder: Bool {
        let path = Bundle.main.bundlePath
        let homeApplications = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
            .path
        return path.hasPrefix("/Applications/") || path.hasPrefix(homeApplications + "/")
    }

    private func configureLoginItemOnFirstLaunchIfNeeded() {
        let currentPath = Bundle.main.bundlePath
        let configured = defaults.bool(forKey: loginConfiguredKey)
        let configuredPath = defaults.string(forKey: loginItemPathKey)
        guard !configured || configuredPath != currentPath else { return }
        guard isInApplicationsFolder else { return }

        func markConfigured() {
            defaults.set(true, forKey: loginConfiguredKey)
            defaults.set(currentPath, forKey: loginItemPathKey)
            refreshLaunchAtLoginStatus()
        }

        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            markConfigured()
        case .notRegistered, .notFound:
            do {
                try SMAppService.mainApp.register()
                markConfigured()
            } catch {
                launchAtLoginError = error.localizedDescription
            }
        @unknown default:
            break
        }
    }

    // MARK: Preview

    #if DEBUG
    static func preview() -> AppModel {
        let model = AppModel(store: OpenCodeCLIStore(home: URL(fileURLWithPath: "/nonexistent")))
        model.connectionInfo = "you@example.com — Default Workspace"
        model.workspaces = [WorkspaceOption(orgID: "wrk_01ExampleWorkspaceID12345678", name: "Default Workspace")]
        model.selectedOrgID = "wrk_01ExampleWorkspaceID12345678"

        func item(_ label: String, _ percent: Int, _ resetsIn: TimeInterval) -> UsageItem {
            let date = Date().addingTimeInterval(resetsIn)
            return UsageItem(
                label: label,
                value: "",
                percent: percent,
                reset: UsageClient.ZenResponse.resetText(date),
                resetShort: UsageClient.ZenResponse.resetShort(date))
        }

        model.snapshot = UsageSnapshot(
            items: [
                item("Rolling", 42, 5 * 3600),
                item("Weekly", 55, 26 * 3600),
                item("Monthly", 30, 30 * 86_400),
            ],
            budgets: [
                Budget(
                    id: "b1", name: "Workspace budget", limit: 100, spent: 6.87,
                    coverage: "workspace", resetsText: "Resets in 12d"),
            ],
            updatedAt: Date(),
            error: nil,
            isStale: false)
        return model
    }
    #endif
}
