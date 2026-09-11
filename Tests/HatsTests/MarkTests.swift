import AppKit
import XCTest
@testable import Hats

final class MarkTests: XCTestCase {
    func testTheAttentionDotFollowsABlockedHatWhateverTheGatewayToggleSays() {
        XCTAssertEqual(MarkState.decide(anyHatBlocked: true, gatewayEnabled: false, gatewayServing: false,
                                        wearing: true, percent: 40), .attention,
                       "a hat that needs a login is surfaced even with the gateway turned off")
        XCTAssertEqual(MarkState.decide(anyHatBlocked: false, gatewayEnabled: false, gatewayServing: false,
                                        wearing: true, percent: 40), .wearing(percent: 40),
                       "a gateway the user turned off is not something to draw attention to")
        XCTAssertEqual(MarkState.decide(anyHatBlocked: false, gatewayEnabled: true, gatewayServing: false,
                                        wearing: true, percent: nil), .attention,
                       "a gateway that should serve and does not is")
        XCTAssertEqual(MarkState.decide(anyHatBlocked: false, gatewayEnabled: true, gatewayServing: true,
                                        wearing: false, percent: nil), .idle)
    }

    private func pixels(_ state: MarkState) throws -> Data {
        let image = Mark.image(state: state)
        XCTAssertTrue(image.isTemplate, "the menu bar recolours a template image; a fixed colour would not adapt")
        XCTAssertGreaterThan(image.size.width, image.size.height, "three letters and a cursor are wider than tall")
        return try XCTUnwrap(image.tiffRepresentation)
    }

    func testEveryStateRendersAndTheStatesAreTellingApart() throws {
        let idle = try pixels(.idle)
        let wearing = try pixels(.wearing(percent: nil))
        let attention = try pixels(.attention)
        let metered = try pixels(.wearing(percent: 85))
        XCTAssertNotEqual(idle, wearing, "a hollow cursor and a solid one must not look the same")
        XCTAssertNotEqual(wearing, attention, "attention has to be visible over plain wearing")
        XCTAssertNotEqual(wearing, metered, "a meter past the threshold changes the mark")
        XCTAssertEqual(try pixels(.wearing(percent: 40)), wearing,
                       "under the threshold there is no meter, so the mark is the plain one")
    }

    func testTheMeterAppearsOnlyFromSeventyPercent() {
        XCTAssertFalse(MarkState.wearing(percent: 69).hasMeter)
        XCTAssertTrue(MarkState.wearing(percent: 70).hasMeter)
        XCTAssertFalse(MarkState.wearing(percent: nil).hasMeter, "no reading, no meter")
        XCTAssertFalse(MarkState.idle.hasMeter)
        XCTAssertFalse(MarkState.attention.hasMeter, "attention wins over the meter")
    }
}
