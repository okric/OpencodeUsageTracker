import Foundation

/// One model/plan usage row as scraped from the OpenCode workspace page.
struct UsageItem: Equatable, Identifiable {
    let label: String
    /// Human-readable usage value from the page (e.g. "$3.42").
    let value: String
    /// Percent used, 0–100.
    let percent: Int
    /// Full reset sentence from the page (e.g. "Resets in 2 days and 7 hours").
    let reset: String
    /// Compact reset (e.g. "2d", "7h", "35m") for the status bar.
    let resetShort: String

    var id: String { label }
}

/// Last successful/failing refresh result published to the UI.
struct UsageSnapshot: Equatable {
    var items: [UsageItem] = []
    var updatedAt: Date? = nil
    /// Non-empty when the last refresh failed; can coexist with older items.
    var error: String? = nil
    /// True when items shown are from an earlier refresh than the latest attempt.
    var isStale: Bool = false

    var hasItems: Bool { !items.isEmpty }
}
