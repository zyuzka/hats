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
    private var queued: [() -> Void] = []

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
            log: { [unowned self] name, details in lines.append((name, details)) },
            run: { [unowned self] in queued.append($0) }
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

    func testTheAccountIsMatchedWithoutRegardToLetterCase() throws {
        try makeTheSocketFile()
        link.answer = .success("Work@Example.com")

        makeReread().rereadNow(for: "hat-work-123", expecting: "work@example.com")

        XCTAssertEqual(lines.map(\.0), ["codexService.loginReread.done"])
    }

    func testALoginThatNamesNoEmailTakesWhateverTheServiceHolds() throws {
        try makeTheSocketFile()
        link.answer = .success("work@example.com")

        makeReread().rereadNow(for: "hat-work-123", expecting: nil)

        XCTAssertEqual(lines.map(\.0), ["codexService.loginReread.done"])
    }

    func testTwoWritesInARowAskTheServiceOnceForTheLatestLogin() throws {
        try makeTheSocketFile()
        link.answer = .success("work@example.com")
        let reread = makeReread()

        reread.reread(for: "hat-personal", login: CodexFixture.login(CodexFixture.personal, refresh: "p-1"))
        reread.reread(for: "hat-work-123", login: CodexFixture.login(CodexFixture.work, refresh: "w-1"))
        queued.forEach { $0() }

        XCTAssertEqual(queued.count, 2)
        XCTAssertEqual(link.asked, 1)
        XCTAssertEqual(lines.map(\.0), ["codexService.loginReread.done"])
        XCTAssertEqual(lines.first?.1, ["hat": "hat-work", "account": "work@example.com"])
    }
}
