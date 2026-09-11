import XCTest
@testable import Hats

final class PollLandingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testTheWornHatIsPolledBeforeAParkedRenewalCanDelayIt() {
        let parked = Slot.parked("personal")
        let slots = FakeSlots([
            parked: credential(expiresAt: milliseconds(now.addingTimeInterval(-60))),
            FakeSlots.live: credential(access: "worn-1", expiresAt: nil, refresh: "r-9"),
        ])
        slots.answer = .renewed(RenewedLogin(accessToken: "a-2", refreshToken: "r-2",
                                             expiresAt: now.addingTimeInterval(28800),
                                             refreshExpiresAt: nil, scopes: [], account: nil))

        _ = AutoSwitchWatch.fetched([("personal", false), ("work", true)],
                                    world: slots.world(now: now))

        XCTAssertEqual(slots.usedTokens.first, "worn-1",
                       "the parked hat is listed first and its renewal blocks the shared usage "
                           + "queue for up to 30 seconds; before this diff a parked expired hat "
                           + "cost no network time at all, so the worn hat's number could not be "
                           + "held up behind one")
        XCTAssertEqual(slots.usedTokens.count, 2, "and both hats are still polled")
    }

    func testTheRenewalIsReportedBeforeEveryPathThatDiscardsThePoll() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Hats/AutoSwitchWatch.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        let landed = String(text[try XCTUnwrap(text.range(of: "private func landed")).lowerBound...])
        let reported = try XCTUnwrap(landed.range(of: "onRenewals(batch.renewals)")).lowerBound
        let firstDiscard = try XCTUnwrap(landed.range(of: "return")).lowerBound

        XCTAssertLessThan(reported, firstDiscard,
                          "a mint is an irreversible keychain write that has already happened, "
                              + "unlike a reading, which describes a moment that may have passed. "
                              + "landed has two paths that drop the batch — a stopped timer, which "
                              + "is the app quitting, and a hat list that moved while the poll ran "
                              + "— and both used to swallow the renewal, leaving the stored expiry "
                              + "quoting a time the keychain no longer holds")
        XCTAssertEqual(landed.components(separatedBy: "onRenewals(batch.renewals)").count - 1, 1,
                       "reported once, so the store cannot be told twice about one mint")
    }
}
