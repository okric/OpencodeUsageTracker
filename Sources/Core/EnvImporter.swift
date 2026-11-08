import Foundation

/// One-time migration from the old Node project's `.env` file: reads
/// `OPENCODE_COOKIE=…` once and copies it into the Keychain. The app never
/// writes to or monitors the file.
enum EnvImporter {
    /// The old Node project directory, relative to the user's home.
    static var legacyPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Xcode Projects/OpencodeDashboard/.env")
    }

    /// Extracts `OPENCODE_COOKIE` (also accepts `export ` prefixes and quotes).
    static func cookie(in text: String) -> String? {
        for line in text.components(separatedBy: .newlines) {
            var trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("export ") {
                trimmed = trimmed.dropFirst("export ".count).trimmingCharacters(in: .whitespaces)
            }
            guard trimmed.hasPrefix("OPENCODE_COOKIE") else { continue }
            guard let equals = trimmed.firstIndex(of: "=") else { continue }
            var value = String(trimmed[trimmed.index(after: equals)...])
                .trimmingCharacters(in: .whitespaces)
            if (value.hasPrefix("\"") && value.hasSuffix("\"") && value.count > 1)
                || (value.hasPrefix("'") && value.hasSuffix("'") && value.count > 1) {
                value.removeFirst()
                value.removeLast()
            }
            return value.isEmpty ? nil : value
        }
        return nil
    }

    /// Reads the cookie from a `.env` file path.
    static func cookie(at url: URL) throws -> String? {
        let text = try String(contentsOf: url, encoding: .utf8)
        return cookie(in: text)
    }

    /// Import candidate from the legacy Node project location, if present.
    static func legacyCookie() -> String? {
        try? cookie(at: legacyPath)
    }
}
