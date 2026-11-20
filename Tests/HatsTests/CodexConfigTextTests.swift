import XCTest
@testable import Hats

final class CodexConfigTextTests: XCTestCase {
    private let ours = "http://127.0.0.1:8788/s3cr3t/codex"
    private func isOurs(_ value: String) -> Bool { value.contains("/s3cr3t/codex") }

    func testANewFileHoldsTheOneKey() {
        XCTAssertEqual(CodexConfigText.setting(ours, in: nil, isOurs: isOurs),
                       .changed("openai_base_url = \"\(ours)\"\n"))
    }

    func testTheKeyGoesIntoTheTopTableAndEverythingElseStaysByteForByte() {
        let text = """
            # my settings
            model = "gpt-5.6" # pinned

            [projects."/tmp/x"]
            trust_level = "trusted"
            """
        guard case .changed(let edited) = CodexConfigText.setting(ours, in: text, isOurs: isOurs) else {
            return XCTFail("the key was not added")
        }
        XCTAssertEqual(edited, """
            # my settings
            model = "gpt-5.6" # pinned

            openai_base_url = "\(ours)"
            [projects."/tmp/x"]
            trust_level = "trusted"
            """)
        XCTAssertEqual(CodexConfigText.find(in: edited)?.value, ours)
        XCTAssertEqual(CodexConfigText.removing(in: edited, isOurs: isOurs, mayEmpty: false), .changed(text))
    }

    func testAFileWithoutATableGetsTheKeyAtTheEnd() {
        XCTAssertEqual(CodexConfigText.setting(ours, in: "model = \"x\"", isOurs: isOurs),
                       .changed("model = \"x\"\nopenai_base_url = \"\(ours)\"\n"))
    }

    func testOurOldValueIsReplacedAndTheSameValueIsLeftAlone() {
        let old = "openai_base_url = 'http://127.0.0.1:9000/s3cr3t/codex' # Hats\nmodel = \"x\"\n"
        XCTAssertEqual(CodexConfigText.setting(ours, in: old, isOurs: isOurs),
                       .changed("openai_base_url = \"\(ours)\"\nmodel = \"x\"\n"))
        let same = "openai_base_url = \"\(ours)\"\n"
        XCTAssertEqual(CodexConfigText.setting(ours, in: same, isOurs: isOurs), .unchanged)
    }

    func testAForeignValueIsNeverTouched() {
        let theirs = "openai_base_url = \"https://proxy.example/v1\"\n"
        XCTAssertEqual(CodexConfigText.setting(ours, in: theirs, isOurs: isOurs), .foreign("https://proxy.example/v1"))
        XCTAssertEqual(CodexConfigText.removing(in: theirs, isOurs: isOurs, mayEmpty: true),
                       .foreign("https://proxy.example/v1"))
    }

    func testTheKeyInsideATableOrACommentIsNotTheTopKey() {
        let text = "# openai_base_url = \"x\"\n[model_providers.mine]\nopenai_base_url = \"y\"\n"
        XCTAssertNil(CodexConfigText.find(in: text))
        guard case .changed(let edited) = CodexConfigText.setting(ours, in: text, isOurs: isOurs) else {
            return XCTFail("the key was not added")
        }
        XCTAssertTrue(edited.hasPrefix("# openai_base_url = \"x\"\nopenai_base_url = \"\(ours)\"\n[model_providers"))
        XCTAssertTrue(edited.hasSuffix("openai_base_url = \"y\"\n"), "the table's own key stays")
    }

    func testChatGPTBaseAndModelCatalogAreNotOurKey() {
        let text = "chatgpt_base_url = \"https://chatgpt.com\"\nmodel_catalog_url = \"https://x\"\n"
        guard case .changed(let edited) = CodexConfigText.setting(ours, in: text, isOurs: isOurs) else {
            return XCTFail("the key was not added")
        }
        XCTAssertTrue(edited.hasPrefix(text))
    }

    func testAWindowsFileKeepsItsLineEnds() {
        let text = "model = \"x\"\r\n\r\n[tui]\r\nx = 1\r\n"
        guard case .changed(let edited) = CodexConfigText.setting(ours, in: text, isOurs: isOurs) else {
            return XCTFail("the key was not added")
        }
        XCTAssertEqual(edited, "model = \"x\"\r\n\r\nopenai_base_url = \"\(ours)\"\r\n[tui]\r\nx = 1\r\n")
        XCTAssertEqual(CodexConfigText.find(in: edited)?.value, ours)
        XCTAssertEqual(CodexConfigText.removing(in: edited, isOurs: isOurs, mayEmpty: false), .changed(text))
        XCTAssertEqual(CodexConfigText.setting(ours, in: "a = 1\r\n", isOurs: isOurs),
                       .changed("a = 1\r\nopenai_base_url = \"\(ours)\"\r\n"))
    }

    func testAValueOverSeveralLinesBeforeTheFirstTableIsNotEdited() {
        for text in ["dirs = [\n  \"a\",\n]\n", "note = \"\"\"\nhi\n\"\"\"\n", "t = { a = 1,\n}\n"] {
            XCTAssertEqual(CodexConfigText.setting(ours, in: text, isOurs: isOurs), .unsupported, text)
            XCTAssertEqual(CodexConfigText.removing(in: text, isOurs: isOurs, mayEmpty: true), .unsupported, text)
        }
        XCTAssertNotEqual(CodexConfigText.setting(ours, in: "dirs = [\"a\"]\n[t]\nx = [\n1,\n]\n", isOurs: isOurs),
                          .unsupported, "one line on top and a long value under a table are fine")
    }

    func testRemovingEmptiesOnlyAFileHatsCreated() {
        let only = "openai_base_url = \"\(ours)\"\n"
        XCTAssertEqual(CodexConfigText.removing(in: only, isOurs: isOurs, mayEmpty: true), .emptied)
        XCTAssertEqual(CodexConfigText.removing(in: only, isOurs: isOurs, mayEmpty: false), .changed(""))
        XCTAssertEqual(CodexConfigText.removing(in: "model = \"x\"\n", isOurs: isOurs, mayEmpty: true), .unchanged)
        XCTAssertEqual(CodexConfigText.removing(in: nil, isOurs: isOurs, mayEmpty: true), .unchanged)
    }
}
