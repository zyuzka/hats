import XCTest
@testable import Hats

final class RefusedTargetNoteTests: XCTestCase {
    func testTheNoteCarriesEnoughToTellTheTwoCausesApart() {
        let note = GatewayRefusedTarget.note(
            uri: "https://otel.example.com/v1/metrics",
            path: "/v1/metrics",
            session: "abcd1234",
            credential: "none"
        )

        XCTAssertEqual(note["uri"], "https://otel.example.com/v1/metrics",
                       "the whole point is whether the client sent an absolute URI — the path "
                           + "alone cannot answer that, and the path alone is all the ledger kept")
        XCTAssertEqual(note["path"], "/v1/metrics")
        XCTAssertEqual(note["session"], "abcd1234")
        XCTAssertEqual(note["credential"], "none")
    }

    func testAMissingSessionSaysSoRatherThanVanishing() {
        let note = GatewayRefusedTarget.note(uri: "/v1/messages", path: "/v1/messages",
                                             session: nil, credential: "none")

        XCTAssertEqual(note["session"], "-")
    }

    func testAnAbsoluteURIIsWhatTheForwarderRefuses() {
        let upstream = URL(string: "https://api.anthropic.com")!

        XCTAssertNil(GatewayForward.upstreamURL(for: "https://otel.example.com/v1/metrics",
                                                upstream: upstream),
                     "a client configured with a proxy sends the absolute form, and this is the "
                         + "refusal a colleague hit with his telemetry")
        XCTAssertEqual(GatewayForward.upstreamURL(for: "/v1/metrics", upstream: upstream)?
            .absoluteString, "https://api.anthropic.com/v1/metrics",
            "and every relative path is sent to Anthropic whatever it was meant for, which is the "
                + "other candidate for the same report")
    }
}
