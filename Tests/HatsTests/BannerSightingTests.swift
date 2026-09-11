import XCTest
@testable import Hats

final class BannerSightingTests: XCTestCase {
    func testARenderIntoAnOpenPopoverIsARead() {
        XCTAssertEqual(
            BannerSighting.of(popoverShown: true, popoverClosing: false, hasBanner: true),
            .seen
        )
    }

    func testARenderIntoAClosingPopoverIsNotARead() {
        XCTAssertEqual(
            BannerSighting.of(popoverShown: true, popoverClosing: true, hasBanner: true),
            .notYet,
            "isShown stays true through the close animation, so the redraw that follows the click "
                + "which closed the popover used to spend the banner nobody had time to read"
        )
    }

    func testNoPopoverAndNoBannerAreBothNotAReadEither() {
        XCTAssertEqual(
            BannerSighting.of(popoverShown: false, popoverClosing: false, hasBanner: true),
            .notYet
        )
        XCTAssertEqual(
            BannerSighting.of(popoverShown: true, popoverClosing: false, hasBanner: false),
            .notYet,
            "there is nothing to mark spent when no banner is drawn"
        )
    }

    func testAPolicyAsksForPermissionOnlyWhenItWouldActuallyNotify() {
        XCTAssertTrue(AutoSwitchPolicy(isOn: true, notifies: true).wantsNotifications)
        XCTAssertFalse(AutoSwitchPolicy(isOn: false, notifies: true).wantsNotifications)
        XCTAssertFalse(AutoSwitchPolicy(isOn: true, notifies: false).wantsNotifications)
    }

    func testAPolicyThatWasAlreadyOnStillWantsPermission() {
        let carriedOverFromAnEarlierLaunch = AutoSwitchPolicy(isOn: true, notifies: true)
        XCTAssertTrue(carriedOverFromAnEarlierLaunch.wantsNotifications,
                      "permission used to be asked for only by the act of switching the setting on, "
                          + "so a policy loaded from settings never asked and the journal carried no "
                          + "notify line of any kind across its whole history")
    }
}
