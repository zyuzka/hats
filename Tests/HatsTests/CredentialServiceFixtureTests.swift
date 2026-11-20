import XCTest
@testable import Hats

final class CredentialServiceFixtureTests: XCTestCase {
    private struct Table: Decodable {
        struct Case: Decodable {
            let name: String
            let environment: [String: String]
            let service: String
        }

        let cases: [Case]
    }

    func testEveryCaseOfTheSharedTableNamesTheCellClaudeCodeHolds() throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("plugin/tests/fixtures/credential-services.json")
        let table = try JSONDecoder().decode(Table.self, from: Data(contentsOf: fixture))

        XCTAssertGreaterThanOrEqual(table.cases.count, 8, "the table the mod reads too")
        for entry in table.cases {
            XCTAssertEqual(CLIState.credentialService(environment: entry.environment), entry.service, entry.name)
        }
    }
}
