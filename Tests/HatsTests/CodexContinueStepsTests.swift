import XCTest
@testable import Hats

final class FakeServiceLink: CodexServiceLink {
    var reads: [Result<CodexThreadState, CodexServiceError>] = []
    var compaction: Result<CodexCompaction, CodexServiceError> = .success(.idle)
    var turn: Result<Void, CodexServiceError> = .success(())
    private(set) var steps: [String] = []
    private(set) var turnText: String?
    private(set) var isClosed = false

    static let idle = CodexThreadState(status: "idle", isEphemeral: false, hasPath: true, isRoot: true)

    func read(_ thread: String) throws -> CodexThreadState {
        steps.append("read")
        let next = reads.isEmpty ? .success(Self.idle) : reads.removeFirst()
        return try next.get()
    }

    func compact(_ thread: String, within: TimeInterval) throws -> CodexCompaction {
        steps.append("compact")
        return try compaction.get()
    }

    func startTurn(_ thread: String, text: String) throws {
        steps.append("turn")
        turnText = text
        try turn.get()
    }

    func close() { isClosed = true }
}

final class CodexContinueStepsTests: XCTestCase {
    private func state(_ status: String, ephemeral: Bool = false, path: Bool = true, root: Bool = true) -> CodexThreadState {
        CodexThreadState(status: status, isEphemeral: ephemeral, hasPath: path, isRoot: root)
    }

    func testAnIdleThreadIsReadTwiceCompactedReadAgainAndToldToGoOn() {
        let link = FakeServiceLink()
        let (outcome, compacted) = CodexContinueSteps.run("t", on: link)
        XCTAssertEqual(outcome, .done)
        XCTAssertTrue(compacted)
        XCTAssertEqual(link.steps, ["read", "read", "compact", "read", "turn"])
        XCTAssertEqual(
            link.turnText,
            "Hats: this thread was compacted at the save threshold. Continue the task from your resume note. "
                + "If the note says the task is done, say so in one line and stop."
        )
    }

    func testAThreadTheUserJustStartedATurnInIsLeftAlone() {
        let link = FakeServiceLink()
        link.reads = [.success(FakeServiceLink.idle), .success(state("active"))]
        let (outcome, compacted) = CodexContinueSteps.run("t", on: link)
        XCTAssertEqual(outcome, .skipped("active"))
        XCTAssertFalse(compacted)
        XCTAssertEqual(link.steps, ["read", "read"], "no compaction once the second read is not idle")
    }

    func testAMissingThreadIsNotLoaded() {
        let link = FakeServiceLink()
        link.reads = [.failure(.refused(code: -32600, message: "no thread"))]
        XCTAssertEqual(CodexContinueSteps.run("t", on: link).outcome, .skipped("notLoaded", detail: "-32600 no thread"))
        link.reads = [.success(state("notLoaded"))]
        XCTAssertEqual(CodexContinueSteps.run("t", on: link).outcome, .skipped("notLoaded"))
    }

    func testAThreadWithoutAFileOrOfASubagentIsLeftAlone() {
        for (read, reason) in [
            (state("idle", ephemeral: true), "ephemeral"),
            (state("idle", path: false), "noPath"),
            (state("idle", root: false), "notRoot"),
            (state("systemError"), "systemError"),
        ] {
            let link = FakeServiceLink()
            link.reads = [.success(read)]
            XCTAssertEqual(CodexContinueSteps.run("t", on: link).outcome, .skipped(reason))
            XCTAssertEqual(link.steps, ["read"])
        }
    }

    func testACompactionThatDoesNotEndIn60SecondsStartsNoTurn() {
        let link = FakeServiceLink()
        link.compaction = .success(.timedOut)
        let (outcome, compacted) = CodexContinueSteps.run("t", on: link)
        XCTAssertEqual(outcome, .failed("compactTimeout", detail: "no idle within 60 s"))
        XCTAssertTrue(compacted)
        XCTAssertFalse(link.steps.contains("turn"))
    }

    func testAConnectionLostAfterTheCompactionStartedCountsAsCompacted() {
        let link = FakeServiceLink()
        link.compaction = .success(.lost(.closed))
        let (outcome, compacted) = CodexContinueSteps.run("t", on: link)
        XCTAssertEqual(outcome, .failed("compactLost", detail: "closed: the service closed the connection"))
        XCTAssertTrue(compacted)
        XCTAssertFalse(link.steps.contains("turn"))
    }

    func testARefusedCompactionStartsNoTurn() {
        let link = FakeServiceLink()
        link.compaction = .failure(.refused(code: 1, message: "busy"))
        let (outcome, compacted) = CodexContinueSteps.run("t", on: link)
        XCTAssertEqual(outcome, .failed("compactRefused", detail: "refused: 1 busy"))
        XCTAssertFalse(compacted)
        XCTAssertFalse(link.steps.contains("turn"))
    }

    func testATurnTheUserStartedRightAfterTheCompactionIsLeftAlone() {
        let link = FakeServiceLink()
        link.reads = [.success(FakeServiceLink.idle), .success(FakeServiceLink.idle), .success(state("active"))]
        let (outcome, compacted) = CodexContinueSteps.run("t", on: link)
        XCTAssertEqual(outcome, .skipped("active"))
        XCTAssertTrue(compacted)
        XCTAssertFalse(link.steps.contains("turn"))
    }

    func testARefusedTurnIsAFailure() {
        let link = FakeServiceLink()
        link.turn = .failure(.closed)
        XCTAssertEqual(
            CodexContinueSteps.run("t", on: link).outcome,
            .failed("turnRefused", detail: "closed: the service closed the connection")
        )
    }

    func testALostConnectionWhileReadingIsAFailureNotASkip() {
        let link = FakeServiceLink()
        link.reads = [.failure(.timedOut("thread/read"))]
        XCTAssertEqual(
            CodexContinueSteps.run("t", on: link).outcome,
            .failed("readFailed", detail: "timedOut: thread/read")
        )
    }
}
