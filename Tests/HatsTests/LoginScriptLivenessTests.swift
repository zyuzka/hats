import XCTest
@testable import Hats

final class LoginScriptLivenessTests: XCTestCase {
    private let path = "/Users/x/Library/Application Support/Hats/login.command"

    func testTheScriptIsRunningWhenAProcessCarriesItsPath() {
        let table = ["/sbin/launchd", "/bin/sh \(path)", "/usr/bin/ssh-agent -l"]
        XCTAssertTrue(Terminal.isScriptRunning(among: table, scriptPath: path))
    }

    func testAnEmptyOrUnrelatedTableMeansItIsNotRunning() {
        XCTAssertFalse(Terminal.isScriptRunning(among: [], scriptPath: path))
        XCTAssertFalse(Terminal.isScriptRunning(among: ["/sbin/launchd", "claude"],
                                                scriptPath: path))
    }

    func testAnotherAccountsScriptOfTheSameNameIsNotThisOne() {
        let table = ["/bin/sh /Users/someone-else/Library/Application Support/Hats/login.command"]
        XCTAssertFalse(Terminal.isScriptRunning(among: table, scriptPath: path))
    }

    func testTheLoginGuardCannotSpendTheWholeSweepBudgetOnTheMainThread() throws {
        XCTAssertLessThan(Terminal.scriptCheckBudget, ProcessTable.budget,
                          "duty() is consulted from the popover and from canStartALogin, both on "
                              + "the main thread, and it asks isScriptRunning, which reads the "
                              + "whole process table. The five-second budget belongs to the sweep "
                              + "the writers pay for off a UI action; a guard that answers a person "
                              + "cannot hold the menu bar that long")

        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Hats/CLI.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        let budgeted = try NSRegularExpression(
            pattern: #"isScriptRunning\(\)[\s\S]{0,200}?ProcessTable\.read\([\s\S]{0,120}?within:"#
        )
        XCTAssertEqual(
            budgeted.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)), 1,
            "and it has to pass that budget rather than take the default, which is the shape the "
                + "concept was missed in: the enumeration behind the other guards listed callers of "
                + "everySessionThatHoldsAPort, while the door was ProcessTable.read, which has two"
        )
    }
}
