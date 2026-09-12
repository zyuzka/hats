import AppKit
import XCTest
@testable import Hats

final class DialogChromeTests: XCTestCase {
    func testNoDialogIsAnNSAlertAnyMore() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Hats")
        let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
        var raw: [String] = []
        for file in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            guard text.contains("NSAlert") else { continue }
            raw.append(file.lastPathComponent)
        }

        XCTAssertEqual(raw, [],
                       "an NSAlert keeps a slot for the app icon whether or not one is set, which "
                           + "is the empty space this app went to its own windows to be rid of: "
                           + "\(raw)")
    }
}
