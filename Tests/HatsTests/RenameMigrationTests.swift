import XCTest
@testable import Hats

final class RenameMigrationTests: XCTestCase {
    private var root: URL!
    private var files: FileManager!

    override func setUpWithError() throws {
        files = FileManager.default
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hats-rename-\(UUID().uuidString)")
        try files.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? files.removeItem(at: root)
    }

    private func legacyAndCurrent() -> (legacy: URL, current: URL) {
        (root.appendingPathComponent("acc-switch"), root.appendingPathComponent("Hats"))
    }

    private func write(_ text: String, to url: URL) throws {
        try files.createDirectory(at: url.deletingLastPathComponent(),
                                  withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func testTheLegacyStateDirectoryIsAdoptedWhenTheNewOneIsAbsent() throws {
        let (legacy, current) = legacyAndCurrent()
        try write("{\"accounts\":[]}", to: legacy.appendingPathComponent("accounts.json"))

        StateDirectory.adopt(from: legacy, to: current, using: files)

        let moved = current.appendingPathComponent("accounts.json")
        XCTAssertTrue(files.fileExists(atPath: moved.path))
        XCTAssertEqual(try String(contentsOf: moved, encoding: .utf8), "{\"accounts\":[]}")
    }

    func testAnEmptyNewDirectoryDoesNotStopTheAdoption() throws {
        let (legacy, current) = legacyAndCurrent()
        try files.createDirectory(at: current, withIntermediateDirectories: true)
        try write("live", to: legacy.appendingPathComponent("operations.log"))

        StateDirectory.adopt(from: legacy, to: current, using: files)

        let moved = current.appendingPathComponent("operations.log")
        XCTAssertEqual(try String(contentsOf: moved, encoding: .utf8), "live")
    }

    func testAdoptionNeverOverwritesAFileTheNewDirectoryAlreadyHas() throws {
        let (legacy, current) = legacyAndCurrent()
        try write("old", to: legacy.appendingPathComponent("settings.json"))
        try write("new", to: current.appendingPathComponent("settings.json"))

        StateDirectory.adopt(from: legacy, to: current, using: files)

        let kept = current.appendingPathComponent("settings.json")
        XCTAssertEqual(try String(contentsOf: kept, encoding: .utf8), "new")
        XCTAssertTrue(files.fileExists(atPath: legacy.appendingPathComponent("settings.json").path))
    }

    func testParkedIDsAreFoundUnderBothTheCurrentAndTheLegacySlotName() {
        let dump = """
        keychain: "login"
        "acct"<blob>="probe"
        "svce"<blob>="Hats parked new-hat"
        keychain: "login"
        "acct"<blob>="probe"
        "svce"<blob>="TMK acc-switch parked old-hat"
        """

        let ids = Set(Keychain.parsedParkedIDs(dump: dump, account: "probe"))

        XCTAssertEqual(ids, ["new-hat", "old-hat"])
    }

    func testTheLegacyGatewayBlockIsRemovedFromAProfile() {
        let profile = [
            "export PATH=/usr/bin",
            ShellEnvironment.legacyOpenMarker,
            "export ANTHROPIC_BASE_URL=http://127.0.0.1:8787",
            ShellEnvironment.legacyCloseMarker,
        ].joined(separator: "\n")

        let after = ShellEnvironment.removed(from: profile)

        XCTAssertEqual(after, "export PATH=/usr/bin\n")
    }

    func testTheNewerLegacyLocationWinsOverTheOlderOne() throws {
        let claudeEra = root.appendingPathComponent("hats")
        let accSwitchEra = root.appendingPathComponent("acc-switch")
        let current = root.appendingPathComponent("Hats")
        try write("newer", to: claudeEra.appendingPathComponent("settings.json"))
        try write("older", to: accSwitchEra.appendingPathComponent("settings.json"))
        try write("older-only", to: accSwitchEra.appendingPathComponent("accounts.json"))

        for legacy in [claudeEra, accSwitchEra] {
            StateDirectory.adopt(from: legacy, to: current, using: files)
        }

        let settings = current.appendingPathComponent("settings.json")
        let accounts = current.appendingPathComponent("accounts.json")
        XCTAssertEqual(try String(contentsOf: settings, encoding: .utf8), "newer")
        XCTAssertEqual(try String(contentsOf: accounts, encoding: .utf8), "older-only")
    }

    func testAnEmptiedLegacyDirectoryIsRemoved() throws {
        let (legacy, current) = legacyAndCurrent()
        try write("x", to: legacy.appendingPathComponent("accounts.json"))

        StateDirectory.adopt(from: legacy, to: current, using: files)

        XCTAssertFalse(files.fileExists(atPath: legacy.path))
    }

    func testTheStateDirectoryLivesInApplicationSupportNotInTheClaudeDirectory() {
        let path = StateDirectory.defaultLocation.path

        XCTAssertTrue(path.hasSuffix("/Library/Application Support/Hats"), path)
        XCTAssertFalse(path.contains("/.claude/"), path)
    }

    func testBothClaudeEraLocationsAreStillAdoptedNewestFirst() {
        let paths = StateDirectory.legacyLocations.map(\.path)

        XCTAssertEqual(paths.count, 2)
        XCTAssertTrue(paths[0].hasSuffix("/.claude/state/hats"), paths[0])
        XCTAssertTrue(paths[1].hasSuffix("/.claude/state/acc-switch"), paths[1])
    }

    func testTheLegacyGatewayBlockIsReplacedByTheCurrentOne() {
        let profile = [
            ShellEnvironment.legacyOpenMarker,
            "export ANTHROPIC_BASE_URL=http://127.0.0.1:8787",
            ShellEnvironment.legacyCloseMarker,
        ].joined(separator: "\n")

        let after = ShellEnvironment.applied(
            to: profile,
            baseURL: "http://127.0.0.1:8787",
            dialect: .posix,
            serving: true
        )

        XCTAssertNotNil(after)
        XCTAssertTrue(after!.contains(ShellEnvironment.openMarker))
        XCTAssertFalse(after!.contains(ShellEnvironment.legacyOpenMarker))
        XCTAssertEqual(after!.components(separatedBy: ShellEnvironment.openMarker).count - 1, 1)
    }
}
