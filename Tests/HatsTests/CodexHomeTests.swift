import Darwin
import XCTest
@testable import Hats

final class CodexHomeTests: XCTestCase {
    private var home = CodexFixture.home()
    private let old = CodexFixture.login(CodexFixture.work, refresh: "old")
    private let new = CodexFixture.login(CodexFixture.personal, refresh: "new")

    override func tearDown() {
        try? FileManager.default.removeItem(at: home.url)
    }

    private func live() -> Data? { try? Data(contentsOf: home.auth) }

    private func assertRefused(_ expected: CodexError, file: StaticString = #filePath, line: UInt = #line) {
        let before = live()
        XCTAssertThrowsError(try home.swap(in: new) { _ in .write }, file: file, line: line) {
            XCTAssertEqual($0 as? CodexError, expected, file: file, line: line)
        }
        XCTAssertEqual(live(), before, "nothing was written", file: file, line: line)
    }

    func testTheStoreModeIsReadFromTheTopOfTheConfig() {
        XCTAssertNil(CodexHome.storeMode(in: "model = \"gpt\"\n"))
        XCTAssertEqual(CodexHome.storeMode(in: "cli_auth_credentials_store = \"keyring\" # here\n"), "keyring")
        XCTAssertEqual(CodexHome.storeMode(in: "cli_auth_credentials_store='file'"), "file")
        XCTAssertNil(CodexHome.storeMode(in: "[profiles.x]\ncli_auth_credentials_store = \"keyring\"\n"),
                     "a key inside a table is not the top-level setting")
    }

    func testAKeyringStoreIsRefusedBeforeAnyWrite() throws {
        try old.write(to: home.auth)
        try "cli_auth_credentials_store = \"auto\"\n".write(to: home.config, atomically: true, encoding: .utf8)

        assertRefused(.notStoredInAFile("cli_auth_credentials_store is auto"))
    }

    func testALinkIsRefused() throws {
        let elsewhere = home.url.appendingPathComponent("elsewhere.json")
        try old.write(to: elsewhere)
        try FileManager.default.createSymbolicLink(at: home.auth, withDestinationURL: elsewhere)

        assertRefused(.liveUnusable("it is a link"))
        XCTAssertEqual(try Data(contentsOf: elsewhere), old)
    }

    func testAReadOnlyFileIsRefused() throws {
        try old.write(to: home.auth)
        chmod(home.auth.path, 0o400)
        defer { chmod(home.auth.path, 0o600) }

        assertRefused(.liveUnusable("it is read-only"))
    }

    func testAFileWithSeveralHardLinksIsRefused() throws {
        try old.write(to: home.auth)
        link(home.auth.path, home.url.appendingPathComponent("twin.json").path)

        assertRefused(.liveUnusable("it has 2 hard links"))
    }

    func testABrokenOrForeignFileIsRefused() throws {
        try Data("{ broken".utf8).write(to: home.auth)
        assertRefused(.liveUnusable("it is not valid JSON"))

        try Data(#"{"auth_mode":"apikey","OPENAI_API_KEY":"sk"}"#.utf8).write(to: home.auth)
        assertRefused(.liveUnusable("it is not a ChatGPT login"))
    }

    func testAMissingFileIsCreatedPrivateAndReadBack() throws {
        XCTAssertTrue(try home.swap(in: new) { live in
            XCTAssertNil(live)
            return .write
        })

        XCTAssertEqual(live(), new)
        XCTAssertEqual(home.permissions(), 0o600)
    }

    func testAFailedRenameLeavesThePreviousFileAndNoTemporaryFile() throws {
        try old.write(to: home.auth)
        home.rename = { _, _ in throw CodexError.writeFailed("disk full") }

        XCTAssertThrowsError(try home.swap(in: new) { _ in .write })

        XCTAssertEqual(live(), old)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: home.url.path)
            .filter { $0.hasPrefix(".auth-hats-") }
        XCTAssertEqual(leftovers, [])
    }

    func testAWriteThatDidNotReadBackIsUndoneWhileTheFileIsStillOurs() throws {
        try old.write(to: home.auth)
        home.rename = { from, to in
            try CodexHome.systemRename(from, to)
            chmod(to.path, 0o644)
        }

        XCTAssertThrowsError(try home.swap(in: new) { _ in .write }) {
            guard case .rolledBack = $0 as? CodexError else { return XCTFail("\($0)") }
        }
        XCTAssertEqual(live(), old)
    }

    func testAChangeByAnotherWriterIsLeftAlone() throws {
        try old.write(to: home.auth)
        let theirs = CodexFixture.login(CodexFixture.work, refresh: "theirs")
        home.rename = { from, to in
            try CodexHome.systemRename(from, to)
            chmod(to.path, 0o644)
            try theirs.write(to: to)
        }

        XCTAssertThrowsError(try home.swap(in: new) { _ in .write }) {
            guard case .leftAlone = $0 as? CodexError else { return XCTFail("\($0)") }
        }
        XCTAssertEqual(live(), theirs, "the rollback does not touch a login that is not Hats'")
    }

    func testBothLocksAreTakenInOrderAndKept() throws {
        try home.swap(in: new) { _ in .write }

        for lock in ["auth.lock", "auth.json.lock"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: home.url.appendingPathComponent(lock).path),
                          "\(lock) stays: Codex holds the same files")
        }
        XCTAssertEqual(home.locks.map(\.lastPathComponent), ["auth.lock", "auth.json.lock"])
    }

    func testAHeldLockStopsTheWriteAfterTheWait() throws {
        try old.write(to: home.auth)
        let fd = open(home.url.appendingPathComponent("auth.json.lock").path, O_RDWR | O_CREAT, 0o600)
        defer { close(fd) }
        XCTAssertEqual(flock(fd, LOCK_EX), 0)

        assertRefused(.lockTimedOut("auth.json.lock"))
    }

    func testKeepWritesNothing() throws {
        try old.write(to: home.auth)

        XCTAssertFalse(try home.swap(in: new) { _ in .keep })
        XCTAssertEqual(live(), old)
    }
}
