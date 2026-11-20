import Darwin
import XCTest
@testable import Hats

final class GroupRunTests: XCTestCase {
    private func run(_ executable: String,
                     _ arguments: [String],
                     environment: [String: String] = [:],
                     seconds: TimeInterval = 10) -> PluginCommandOutcome {
        GroupRun.getOutcome(of: PluginCommandLine(
            executable: executable,
            arguments: arguments,
            environment: environment,
            seconds: seconds
        ))
    }

    private func text(_ data: Data) -> String { String(bytes: data, encoding: .utf8) ?? "" }

    private func hasExited(_ pid: pid_t, within seconds: Int) -> Bool {
        let queue = kqueue()
        defer { close(queue) }
        var change = kevent(
            ident: UInt(pid),
            filter: Int16(EVFILT_PROC),
            flags: UInt16(EV_ADD | EV_ONESHOT),
            fflags: NOTE_EXIT,
            data: 0,
            udata: nil
        )
        var event = kevent()
        var limit = timespec(tv_sec: seconds, tv_nsec: 0)
        let count = kevent(queue, &change, 1, &event, 1, &limit)
        if count < 0 { return errno == ESRCH }
        if count == 0 { return false }

        return event.flags & UInt16(EV_ERROR) == 0 || Int32(event.data) == ESRCH
    }

    func testBothStreamsAndTheExitCodeAreRead() {
        let outcome = run("/bin/sh", ["-c", "echo out; echo err >&2; exit 3"])

        XCTAssertEqual(outcome.end, .exited(3))
        XCTAssertEqual(text(outcome.stdout), "out\n")
        XCTAssertEqual(text(outcome.stderr), "err\n")
        XCTAssertEqual(outcome.trouble, "exit code 3: err")
    }

    func testATimedOutCommandStopsWithEverythingItStarted() throws {
        let outcome = run("/bin/sh", ["-c", "sleep 60 & echo $!; wait"], seconds: 1)

        XCTAssertEqual(outcome.end, .timedOut)
        let child = try XCTUnwrap(pid_t(text(outcome.stdout).trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertTrue(hasExited(child, within: 5),
                      "the sleep the shell started belongs to the same group and is stopped with it")
    }

    func testEveryProcessOfTheGroupIsAskedToStopBeforeItIsKilled() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let marker = folder.appendingPathComponent("term").path
        let ready = folder.appendingPathComponent("ready").path
        let child = "trap 'echo got-term > \"\(marker)\"; exit 0' TERM; : > \"\(ready)\"; sleep 60 & wait"
        let parent = "trap 'wait' TERM; /bin/sh -c \"$0\" & wait"

        let outcome = run("/bin/sh", ["-c", parent, child], seconds: 3)

        XCTAssertEqual(outcome.end, .timedOut)
        XCTAssertTrue(FileManager.default.fileExists(atPath: ready),
                      "the child set its trap before the signal; without this a slow start reads as a lost SIGTERM")
        XCTAssertEqual(try? String(contentsOfFile: marker, encoding: .utf8), "got-term\n",
                       "SIGTERM goes to the whole group, so what claude started can clean up before SIGKILL")
    }

    func testAnExitInTimeKeepsItsCodeWhileADescendantHoldsTheOutput() throws {
        let outcome = run("/bin/sh", ["-c", "sleep 60 & echo $!"], seconds: 1)

        XCTAssertEqual(outcome.end, .exited(0), "the command itself answered in time")
        XCTAssertTrue(outcome.isTruncated, "what the descendant might still have written is lost, and that is said")
        let child = try XCTUnwrap(pid_t(text(outcome.stdout).trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertTrue(hasExited(child, within: 5), "the descendant holding the output is stopped with the group")
    }

    func testADescendantThatLeftTheGroupDoesNotKeepTheReaderWaiting() throws {
        let script = "perl -e '$| = 1; print \"$$\\n\"; setpgrp(0, 0); sleep 6; print \"late\\n\"; sleep 30' & "
            + "sleep 0.3; exit 0"
        var outcome: PluginCommandOutcome?
        let returned = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            outcome = self.run("/bin/sh", ["-c", script], seconds: 1)
            returned.signal()
        }

        let isReturned = returned.wait(timeout: .now() + 20) == .success

        XCTAssertTrue(isReturned, "reading stops once the group is stopped, even if a pipe stays open")
        let finished = try XCTUnwrap(outcome)
        XCTAssertEqual(finished.end, .exited(0))
        XCTAssertTrue(finished.isTruncated)
        let escaped = try XCTUnwrap(pid_t(text(finished.stdout).trimmingCharacters(in: .whitespacesAndNewlines)))
        defer { kill(escaped, SIGKILL) }
        XCTAssertTrue(hasExited(escaped, within: 15),
                      "the reader let go of the pipe, so the escaped writer dies on its next write instead of being read")
    }

    func testACommandThatIgnoresTermIsKilled() throws {
        let outcome = run("/bin/sh", ["-c", "trap '' TERM; echo $$; sleep 60"], seconds: 1)

        XCTAssertEqual(outcome.end, .timedOut)
        let shell = try XCTUnwrap(pid_t(text(outcome.stdout).trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertTrue(hasExited(shell, within: 5), "SIGKILL follows the grace period for a command deaf to SIGTERM")
    }

    func testOutputBeyondTheCapIsCutAndSaysSo() {
        let outcome = run("/usr/bin/head", ["-c", String(GroupRun.outputCap + 1000), "/dev/zero"])

        XCTAssertEqual(outcome.end, .exited(0))
        XCTAssertTrue(outcome.isTruncated)
        XCTAssertEqual(outcome.stdout.count, GroupRun.outputCap)
        XCTAssertNotNil(outcome.trouble, "a cut answer is a trouble even with exit code 0")
    }

    func testAMissingExecutableDoesNotStart() {
        let outcome = run("/nonexistent/claude", ["--version"])

        guard case .notStarted = outcome.end else { return XCTFail("expected notStarted, got \(outcome.end)") }
    }

    func testTheCommandGetsExactlyTheGivenEnvironmentTheRootFolderAndNoInput() {
        let environment = run("/usr/bin/env", [], environment: ["ONLY": "this"])
        let folder = run("/bin/pwd", [])
        let input = run("/bin/cat", [], seconds: 5)

        XCTAssertEqual(text(environment.stdout), "ONLY=this\n")
        XCTAssertEqual(text(folder.stdout), "/\n")
        XCTAssertEqual(input.end, .exited(0), "stdin is /dev/null, so a reader ends at once")
    }

    func testOpenDescriptorsOfHatsDoNotLeakIntoTheCommand() {
        var opened: [Int32] = [-1, -1]
        XCTAssertEqual(pipe(&opened), 0)
        let held = opened.map { fcntl($0, F_DUPFD, 300) }
        defer { (opened + held).forEach { close($0) } }

        let outcome = run("/bin/sh", ["-c", "ls /dev/fd"])

        let listed = Set(text(outcome.stdout).split(separator: "\n").compactMap { Int32($0) })
        XCTAssertFalse(listed.contains(held[0]), "listed \(listed), held \(held)")
        XCTAssertFalse(listed.contains(held[1]), "a gateway socket would stay open in claude the same way")
    }
}
