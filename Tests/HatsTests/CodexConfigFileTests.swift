import XCTest
@testable import Hats

final class CodexConfigFileTests: XCTestCase {
    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("hats-codex-config-\(UUID().uuidString.prefix(8))")
    private let ours = "http://127.0.0.1:8788/s3cr3t/codex"

    private var config: URL { folder.appendingPathComponent("config.toml") }

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    private func setting(_ text: String?) -> CodexConfigEdit {
        CodexConfigText.setting(ours, in: text) { $0.contains("/s3cr3t/") }
    }

    private func removing(_ text: String?) -> CodexConfigEdit {
        CodexConfigText.removing(in: text, isOurs: { $0.contains("/s3cr3t/") }, mayEmpty: true)
    }

    private func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

    func testAMissingFileIsCreatedAndRemovedAgainWhenNothingElseIsInIt() throws {
        let file = CodexConfigFile(url: config)
        XCTAssertEqual(try file.apply(setting), .written)
        XCTAssertEqual(read(config), "openai_base_url = \"\(ours)\"\n")
        XCTAssertEqual(try file.apply(removing), .removed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: config.path))
    }

    func testTheRestOfTheFileAndItsModeSurviveTheRoundTrip() throws {
        let text = "# keep me\nmodel = \"x\"\n\n[tui]\nfullscreen = true\n"
        try text.write(to: config, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.path)
        let file = CodexConfigFile(url: config)

        XCTAssertEqual(try file.apply(setting), .written)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: config.path)[.posixPermissions] as? Int, 0o600)
        XCTAssertEqual(try file.apply(removing), .written)
        XCTAssertEqual(read(config), text)
    }

    func testALinkIsFollowedAndStaysALink() throws {
        let real = folder.appendingPathComponent("dotfiles-config.toml")
        try "model = \"x\"\n".write(to: real, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(atPath: config.path, withDestinationPath: real.lastPathComponent)

        XCTAssertEqual(try CodexConfigFile(url: config).apply(setting), .written)

        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: config.path), real.lastPathComponent,
                       "the link itself is not replaced by a file")
        XCTAssertEqual(read(real), "model = \"x\"\nopenai_base_url = \"\(ours)\"\n")
    }

    func testAChangeBetweenTheReadAndTheRenameIsKeptAndTheEditIsAppliedToIt() throws {
        try "model = \"x\"\n".write(to: config, atomically: true, encoding: .utf8)
        var file = CodexConfigFile(url: config)
        var races = 1
        file.beforeRename = { [config] in
            guard races > 0 else { return }
            races -= 1
            try? "model = \"y\"\n".write(to: config, atomically: true, encoding: .utf8)
        }

        XCTAssertEqual(try file.apply(setting), .written)

        XCTAssertEqual(read(config), "model = \"y\"\nopenai_base_url = \"\(ours)\"\n",
                       "the other writer's change survives and the key is on top of it")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasPrefix(".config-hats-") }
        XCTAssertEqual(leftovers, [], "the temporary file of the abandoned try is gone")
    }

    func testAFileThatNeverStopsChangingIsGivenUpLoudly() throws {
        try "model = \"x\"\n".write(to: config, atomically: true, encoding: .utf8)
        var file = CodexConfigFile(url: config)
        var round = 0
        file.beforeRename = { [config] in
            round += 1
            try? "model = \"v\(round)\"\n".write(to: config, atomically: true, encoding: .utf8)
        }

        XCTAssertThrowsError(try file.apply(setting))
        XCTAssertEqual(read(config), "model = \"v\(CodexConfigFile.attempts)\"\n")
    }

    func testAForeignKeyIsLeftAlone() throws {
        let theirs = "openai_base_url = \"https://proxy.example\"\n"
        try theirs.write(to: config, atomically: true, encoding: .utf8)

        XCTAssertEqual(try CodexConfigFile(url: config).apply(setting), .foreign("https://proxy.example"))
        XCTAssertEqual(read(config), theirs)
    }
}
