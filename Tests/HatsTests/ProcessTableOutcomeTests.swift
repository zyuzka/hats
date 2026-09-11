import XCTest
@testable import Hats

final class ProcessTableOutcomeTests: XCTestCase {
    private let usageText = Data("""
    usage: ps [-AaCcEefhjlMmrSTvwXx] [-O fmt | -o fmt] [-G gid[,gid...]]
              [-u]
    """.utf8)

    private let table = Data("""
    /bin/zsh
    /usr/local/bin/claude
    /bin/bash /Users/x/Library/Application Support/Hats/login.sh
    """.utf8)

    func testASuccessfulReadIsTheTable() {
        XCTAssertEqual(ProcessTable.output(data: table, reason: .exit, status: 0),
                       String(data: table, encoding: .utf8))
    }

    func testAnEmptyTableIsAnAnswerAndNotAFailure() {
        XCTAssertEqual(ProcessTable.output(data: Data(), reason: .exit, status: 0), "")
    }

    func testANonZeroStatusIsUnreadableEvenWithOutputOnStdout() {
        XCTAssertNil(ProcessTable.output(data: usageText, reason: .exit, status: 1))
    }

    func testAProcessKilledBySignalIsUnreadable() {
        XCTAssertNil(ProcessTable.output(data: table, reason: .uncaughtSignal, status: 9))
    }

    func testUsageTextWouldHaveAnsweredTheScriptQuestionWithNo() {
        let lines = String(data: usageText, encoding: .utf8)!
            .split(separator: "\n").map(String.init)

        XCTAssertFalse(Terminal.isScriptRunning(
            among: lines,
            scriptPath: "/Users/x/Library/Application Support/Hats/login.sh"))
        XCTAssertNil(ProcessTable.output(data: usageText, reason: .exit, status: 1))
    }

    func testATableCarryingTheScriptAnswersYes() {
        let lines = String(data: table, encoding: .utf8)!
            .split(separator: "\n").map(String.init)

        XCTAssertTrue(Terminal.isScriptRunning(
            among: lines,
            scriptPath: "/Users/x/Library/Application Support/Hats/login.sh"))
    }

    func testAReadThatOutstaysItsBudgetIsRefusedRatherThanWaitedOut() {
        let started = ContinuousClock.now

        let answer = ProcessTable.read(["5"], within: 0.2, running: "/bin/sleep")

        XCTAssertNil(answer, "a table that never arrived is not an empty table")
        XCTAssertLessThan(started.duration(to: .now), .seconds(2),
                          "before the budget the read was waitUntilExit with no deadline at all, so "
                              + "a stalled ps hung whichever thread asked - and activate asks from "
                              + "the main one, which is the whole interface")
    }

    func testAReadInsideItsBudgetStillAnswers() {
        XCTAssertNotNil(ProcessTable.read(["-eo", "pid="], within: 5),
                        "the ordinary path must be untouched by the deadline")
    }

    func testTheOutcomeIsReportedOnEachChangeAndNotOnEachFailure() {
        _ = ProcessTable.noteOutcome(timedOut: false, within: 1)

        XCTAssertEqual(ProcessTable.noteOutcome(timedOut: true, within: 1), "processTable.timedOut",
                       "the first failure is the signal and still goes in")
        XCTAssertNil(ProcessTable.noteOutcome(timedOut: true, within: 1),
                     "measured 2026-09-11: the line was written on every failure, and one burst put "
                         + "484 of them into ten minutes — 1218 of the journal's 1905 lines. "
                         + "Journal.log truncates past 200 KB and keeps the last 500, so a run of "
                         + "these evicts the switch and renewal history the file exists for")
        XCTAssertNil(ProcessTable.noteOutcome(timedOut: true, within: 1))
        XCTAssertEqual(ProcessTable.noteOutcome(timedOut: false, within: 1),
                       "processTable.answeredAgain",
                       "and the other end of the interval, so a reader can tell a burst that "
                           + "stopped from one still running")
        XCTAssertNil(ProcessTable.noteOutcome(timedOut: false, within: 1),
                     "the state is static and outlives one test method, which is why this check "
                         + "drives it to a known value first instead of assuming the initial one — "
                         + "testAReadThatOutstaysItsBudget moves the same state")
    }
}
