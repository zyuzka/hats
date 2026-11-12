import XCTest
@testable import Hats

final class SessionHandoffVersionTests: XCTestCase {
    private static func installed(_ version: String?, folder: String? = nil, isEnabled: Bool = true) -> SessionHandoffFace {
        .installed(version: version, folder: folder, isEnabled: isEnabled, elsewhere: [])
    }

    func testOnlyThreeDigitPartsAreAVersion() {
        let cases: [(text: String, parts: [Int]?)] = [
            ("0.1.0", [0, 1, 0]),
            ("10.20.30", [10, 20, 30]),
            ("01.2.3", [1, 2, 3]),
            ("", nil),
            ("9d2cf39", nil),
            ("unknown", nil),
            ("1.2", nil),
            ("1.2.3.4", nil),
            ("v0.1.0", nil),
            ("0.1.0-rc1", nil),
            ("99999999999999999999.0.0", nil),
            ("1..3", nil),
            (".1.2", nil),
            ("1.2.", nil),
            ("+1.2.3", nil),
            ("-1.2.3", nil),
            (" 1.2.3", nil),
            ("1.2.3 ", nil),
            ("1.2.3\n", nil),
            ("\u{0661}.\u{0662}.\u{0663}", nil),
        ]

        for (text, parts) in cases {
            XCTAssertEqual(PluginVersion(text)?.parts, parts, "\"\(text)\"")
        }
    }

    func testVersionsCompareByNumberNotByText() throws {
        let nine = try XCTUnwrap(PluginVersion("0.9.0"))
        let ten = try XCTUnwrap(PluginVersion("0.10.0"))

        XCTAssertLessThan(nine, ten, "0.9.0 is older than 0.10.0, though \"0.9.0\" > \"0.10.0\" as text")
        XCTAssertLessThan(try XCTUnwrap(PluginVersion("1.9.9")), try XCTUnwrap(PluginVersion("2.0.0")))
        XCTAssertEqual(try XCTUnwrap(PluginVersion("1.2.3")), try XCTUnwrap(PluginVersion("1.2.3")))
        XCTAssertFalse(ten < nine)
    }

    func testAnOlderGitHubInstallationIsOffered() {
        XCTAssertEqual(
            Self.installed("0.1.0").findOffer(own: "0.2.0"),
            SessionHandoffOffer(installed: "0.1.0", own: "0.2.0")
        )
        XCTAssertEqual(
            Self.installed("0.9.0").findOffer(own: "0.10.0"),
            SessionHandoffOffer(installed: "0.9.0", own: "0.10.0")
        )
        XCTAssertEqual(
            Self.installed("0.1.0", isEnabled: false).findOffer(own: "0.2.0"),
            SessionHandoffOffer(installed: "0.1.0", own: "0.2.0"),
            "a switched-off plugin is offered in the row too"
        )
    }

    func testNothingIsOfferedUnlessBothVersionsAreNumbersAndTheInstalledOneIsOlder() {
        let notOffered: [(face: SessionHandoffFace, own: String, why: String)] = [
            (Self.installed("0.2.0"), "0.2.0", "the same version"),
            (Self.installed("0.3.0"), "0.2.0", "a newer version"),
            (Self.installed(nil), "0.2.0", "no version field"),
            (Self.installed("9d2cf39"), "0.2.0", "a commit hash"),
            (Self.installed("unknown"), "0.2.0", "unknown"),
            (Self.installed("1.2"), "0.2.0", "two parts"),
            (Self.installed("0.1.0"), "1.2.3.4", "own with four parts"),
            (Self.installed("0.1.0"), "v0.2.0", "own with a v"),
            (Self.installed("0.1.0"), "0.2.0-rc1", "own with a suffix"),
            (Self.installed("0.1.0"), "99999999999999999999.0.0", "own beyond Int"),
            (Self.installed("0.1.0", folder: "/market"), "0.2.0", "from a folder marketplace"),
            (.notInstalled(elsewhere: []), "0.2.0", "not installed"),
            (.notOurs("another plugin"), "0.2.0", "not ours"),
            (.unknown("the list could not be read"), "0.2.0", "unknown"),
            (.unread, "0.2.0", "not read yet"),
        ]

        for (face, own, why) in notOffered {
            XCTAssertNil(face.findOffer(own: own), why)
        }
    }

    func testTheBundledVersionIsTheVersionOfThePluginInThisRepository() throws {
        let manifest = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("plugin/.claude-plugin/plugin.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any]
        let version = try XCTUnwrap(object?["version"] as? String)

        XCTAssertEqual(
            SessionHandoffProvenance.bundledVersion,
            version,
            "plugin/.claude-plugin/plugin.json says \(version), SessionHandoffProvenance.bundledVersion says "
                + "\(SessionHandoffProvenance.bundledVersion): raise the constant with the plugin"
        )
    }

    func testTheBundledVersionIsHandedInOnlyByMain() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Hats")
        let names = try FileManager.default.contentsOfDirectory(atPath: sources.path).filter { $0.hasSuffix(".swift") }
        var users: [String] = []
        for name in names {
            let text = try String(contentsOf: sources.appendingPathComponent(name), encoding: .utf8)
            if text.contains("bundledVersion") { users.append(name) }
        }

        XCTAssertEqual(users.sorted(), ["SessionHandoffFace.swift", "main.swift"])
    }
}
