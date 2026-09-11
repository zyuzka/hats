import XCTest
@testable import Hats

final class JournalDestinationTests: XCTestCase {
    func testOnlyTheAppItselfWritesTheOperatorsLog() {
        XCTAssertEqual(JournalDestination.of(bundleIdentifier: Journal.ours, ours: Journal.ours),
                       .theOperatorsLog)
        XCTAssertEqual(JournalDestination.of(bundleIdentifier: "com.apple.dt.xctest.tool",
                                             ours: Journal.ours),
                       .standardError,
                       "measured: that is what this suite's process calls itself, so asking whether "
                           + "a bundle identifier merely exists answers yes inside the tests")
        XCTAssertEqual(JournalDestination.of(bundleIdentifier: nil, ours: Journal.ours),
                       .standardError)
    }

    func testThisTestProcessIsNotTheApp() {
        XCTAssertEqual(Journal.destination, .standardError,
                       "the whole point: the suite must not be able to reach the file")
    }

    func testLoggingFromTheSuiteLeavesNoLineInTheOperatorsLog() throws {
        let path = Journal.url.path
        try XCTSkipUnless(FileManager.default.fileExists(atPath: path),
                          "with no log on this machine the check would pass without measuring")
        let marker = "test.probe.\(UUID().uuidString)"

        Journal.log(marker, ["slot": "Hats parked personal"])

        let written = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertFalse(written.contains(marker),
                       "a suite run left ten renew lines carrying a fabricated account in the log a "
                           + "person reads to diagnose a real switch, and they were read as real once")
    }

    func testTheIdentifierIsTheOneTheBuildScriptStamps() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Build/build-app.sh")
        let text = try String(contentsOf: script, encoding: .utf8)
        XCTAssertTrue(text.contains("<string>\(Journal.ours)</string>"),
                      "the destination turns on this identifier matching the bundle the script "
                          + "assembles; a rename there would send the app's own journal to stderr "
                          + "and nothing would say so")
    }
}
