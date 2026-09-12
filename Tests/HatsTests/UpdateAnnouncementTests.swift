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

final class UpdateOfferTests: XCTestCase {
    private let release = ReleaseOnGitHub(
        version: "0.3.0",
        page: URL(string: "https://example.com/releases/0.3.0")!,
        asset: URL(string: "https://example.com/Hats-0.3.0.dmg")!
    )

    func testTheOfferToDownloadWarnsAboutTheBlockThatFollows() {
        let detail = HatsCopy.updateVerdict(.available(release)).detail

        XCTAssertTrue(detail.contains("Privacy & Security"), detail)
        XCTAssertTrue(detail.contains("Open Anyway"),
                      "the person is about to download an app macOS will refuse to open, and the "
                          + "screen that refuses it says 'malware' — saying so here, before the "
                          + "download, is the difference between a step and a scare")
    }

    func testAReleaseWithNoDiskImageDoesNotPromiseADownload() {
        let pageOnly = ReleaseOnGitHub(version: "0.3.0",
                                       page: URL(string: "https://example.com/r")!,
                                       asset: nil)

        XCTAssertEqual(HatsCopy.updateVerdict(.available(pageOnly)).detail,
                       "The release page has the details.")
    }
}
