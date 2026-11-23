import XCTest
@testable import Hats

final class GatewaysPanelTests: XCTestCase {
    private func source(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/Hats/\(name)"), encoding: .utf8)
    }

    func testBothGatewaysLiveOnTheOneGatewayTab() throws {
        let tabs = try source("SettingsWindow.swift")

        XCTAssertTrue(tabs.contains("            GatewaysPanel(model: model, drafts: drafts)\n"
                                        + "                .tabItem { Text(\"Gateway\") }"))
        XCTAssertFalse(tabs.contains("Codex gateway"), "no tab of its own for the Codex gateway")
        XCTAssertFalse(tabs.contains("CodexGatewayPanel"), "the Codex panel is reached through the Gateway tab")
    }

    func testTheGatewayTabShowsClaudeFirstThenCodex() throws {
        let panel = try source("GatewaysPanel.swift")
        let claude = try XCTUnwrap(panel.range(of: " GatewayPanel(model: model, drafts: drafts)"))
        let codex = try XCTUnwrap(panel.range(of: "CodexGatewayPanel(model: model, drafts: drafts)"))

        XCTAssertLessThan(claude.lowerBound, codex.lowerBound)
    }

    func testEveryTabOfTheSettingsWindowScrolls() throws {
        let window = try source("SettingsWindow.swift")
        let tabView = try XCTUnwrap(window.range(of: "TabView {"))
        let end = try XCTUnwrap(window.range(of: ".padding(14)", range: tabView.upperBound..<window.endIndex))
        let tabs = String(window[tabView.upperBound..<end.lowerBound])
        let names = try NSRegularExpression(pattern: "\\b([A-Z][A-Za-z]*Panel)\\(")
            .matches(in: tabs, range: NSRange(tabs.startIndex..., in: tabs))
            .compactMap { Range($0.range(at: 1), in: tabs).map { String(tabs[$0]) } }
        let panels = Array(NSOrderedSet(array: names).array as? [String] ?? [])

        let flat = try panels.filter { name in
            let panel = try source(name + ".swift")
            guard let body = panel.range(of: "var body: some View {") else { return true }

            return !panel[body.upperBound...].drop { $0.isWhitespace }.hasPrefix("ScrollView {")
        }

        XCTAssertEqual(panels.count, 5, "the tabs are read from the TabView of the settings window")
        XCTAssertEqual(flat, [], "a tab taller than the window pushes the tab bar under the title instead of scrolling")
    }

    func testTheCloseQuestionNamesTheGatewayFieldsAsTheirPanelsDo() throws {
        let codex = try source("CodexGatewayPanel.swift")
        let settle = try source("GatewaySettleRow.swift")

        XCTAssertEqual(SettingsDrafts.getName(.codexPort), HatsCopy.codexGatewayPortLabel)
        XCTAssertEqual(SettingsDrafts.getName(.settle), HatsCopy.settleLabel)
        XCTAssertTrue(codex.contains("label: HatsCopy.codexGatewayPortLabel,"), "one name for the Codex port field")
        XCTAssertTrue(settle.contains("Text(HatsCopy.settleLabel)"), "one name for the Settle row")
        XCTAssertTrue(settle.contains("label: HatsCopy.settleLabel,"), "one name for the Settle field")
    }
}
