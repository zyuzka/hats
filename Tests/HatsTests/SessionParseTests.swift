import XCTest
@testable import Hats

final class SessionParseTests: XCTestCase {
    private let spacedPath = "/Users/Build User/bin/claude"

    private func executables(_ pairs: [Int32: String]) -> [Int32: String] { pairs }

    func testAnExecutablePathIsTheWholeRestOfTheLine() {
        let map = Session.parsedExecutables(psOutput: """
        1234 claude
        77 /opt/homebrew/bin/claude
        88 \(spacedPath)
        99
        """)
        XCTAssertEqual(map[1234], "claude")
        XCTAssertEqual(map[77], "/opt/homebrew/bin/claude")
        XCTAssertEqual(map[88], spacedPath)
        XCTAssertNil(map[99])
    }

    func testABareClaudeIsAnInteractiveSession() {
        let session = Session.parse(psLine: "1234 05:12 claude",
                                    executables: executables([1234: "claude"]))
        XCTAssertEqual(session?.pid, 1234)
        XCTAssertEqual(session?.elapsed, "05:12")
        XCTAssertEqual(session?.isInteractive, true)
    }

    func testAClaudeReachedByAbsolutePathIsTheSameSession() {
        let session = Session.parse(psLine: "77 1-02:03:04 /opt/homebrew/bin/claude --continue",
                                    executables: executables([77: "/opt/homebrew/bin/claude"]))
        XCTAssertEqual(session?.pid, 77)
        XCTAssertEqual(session?.isInteractive, true)
    }

    func testAClaudeUnderAPathWithASpaceIsStillASession() {
        let session = Session.parse(psLine: "88 00:07 \(spacedPath) --continue",
                                    executables: executables([88: spacedPath]))
        XCTAssertEqual(session?.pid, 88)
        XCTAssertEqual(session?.isInteractive, true)
    }

    func testAHelperProcessWithClaudeInItsPathIsNotASession() {
        let map = executables([88: "/Users/x/.claude/bin/mcp-server",
                               89: "/opt/homebrew/bin/node"])
        XCTAssertNil(Session.parse(psLine: "88 00:01 /Users/x/.claude/bin/mcp-server",
                                   executables: map))
        XCTAssertNil(Session.parse(psLine: "89 00:01 node /Users/x/claude-agent-server/index.js",
                                   executables: map))
    }

    func testAProcessWithNoExecutableRecordedIsNotASession() {
        XCTAssertNil(Session.parse(psLine: "1234 05:12 claude", executables: [:]))
    }

    func testAOneShotInvocationIsNotInteractive() {
        let map = executables([5: "claude"])
        XCTAssertEqual(Session.parse(psLine: "5 00:02 claude -p 'ask'",
                                     executables: map)?.isInteractive, false)
        XCTAssertEqual(Session.parse(psLine: "5 00:02 claude -p",
                                     executables: map)?.isInteractive, false)
        XCTAssertEqual(Session.parse(psLine: "5 00:02 claude --print hello",
                                     executables: map)?.isInteractive, false)
    }

    func testDiscoveryKeepsABatchSessionBecauseItHoldsThePortJustTheSame() {
        let table: ([String]) -> String? = { arguments in
            arguments.contains("pid=,comm=")
                ? "111 /usr/local/bin/claude\n222 /usr/local/bin/claude\n333 /bin/zsh\n"
                : "111 01:00 claude\n222 00:20 claude -p ask\n333 09:00 zsh\n"
        }
        let found = SessionDiscovery.everySessionThatHoldsAPort(readingTheProcessTable: table)
        XCTAssertEqual(found?.map(\.pid), [111, 222],
                       "the reader answers a dependency question, and a claude -p run loses the "
                           + "gateway exactly as an interactive one does; zsh is not a session")
        XCTAssertEqual(found?.map(\.isInteractive), [true, false],
                       "the flag is still carried, because the display filter is applied where the "
                           + "display is")
    }

    func testDiscoveryReportsNothingRatherThanAnEmptyListWhenPsFails() {
        XCTAssertNil(SessionDiscovery.everySessionThatHoldsAPort(readingTheProcessTable: { _ in nil }),
                     "nil is unknown and the guard refuses on it; an empty list would read as safe")
    }

    func testALineThatIsNotAProcessRowIsNotASession() {
        let map = executables([1234: "claude"])
        XCTAssertNil(Session.parse(psLine: "", executables: map))
        XCTAssertNil(Session.parse(psLine: "PID ELAPSED COMMAND", executables: map))
        XCTAssertNil(Session.parse(psLine: "1234 05:12", executables: map))
    }
}
