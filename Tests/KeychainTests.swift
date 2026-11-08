import XCTest
@testable import OpencodeDashboard

final class KeychainTests: XCTestCase {
    func testSaveReadDeleteRoundTrip() throws {
        let store = KeychainStore(service: "com.opencode.dashboard.test")
        defer { try? store.delete(.cookie) }

        try store.save("cookie-value", for: .cookie)
        XCTAssertEqual(store.read(.cookie), "cookie-value")

        try store.save("cookie-value-2", for: .cookie)
        XCTAssertEqual(store.read(.cookie), "cookie-value-2")

        try store.delete(.cookie)
        XCTAssertNil(store.read(.cookie))
    }

    func testEmptySaveDeletes() throws {
        let store = KeychainStore(service: "com.opencode.dashboard.test")
        try store.save("value", for: .cookie)
        try store.save("", for: .cookie)
        XCTAssertNil(store.read(.cookie))
    }

    func testWorkspaceIDExtraction() {
        XCTAssertEqual(
            OpenCodeClient.workspaceID(from: "https://opencode.ai/workspace/wrk_01ExampleWorkspaceID12345678/go"),
            "wrk_01ExampleWorkspaceID12345678")
        XCTAssertEqual(OpenCodeClient.workspaceID(from: "wrk_abc"), "wrk_abc")
        XCTAssertEqual(OpenCodeClient.workspaceID(from: "https://example.com/wrk_abc"), "")
    }

    func testPageURLBuild() {
        let client = OpenCodeClient(workspacePath: "wrk_abc", cookie: "x")
        XCTAssertEqual(
            client.pageURL?.absoluteString,
            "https://opencode.ai/workspace/wrk_abc/go")
    }

    func testEnvCookieParsing() {
        XCTAssertEqual(EnvImporter.cookie(in: "OPENCODE_COOKIE=abc\n"), "abc")
        XCTAssertEqual(EnvImporter.cookie(in: "export OPENCODE_COOKIE=\"x y\"\nFOO=1"), "x y")
        XCTAssertNil(EnvImporter.cookie(in: "FOO=bar"))
    }
}
