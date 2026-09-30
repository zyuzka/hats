import AppKit
import XCTest
@testable import Hats

final class MarkTests: XCTestCase {
    func testTheAttentionDotFollowsABlockedHatWhateverTheGatewayToggleSays() {
        XCTAssertEqual(MarkState.decide(anyHatBlocked: true, gatewayEnabled: false, gatewayServing: false,
                                        wearing: true, percent: 40, autoSwitchWarnsAboutTheWornHat: false), .attention,
                       "a hat that needs a login is surfaced even with the gateway turned off")
        XCTAssertEqual(MarkState.decide(anyHatBlocked: false, gatewayEnabled: false, gatewayServing: false,
                                        wearing: true, percent: 40, autoSwitchWarnsAboutTheWornHat: false),
                       .wearing(percent: 40),
                       "a gateway the user turned off is not something to draw attention to")
        XCTAssertEqual(MarkState.decide(anyHatBlocked: false, gatewayEnabled: true, gatewayServing: false,
                                        wearing: true, percent: nil, autoSwitchWarnsAboutTheWornHat: false), .attention,
                       "a gateway that should serve and does not is")
        XCTAssertEqual(MarkState.decide(anyHatBlocked: false, gatewayEnabled: true, gatewayServing: true,
                                        wearing: false, percent: nil, autoSwitchWarnsAboutTheWornHat: false), .idle)
    }

    func testAWarningAboutTheWornHatKeepsTheMeterAndAddsTheDot() {
        XCTAssertEqual(MarkState.decide(anyHatBlocked: false, gatewayEnabled: true, gatewayServing: true,
                                        wearing: true, percent: 89, autoSwitchWarnsAboutTheWornHat: true),
                       .wearingWithAttention(percent: 89),
                       "the number is what the person needs most while it is going stale, so it stays "
                           + "and the dot is drawn beside it rather than instead of it")
        XCTAssertEqual(MarkState.decide(anyHatBlocked: true, gatewayEnabled: true, gatewayServing: false,
                                        wearing: true, percent: 89, autoSwitchWarnsAboutTheWornHat: true),
                       .wearingWithAttention(percent: 89),
                       "both older reasons for attention are true here too, and the early return used "
                           + "to eat the meter before the worn hat was ever looked at")
        XCTAssertEqual(MarkState.decide(anyHatBlocked: false, gatewayEnabled: true, gatewayServing: true,
                                        wearing: false, percent: nil, autoSwitchWarnsAboutTheWornHat: true), .idle,
                       "with no hat on there is no worn hat to warn about - neither a usage "
                           + "that cannot be read nor a limit reached with nowhere to go")
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
        XCTAssertNil(MarkState.wearing(percent: 69).meter)
        XCTAssertEqual(MarkState.wearing(percent: 70).meter, 70)
        XCTAssertNil(MarkState.wearing(percent: nil).meter, "no reading, no meter")
        XCTAssertNil(MarkState.idle.meter)
        XCTAssertNil(MarkState.attention.meter,
                     "the two older reasons for attention — a blocked hat and a gateway that "
                         + "should serve and does not — carry no percentage of their own, so "
                         + "there is nothing to meter. A warning about the worn hat is a third "
                         + "reason and keeps its number")
        XCTAssertEqual(MarkState.wearingWithAttention(percent: 85).meter, 85)
        XCTAssertNil(MarkState.wearingWithAttention(percent: 69).meter)
        XCTAssertNil(MarkState.wearingWithAttention(percent: nil).meter)
    }

    func testTheMeterAndTheDotAreDrawnTogether() throws {
        let both = try pixels(.wearingWithAttention(percent: 85))
        XCTAssertNotEqual(both, try pixels(.wearing(percent: 85)),
                          "the dot has to be visible over a hat that is on")
        XCTAssertNotEqual(both, try pixels(.attention),
                          "and the mark still says a hat is on, which plain attention does not")
        XCTAssertNotEqual(both, try pixels(.wearingWithAttention(percent: nil)),
                          "the meter is still drawn while the reading cannot be refreshed - this is "
                              + "the whole point of the third attention reason, and the two places "
                              + "that pick the meter used to answer by matching .wearing alone, "
                              + "which would have dropped it in silence. A hat stranded at its limit "
                              + "keeps its number for the same reason: the figure is what "
                              + "the person is deciding on")
        XCTAssertEqual(try pixels(.wearingWithAttention(percent: 40)),
                       try pixels(.wearingWithAttention(percent: nil)),
                       "under the threshold there is no meter, exactly as for plain wearing")
    }
}
