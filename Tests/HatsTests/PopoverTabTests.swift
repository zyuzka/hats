import XCTest
@testable import Hats

final class PopoverTabTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        super.setUp()
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hats-popover-tab-\(UUID().uuidString)/settings.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        super.tearDown()
    }

    private func write(_ json: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url)
    }

    func testTheDefaultTabIsClaude() {
        XCTAssertEqual(AppSettings().popoverTab, .claudeCode)
        XCTAssertEqual(AppSettings.loaded(from: url).popoverTab, .claudeCode)
    }

    func testTheCodexTabSurvivesASaveAndALoad() throws {
        var settings = AppSettings()
        settings.popoverTab = .codex
        try settings.save(to: url)

        XCTAssertEqual(AppSettings.loaded(from: url).popoverTab, .codex)
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains(#""popoverTab" : "codex""#))
    }

    func testAnOldFileWithoutTheFieldOpensClaudeAndKeepsEveryOtherSetting() throws {
        try write(#"{"gatewayPort": 9001, "usageDisplay": "bars"}"#)
        let old = AppSettings.loaded(from: url)
        XCTAssertEqual(old.popoverTab, .claudeCode)
        XCTAssertEqual(old.gatewayPort, 9001)
        XCTAssertEqual(old.usageDisplay, .bars)

        for broken in [#""gemini""#, "5", "null", "{}"] {
            try write(#"{"gatewayPort": 9001, "usageDisplay": "bars", "popoverTab": "# + broken + "}")
            let settings = AppSettings.loaded(from: url)
            XCTAssertEqual(settings.popoverTab, .claudeCode, broken)
            XCTAssertEqual(settings, old, broken)
        }
    }

    private func row(_ id: String, wearing: Bool, tool: Tool) -> HatRowState {
        var hat = Account(id: id, email: "\(id)@company.com", browser: nil)
        hat.name = id.capitalized
        hat.tool = tool
        return HatRowState(hat: hat, isWearing: wearing, usage: nil, usageTrouble: nil)
    }

    func testTheWornHatIsFoundPerProvider() {
        var snapshot = HatsSnapshot()
        snapshot.header = "work@company.com"
        snapshot.rows = [row("work", wearing: true, tool: .claudeCode), row("home", wearing: false, tool: .claudeCode)]
        snapshot.codexRows = [row("plus", wearing: false, tool: .codex), row("team", wearing: true, tool: .codex)]

        XCTAssertEqual(snapshot.wearing(on: .claudeCode)?.id, "work")
        XCTAssertEqual(snapshot.wearing(on: .codex)?.id, "team")
        XCTAssertEqual(snapshot.wearing?.id, "work", "the menu bar and the auto-switch still read the Claude hat")
        XCTAssertEqual(snapshot.headerTitle(on: .codex), "Team")
        XCTAssertEqual(snapshot.rows(of: .codex).map(\.id), ["plus", "team"])
        XCTAssertEqual(snapshot.rows(of: .claudeCode).map(\.id), ["work", "home"])
    }

    func testWithNoWornHatTheHeaderSaysSoForItsTab() {
        var snapshot = HatsSnapshot()
        snapshot.header = "Not logged in"
        snapshot.codexRows = [row("plus", wearing: false, tool: .codex)]

        XCTAssertEqual(snapshot.headerTitle(on: .claudeCode), "Not logged in")
        XCTAssertEqual(snapshot.headerTitle(on: .codex), "No Codex hat on")
    }

    func testTheAddFormStartsOnTheProviderItIsOpenedFor() {
        XCTAssertEqual(HatFormState().tool, .claudeCode)
        XCTAssertEqual(HatFormState(tool: .codex).tool, .codex)
    }

    func testThePopoverPlusOpensTheAddFormForTheOpenTab() {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = { (name: String) in
            (try? String(contentsOf: root.appendingPathComponent("Sources/Hats/\(name)"), encoding: .utf8)) ?? ""
        }

        XCTAssertTrue(source("HatListView.swift").contains("model.actions?.addHat(for: tab)"))
        XCTAssertTrue(source("ManageHatsPanel.swift").contains("model.actions?.addHat(for: tool)"),
                      "each provider section of the Hats tab adds a hat of its own provider")
        XCTAssertTrue(source("Dialogs+Forms.swift").contains("let state = HatFormState(tool: tool)"))
    }

    func testTheHatsTabListsClaudeHatsThenCodexHatsEachUnderItsName() {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let panel = (try? String(contentsOf: root.appendingPathComponent("Sources/Hats/ManageHatsPanel.swift"),
                                 encoding: .utf8)) ?? ""
        let claude = panel.range(of: "section(.claudeCode)")
        let codex = panel.range(of: "section(.codex)")

        XCTAssertNotNil(claude)
        XCTAssertNotNil(codex)
        if let claude, let codex { XCTAssertLessThan(claude.lowerBound, codex.lowerBound) }
        XCTAssertTrue(panel.contains("let rows = model.snapshot.rows(of: tool)"), "one list per provider")
        XCTAssertFalse(panel.contains("rows + model.snapshot.codexRows\n            ForEach"),
                       "no list of every hat together")
        XCTAssertTrue(panel.contains("Text(tool.displayName)"))
    }

    func testEachTabNamesTheAveragesOfItsHatsSoNoSwitchIsNeededToSeeThem() {
        let summary = ProviderSummary(
            session: ProviderAverage(withoutVacation: 42, withVacation: 50),
            week: ProviderAverage(withoutVacation: 61, withVacation: nil)
        )
        XCTAssertEqual(HatsCopy.tab(.codex, averages: summary), "Codex 42% · 61%",
                       "the tab shows the averages without hats on vacation, like the line under it")
        let weekOnly = ProviderSummary(
            session: ProviderAverage(withoutVacation: nil, withVacation: nil),
            week: ProviderAverage(withoutVacation: 20, withVacation: nil)
        )
        XCTAssertEqual(HatsCopy.tab(.codex, averages: weekOnly), "Codex – · 20%")
        let nothing = ProviderSummary(
            session: ProviderAverage(withoutVacation: nil, withVacation: 70),
            week: ProviderAverage(withoutVacation: nil, withVacation: nil)
        )
        XCTAssertEqual(HatsCopy.tab(.claudeCode, averages: nothing), "Claude",
                       "a tab with nothing read, or only hats on vacation, is just its name")
    }

    func testTheNameOfAHatOnVacationIsPinkWhereverItIsListed() {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = { (name: String) in
            (try? String(contentsOf: root.appendingPathComponent("Sources/Hats/\(name)"), encoding: .utf8)) ?? ""
        }

        XCTAssertTrue(source("HatRowView.swift")
            .contains(".foregroundColor(row.isOnVacation && !lit ? Color(nsColor: ProviderColors.vacation) : nil)"),
                      "pink in the popover, white on a highlighted row")
        for name in ["ManageHatsPanel.swift", "AutoSwitchBlock.swift"] {
            XCTAssertTrue(source(name)
                .contains(".foregroundColor(row.isOnVacation ? Color(nsColor: ProviderColors.vacation) : nil)"), name)
        }
        let pink = ProviderColors.vacation.usingColorSpace(.sRGB)
        XCTAssertNotNil(pink)
        if let pink {
            XCTAssertGreaterThan(pink.redComponent, pink.greenComponent + 0.3, "pink is red with some blue")
            XCTAssertGreaterThan(pink.blueComponent, pink.greenComponent, "pink, not orange")
        }
        XCTAssertNotEqual(ProviderColors.vacation, ProviderColors.claude)
    }

    func testAnEmptyTabNamesItsProviderAndPointsAtAddHat() {
        XCTAssertEqual(HatsCopy.noHats(on: .codex), "No Codex hats yet")
        XCTAssertEqual(HatsCopy.noHats(on: .claudeCode), "No Claude hats yet")
        XCTAssertTrue(HatsCopy.noHatsHint(on: .codex).contains("Add hat"))
        XCTAssertEqual(Tool.claudeCode.displayName, "Claude Code", "the tab title is its own text")
        XCTAssertEqual(HatsCopy.tab(.claudeCode), "Claude")
    }
}
