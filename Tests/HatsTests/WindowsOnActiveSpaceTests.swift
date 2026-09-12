import XCTest
@testable import Hats

final class WindowsOnActiveSpaceTests: XCTestCase {
    func testEveryWindowTheAppOpensComesToTheDesktopInFrontOfYou() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Hats")
        let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
        var missing: [String] = []
        for file in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            guard text.contains("NSWindow(") else { continue }
            guard !text.contains("collectionBehavior") else { continue }
            missing.append(file.lastPathComponent)
        }

        XCTAssertEqual(missing, [],
                       "a window left on another desktop is invisible to the person who asked for "
                           + "it, and a modal one taken there blocks the whole app while the reason "
                           + "cannot be seen — measured on a live machine: settings on one desktop, "
                           + "the update prompt on another, and the app reading as frozen: \(missing)")
    }
}
