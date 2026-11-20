import Darwin
import XCTest
@testable import Hats

final class WindowThresholdsFileTests: XCTestCase {
    private static let keys: Set<String> = [
        "warn_percent",
        "save_percent",
        "after_save",
        "drain",
        "drain_minutes",
        "limit_warn_percent",
        "limit_save_percent",
        "written_at",
    ]
    private var root: URL!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("window-thresholds-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func thresholds(_ warn: Int?, _ save: Int?, _ after: AfterSave = .offerClear) -> ContextThresholds {
        var made = ContextThresholds()
        made.warnPercent = warn
        made.savePercent = save
        made.afterSave = after

        return made
    }

    private func written(_ file: WindowThresholdsFile) throws -> [String: Any] {
        let data = try Data(contentsOf: file.url)

        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func source(_ name: String) -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(name)

        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func testTheFileCarriesTheThresholdsTheActionAndTheTimeOfWriting() throws {
        var file = WindowThresholdsFile(root: root)

        XCTAssertEqual(file.setThresholds(thresholds(45, 55, .offerClear), limits: LimitThresholds(), at: now), .written)

        let fields = try written(file)
        XCTAssertEqual(file.url, root.appendingPathComponent("window-thresholds.json"))
        XCTAssertEqual(fields["warn_percent"] as? Int, 45)
        XCTAssertEqual(fields["save_percent"] as? Int, 55)
        XCTAssertEqual(fields["after_save"] as? String, "offer_clear")
        XCTAssertEqual(fields["written_at"] as? String, "2027-01-15T08:00:00Z")
        XCTAssertEqual(fields["drain"] as? Bool, false)
        XCTAssertEqual(fields["drain_minutes"] as? Int, 10)
        XCTAssertEqual(Set(fields.keys), Self.keys)
    }

    func testTheFileCarriesTheDrainAndItsMinutesAndIsRewrittenWhenTheyChange() throws {
        var file = WindowThresholdsFile(root: root)
        var chosen = thresholds(45, 55, .tell)
        XCTAssertEqual(file.setThresholds(chosen, limits: LimitThresholds(), at: now), .written)
        chosen.drain = true
        chosen.drainMinutes = 5

        XCTAssertEqual(file.setThresholds(chosen, limits: LimitThresholds(), at: now), .written)

        let fields = try written(file)
        XCTAssertEqual(fields["drain"] as? Bool, true)
        XCTAssertEqual(fields["drain_minutes"] as? Int, 5)
        let text = try String(contentsOf: file.url, encoding: .utf8)
        XCTAssertTrue(text.contains(#""drain" : true"#), "a JSON boolean, which the mod takes only as true: \(text)")
    }

    func testAnOffThresholdIsAnExplicitNullAndEachActionHasItsName() throws {
        var file = WindowThresholdsFile(root: root)
        let cases: [(ContextThresholds, Any, Any, String)] = [
            (thresholds(30, nil, .tell), 30, NSNull(), "tell"),
            (thresholds(nil, 70, .offerExit), NSNull(), 70, "offer_exit"),
            (thresholds(nil, nil, .offerClear), NSNull(), NSNull(), "offer_clear"),
            (thresholds(45, 55, .clear), 45, 55, "clear"),
        ]
        for (chosen, warn, save, after) in cases {
            XCTAssertEqual(file.setThresholds(chosen, limits: LimitThresholds(), at: now), .written)

            let fields = try written(file)
            XCTAssertEqual(fields["warn_percent"] as? NSObject, warn as? NSObject, "\(chosen)")
            XCTAssertEqual(fields["save_percent"] as? NSObject, save as? NSObject, "\(chosen)")
            XCTAssertEqual(fields["after_save"] as? String, after)
            XCTAssertEqual(Set(fields.keys), Self.keys,
                           "the key stays when the value is null: the mod reads a missing key as a broken file")
        }
    }

    func testTheStageFolderIsMadeForHatsAloneWhenItIsMissing() throws {
        var file = WindowThresholdsFile(root: root)

        XCTAssertEqual(file.setThresholds(ContextThresholds(), limits: LimitThresholds(), at: now), .written)

        var facts = stat()
        XCTAssertEqual(lstat(root.appendingPathComponent("session-thresholds").path, &facts), 0)
        XCTAssertEqual(facts.st_mode & S_IFMT, S_IFDIR)
        XCTAssertEqual(facts.st_mode & 0o777, 0o700)

        try FileManager.default.removeItem(at: file.stageFolder)
        XCTAssertEqual(file.setThresholds(ContextThresholds(), limits: LimitThresholds(), at: now), .unchanged)
        XCTAssertEqual(lstat(file.stageFolder.path, &facts), 0, "a folder removed later is made again on the next write")
    }

    func testTheFileIsRewrittenOnlyWhenTheThresholdsChange() throws {
        var file = WindowThresholdsFile(root: root)
        XCTAssertEqual(file.setThresholds(thresholds(45, 55), limits: LimitThresholds(), at: now), .written)
        let inode = try FileManager.default.attributesOfItem(atPath: file.url.path)[.systemFileNumber] as? Int

        XCTAssertEqual(file.setThresholds(thresholds(45, 55), limits: LimitThresholds(), at: now.addingTimeInterval(60)), .unchanged)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: file.url.path)[.systemFileNumber] as? Int, inode)
        XCTAssertEqual(try written(file)["written_at"] as? String, "2027-01-15T08:00:00Z")

        XCTAssertEqual(file.setThresholds(thresholds(45, 55, .tell), limits: LimitThresholds(), at: now.addingTimeInterval(120)), .written)
        XCTAssertEqual(try written(file)["after_save"] as? String, "tell")
    }

    func testADeletedFileComesBackOnTheNextWrite() throws {
        var file = WindowThresholdsFile(root: root)
        XCTAssertEqual(file.setThresholds(ContextThresholds(), limits: LimitThresholds(), at: now), .written)
        try FileManager.default.removeItem(at: file.url)

        XCTAssertEqual(file.setThresholds(ContextThresholds(), limits: LimitThresholds(), at: now.addingTimeInterval(60)), .written)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.url.path))
        XCTAssertEqual(file.setThresholds(ContextThresholds(), limits: LimitThresholds(), at: now.addingTimeInterval(120)), .unchanged)
    }

    func testAStageFolderThatIsAFileIsAFailureWhileTheThresholdsAreStillWritten() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: root.appendingPathComponent("session-thresholds"))
        var file = WindowThresholdsFile(root: root)

        let first = file.setThresholds(ContextThresholds(), limits: LimitThresholds(), at: now)

        XCTAssertEqual(first, .failed("session-thresholds: it is a link or not a folder"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.url.path), "the mod still gets its thresholds")
        XCTAssertEqual(file.setThresholds(ContextThresholds(), limits: LimitThresholds(), at: now), first, "the same trouble is reported again")
    }

    func testAFailedWriteIsJournaledOncePerReasonAndForgottenOnSuccess() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let blocked = root.appendingPathComponent("window-thresholds.json")
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        var lines: [[String: String]] = []
        let channel = ContextThresholdsChannel(root: root, launchedAt: now, notify: { _ in }, log: { event, details in
            if event == "windowThresholds.notSaved" { lines.append(details) }
        })

        channel.setThresholds(ContextThresholds(), limits: LimitThresholds(), at: now)
        channel.setThresholds(ContextThresholds(), limits: LimitThresholds(), at: now)
        XCTAssertEqual(lines.count, 1, "every redraw writes, so the same reason is told once")

        try FileManager.default.removeItem(at: blocked)
        channel.setThresholds(ContextThresholds(), limits: LimitThresholds(), at: now)
        XCTAssertTrue(FileManager.default.fileExists(atPath: blocked.path))
        try FileManager.default.removeItem(at: blocked)
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        channel.setThresholds(thresholds(30, 40), limits: LimitThresholds(), at: now)

        XCTAssertEqual(lines.count, 2, "a success forgets the reason, so the same failure later is told again")
        XCTAssertNotNil(lines.first?["reason"])
    }

    private func getBody(of function: String, in source: String) throws -> Substring {
        let start = try XCTUnwrap(source.range(of: function), "\(function) is gone")
        let rest = source[start.upperBound...]
        let end = rest.range(of: "\n    }\n")?.lowerBound ?? rest.endIndex

        return rest[..<end]
    }

    func testTwoDifferentFailuresInARowAreTwoJournalLinesAndARepeatIsNone() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let blocked = root.appendingPathComponent("window-thresholds.json")
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        var reasons: [String] = []
        let channel = ContextThresholdsChannel(root: root, launchedAt: now, notify: { _ in }, log: { event, details in
            if event == "windowThresholds.notSaved" { reasons.append(details["reason"] ?? "") }
        })

        channel.setThresholds(ContextThresholds(), limits: LimitThresholds(), at: now)
        try FileManager.default.removeItem(at: blocked)
        try FileManager.default.removeItem(at: root.appendingPathComponent("session-thresholds"))
        try Data("x".utf8).write(to: root.appendingPathComponent("session-thresholds"))
        channel.setThresholds(ContextThresholds(), limits: LimitThresholds(), at: now)
        channel.setThresholds(ContextThresholds(), limits: LimitThresholds(), at: now)
        channel.setThresholds(ContextThresholds(), limits: LimitThresholds(), at: now)

        XCTAssertEqual(reasons.count, 2, "\(reasons)")
        XCTAssertNotEqual(reasons.first, "", "the write failure names its reason")
        XCTAssertNotEqual(reasons.first, reasons.last)
        XCTAssertEqual(reasons.last, "session-thresholds: it is a link or not a folder")
    }

    func testAThresholdsFileDeletedBetweenTwoRedrawsComesBackFromTheChannel() throws {
        let channel = ContextThresholdsChannel(root: root, launchedAt: now, notify: { _ in }, log: { _, _ in })
        let file = root.appendingPathComponent("window-thresholds.json")
        channel.setThresholds(ContextThresholds(), limits: LimitThresholds(), at: now)
        try FileManager.default.removeItem(at: file)

        channel.setThresholds(ContextThresholds(), limits: LimitThresholds(), at: now.addingTimeInterval(60))

        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testEveryRedrawWritesTheThresholdsAndAChangeIsSavedAndRedrawn() throws {
        let redraw = try getBody(of: "    func redraw() {\n", in: source("Sources/Hats/AppDelegate+Redraw.swift"))
        let update = source("Sources/Hats/AppDelegate+ContextThresholds.swift")
        let main = source("Sources/Hats/main.swift")

        XCTAssertTrue(redraw.contains("        writeTheHatUsage()\n"
                                          + "        contextChannel.setThresholds(settings.contextThresholds, limits: settings.limitThresholds, at: Date())\n"),
                      "the file is written on every redraw, unconditionally, next to the hat usage")
        XCTAssertEqual(redraw.components(separatedBy: "contextChannel.setThresholds(").count, 2,
                       "once per redraw, and in redraw itself rather than elsewhere in the file")
        XCTAssertTrue(update.contains("settings.contextThresholds = thresholds\n        saveSettings()\n        redraw()"))
        XCTAssertTrue(main.contains("let contextChannel = ContextThresholdsChannel(launchedAt: Date())"))
        XCTAssertTrue(main.contains("        startTheContextChannel()\n"))
        XCTAssertTrue(update.contains("contextChannel.start { [weak self] in self?.sessionWindows.windows ?? [] }"))
    }

    func testTheNamesHatsWritesAreTheNamesTheModReads() {
        let mod = source("plugin/hooks/thresholds.js") + source("plugin/hooks/files.js")

        XCTAssertTrue(mod.contains("THRESHOLDS_FILE = '\(WindowThresholdsFile.name)'"))
        XCTAssertTrue(mod.contains("STAGE_FOLDER = '\(WindowThresholdsFile.stageFolderName)'"))
        for key in ["data.warn_percent", "data.save_percent", "data.after_save"] {
            XCTAssertTrue(mod.contains(key), key)
        }
        for action in AfterSave.allCases {
            XCTAssertTrue(mod.contains("  '\(action.rawValue)',\n"), "the mod knows \(action.rawValue)")
        }
        for key in ["data.drain === true", "data.drain_minutes"] {
            XCTAssertTrue(mod.contains(key), key)
        }
        XCTAssertTrue(mod.contains("const MINUTES_RANGE = { low: 1, high: 60 }"))
        XCTAssertTrue(mod.contains("drainMinutes: \(ContextThresholds.defaultDrainMinutes),"))
        XCTAssertEqual(ContextThresholds.drainMinutesRange, 1...60)
        XCTAssertTrue(mod.contains("const WARN_RANGE = { low: 10, high: 94 }"))
        XCTAssertTrue(mod.contains("const SAVE_RANGE = { low: 11, high: 95 }"))
        XCTAssertEqual(ContextThresholds.warnRange, 10...94)
        XCTAssertEqual(ContextThresholds.saveRange, 11...95)
    }

    func testTheDefaultFileLivesInTheStateFolder() {
        XCTAssertEqual(WindowThresholdsFile().url, StateDirectory.url.appendingPathComponent("window-thresholds.json"))
        XCTAssertEqual(WindowThresholdsFile().stageFolder, StateDirectory.url.appendingPathComponent("session-thresholds"))
    }
}
