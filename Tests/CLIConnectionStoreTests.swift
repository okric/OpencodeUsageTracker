import XCTest
@testable import OpencodeDashboard

final class CLIConnectionStoreTests: XCTestCase {
    func testCredentialWithOrgMetadata() throws {
        let connection = try XCTUnwrap(OpenCodeCLIStore.connection(credentialJSON: Data("""
        {
          "type": "oauth",
          "methodID": "device",
          "refresh": "rt_123",
          "access": "at_456",
          "expires": 1794965979658,
          "metadata": {
            "server": "https://opencode.ai/console",
            "orgID": "wrk_01ExampleWorkspaceID12345678",
            "orgName": "Default Workspace",
            "email": "a@b.c"
          }
        }
        """.utf8)))

        XCTAssertEqual(connection.orgID, "wrk_01ExampleWorkspaceID12345678")
        XCTAssertEqual(connection.orgName, "Default Workspace")
        XCTAssertEqual(connection.email, "a@b.c")
        XCTAssertEqual(connection.server, "https://opencode.ai/console")
        guard case let .oauth(access, refresh, expires) = connection.kind else {
            return XCTFail("expected oauth")
        }
        XCTAssertEqual(access, "at_456")
        XCTAssertEqual(refresh, "rt_123")
        XCTAssertNotNil(expires)
        XCTAssertTrue(connection.isValid)
    }

    func testIgnoresCredentialsWithoutOrg() {
        // Plain API-key connections cannot call the console usage endpoints.
        XCTAssertNil(OpenCodeCLIStore.connection(credentialJSON: Data(
            "{\"type\":\"api\",\"key\":\"sk-abc\"}".utf8)))
        XCTAssertNil(OpenCodeCLIStore.connection(credentialJSON: Data(
            "{\"type\":\"oauth\",\"access\":\"at\"}".utf8))) // oauth but no metadata/orgID
        XCTAssertNil(OpenCodeCLIStore.connection(credentialJSON: Data(
            "not json".utf8)))
    }

    func testAccountDescription() throws {
        let connection = try XCTUnwrap(OpenCodeCLIStore.connection(credentialJSON: Data("""
        {"type":"oauth","access":"a","metadata":{"orgID":"wrk_1","orgName":"Team WS","email":"x@y.z"}}
        """.utf8)))
        XCTAssertEqual(connection.accountDescription, "x@y.z — Team WS")
    }
}
