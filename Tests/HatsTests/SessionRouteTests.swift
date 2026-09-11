import XCTest
@testable import Hats

final class SessionRouteTests: XCTestCase {
    private let gateway = "http://127.0.0.1:8787"

    func testNoEnvironmentIsUnknownAndNoVariableIsDirect() {
        XCTAssertEqual(SessionRoute.of(environment: nil), .unknown)
        XCTAssertEqual(SessionRoute.of(environment: ["HOME": "/x"]), .direct)
        XCTAssertEqual(SessionRoute.of(environment: ["ANTHROPIC_BASE_URL": ""]), .direct)
        XCTAssertEqual(SessionRoute.of(environment: ["ANTHROPIC_BASE_URL": "  "]), .direct)
    }

    func testAValueIsKeptAsWrittenAndComparedLoosely() {
        XCTAssertEqual(SessionRoute.of(environment: ["ANTHROPIC_BASE_URL": " http://127.0.0.1:8787/ "]),
                       .pointedAt("http://127.0.0.1:8787/"))
        XCTAssertTrue(SessionRoute.pointedAt("http://127.0.0.1:8787/").isThrough(gatewayAt: gateway))
        XCTAssertTrue(SessionRoute.pointedAt("HTTP://127.0.0.1:8787").isThrough(gatewayAt: gateway))
    }

    func testAnotherAddressIsPointedAtButNotThrough() {
        XCTAssertFalse(SessionRoute.pointedAt("http://127.0.0.1:8786").isThrough(gatewayAt: gateway))
        XCTAssertFalse(SessionRoute.pointedAt("http://localhost:8787").isThrough(gatewayAt: gateway),
                       "the gateway binds 127.0.0.1 and does not answer to any other spelling")
        XCTAssertFalse(SessionRoute.direct.isThrough(gatewayAt: gateway))
        XCTAssertFalse(SessionRoute.unknown.isThrough(gatewayAt: gateway))
    }
}
