import XCTest
@testable import OpencodeUsageTracker

final class UsageClientTests: XCTestCase {
    private let zenJSON: [String: Any] = [
        "usage": [
            "rolling": ["status": "ok", "percent": 0, "resetsAt": "2026-11-08T22:46:58.000Z"],
            "weekly": ["status": "ok", "percent": 2, "resetsAt": "2026-11-09T00:00:00.000Z"],
            "monthly": ["status": "ok", "percent": 1, "resetsAt": "2026-12-08T03:39:30.000Z"],
        ]
    ]

    private func date(_ iso: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return try XCTUnwrap(formatter.date(from: iso))
    }

    func testParseUsageWindows() throws {
        let parsed = try XCTUnwrap(UsageClient.parseUsage(zenJSON))
        XCTAssertEqual(parsed.rolling, .init(status: "ok", percent: 0, resetsAt: try date("2026-11-08T22:46:58.000Z")))
        XCTAssertEqual(parsed.weekly.percent, 2)
        XCTAssertEqual(parsed.monthly.percent, 1)
    }

    func testItemsAreRollingWeeklyMonthly() throws {
        let parsed = try XCTUnwrap(UsageClient.parseUsage(zenJSON))
        let labels = parsed.items.map(\.label)
        XCTAssertEqual(labels, ["Rolling", "Weekly", "Monthly"])
        XCTAssertEqual(parsed.items.map(\.percent), [0, 2, 1])
        XCTAssertTrue(parsed.items.allSatisfy { !$0.reset.isEmpty })
        XCTAssertTrue(parsed.items.allSatisfy { !$0.resetShort.isEmpty })
    }

    func testParseUsageRejectsUnexpectedShape() {
        XCTAssertNil(UsageClient.parseUsage(["foo": 1]))
        XCTAssertTrue(UsageClient.parseUsage([:]).isNil)
    }

    func testResetTextRelative() {
        let now = Date()
        XCTAssertEqual(
            UsageClient.ZenResponse.resetText(now.addingTimeInterval(3600), now: now),
            "Resets in 1h")
        XCTAssertEqual(
            UsageClient.ZenResponse.resetText(now.addingTimeInterval(-10), now: now),
            "Resets now")
        XCTAssertEqual(
            UsageClient.ZenResponse.resetShort(now.addingTimeInterval(90), now: now),
            "1m")
        XCTAssertEqual(
            UsageClient.ZenResponse.resetShort(now.addingTimeInterval(-5), now: now),
            "now")
    }

    func testParseBudgets() throws {
        let budgets = UsageClient.parseBudgets([
            "budgets": [[
                "ruleID": "rule_1",
                "limitDollars": 100.0,
                "spentDollars": 6.87,
                "coverage": ["type": "workspace"],
                "resetsAt": "2026-12-01T00:00:00.000Z",
            ]]
        ])
        XCTAssertEqual(budgets.count, 1)
        XCTAssertEqual(budgets[0].name, "Workspace budget")
        XCTAssertEqual(budgets[0].limit, 100)
        XCTAssertEqual(budgets[0].spent, 6.87)
        XCTAssertEqual(budgets[0].percent, 6)
    }

    func testActivityPageURL() {
        let connection = CLIConnection(
            server: "https://opencode.ai/console",
            orgID: "wrk_123",
            orgName: "Default Workspace",
            email: "a@b.c",
            kind: .oauth(access: "tok", refresh: nil, expires: nil))
        let client = UsageClient(connection: connection)
        XCTAssertEqual(
            client.activityPageURL?.absoluteString,
            "https://opencode.ai/console/wrk_123/activity/overview")
        XCTAssertEqual(client.serverBase, "https://opencode.ai")
    }
}

// Small shim so XCTAssertNil-style checks read cleanly without importing extra bools.
private extension Optional {
    var isNil: Bool { self == nil }
}
