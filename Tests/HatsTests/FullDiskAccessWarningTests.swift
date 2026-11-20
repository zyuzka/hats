import XCTest
@testable import Hats

final class FullDiskAccessWarningTests: XCTestCase {
    func testWithFullDiskAccessThereIsNoWarning() {
        XCTAssertNil(HatsCopy.browserAccessWarning(hasFullDiskAccess: true, unreadable: [.stable]))
    }

    func testWithoutFullDiskAccessTheWarningSaysSoAndNamesWhatIsHidden() throws {
        let plain = try XCTUnwrap(HatsCopy.browserAccessWarning(hasFullDiskAccess: false, unreadable: []))
        let named = try XCTUnwrap(HatsCopy.browserAccessWarning(hasFullDiskAccess: false, unreadable: [.stable]))

        XCTAssertTrue(plain.contains("Full Disk Access"))
        XCTAssertFalse(plain.contains("Chrome"))
        XCTAssertTrue(named.contains("Chrome is hidden now"))
    }

    func testTheMenuBannerNamesTheAccessAndHowToGetIt() {
        XCTAssertTrue(HatsCopy.fullDiskAccessBanner.contains("Full Disk Access"))
        XCTAssertTrue(HatsCopy.fullDiskAccessBanner.contains("quit and open Hats again"))
        XCTAssertTrue(HatsCopy.fullDiskAccessButton.contains("Full Disk Access"))
        XCTAssertEqual(
            BrowserChoice.fullDiskAccessSettings?.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        )
    }

    func testTheAccessCheckOpensItsProbeAndAClosedOneMeansNoAccess() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let open = folder.appendingPathComponent("open")
        let closed = folder.appendingPathComponent("closed")
        try Data("x".utf8).write(to: open)
        try Data("x".utf8).write(to: closed)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: closed.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: closed.path) }

        let missing = folder.appendingPathComponent("missing")
        XCTAssertTrue(FullDiskAccess.isGranted(probes: [open]))
        XCTAssertFalse(FullDiskAccess.isGranted(probes: [closed]))
        XCTAssertFalse(FullDiskAccess.isGranted(probes: [missing]))
        XCTAssertFalse(FullDiskAccess.isGranted(probes: [missing, closed]), "the first probe that is there decides")
        XCTAssertTrue(FullDiskAccess.isGranted(probes: [missing, open]))
        XCTAssertFalse(FullDiskAccess.isGranted(probes: [closed, open]), "a closed Safari file is not overruled")
    }
}
