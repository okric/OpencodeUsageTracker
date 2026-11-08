import Foundation

/// One usage window (Rolling / Weekly / Monthly) from the OpenCode Go API.
struct UsageItem: Equatable, Identifiable {
    let label: String
    /// Optional detail (currently unused; keep for future API values).
    let value: String
    /// Percent used, 0–100.
    let percent: Int
    /// Human reset sentence (e.g. "Resets in 5h").
    let reset: String
    /// Compact reset ("5h", "22h", "1d") for the status bar.
    let resetShort: String

    var id: String { label }
}

/// A spend budget from the workspace's policy store.
struct Budget: Equatable, Identifiable {
    let id: String
    let name: String
    let limit: Double
    let spent: Double
    let coverage: String
    let resetsText: String

    var percent: Int {
        guard limit > 0 else { return 0 }
        return min(100, Int((spent / limit * 100).rounded(.down)))
    }
}

/// Last refresh result published to the UI.
struct UsageSnapshot: Equatable {
    var items: [UsageItem] = []
    var budgets: [Budget] = []
    var updatedAt: Date? = nil
    /// Non-empty when the last refresh failed; can coexist with older items.
    var error: String? = nil
    /// True when items shown are from an earlier refresh than the latest attempt.
    var isStale: Bool = false

    var hasItems: Bool { !items.isEmpty }
}
