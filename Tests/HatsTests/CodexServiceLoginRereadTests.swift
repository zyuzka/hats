import XCTest
@testable import Hats

final class CodexRereadHarness {
    final class FakeLink: CodexLoginLink {
        var answer: Result<CodexServiceAccount, Error> = .success(CodexRereadHarness.work)
        var duringTheCall: (() -> Void)?
        var asked = 0
        var closed = 0

        func findAccountAfterRereadingLogin() throws -> CodexServiceAccount {
            asked += 1
            duringTheCall?()
            return try answer.get()
        }

        func close() { closed += 1 }
    }

    static let work = CodexServiceAccount(email: "work@example.com", owner: CodexFixture.work.owner)
    static let expectingWork: CodexServiceLoginReread.Expected = ("work@example.com", CodexFixture.work.owner)

    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("hats-reread-\(UUID().uuidString)")
    let link = FakeLink()
    var connects: [String] = []
    var connectFails: CodexServiceError?
    var lines: [(String, [String: String])] = []
    var queued: [() -> Void] = []

    var socket: URL { folder.appendingPathComponent(CodexContinueRun.socketPath) }

    func makeReread() -> CodexServiceLoginReread {
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

    func makeTheSocketFile() throws {
        try FileManager.default.createDirectory(
            at: socket.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: socket)
    }

    func runTheQueue() {
        while !queued.isEmpty { queued.removeFirst()() }
    }
}

final class CodexServiceLoginRereadTests: XCTestCase {
    private let harness = CodexRereadHarness()

    override func tearDown() {
        try? FileManager.default.removeItem(at: harness.folder)
        super.tearDown()
    }

    func testWithoutTheSocketNothingConnectsAndTheSkipIsLogged() {
        harness.makeReread().rereadNow(for: "hat-work-123", expecting: CodexRereadHarness.expectingWork)

        XCTAssertEqual(harness.connects, [])
        XCTAssertEqual(harness.lines.map(\.0), ["codexService.loginReread.skipped"])
        XCTAssertEqual(harness.lines.first?.1, ["hat": "hat-work", "reason": "noService"])
    }

    func testTheServiceRereadsTheLoginAndTheAccountItNowHoldsIsLogged() throws {
        try harness.makeTheSocketFile()

        harness.makeReread().rereadNow(for: "hat-work-123", expecting: CodexRereadHarness.expectingWork)

        XCTAssertEqual(harness.connects, [harness.socket.path])
        XCTAssertEqual(harness.link.asked, 1)
        XCTAssertEqual(harness.link.closed, 1)
        XCTAssertEqual(harness.lines.map(\.0), ["codexService.loginReread.done"])
        XCTAssertEqual(harness.lines.first?.1, ["hat": "hat-work", "account": "work@example.com"])
    }

    func testAServiceThatIsNotListeningIsASkipNotAFailure() throws {
        try harness.makeTheSocketFile()
        harness.connectFails = .noService("connection refused")

        harness.makeReread().rereadNow(for: "hat-work-123", expecting: CodexRereadHarness.expectingWork)

        XCTAssertEqual(harness.lines.map(\.0), ["codexService.loginReread.skipped"])
        XCTAssertEqual(
            harness.lines.first?.1,
            ["hat": "hat-work", "reason": "noService", "detail": "connection refused"]
        )
    }

    func testARefusedCallIsLoggedAsAFailureAndTheLinkIsClosed() throws {
        try harness.makeTheSocketFile()
        harness.link.answer = .failure(CodexServiceError.refused(code: -32601, message: "unknown method"))

        harness.makeReread().rereadNow(for: "hat-work-123", expecting: CodexRereadHarness.expectingWork)

        XCTAssertEqual(harness.link.closed, 1)
        XCTAssertEqual(harness.lines.map(\.0), ["codexService.loginReread.failed"])
        XCTAssertEqual(harness.lines.first?.1, ["hat": "hat-work", "detail": "refused: -32601 unknown method"])
    }

    func testTwoWritesInARowAskTheServiceOnceForTheLatestLogin() throws {
        try harness.makeTheSocketFile()
        let reread = harness.makeReread()

        reread.reread(for: "hat-personal", login: CodexFixture.login(CodexFixture.personal, refresh: "p-1"))
        reread.reread(for: "hat-work-123", login: CodexFixture.login(CodexFixture.work, refresh: "w-1"))
        XCTAssertEqual(harness.queued.count, 2)
        harness.runTheQueue()

        XCTAssertEqual(harness.link.asked, 1)
        XCTAssertEqual(harness.lines.map(\.0), ["codexService.loginReread.done"])
        XCTAssertEqual(harness.lines.first?.1, ["hat": "hat-work", "account": "work@example.com"])
    }

    func testAnAnswerForALoginReplacedDuringTheCallIsLeftToTheNewerOne() throws {
        try harness.makeTheSocketFile()
        let reread = harness.makeReread()
        reread.reread(for: "hat-personal", login: CodexFixture.login(CodexFixture.personal, refresh: "p-1"))
        harness.link.duringTheCall = { [harness] in
            harness.link.duringTheCall = nil
            reread.reread(for: "hat-work-123", login: CodexFixture.login(CodexFixture.work, refresh: "w-1"))
        }

        harness.runTheQueue()

        XCTAssertEqual(harness.link.asked, 2)
        XCTAssertEqual(harness.lines.map(\.0), ["codexService.loginReread.done"])
        XCTAssertEqual(harness.lines.first?.1, ["hat": "hat-work", "account": "work@example.com"])
    }
}
