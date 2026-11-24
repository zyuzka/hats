import XCTest
@testable import Hats

final class CodexServiceLoginRereadTests: XCTestCase {
    private final class FakeLink: CodexLoginLink {
        var answer: Result<String?, Error> = .success("work@example.com")
        var asked = 0
        var closed = 0

        func findAccountAfterRereadingLogin() throws -> String? {
            asked += 1
            return try answer.get()
        }

        func close() { closed += 1 }
    }

    private var folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("hats-reread-\(UUID().uuidString)")
    private let link = FakeLink()
    private var connects: [String] = []
    private var connectFails: CodexServiceError?
    private var lines: [(String, [String: String])] = []

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    private func makeReread() -> CodexServiceLoginReread {
        CodexServiceLoginReread(
            codex: folder,
            connect: { [unowned self] path in
                connects.append(path)
                if let connectFails { throw connectFails }
                return link
            },
            log: { [unowned self] name, details in lines.append((name, details)) }
        )
    }

    private func makeTheSocketFile() throws {
        let socket = folder.appendingPathComponent(CodexContinueRun.socketPath)
        try FileManager.default.createDirectory(
            at: socket.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: socket)
    }

    func testWithoutTheSocketNothingConnectsAndTheSkipIsLogged() {
        makeReread().rereadNow(for: "hat-work-123", expecting: "work@example.com")

        XCTAssertEqual(connects, [])
        XCTAssertEqual(lines.map(\.0), ["codexService.loginReread.skipped"])
        XCTAssertEqual(lines.first?.1, ["hat": "hat-work", "reason": "noService"])
    }

    func testTheServiceRereadsTheLoginAndTheAccountItNowHoldsIsLogged() throws {
        try makeTheSocketFile()

        makeReread().rereadNow(for: "hat-work-123", expecting: "work@example.com")

        XCTAssertEqual(connects, [folder.appendingPathComponent(CodexContinueRun.socketPath).path])
        XCTAssertEqual(link.asked, 1)
        XCTAssertEqual(link.closed, 1)
        XCTAssertEqual(lines.map(\.0), ["codexService.loginReread.done"])
        XCTAssertEqual(lines.first?.1, ["hat": "hat-work", "account": "work@example.com"])
    }

    func testAServiceThatIsNotListeningIsASkipNotAFailure() throws {
        try makeTheSocketFile()
        connectFails = .noService("connection refused")

        makeReread().rereadNow(for: "hat-work-123", expecting: "work@example.com")

        XCTAssertEqual(lines.map(\.0), ["codexService.loginReread.skipped"])
        XCTAssertEqual(lines.first?.1, ["hat": "hat-work", "reason": "noService", "detail": "connection refused"])
    }

    func testARefusedCallIsLoggedAsAFailureAndTheLinkIsClosed() throws {
        try makeTheSocketFile()
        link.answer = .failure(CodexServiceError.refused(code: -32601, message: "unknown method"))

        makeReread().rereadNow(for: "hat-work-123", expecting: "work@example.com")

        XCTAssertEqual(link.closed, 1)
        XCTAssertEqual(lines.map(\.0), ["codexService.loginReread.failed"])
        XCTAssertEqual(lines.first?.1, ["hat": "hat-work", "detail": "refused: -32601 unknown method"])
    }

    func testAServiceStillOnAnotherAccountIsLoggedAsSuch() throws {
        try makeTheSocketFile()
        link.answer = .success("personal@example.com")

        makeReread().rereadNow(for: "hat-work-123", expecting: "work@example.com")

        XCTAssertEqual(lines.map(\.0), ["codexService.loginReread.otherAccount"])
        XCTAssertEqual(
            lines.first?.1,
            ["hat": "hat-work", "account": "personal@example.com", "expected": "work@example.com"]
        )
    }

    func testAServiceThatNamesNoAccountIsNotLoggedAsDone() throws {
        try makeTheSocketFile()
        link.answer = .success(nil)

        makeReread().rereadNow(for: "hat-work-123", expecting: "work@example.com")

        XCTAssertEqual(lines.map(\.0), ["codexService.loginReread.otherAccount"])
        XCTAssertEqual(lines.first?.1, ["hat": "hat-work", "account": "-", "expected": "work@example.com"])
    }
}
