import Foundation
import SQLite3

/// One connection exported from the OpenCode CLI's credential store.
/// For usage we need an OAuth device-link token plus its workspace (org) id;
/// API keys (`sk-…`) are rejected by the console usage endpoints.
struct CLIConnection: Equatable {
    enum Kind: Equatable {
        case oauth(access: String, refresh: String?, expires: Date?)
        case apiKey(value: String)
    }

    /// Console server (e.g. "https://opencode.ai/console"); defaults per CLI.
    var server: String
    /// Workspace id ("wrk_…") used in the org headers and page URLs.
    var orgID: String
    var orgName: String?
    var email: String?
    var kind: Kind

    var accountDescription: String {
        let who = email ?? orgName ?? "OpenCode"
        return orgName.map { "\(who) — \($0)" } ?? who
    }

    var isValid: Bool {
        if case let .oauth(access, _, _) = kind {
            return !access.isEmpty && !orgID.isEmpty
        }
        return false
    }
}

enum CLIStoreError: LocalizedError {
    case notInstalled
    case databaseUnreadable(String)
    case noWorkspaceConnection

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "OpenCode CLI not found. Install it and sign in (`opencode`), then use /connect to link this device."
        case let .databaseUnreadable(message):
            return "Could not read the OpenCode CLI store: \(message)"
        case .noWorkspaceConnection:
            return "No linked workspace found in the OpenCode CLI. Run the CLI once and connect the device."
        }
    }
}

/// Reads connections straight from the opencode CLI's store
/// (`~/.local/share/opencode/opencode.db`, with `auth.json` as fallback).
/// Secrets are used in memory only; the CLI remains the source of truth, so
/// token renewals by the CLI are picked up on the next read.
struct OpenCodeCLIStore {
    static let defaultServer = "https://opencode.ai/console"

    let databaseURL: URL
    let authURL: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        databaseURL = home
            .appendingPathComponent(".local/share/opencode/opencode.db")
        authURL = home
            .appendingPathComponent(".local/share/opencode/auth.json")
    }

    /// All usable workspace connections, preferring device/OAuth links.
    func connections() throws -> [CLIConnection] {
        var found: [CLIConnection] = []
        var sawDatabase = false

        if let rows = try? databaseCredentialValues() {
            sawDatabase = true
            for data in rows {
                if let connection = Self.connection(credentialJSON: data) {
                    found.append(connection)
                }
            }
        }

        // Older CLI builds stored connections in auth.json.
        if !sawDatabase || found.isEmpty,
           let data = try? Data(contentsOf: authURL),
           let authConnection = Self.connection(authJSON: data) {
            found.append(authConnection)
        }

        return found
    }

    // MARK: SQLite

    /// Raw `credential.value` JSON blobs for the `opencode` integration.
    private func databaseCredentialValues() throws -> [Data] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw CLIStoreError.notInstalled
        }

        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "could not open"
            if let database { sqlite3_close_v2(database) }
            throw CLIStoreError.databaseUnreadable(message)
        }
        defer { sqlite3_close_v2(database) }
        sqlite3_busy_timeout(database, 500)

        let query = "SELECT value FROM credential WHERE integration_id = 'opencode'"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK, let statement else {
            let message = String(cString: sqlite3_errmsg(database))
            throw CLIStoreError.databaseUnreadable(message)
        }
        defer { sqlite3_finalize(statement) }

        var values: [Data] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let text = sqlite3_column_text(statement, 0) else { continue }
            values.append(Data(String(cString: text).utf8))
        }
        return values
    }

    // MARK: JSON parsing (pure, unit-testable)

    struct CredentialMismatch: Error {}

    static func connection(credentialJSON: Data) -> CLIConnection? {
        guard let json = try? JSONSerialization.jsonObject(with: credentialJSON) as? [String: Any]
        else { return nil }
        return connection(credential: json)
    }

    static func connection(credential json: [String: Any]) -> CLIConnection? {
        // Only device/workspace links carry the org metadata usage needs.
        guard let metadata = json["metadata"] as? [String: Any],
              let orgID = metadata["orgID"] as? String, !orgID.isEmpty
        else { return nil }

        let server = metadata["server"] as? String ?? defaultServer
        let orgName = metadata["orgName"] as? String
        let email = metadata["email"] as? String

        let kind: CLIConnection.Kind
        switch json["type"] as? String {
        case "oauth":
            let access = json["access"] as? String ?? ""
            guard !access.isEmpty else { return nil }
            var expires: Date?
            if let millis = json["expires"] as? Double, millis > 0 {
                expires = Date(timeIntervalSince1970: millis / 1000)
            }
            let refresh = json["refresh"] as? String
            kind = .oauth(access: access, refresh: refresh, expires: expires)
        case "key", "api":
            guard let key = json["key"] as? String, !key.isEmpty else { return nil }
            kind = .apiKey(value: key)
        default:
            return nil
        }

        return CLIConnection(
            server: server,
            orgID: orgID,
            orgName: orgName,
            email: email,
            kind: kind)
    }

    /// Legacy `auth.json` shape: provider name → credential object.
    static func connection(authJSON: Data) -> CLIConnection? {
        guard let json = try? JSONSerialization.jsonObject(with: authJSON) as? [String: Any]
        else { return nil }
        var best: CLIConnection?
        for (_, entry) in json where entry is [String: Any] {
            guard let credential = entry as? [String: Any],
                  var parsed = connection(credential: credential)
            else { continue }
            if parsed.server == defaultServer, let server = credentialValueServer(credential) {
                parsed.server = server
            }
            if parsed.isValid && best?.isValid != true {
                best = parsed
            }
        }
        return best
    }

    private static func credentialValueServer(_ credential: [String: Any]) -> String? {
        (credential["metadata"] as? [String: Any])?["server"] as? String
    }
}
