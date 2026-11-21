import XCTest

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

    func testTheGatewayTabShowsClaudeFirstThenCodexAndScrolls() throws {
        let panel = try source("GatewaysPanel.swift")
        let claude = try XCTUnwrap(panel.range(of: " GatewayPanel(model: model, drafts: drafts)"))
        let codex = try XCTUnwrap(panel.range(of: "CodexGatewayPanel(model: model, drafts: drafts)"))

        XCTAssertLessThan(claude.lowerBound, codex.lowerBound)
        XCTAssertTrue(panel.contains("ScrollView"))
    }
}
