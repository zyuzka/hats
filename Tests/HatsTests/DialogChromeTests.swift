import AppKit
import XCTest
@testable import Hats

final class DialogChromeTests: XCTestCase {
    func testTheStandInForTheLogoTakesNoRoom() {
        XCTAssertEqual(HatDialogs.noLogo.size, NSSize(width: 1, height: 1),
                       "left alone an NSAlert draws the app icon at full size, which is what made "
                           + "the sign-in refusal look like a poster rather than a sentence. The "
                           + "alert itself cannot be built here: NSAlert needs a running "
                           + "application and segfaults in a unit test")
    }

    func testEveryDialogInTheAppIsBuiltThroughThatOneFactory() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Hats")
        let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
        var raw: [String] = []
        for file in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            guard text.contains("= NSAlert()") else { continue }
            raw.append(file.lastPathComponent)
        }

        XCTAssertEqual(raw, ["Dialogs.swift"],
                       "a dialog built straight from NSAlert() keeps the logo, and the next one "
                           + "written somewhere else would quietly bring it back: \(raw)")
    }
}
