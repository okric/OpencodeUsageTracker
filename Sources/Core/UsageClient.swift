import Foundation

/// Talks to the OpenCode Console usage endpoints that the opencode CLI itself
/// uses: `zen/go/v1/usage` (Rolling/Weekly/Monthly windows) and the workspace
/// budget policies. Authenticated with the CLI's device link (OAuth access
/// token); plain `sk-` API keys are rejected by these endpoints.
struct UsageClient {
    var connection: CLIConnection
    var session: URLSession = .shared

    static let defaultServerBase = "https://opencode.ai"

    var serverBase: String {
        let server = connection.server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !server.isEmpty, let url = URL(string: server), let host = url.host else {
            return Self.defaultServerBase
        }
        let scheme = url.scheme ?? "https"
        return "\(scheme)://\(host)"
    }

    var consoleBase: String {
        let server = connection.server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !server.isEmpty, URL(string: server) != nil else {
            return Self.defaultServerBase + "/console"
        }
        return server
    }

    /// The workspace activity page the CLI links to in its usage view.
    var activityPageURL: URL? {
        URL(string: "\(consoleBase)/\(connection.orgID)/activity/overview")
    }

    struct ZenWindow: Equatable {
        var status: String
        var percent: Int
        var resetsAt: Date?
    }

    struct ZenResponse: Equatable {
        var rolling: ZenWindow
        var weekly: ZenWindow
        var monthly: ZenWindow

        var items: [UsageItem] {
            [item("Rolling", rolling), item("Weekly", weekly), item("Monthly", monthly)]
        }

        private func item(_ label: String, _ window: ZenWindow) -> UsageItem {
            let reset = Self.resetText(window.resetsAt)
            return UsageItem(
                label: label,
                value: "",
                percent: min(100, max(0, window.percent)),
                reset: reset,
                resetShort: Self.resetShort(window.resetsAt))
        }

        /// "Resets in 5h" / "Resets now" when the window already passed.
        static func resetText(_ date: Date?, now: Date = Date()) -> String {
            guard let date else { return "" }
            let delta = Int(date.timeIntervalSince(now).rounded())
            if delta <= 0 { return "Resets now" }
            return "Resets in \(Self.durationText(delta))"
        }

        /// Compact countdown for the status bar; "5h", "22m", "2d"…
        static func resetShort(_ date: Date?, now: Date = Date()) -> String {
            guard let date else { return "" }
            let delta = Int(date.timeIntervalSince(now).rounded())
            guard delta > 0 else { return "now" }
            return Self.durationText(delta)
        }

        static func durationText(_ seconds: Int) -> String {
            if seconds >= 86_400 {
                return "\(seconds / 86_400)d"
            }
            if seconds >= 3_600 {
                return "\(seconds / 3_600)h"
            }
            return "\(max(1, seconds / 60))m"
        }
    }

    func fetchUsage() async throws -> (items: [UsageItem], budgets: [Budget]) {
        guard case let .oauth(access, _, _) = connection.kind, !access.isEmpty, !connection.orgID.isEmpty
        else {
            throw OpenCodeUsageError.requiresDeviceLink
        }
        let authHeader = "Bearer \(access)"

        guard let usageURL = URL(string: "\(serverBase)/zen/go/v1/usage") else {
            throw OpenCodeUsageError.badURL
        }
        let usage = try await fetchJSON(
            url: usageURL,
            headers: ["Authorization": authHeader, "x-opencode-org-id": connection.orgID],
            expecting: "usage")
        guard let windows = Self.parseUsage(usage) else {
            throw OpenCodeUsageError.unexpectedResponse
        }

        var budgets: [Budget] = []
        if let budgetsURL = URL(string: "\(consoleBase)/api/policies/current-budgets") {
            budgets = (try? await Self.parseBudgets(fetchJSON(
                url: budgetsURL,
                headers: ["Authorization": authHeader, "x-org-id": connection.orgID],
                expecting: nil))) ?? []
        }

        return (windows.items, budgets)
    }

    private func fetchJSON(
        url: URL,
        headers: [String: String],
        expecting key: String?
    ) async throws -> [String: Any] {
        var request = URLRequest(url: url, timeoutInterval: 20)
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OpenCodeUsageError.transport(error.localizedDescription)
        }

        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: break
        case 401: throw OpenCodeUsageError.unauthorized
        case 403: throw OpenCodeUsageError.unavailable
        case let status: throw OpenCodeUsageError.http(status)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            throw OpenCodeUsageError.unexpectedResponse
        }
        guard let object = json as? [String: Any] else {
            throw OpenCodeUsageError.unexpectedResponse
        }
        if let key, object[key] == nil {
            throw OpenCodeUsageError.unexpectedResponse
        }
        if object["type"] as? String == "error",
           let error = object["error"] as? [String: Any],
           let message = error["message"] as? String
        {
            throw OpenCodeUsageError.server(message)
        }
        return object
    }

    // MARK: Parsing (pure, unit-testable)

    static func parseUsage(_ json: [String: Any]) -> ZenResponse? {
        guard let usage = json["usage"] else { return nil }
        let rolling = window(usage, "rolling")
        let weekly = window(usage, "weekly")
        let monthly = window(usage, "monthly")
        guard rolling != nil, weekly != nil, monthly != nil else { return nil }
        return ZenResponse(
            rolling: rolling!,
            weekly: weekly!,
            monthly: monthly!)
    }

    private static func window(_ usage: Any, _ name: String) -> ZenWindow? {
        guard let dict = (usage as? [String: Any])?[name] as? [String: Any]
        else { return nil }
        guard let percent = dict["percent"] as? Double ?? (dict["percent"] as? Int).map({ Double($0) })
        else { return nil }
        let status = dict["status"] as? String ?? "ok"
        var resets: Date?
        if let millis = dict["resetsAt"] as? Double {
            resets = Date(timeIntervalSince1970: millis / 1000)
        }
        if let text = dict["resetsAt"] as? String {
            resets = Self.parseISODate(text)
        }
        return ZenWindow(
            status: status,
            percent: Int(percent.rounded(.down)),
            resetsAt: resets)
    }

    private static func parseISODate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    static func parseBudgets(_ json: [String: Any]) -> [Budget] {
        guard let array = json["budgets"] as? [[String: Any]] else { return [] }
        return array.compactMap { entry in
            guard let id = entry["ruleID"] as? String,
                  let limit = number(entry, "limitDollars"),
                  let spent = number(entry, "spentDollars")
            else { return nil }
            let coverage: String
            switch entry["coverage"] as? [String: Any] {
            case let dict?:
                coverage = dict["type"] as? String ?? "workspace"
            default:
                coverage = "workspace"
            }
            var resetsText = ""
            if let resetsAt = entry["resetsAt"] as? String,
               let date = parseISODate(resetsAt)
            {
                resetsText = ZenResponse.resetText(date)
            }
            let scopeModels = (entry["models"] as? [[String: Any]]) ?? []
            let named = (entry["vendors"] as? [String]) ?? []
            let name = !named.isEmpty
                ? named.joined(separator: ", ")
                : (scopeModels.first?["name"] as? String ?? "Workspace budget")
            return Budget(
                id: id,
                name: name,
                limit: limit,
                spent: spent,
                coverage: coverage,
                resetsText: resetsText)
        }
    }

    private static func number(_ dict: [String: Any], _ key: String) -> Double? {
        dict[key] as? Double ?? (dict[key] as? Int).map({ Double($0) })
    }
}

enum OpenCodeUsageError: LocalizedError {
    case requiresDeviceLink
    case badURL
    case transport(String)
    case unauthorized
    case unavailable
    case http(Int)
    case unexpectedResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .requiresDeviceLink:
            return "Connect OpenCode: run `opencode` in a terminal, then /connect to link this device."
        case .badURL:
            return "Invalid OpenCode console URL."
        case let .transport(message):
            return message
        case .unauthorized:
            return "OpenCode rejected the credential—re-sign in from the CLI, then retry."
        case .unavailable:
            return "Usage is not available for this account."
        case let .http(status):
            return "OpenCode returned HTTP \(status)."
        case .unexpectedResponse:
            return "Unexpected response from the usage API."
        case let .server(message):
            return message
        }
    }
}
