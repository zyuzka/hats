import XCTest
@testable import Hats

final class CodexHomeLocationTests: XCTestCase {
    func testCodexHomeIsHonouredAsCodexDoes() {
        let url = CodexHome.location(environment: ["CODEX_HOME": "/tmp/elsewhere", "HATS_STATE_HOME": "/tmp/state"],
                                     home: "/Users/someone")

        XCTAssertEqual(url.path, "/tmp/elsewhere")
    }

    func testATestStateFolderKeepsTheLiveCodexFolderOutOfReach() {
        XCTAssertEqual(CodexHome.location(environment: ["HATS_STATE_HOME": "/tmp/state"], home: "/Users/someone").path,
                       "/tmp/state/codex")
        XCTAssertEqual(CodexHome.location(environment: ["CODEX_HOME": ""], home: "/Users/someone").path,
                       "/Users/someone/.codex", "an empty CODEX_HOME counts as unset")
    }

    func testThisSuiteNeverReachesTheLiveCodexFolder() throws {
        let environment = ProcessInfo.processInfo.environment
        let state = environment[StateDirectory.overrideName] ?? ""
        try XCTSkipIf(state.isEmpty || !(environment["CODEX_HOME"] ?? "").isEmpty, "only with HATS_STATE_HOME alone")

        XCTAssertEqual(CodexHome.real.url.path, URL(fileURLWithPath: state).appendingPathComponent("codex").path)
        XCTAssertNotEqual(CodexHome.real.url.path, NSHomeDirectory() + "/.codex")
    }

    func testAQuotedKeyIsTheSameSetting() {
        XCTAssertEqual(CodexHome.storeMode(in: "'cli_auth_credentials_store' = \"keyring\"\n"), "keyring")
        XCTAssertEqual(CodexHome.storeMode(in: "\"cli_auth_credentials_store\" = 'auto'\n"), "auto")
    }
}
