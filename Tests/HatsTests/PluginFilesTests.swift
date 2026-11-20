import XCTest
@testable import Hats

final class PluginFilesTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("plugin-files-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: folder)
    }

    private func path(_ name: String) -> String { folder.appendingPathComponent(name).path }

    func testAMissingFileIsMissing() {
        XCTAssertEqual(PluginFiles.getContents(of: path("settings.json")), .missing)
    }

    func testAFolderInPlaceOfTheFileIsUnreadable() throws {
        try FileManager.default.createDirectory(atPath: path("settings.json"), withIntermediateDirectories: false)

        let read = PluginFiles.getContents(of: path("settings.json"))

        XCTAssertEqual(read, .unreadable("it is not a regular file"))
        XCTAssertTrue(PluginFiles.isDirectory(path("settings.json")))
    }

    func testARegularFileIsRead() throws {
        try Data("{}\n".utf8).write(to: URL(fileURLWithPath: path("settings.json")))

        XCTAssertEqual(PluginFiles.getContents(of: path("settings.json")), .read(Data("{}\n".utf8)))
        XCTAssertFalse(PluginFiles.isDirectory(path("settings.json")))
    }

    func testALinkAndItsTargetAreTheSameFile() throws {
        try Data("x".utf8).write(to: URL(fileURLWithPath: path("python3")))
        try FileManager.default.createSymbolicLink(atPath: path("link"), withDestinationPath: path("python3"))

        XCTAssertTrue(PluginFiles.isSameFile(path("link"), path("python3")))
    }

    func testTwoDifferentFilesAreNotTheSame() throws {
        try Data("x".utf8).write(to: URL(fileURLWithPath: path("one")))
        try Data("x".utf8).write(to: URL(fileURLWithPath: path("two")))

        XCTAssertFalse(PluginFiles.isSameFile(path("one"), path("two")))
        XCTAssertFalse(PluginFiles.isSameFile(path("one"), path("missing")))
    }
}
