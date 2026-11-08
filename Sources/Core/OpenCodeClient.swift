import Foundation

enum OpenCodeError: LocalizedError {
    case missingCookie
    case invalidWorkspaceURL(String)
    case http(Int)
    case notFound
    case noUsageData
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .missingCookie:
            return "No OpenCode cookie stored—add it in Settings."
        case let .invalidWorkspaceURL(raw):
            return "Invalid workspace URL: \(raw)"
        case let .http(status):
            return "OpenCode returned HTTP \(status)"
        case .notFound:
            return "Workspace page not found—check the workspace URL in Settings."
        case .noUsageData:
            return "No usage data found—your cookie may be expired."
        case let .transport(message):
            return message
        }
    }
}

/// Fetches the OpenCode workspace page with the stored session cookie and
/// parses usage rows out of the server-rendered HTML.
struct OpenCodeClient {
    /// Accepts either the full workspace page URL or a bare `wrk_…` id.
    var workspacePath: String
    var cookie: String
    var session: URLSession = .shared

    static let defaultWorkspacePath = "wrk_01ExampleWorkspaceID12345678"
    static let baseURLString = "https://opencode.ai"

    /// Normalized page URL: `wrk_…` becomes `https://opencode.ai/workspace/<id>/go`.
    var pageURL: URL? {
        let id = Self.workspaceID(from: workspacePath)
        guard !id.isEmpty else { return URL(string: workspacePath) }
        return URL(string: "\(Self.baseURLString)/workspace/\(id)/go")
    }

    static func workspaceID(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.hasPrefix("wrk_") { return trimmed }
        guard let url = URL(string: trimmed), let host = url.host, host.hasSuffix("opencode.ai") else {
            return ""
        }
        return url.pathComponents.first { $0.hasPrefix("wrk_") } ?? ""
    }

    func fetchUsage() async throws -> [UsageItem] {
        guard !cookie.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw OpenCodeError.missingCookie
        }
        guard let url = pageURL else {
            throw OpenCodeError.invalidWorkspaceURL(workspacePath)
        }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OpenCodeError.transport(error.localizedDescription)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200: break
        case 401: throw OpenCodeError.noUsageData
        case 404: throw OpenCodeError.notFound
        case 400...499: throw OpenCodeError.noUsageData
        default: throw OpenCodeError.http(status)
        }

        let html = String(data: data, encoding: .utf8) ?? ""
        let items = UsageParser.parse(html)
        guard !items.isEmpty else { throw OpenCodeError.noUsageData }
        return items
    }
}
