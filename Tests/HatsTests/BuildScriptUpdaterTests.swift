import XCTest
@testable import Hats

final class BuildScriptUpdaterTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private func plistTheBuildWrites() throws -> [String: Any] {
        let script = try String(contentsOf: root.appendingPathComponent("Build/build-app.sh"), encoding: .utf8)
        let opening = try XCTUnwrap(script.range(of: "<<'PLIST'\n"), "the Info.plist is a quoted heredoc")
        let closing = try XCTUnwrap(script.range(of: "\nPLIST\n", range: opening.upperBound..<script.endIndex))
        let body = Data(script[opening.upperBound..<closing.lowerBound].utf8)
        let parsed = try PropertyListSerialization.propertyList(from: body, format: nil)

        return try XCTUnwrap(parsed as? [String: Any])
    }

    func testTheBuildNumberIsTheVersionAPersonSees() throws {
        let plist = try plistTheBuildWrites()
        let shown = try XCTUnwrap(plist["CFBundleShortVersionString"] as? String)
        let build = try XCTUnwrap(plist["CFBundleVersion"] as? String)
        XCTAssertEqual(
            build,
            shown,
            "Sparkle compares CFBundleVersion with the feed's sparkle:version, which the packaging writes "
                + "from the shown version; a build number stuck at 1 would make every release look the same"
        )
    }

    func testTheUpdaterChecksByItselfAndInstallsOnlyWhenAsked() throws {
        let plist = try plistTheBuildWrites()
        XCTAssertEqual(
            plist["SUFeedURL"] as? String,
            "https://github.com/zyuzka/hats/releases/latest/download/appcast.xml"
        )
        XCTAssertEqual(
            plist["SUEnableAutomaticChecks"] as? Bool,
            true,
            "unset, Sparkle asks permission on the second launch instead of checking"
        )
        XCTAssertEqual(
            plist["SUScheduledCheckInterval"] as? Int,
            21600,
            "six hours"
        )
        XCTAssertEqual(
            plist["SUAllowsAutomaticUpdates"] as? Bool,
            false,
            "with it on, the update window offers to install without asking next time"
        )
        XCTAssertNil(plist["SUAutomaticallyUpdate"], "installation happens only on a person's click")
        XCTAssertNil(plist["SUEnableInstallerLauncherService"], "that service is for sandboxed apps")
        XCTAssertNil(
            plist["NSAppTransportSecurity"],
            "the release reads its feed over https; only a trial build adds an exception"
        )
    }

    func testTheUpdateAndTheFeedAreVerifiedWithAKey() throws {
        let plist = try plistTheBuildWrites()
        let key = try XCTUnwrap(plist["SUPublicEDKey"] as? String)
        XCTAssertEqual(
            Data(base64Encoded: key)?.count,
            32,
            "an Ed25519 public key is 32 bytes"
        )
        XCTAssertEqual(
            plist["SUVerifyUpdateBeforeExtraction"] as? Bool,
            true,
            "the image is checked before anything in it is opened"
        )
        XCTAssertEqual(
            plist["SURequireSignedFeed"] as? Bool,
            true,
            "an altered feed is refused, and with it the update and its notes"
        )
        XCTAssertTrue(
            AppUpdates.isTheBundleConfigured(plist),
            "the bundle the script builds is one the app starts an updater for"
        )
    }

    func testSparkleIsImportedInExactlyOneFile() throws {
        let sources = root.appendingPathComponent("Sources/Hats")
        let names = try FileManager.default.contentsOfDirectory(atPath: sources.path)
            .filter { $0.hasSuffix(".swift") }
        XCTAssertGreaterThan(
            names.count,
            100,
            "the walk has to see the real source tree to mean anything"
        )
        var importing: [String] = []
        for name in names.sorted() {
            let text = try String(contentsOf: sources.appendingPathComponent(name), encoding: .utf8)
            let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            if lines.contains("import Sparkle") { importing.append(name) }
        }
        XCTAssertEqual(
            importing,
            [
                "SparkleUpdates.swift",
            ],
            "the rest of the app talks to the updater through AppUpdater, so replacing Sparkle touches one file"
        )
    }
}
