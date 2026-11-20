import XCTest
@testable import Hats

final class CodexSignInBrowserTests: XCTestCase {
    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("hats-browser-\(UUID().uuidString.prefix(8))")

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    func testTheSignInAddressGoesOnlyToTheHatsBrowserWrapper() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let record = folder.appendingPathComponent("opened.txt")
        let wrapper = folder.appendingPathComponent("hat-browser.sh")
        try "#!/bin/sh\nprintf '%s' \"$@\" > \(CLI.shellQuote(record.path))\n"
            .write(to: wrapper, atomically: true, encoding: .utf8)
        let url = try XCTUnwrap(URL(string: "https://auth.openai.com/oauth/authorize?state=s&code_challenge=c"))

        try CodexSignInFlow.open(url, with: wrapper)

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, !FileManager.default.fileExists(atPath: record.path) {
            Thread.sleep(forTimeInterval: 0.02)
        }
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertEqual(try String(contentsOf: record, encoding: .utf8), url.absoluteString,
                       "the address is the only argument the hat's wrapper gets")
    }

    func testAHatWithoutABrowserOfItsOwnOpensNothing() {
        let model = CodexSignInModel(title: "Signing in to Codex as work@example.com", text: "")

        XCTAssertThrowsError(try CodexSignInFlow().begin(model, hat: "work", browser: .systemDefault) { _ in }) {
            XCTAssertEqual($0 as? CodexError, .noBrowser("work"), "the default browser is never used")
        }
    }

    func testTheWrapperOpensTheChosenBrowserIdentity() throws {
        let override = ProcessInfo.processInfo.environment[StateDirectory.overrideName] ?? ""
        try XCTSkipIf(override.isEmpty, "the wrapper is written under StateDirectory")

        let safari = try String(contentsOf: try XCTUnwrap(BrowserChoice.safari.wrapperScript()), encoding: .utf8)
        let chrome = try String(
            contentsOf: try XCTUnwrap(BrowserChoice.chrome(.stable, "Profile 2").wrapperScript()),
            encoding: .utf8
        )

        XCTAssertTrue(safari.contains("exec open -a Safari \"$@\""))
        XCTAssertTrue(chrome.contains("--profile-directory='Profile 2' \"$@\""))
        XCTAssertNil(try BrowserChoice.systemDefault.wrapperScript())
    }
}
