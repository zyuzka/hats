import XCTest
@testable import Hats

final class SessionStageContractTests: XCTestCase {
    private var work: URL!
    private let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("stage-contract-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: work)
    }

    private func findNode() throws -> URL {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let folders = path.split(separator: ":").map(String.init) + [
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ]
        for folder in folders {
            let node = URL(fileURLWithPath: folder).appendingPathComponent("node")
            if FileManager.default.isExecutableFile(atPath: node.path) { return node }
        }
        throw XCTSkip("node is not installed, so the mod's own writer cannot be run")
    }

    private var script: String {
        """
        import { writeStage } from '\(repository.appendingPathComponent("plugin/hooks/files.js").path)'
        import {
          createEvent,
          createLimits,
          getLimitsRecord,
          setEpisode,
        } from '\(repository.appendingPathComponent("plugin/hooks/limit-rules.js").path)'
        let text = ''
        for await (const chunk of process.stdin) text += chunk
        const input = JSON.parse(text)
        const written = []
        const getEvent = event => (event ? createEvent(event) : null)
        const getLimits = readings => {
          const limits = createLimits()
          for (const reading of readings) {
            const thresholds = { warn: reading.warn, save: reading.save }
            const episode = setEpisode(limits, { kind: reading.kind, reading, thresholds })
            episode.warned = episode.warned ?? getEvent(reading.warned)
            episode.asked = episode.asked ?? getEvent(reading.asked)
          }
          return getLimitsRecord(limits)
        }
        for (const record of input.records) {
          if (record.limitReadings) record.limits = getLimits(record.limitReadings)
          const $ = {
            env: { get: async name => input.env[name] ?? '' },
            fs: {
              stat: async path => {
                if (path.endsWith('.json')) throw new Error('absent')
                return { kind: 'dir', isLink: false }
              },
              write: async (path, text) => { written.push({ path, text }) },
            },
            clock: { now: async () => input.now },
          }
          await writeStage($, record)
        }
        process.stdout.write(JSON.stringify(written))
        """
    }

    private func runTheMod(_ records: [[String: Any]], env: [String: String]) throws -> [(path: String, text: String)] {
        let process = Process()
        process.executableURL = try findNode()
        process.arguments = ["--input-type=module", "-e", script]
        let output = Pipe()
        let entry = Pipe()
        process.standardOutput = output
        process.standardInput = entry
        try process.run()
        let input: [String: Any] = [
            "records": records,
            "env": env,
            "now": now.timeIntervalSince1970 * 1000,
        ]
        entry.fileHandleForWriting.write(try JSONSerialization.data(withJSONObject: input))
        try entry.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "the mod's writer ran")
        let written = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: String]])

        return written.map { ($0["path"] ?? "", $0["text"] ?? "") }
    }

    private func record(
        _ id: String,
        stage: String,
        rounds: (Int, Int),
        percent: Int?,
        thresholds: (Int?, Int?) = (45, 55),
        reason: String? = nil,
        after: AfterSave = .offerClear,
        drainMinutes: Int? = nil
    ) -> [String: Any] {
        let limits: [String: Any] = [
            "warn": thresholds.0 ?? NSNull(),
            "save": thresholds.1 ?? NSNull(),
            "after": after.rawValue,
        ]

        return [
            "id": id,
            "cwd": "/tmp/probe",
            "stage": stage,
            "warnRound": rounds.0,
            "saveRound": rounds.1,
            "percent": percent ?? NSNull(),
            "thresholds": limits,
            "reason": reason ?? NSNull(),
            "marker": stage == "saved" ? "/tmp/probe-config/state/handoff/123-456.json" : NSNull(),
            "drainMinutes": drainMinutes ?? NSNull(),
        ]
    }

    func testEveryStageTheModWritesIsReadByHatsWithTheSameRoundsAndNumbers() throws {
        let session = "5a32129e-d019-4c3e-9f7a-2b1c0d9e8f70"
        let cases: [([String: Any], SessionStage)] = [
            (record(session, stage: "warned", rounds: (1, 0), percent: 47), expect(session, .warned, (1, 0), 47)),
            (record(session, stage: "requested", rounds: (1, 1), percent: 56), expect(session, .requested, (1, 1), 56)),
            (record(session, stage: "saved", rounds: (1, 1), percent: 56), expect(session, .saved, (1, 1), 56)),
            (record("manual-1", stage: "saved", rounds: (0, 0), percent: 57, reason: "manual"),
             expect("manual-1", .saved, (0, 0), 57)),
            (record(session, stage: "failed", rounds: (1, 2), percent: 58, reason: "no marker this turn"),
             expect(session, .failed, (1, 2), 58)),
            (record(session, stage: "interrupted", rounds: (1, 2), percent: nil, reason: "plugin reloaded"),
             expect(session, .interrupted, (1, 2), nil)),
            (record("warn-only", stage: "warned", rounds: (1, 0), percent: 47, thresholds: (45, nil)),
             expect("warn-only", .warned, (1, 0), 47, save: nil)),
            (record(session, stage: "cleared", rounds: (1, 3), percent: 56, after: .clear),
             expect(session, .cleared, (1, 3), 56, after: .clear)),
            (record(session, stage: "kept", rounds: (1, 3), percent: 56, reason: "a draft is in the prompt", after: .clear),
             expect(session, .kept, (1, 3), 56, after: .clear)),
            (record(session, stage: "waiting", rounds: (1, 4), percent: 56, drainMinutes: 5),
             expect(session, .waiting, (1, 4), 56, drainMinutes: 5)),
            (record(session, stage: "warned", rounds: (1, 4), percent: 56, reason: "wait cancelled", drainMinutes: 5),
             expect(session, .warned, (1, 4), 56, drainMinutes: 5)),
        ]

        let written = try runTheMod(cases.map(\.0), env: [StateDirectory.overrideName: work.path])

        XCTAssertEqual(written.count, cases.count, "the mod wrote one file per record")
        for ((_, expected), file) in zip(cases, written) {
            let name = URL(fileURLWithPath: file.path).lastPathComponent
            try Data(file.text.utf8).write(to: work.appendingPathComponent(name))

            XCTAssertEqual(SessionStageFile.getRecord(name, in: work), .read(expected), file.text)
        }
    }

    private func expect(
        _ session: String,
        _ kind: SessionStageKind,
        _ rounds: (Int, Int),
        _ percent: Int?,
        save: Int? = 55,
        after: AfterSave = .offerClear,
        drainMinutes: Int? = nil
    ) -> SessionStage {
        SessionStage(
            session: session,
            cwd: "/tmp/probe",
            kind: kind,
            warnRound: rounds.0,
            saveRound: rounds.1,
            percent: percent,
            warnPercent: 45,
            savePercent: save,
            at: now,
            afterSave: after,
            drainMinutes: drainMinutes,
            limitEpisodes: [],
            limitTrouble: nil
        )
    }

    func testLimitEventsTheModWritesWithoutAWindowStageAreReadByHats() throws {
        let session = "5a32129e-d019-4c3e-9f7a-2b1c0d9e8f71"
        let resets = now.addingTimeInterval(3 * 3600)
        let warnedAt = now.addingTimeInterval(0.8)
        let askedAt = now.addingTimeInterval(60.115)
        let first: [String: Any] = [
            "kind": "five_hour",
            "percent": 72,
            "resetsMs": (resets.timeIntervalSince1970 - 2 * 3600) * 1000,
            "warn": 70,
            "save": 80,
            "warned": ["now": warnedAt.timeIntervalSince1970 * 1000, "percent": 72, "worn": "work", "reason": "no_hat"],
        ]
        let second: [String: Any] = [
            "kind": "five_hour",
            "percent": 81.5,
            "resetsMs": resets.timeIntervalSince1970 * 1000,
            "warn": 70,
            "save": 80,
            "asked": ["now": askedAt.timeIntervalSince1970 * 1000, "percent": 81.5, "worn": "work", "reason": "hats_not_running"],
        ]
        var input = record(session, stage: "warned", rounds: (0, 0), percent: nil)
        input["stage"] = NSNull()
        input["limitReadings"] = [first, second]

        let written = try runTheMod([input], env: [StateDirectory.overrideName: work.path])

        let file = try XCTUnwrap(written.first)
        let name = URL(fileURLWithPath: file.path).lastPathComponent
        try Data(file.text.utf8).write(to: work.appendingPathComponent(name))
        guard case .read(let stage) = SessionStageFile.getRecord(name, in: work) else {
            return XCTFail("Hats did not read the mod's record: \(file.text)")
        }
        XCTAssertNil(stage.kind)
        let events = stage.limitEpisodes.flatMap(\.events)
        XCTAssertEqual(events.map(\.stage), [.warned, .asked], file.text)
        XCTAssertEqual(events.map(\.reason), [.noHat, .hatsNotRunning])
        XCTAssertEqual(events.map(\.percent), [72, 81.5])
        XCTAssertEqual(events.map { LimitThresholdNotices.getMilliseconds(of: $0.at) }, [
            LimitThresholdNotices.getMilliseconds(of: warnedAt),
            LimitThresholdNotices.getMilliseconds(of: askedAt),
        ])
        XCTAssertEqual(
            Set(stage.limitEpisodes.map(\.resetsAt)),
            [resets, resets.addingTimeInterval(-2 * 3600)],
            "the current episode and the previous one"
        )
    }

    func testAnEarlySignalTheModWritesIsReadByHatsWithItsPaceFieldsAndToldOnce() throws {
        let session = "5a32129e-d019-4c3e-9f7a-2b1c0d9e8f71"
        let resets = now.addingTimeInterval(3 * 3600)
        let early: [String: Any] = ["target": 80, "lead": 682, "minutes": 11]
        let warned: [String: Any] = [
            "now": now.timeIntervalSince1970 * 1000 + 800,
            "percent": 58,
            "worn": "work",
            "reason": "no_hat",
            "early": early,
        ]
        let asked: [String: Any] = [
            "now": now.timeIntervalSince1970 * 1000 + 60_115,
            "percent": 81.5,
            "worn": "work",
            "reason": "no_hat",
            "target": 80,
            "lead": 682,
        ]
        let reading: [String: Any] = [
            "kind": "five_hour",
            "percent": 81.5,
            "resetsMs": resets.timeIntervalSince1970 * 1000,
            "warn": 70,
            "save": 80,
            "warned": warned,
            "asked": asked,
        ]
        var input = record(session, stage: "warned", rounds: (0, 0), percent: nil)
        input["stage"] = NSNull()
        input["limitReadings"] = [reading]

        let written = try runTheMod([input], env: [StateDirectory.overrideName: work.path])

        let file = try XCTUnwrap(written.first)
        let name = URL(fileURLWithPath: file.path).lastPathComponent
        try Data(file.text.utf8).write(to: work.appendingPathComponent(name))
        guard case .read(let stage) = SessionStageFile.getRecord(name, in: work) else {
            return XCTFail("Hats did not read the mod's record: \(file.text)")
        }
        let events = stage.limitEpisodes.flatMap(\.events)
        XCTAssertEqual(events.map(\.early), [true, false], file.text)
        XCTAssertEqual(events.map(\.minutesToSave), [11, nil])
        XCTAssertEqual(events.map(\.target), [80, 80])
        XCTAssertEqual(events.map(\.leadSeconds), [682, 682])
        var lines: [[String: String]] = []
        var bodies: [String] = []
        let notices = LimitThresholdNotices(
            root: work,
            launchedAt: now,
            notify: { bodies.append($0.body) },
            log: { event, details in if event == "limit.alert" { lines.append(details) } },
            now: { self.now.addingTimeInterval(120) }
        )
        notices.noteARead(SessionStagesRead(stages: [stage], listed: [session]))
        XCTAssertEqual(bodies, [
            "Spending fast: 80% in about 11 min. No other hat to switch to.",
            "No other hat to switch to. Sessions anchor at the end of their turn.",
        ])
        XCTAssertEqual(lines.map { $0["early"] }, ["1", "0"])
        XCTAssertEqual(lines.map { $0["minutes_to_save"] }, ["11", nil])
        XCTAssertEqual(lines.map { $0["episode"] }, [
            ISO8601DateFormatter().string(from: resets),
            ISO8601DateFormatter().string(from: resets),
        ])
    }

    func testTheModWritesStagesIntoTheFolderHatsMakesAndReads() throws {
        let stateHome = try XCTUnwrap(
            ProcessInfo.processInfo.environment[StateDirectory.overrideName],
            "run the suite with HATS_STATE_HOME set, as CLAUDE.md and CI do"
        )
        let one = [record("5a32129e-d019", stage: "warned", rounds: (1, 0), percent: 47)]

        let overridden = try runTheMod(one, env: [StateDirectory.overrideName: stateHome, "HOME": NSHomeDirectory()])
        let plain = try runTheMod(one, env: ["HOME": NSHomeDirectory()])

        XCTAssertEqual(
            overridden.first.map { URL(fileURLWithPath: $0.path).deletingLastPathComponent().path },
            WindowThresholdsFile().stageFolder.path
        )
        XCTAssertEqual(
            plain.first.map { URL(fileURLWithPath: $0.path).deletingLastPathComponent().path },
            StateDirectory.defaultLocation.appendingPathComponent(WindowThresholdsFile.stageFolderName).path,
            "with no HATS_STATE_HOME both take ~/Library/Application Support/Hats"
        )
    }
}
