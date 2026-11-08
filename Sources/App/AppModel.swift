import AppKit
import Combine
import Foundation
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot = UsageSnapshot()
    @Published private(set) var isLoading = false
    @Published private(set) var hasCookie = false
    @Published private(set) var workspacePath = OpenCodeClient.defaultWorkspacePath
    @Published private(set) var refreshInterval: TimeInterval = 300
    @Published private(set) var launchAtLogin = false
    @Published private(set) var launchAtLoginNeedsApproval = false
    @Published private(set) var launchAtLoginError: String?
    @Published private(set) var isChangingLaunchAtLogin = false

    private let credentials: KeychainStore
    private let defaults: UserDefaults

    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?

    private let refreshKey = "refreshInterval"
    private let workspaceKey = "workspacePath"
    private let legacyImportKey = "didImportLegacyEnv"
    private let loginConfiguredKey = "didConfigureLoginItem"
    private let loginItemPathKey = "loginItemPath"

    init(
        credentials: KeychainStore = KeychainStore(),
        defaults: UserDefaults = .standard)
    {
        self.credentials = credentials
        self.defaults = defaults

        hasCookie = credentials.has(.cookie)
        if let stored = defaults.string(forKey: workspaceKey), !stored.isEmpty {
            workspacePath = stored
        }
        let storedInterval = defaults.double(forKey: refreshKey)
        refreshInterval = storedInterval >= 60 ? storedInterval : 300
    }

    var needsSetup: Bool { !hasCookie }

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

    // MARK: Refresh

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        guard let cookie = credentials.read(.cookie) else {
            hasCookie = false
            if !snapshot.hasItems {
                snapshot = UsageSnapshot()
                snapshot.error = nil
            }
            return
        }
        hasCookie = true

        let client = OpenCodeClient(workspacePath: workspacePath, cookie: cookie)
        do {
            let items = try await client.fetchUsage()
            snapshot = UsageSnapshot(
                items: items,
                updatedAt: Date(),
                error: nil,
                isStale: false)
        } catch {
            var newSnapshot = snapshot
            newSnapshot.error = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            newSnapshot.isStale = newSnapshot.hasItems
            snapshot = newSnapshot
        }
    }

    func refreshNow() {
        Task { await refresh() }
    }

    // MARK: Cookie

    /// Saves the cookie after verifying it fetches real usage data.
    func saveCookie(_ rawValue: String) async throws {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw OpenCodeError.missingCookie }

        let probe = OpenCodeClient(workspacePath: workspacePath, cookie: value)
        let items = try await probe.fetchUsage()

        try credentials.save(value, for: .cookie)
        hasCookie = true
        snapshot = UsageSnapshot(items: items, updatedAt: Date(), error: nil, isStale: false)
        scheduleTimer()
    }

    func removeCookie() {
        try? credentials.delete(.cookie)
        hasCookie = false
        snapshot = UsageSnapshot()
        refreshNow()
    }

    // MARK: Legacy .env import

    /// One-time import of OPENCODE_COOKIE from the old Node project's `.env`.
    /// No-op when the flag was recorded or there is nothing to import.
    func migrateLegacyCookieIfNeeded() async {
        guard !hasCookie, !defaults.bool(forKey: legacyImportKey) else { return }
        guard let cookie = EnvImporter.legacyCookie() else {
            defaults.set(true, forKey: legacyImportKey)
            return
        }
        defaults.set(true, forKey: legacyImportKey)

        let probe = OpenCodeClient(workspacePath: workspacePath, cookie: cookie)
        guard let items = try? await probe.fetchUsage() else { return }

        try? credentials.save(cookie, for: .cookie)
        hasCookie = true
        snapshot = UsageSnapshot(items: items, updatedAt: Date(), error: nil, isStale: false)
        scheduleTimer()
    }

    func importFromEnvFile(at url: URL) async throws -> Bool {
        guard let cookie = try EnvImporter.cookie(at: url) else { return false }
        try await saveCookie(cookie)
        return true
    }

    // MARK: Workspace

    /// Accepts a full URL or a bare `wrk_…` id; throws when neither.
    func setWorkspacePath(_ raw: String) throws {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw OpenCodeError.invalidWorkspaceURL(trimmed)
        }
        guard OpenCodeClient.workspaceID(from: trimmed).hasPrefix("wrk_")
            || URL(string: trimmed) != nil && trimmed.contains("://")
        else {
            throw OpenCodeError.invalidWorkspaceURL(trimmed)
        }
        workspacePath = trimmed
        defaults.set(trimmed, forKey: workspaceKey)
        refreshNow()
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

    /// The app is installed in /Applications for distribution. On its first launch
    /// there, opt into launch-at-login once; the Settings toggle remains authoritative.
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

    // MARK: Links

    func openWorkspacePage() {
        let client = OpenCodeClient(workspacePath: workspacePath, cookie: "")
        guard let url = client.pageURL else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Preview

    #if DEBUG
    /// Deterministic configured state for the Xcode preview canvas.
    static func preview() -> AppModel {
        let model = AppModel(credentials: KeychainStore(service: "com.opencode.dashboard.preview"))
        model.hasCookie = true
        model.snapshot = UsageSnapshot(
            items: [
                UsageItem(
                    label: "Claude Sonnet 4.5",
                    value: "$3.42",
                    percent: 42,
                    reset: "Resets in 2 days and 7 hours",
                    resetShort: "2d"),
                UsageItem(
                    label: "GPT-5 Codex",
                    value: "$1.10",
                    percent: 55,
                    reset: "Resets in 5 hours",
                    resetShort: "5h"),
                UsageItem(
                    label: "Gemini 3 Flash",
                    value: "$0.30",
                    percent: 30,
                    reset: "Resets in 35 minutes",
                    resetShort: "35m"),
            ],
            updatedAt: Date(),
            error: nil,
            isStale: false)
        return model
    }
    #endif
}
