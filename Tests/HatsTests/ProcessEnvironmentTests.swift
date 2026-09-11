import XCTest
@testable import Hats

final class ProcessEnvironmentTests: XCTestCase {
    private func procargs(argc: Int32, arguments: [String], environment: [String]) -> [UInt8] {
        var bytes = withUnsafeBytes(of: argc.littleEndian) { Array($0) }
        bytes += Array("/usr/local/bin/claude".utf8) + [0, 0, 0]
        for argument in arguments { bytes += Array(argument.utf8) + [0] }
        for entry in environment { bytes += Array(entry.utf8) + [0] }
        return bytes
    }

    func testAnArgumentThatLooksLikeAnAssignmentIsNotTheEnvironment() {
        let bytes = procargs(argc: 2,
                             arguments: ["claude", "ANTHROPIC_BASE_URL=trap"],
                             environment: ["HOME=/Users/x", "ANTHROPIC_BASE_URL=http://127.0.0.1:8787"])
        let environment = ProcessEnvironment.parsed(procargs: bytes)
        XCTAssertEqual(environment?["ANTHROPIC_BASE_URL"], "http://127.0.0.1:8787")
        XCTAssertEqual(environment?["HOME"], "/Users/x")
    }

    func testAnEmptyArgumentStillCountsTowardsArgc() {
        let bytes = procargs(argc: 3, arguments: ["claude", "", "--continue"], environment: ["A=1"])
        XCTAssertEqual(ProcessEnvironment.parsed(procargs: bytes), ["A": "1"],
                       "dropping empties before counting would hand the last argument over as a variable")
    }

    func testOnlyTheWantedNamesAreKeptWhenAskedFor() {
        let bytes = procargs(argc: 1, arguments: ["claude"],
                             environment: ["AWS_SECRET_ACCESS_KEY=hush", "ANTHROPIC_BASE_URL=http://127.0.0.1:8787"])
        XCTAssertEqual(ProcessEnvironment.parsed(procargs: bytes, keeping: ["ANTHROPIC_BASE_URL"]),
                       ["ANTHROPIC_BASE_URL": "http://127.0.0.1:8787"],
                       "another process's secrets never enter this app's memory as values")
        XCTAssertEqual(ProcessEnvironment.parsed(procargs: bytes, keeping: ["NOPE"]), [:])
    }

    func testAProcessWithNoEnvironmentReadsAsEmptyNotAsUnknown() {
        let bytes = procargs(argc: 1, arguments: ["claude"], environment: [])
        XCTAssertEqual(ProcessEnvironment.parsed(procargs: bytes), [:])
    }

    func testABufferThatCannotHoldItsOwnArgcIsUnknown() {
        XCTAssertNil(ProcessEnvironment.parsed(procargs: [0, 0, 0]))
        XCTAssertNil(ProcessEnvironment.parsed(procargs: procargs(argc: 5, arguments: ["claude"], environment: ["A=1"])),
                     "argc promises five strings and two arrive; guessing which are arguments would be guessing")
        XCTAssertNil(ProcessEnvironment.parsed(procargs: procargs(argc: -1, arguments: [], environment: [])))
    }

    func testAValueKeepsEverythingAfterTheFirstEqualsAndTheFirstNameWins() {
        let bytes = procargs(argc: 0, arguments: [], environment: ["X=a=b", "=nameless", "X=second", "plain"])
        XCTAssertEqual(ProcessEnvironment.parsed(procargs: bytes), ["X": "a=b"])
    }

    func testTheOwnProcessReadsBackThroughSysctl() throws {
        let read = try XCTUnwrap(
            ProcessEnvironment.read(pid: ProcessInfo.processInfo.processIdentifier).values
        )
        XCTAssertEqual(read["HOME"], ProcessInfo.processInfo.environment["HOME"])
        XCTAssertFalse(read.isEmpty)
    }

    func testAProcessThatIsNotOursIsUnreadableRatherThanGone() {
        XCTAssertEqual(ProcessEnvironment.read(pid: 0), .unreadable,
                       "the kernel task belongs to nobody who asks, and a refusal to read a process "
                           + "that IS running must not be reported as the process having exited")
    }

    func testASessionThatExitedBeforeTheReadIsGoneRatherThanUnreadable() throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try child.run()
        let pid = child.processIdentifier
        child.waitUntilExit()

        XCTAssertEqual(ProcessEnvironment.read(pid: pid), .processGone,
                       "a session that exited between the sweep and this read is absent, not a "
                           + "failure — telling the two apart is what lets the disagreement guard "
                           + "refuse only when it genuinely cannot see. Measured: KERN_PROCARGS2 "
                           + "answers EINVAL for an exited pid, for an out-of-range pid and for the "
                           + "kernel task alike, so the liveness question has to be asked with a "
                           + "signal instead")
    }

    func testARunningProcessThatRefusesToBeReadIsUnreadableRatherThanGone() {
        XCTAssertEqual(ProcessEnvironment.read(pid: 1), .unreadable,
                       "launchd is running and is not ours to read, and a refusal must not be "
                           + "reported as an exit — that is the direction that switches the guard off")
    }
}
