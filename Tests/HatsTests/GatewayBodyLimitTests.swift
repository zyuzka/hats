import NIOHTTP1
import XCTest
@testable import Hats

final class GatewayBodyLimitTests: XCTestCase {
    private func headers(contentLength: String?) -> HTTPHeaders {
        var out = HTTPHeaders()
        if let contentLength { out.add(name: "Content-Length", value: contentLength) }
        return out
    }

    func testADeclaredLengthAboveTheLimitIsRefusedBeforeAByteIsRead() {
        XCTAssertFalse(GatewayBodyLimit.allowsDeclaredLength(
            in: headers(contentLength: "1025"), limit: 1024))
        XCTAssertTrue(GatewayBodyLimit.allowsDeclaredLength(
            in: headers(contentLength: "1024"), limit: 1024),
                      "the limit itself is still allowed")
    }

    func testALengthThatCannotBeReadLeavesTheDecisionToTheAccumulation() {
        for declared in ["", "abc", "99999999999999999999999999", "-1 "] {
            XCTAssertTrue(
                GatewayBodyLimit.allowsDeclaredLength(
                    in: headers(contentLength: declared), limit: 1024),
                "an unreadable \(declared.debugDescription) must not be trusted either way; "
                    + "the bytes that actually arrive are what the second door counts"
            )
        }
        XCTAssertTrue(GatewayBodyLimit.allowsDeclaredLength(
            in: headers(contentLength: nil), limit: 1024),
                      "a chunked request declares no length at all")
    }

    func testTheAccumulationCountsWhatIsAlreadyBufferedAndWhatIsArriving() {
        XCTAssertTrue(GatewayBodyLimit.allows(buffered: 512, incoming: 512, limit: 1024))
        XCTAssertFalse(GatewayBodyLimit.allows(buffered: 512, incoming: 513, limit: 1024),
                       "a chunk is weighed against what is already held, not on its own")
        XCTAssertFalse(GatewayBodyLimit.allows(buffered: 0, incoming: 2048, limit: 1024))
    }
}
