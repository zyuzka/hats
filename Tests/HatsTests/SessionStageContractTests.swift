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
        let text = ''
        for await (const chunk of process.stdin) text += chunk
        const input = JSON.parse(text)
        const written = []
        for (const record of input.records) {
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
        after: AfterSave = .offerClear
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
        after: AfterSave = .offerClear
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
            afterSave: after
        )
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
