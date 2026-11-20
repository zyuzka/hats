import XCTest
@testable import Hats

final class CodexContinueRunTests: XCTestCase {
    private let session = "01a1f45d-1f8b-70d2-9802-e99966ada0d2"
    private var root: URL!
    private var codex: URL!
    private var notes: URL!
    private let logged = Locked<[(String, [String: String])]>([])
    private let made = Locked<[FakeServiceLink]>([])
    private var runs: [CodexContinueRun] = []
    private var now = Date()
    private let on = CodexContinueRun.Wish(isOn: true, warnPercent: 60, savePercent: 70)

    private var lines: [(String, [String: String])] { logged.value }
    private var links: [FakeServiceLink] { made.value }

    override func setUpWithError() throws {
        try super.setUpWithError()
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("hats-ccr-\(UUID().uuidString)")
        root = base.appendingPathComponent("state")
        codex = base.appendingPathComponent("codex")
        notes = base.appendingPathComponent(CodexNotes.folderName)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(CodexCompactLimitSync.folderName),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try Data("note".utf8).write(to: notes.appendingPathComponent("\(session).md"))
        logged.value = []
        made.value = []
        runs = []
    }

    override func tearDown() {
        runs.forEach { $0.stop() }
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
        super.tearDown()
    }

    private func makeRun(lookEvery: TimeInterval = 3600, connect: CodexContinueRun.Connect? = nil) -> CodexContinueRun {
        let run = CodexContinueRun(
            root: root,
            codex: codex,
            notes: notes,
            lookEvery: lookEvery,
            connect: connect ?? { [made] _ in
                let link = FakeServiceLink()
                made.mutate { $0.append(link) }
                return link
            },
            log: { [logged] name, details in logged.mutate { $0.append((name, details)) } },
            now: { [unowned self] in now }
        )
        runs.append(run)
        return run
    }

    private func serviceIsUp() throws {
        let socket = codex.appendingPathComponent(CodexContinueRun.socketPath)
        try FileManager.default.createDirectory(at: socket.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: socket)
    }

    private func window(_ percent: Int, _ event: String = "Stop", ago: TimeInterval = 25) throws {
        let stamp = ISO8601DateFormatter().string(from: now.addingTimeInterval(-ago))
        let text = #"{"session": "\#(session)", "window": 475000, "percent": \#(percent), "event": "\#(event)", "#
            + #""written_at": "\#(stamp)"}"#
        let url = root.appendingPathComponent(CodexCompactLimitSync.folderName).appendingPathComponent("\(session).json")
        try Data(text.utf8).write(to: url)
    }

    private func settle(_ run: CodexContinueRun, _ wish: CodexContinueRun.Wish) {
        run.configure(wish)
        run.lookNow()
    }

    func testATurnEndedPastTheSaveThresholdIsContinuedOnceAndLogged() throws {
        try serviceIsUp()
        try window(72)
        let run = makeRun()
        settle(run, on)
        XCTAssertEqual(links.first?.steps, ["read", "read", "compact", "read", "turn"])
        XCTAssertEqual(links.first?.isClosed, true)
        XCTAssertEqual(lines.map(\.0), ["codexContinue.done"])
        XCTAssertEqual(lines.first?.1, ["session": session, "percent": "72"])
        now += 30
        try window(76, ago: 25)
        run.lookNow()
        XCTAssertEqual(links.count, 1, "past the threshold again after the action: nothing until below the warning")
    }

    func testTheRunLooksByItselfOnceConfigured() throws {
        try serviceIsUp()
        try window(72)
        makeRun(lookEvery: 0.05).configure(on)
        let deadline = Date().addingTimeInterval(3)
        while lines.isEmpty, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        XCTAssertEqual(lines.map(\.0), ["codexContinue.done"])
    }

    func testWithoutANoteTheThreadIsLeftAlone() throws {
        try serviceIsUp()
        try window(72)
        try FileManager.default.removeItem(at: notes.appendingPathComponent("\(session).md"))
        settle(makeRun(), on)
        XCTAssertTrue(links.isEmpty)
        XCTAssertEqual(lines.map(\.0), ["codexContinue.skipped"])
        XCTAssertEqual(lines.first?.1["reason"], "noNote")
    }

    func testANotesFolderOthersCanEnterCountsAsNoNote() throws {
        try serviceIsUp()
        try window(72)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: notes.path)
        settle(makeRun(), on)
        XCTAssertTrue(links.isEmpty)
        XCTAssertEqual(lines.first?.1["reason"], "noNote")
    }

    func testWithTheSwitchOffHatsSaysNothingAndDoesNothing() throws {
        try serviceIsUp()
        try window(72)
        settle(makeRun(), CodexContinueRun.Wish(isOn: false, warnPercent: 60, savePercent: 70))
        XCTAssertTrue(links.isEmpty)
        XCTAssertTrue(lines.isEmpty)
    }

    func testWithTheSaveThresholdOffNothingHappens() throws {
        try serviceIsUp()
        try window(72)
        settle(makeRun(), CodexContinueRun.Wish(isOn: true, warnPercent: 60, savePercent: nil))
        XCTAssertTrue(links.isEmpty)
        XCTAssertTrue(lines.isEmpty)
    }

    func testBelowTheSaveThresholdNothingHappens() throws {
        try serviceIsUp()
        try window(65)
        settle(makeRun(), on)
        XCTAssertTrue(links.isEmpty)
        XCTAssertTrue(lines.isEmpty)
    }

    func testWithoutTheServiceItIsSkippedOnceAndTriedAgainLater() throws {
        try window(72)
        let run = makeRun()
        settle(run, on)
        run.lookNow()
        XCTAssertEqual(lines.map(\.0), ["codexContinue.skipped"])
        XCTAssertEqual(lines.first?.1["reason"], "noService")
        try serviceIsUp()
        run.lookNow()
        XCTAssertEqual(lines.map(\.0), ["codexContinue.skipped", "codexContinue.done"])
    }

    func testAConnectionThatCannotBeMadeIsNoService() throws {
        try serviceIsUp()
        try window(72)
        let run = makeRun { _ in throw CodexServiceError.noService("connection refused") }
        settle(run, on)
        run.lookNow()
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines.first?.1["reason"], "noService")
    }

    func testAFailedHandshakeIsConnectFailedAndThatEndOfTurnIsNotTriedAgain() throws {
        try serviceIsUp()
        try window(72)
        let tries = Locked(0)
        let run = makeRun { _ in
            tries.mutate { $0 += 1 }
            throw CodexServiceError.handshake("status 403")
        }
        settle(run, on)
        run.lookNow()
        XCTAssertEqual(tries.value, 1)
        XCTAssertEqual(lines.map(\.0), ["codexContinue.failed"])
        XCTAssertEqual(lines.first?.1["reason"], "connectFailed")
        XCTAssertEqual(lines.first?.1["detail"], "status 403")
    }

    func testACompactionThatTimesOutIsNotRetriedUntilBelowTheWarningThreshold() throws {
        try serviceIsUp()
        try window(72)
        let run = makeRun { [made] _ in
            let link = FakeServiceLink()
            link.compaction = .success(.timedOut)
            made.mutate { $0.append(link) }
            return link
        }
        settle(run, on)
        XCTAssertEqual(lines.first?.1["reason"], "compactTimeout")
        now += 30
        try window(74, ago: 25)
        run.lookNow()
        XCTAssertEqual(links.count, 1, "a later end of turn past the threshold is not tried")
        now += 30
        try window(30, ago: 25)
        run.lookNow()
        now += 30
        try window(73, ago: 25)
        run.lookNow()
        XCTAssertEqual(links.count, 2, "below the warning threshold arms it again")
    }

    func testASecondSessionWhoseTurnEndedAgainWhileTheFirstWasCompactedIsReadAgain() throws {
        let other = "01a1f45d-1f8b-70d2-9802-e99966ada0d3"
        try Data("note".utf8).write(to: notes.appendingPathComponent("\(other).md"))
        try serviceIsUp()
        let folder = root.appendingPathComponent(CodexCompactLimitSync.folderName)
        let write = { [now] (id: String, percent: Int, ago: TimeInterval) in
            let stamp = ISO8601DateFormatter().string(from: now.addingTimeInterval(-ago))
            let text = #"{"session": "\#(id)", "window": 475000, "percent": \#(percent), "event": "Stop", "#
                + #""written_at": "\#(stamp)"}"#
            try Data(text.utf8).write(to: folder.appendingPathComponent("\(id).json"))
        }
        let first = session
        try write(first, 72, 25)
        try write(other, 74, 25)
        let run = makeRun { [made] _ in
            let link = FakeServiceLink()
            made.mutate { $0.append(link) }
            if made.value.count == 1 {
                try write(first, 30, 21)
                try write(other, 30, 21)
            }
            return link
        }

        settle(run, on)

        XCTAssertEqual(links.count, 1,
                       "the other session ended a new turn below the threshold while the first was compacted")
    }

    func testAnEndOfTurnThatAgedPastTenMinutesWhileWaitingIsLeftAlone() throws {
        try serviceIsUp()
        try window(72, ago: CodexContinue.freshFor + 1)
        settle(makeRun(), on)
        XCTAssertTrue(links.isEmpty)
    }

    func testAUserTurnIsSkippedAsActiveOnceAndTheSameEndOfTurnIsNotTriedAgain() throws {
        try serviceIsUp()
        try window(72)
        let run = makeRun { [made] _ in
            let link = FakeServiceLink()
            link.reads = [.success(FakeServiceLink.idle), .success(CodexThreadState(
                status: "active", isEphemeral: false, hasPath: true, isRoot: true
            ))]
            made.mutate { $0.append(link) }
            return link
        }
        settle(run, on)
        run.lookNow()
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(lines.map(\.0), ["codexContinue.skipped"])
        XCTAssertEqual(lines.first?.1["reason"], "active")
        XCTAssertFalse(links[0].steps.contains("compact"))
    }
}
