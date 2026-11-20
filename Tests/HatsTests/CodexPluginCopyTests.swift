import XCTest
@testable import Hats

final class CodexPluginCopyTests: XCTestCase {
    private var root: URL!
    private var copy: String { root.appendingPathComponent("copy").path }
    private var folder: String { root.appendingPathComponent("folder").path }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("codex-copy-\(UUID().uuidString)")
        for side in ["copy", "folder"] {
            try write("plugin.json", "{}", in: side)
            try write("scripts/window.py", "print(1)\n", in: side)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ name: String, _ text: String, in side: String) throws {
        let url = root.appendingPathComponent(side).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func testTheSameFilesAreTheSame() {
        XCTAssertEqual(CodexPluginCopy.compare(copy: copy, folder: folder), .same)
    }

    func testOtherContentDiffers() throws {
        try write("scripts/window.py", "print(2)\n", in: "folder")

        XCTAssertEqual(CodexPluginCopy.compare(copy: copy, folder: folder), .differs("scripts/window.py differs"))
    }

    func testAnotherSetOfFilesDiffers() throws {
        try write("scripts/note_back.py", "", in: "folder")
        XCTAssertEqual(
            CodexPluginCopy.compare(copy: copy, folder: folder),
            .differs("scripts/note_back.py is only in the folder")
        )

        try write("scripts/note_back.py", "", in: "copy")
        try write("old.py", "", in: "copy")
        XCTAssertEqual(CodexPluginCopy.compare(copy: copy, folder: folder), .differs("old.py is only in Codex's copy"))
    }

    func testAMissingCopyDiffers() throws {
        try FileManager.default.removeItem(atPath: copy)

        XCTAssertEqual(CodexPluginCopy.compare(copy: copy, folder: folder), .differs("Codex has no copy at \(copy)"))
    }

    func testAMissingFolderIsUnreadable() throws {
        try FileManager.default.removeItem(atPath: folder)

        guard case .unreadable(let reason) = CodexPluginCopy.compare(copy: copy, folder: folder) else {
            return XCTFail("a missing folder gives no Refresh")
        }
        XCTAssertTrue(reason.hasPrefix("the folder \(folder) could not be read"))
    }

    func testALinkIsComparedAsALinkAndNotFollowed() throws {
        try write("outside.txt", "secret", in: "elsewhere")
        let outside = root.appendingPathComponent("elsewhere/outside.txt").path
        try FileManager.default.createSymbolicLink(atPath: folder + "/link", withDestinationPath: outside)
        try FileManager.default.createSymbolicLink(atPath: copy + "/link", withDestinationPath: outside)
        XCTAssertEqual(CodexPluginCopy.compare(copy: copy, folder: folder), .same)

        try FileManager.default.removeItem(atPath: copy + "/link")
        try write("link", "secret", in: "copy")
        XCTAssertEqual(CodexPluginCopy.compare(copy: copy, folder: folder), .differs("link differs"),
                       "a file with the content the link points at is not the link")
    }

    func testALinkedFolderIsNotWalked() throws {
        try FileManager.default.createSymbolicLink(atPath: folder + "/loop", withDestinationPath: folder)
        try FileManager.default.createSymbolicLink(atPath: copy + "/loop", withDestinationPath: folder)

        XCTAssertEqual(CodexPluginCopy.compare(copy: copy, folder: folder), .same)
    }

    func testARootThatIsALinkToAFolderIsFollowed() throws {
        let linked = root.appendingPathComponent("linked").path
        try FileManager.default.createSymbolicLink(atPath: linked, withDestinationPath: folder)

        XCTAssertEqual(CodexPluginCopy.compare(copy: copy, folder: linked), .same)
    }

    func testBytecodeAndFinderFilesAreIgnored() throws {
        try write("scripts/__pycache__/hats_codex.cpython-313.pyc", "x", in: "copy")
        try write(".DS_Store", "x", in: "folder")

        XCTAssertEqual(CodexPluginCopy.compare(copy: copy, folder: folder), .same)
    }

    func testAFileOverTheCapIsUnreadable() throws {
        let big = String(repeating: "a", count: CodexPluginCopy.fileCap + 1)
        try write("big.bin", big, in: "copy")

        guard case .unreadable(let reason) = CodexPluginCopy.compare(copy: copy, folder: folder) else {
            return XCTFail("a file over the cap is not read")
        }
        XCTAssertTrue(reason.contains("big.bin is larger than 4 MB"))
    }
}
