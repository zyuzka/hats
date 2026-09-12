import XCTest
@testable import Hats

final class UpdateAnnouncementTests: XCTestCase {
    func testAVersionIsAnnouncedOnceAndThenLeftAlone() {
        XCTAssertTrue(UpdateAnnouncement.isWorthAnnouncing("0.2.0", announced: nil))
        XCTAssertFalse(UpdateAnnouncement.isWorthAnnouncing("0.2.0", announced: "0.2.0"),
                       "the check runs every six hours, so announcing on every one of them would "
                           + "be a notification four times a day about the same release")
    }

    func testTheNextVersionIsAnnouncedAgain() {
        XCTAssertTrue(UpdateAnnouncement.isWorthAnnouncing("0.3.0", announced: "0.2.0"))
    }

    func testTheNoticeNamesTheVersionAndWhereToGetIt() {
        XCTAssertEqual(HatsCopy.updateAnnouncement("0.2.0").title, "Hats 0.2.0 is out")
        XCTAssertEqual(HatsCopy.updateAnnouncement("0.2.0").body,
                       "Open Settings \u{2192} General to download it.")
    }

    func testTheSettingsButtonSaysWhichVersionIsWaiting() {
        XCTAssertEqual(HatsCopy.updateButton(waiting: "0.2.0"), "Update to 0.2.0\u{2026}")
        XCTAssertEqual(HatsCopy.updateButton(waiting: nil), "Check for Updates\u{2026}",
                       "with nothing waiting the button keeps its ordinary name rather than "
                           + "implying an update exists")
    }
}
