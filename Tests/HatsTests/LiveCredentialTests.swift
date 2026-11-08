import XCTest
@testable import Hats

final class LiveCredentialTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let hats: AutoSwitchWatch.Hats = [
        ("personal", false),
        ("work", true),
    ]

    func testThePollRemembersTheKeyOfTheWornHatAsTheGatewaySeesIt() {
        let slots = FakeSlots([
            Slot.parked("personal"): credential(access: "parked-1", expiresAt: nil),
            FakeSlots.live: credential(access: "worn-1", expiresAt: nil),
        ])

        let batch = AutoSwitchWatch.fetched(hats, world: slots.world(now: now))

        XCTAssertEqual(
            batch.liveCredential,
            LiveCredential(hat: "work", fingerprint: GatewayCredential.fingerprint("Bearer worn-1")),
            "the worn hat's bare token and the same token as a Bearer header give one fingerprint"
        )
    }

    func testNoUsableTokenOnTheWornHatLeavesTheKeyUnknown() {
        let expired = credential(access: "worn-1", expiresAt: milliseconds(now.addingTimeInterval(-60)))
        let parked = credential(access: "parked-1", expiresAt: nil)
        let withExpired = FakeSlots([
            Slot.parked("personal"): parked,
            FakeSlots.live: expired,
        ])
        let withoutLive = FakeSlots([
            Slot.parked("personal"): parked,
        ])

        let stale = AutoSwitchWatch.fetched(hats, world: withExpired.world(now: now))
        let nothing = AutoSwitchWatch.fetched(hats, world: withoutLive.world(now: now))
        let unknownSlot = AutoSwitchWatch.fetched(hats, world: withoutLive.world(now: now, liveSlot: nil))

        XCTAssertNil(stale.liveCredential, "an expired token on the worn hat is not remembered")
        XCTAssertNil(nothing.liveCredential, "an empty live slot leaves no key")
        XCTAssertNil(unknownSlot.liveCredential, "an unknown live slot leaves no key")
        XCTAssertEqual(
            withoutLive.usedTokens,
            [
                "parked-1",
                "parked-1",
            ],
            "the parked hat's token was fetched in both polls"
        )
    }

    func testEveryLandedPollReplacesTheKeyItRemembered() {
        let watch = AutoSwitchWatch()
        watch.start(hats: { [hats] in hats })
        defer { watch.stop() }
        var read = UsagePollBatch()
        read.liveCredential = LiveCredential(hat: "work", fingerprint: "abcd1234")

        watch.landed(
            read,
            polled: hats,
            from: .timer
        )
        let afterARead = watch.liveCredential
        watch.landed(
            UsagePollBatch(),
            polled: hats,
            from: .timer
        )

        XCTAssertEqual(afterARead, LiveCredential(hat: "work", fingerprint: "abcd1234"))
        XCTAssertNil(watch.liveCredential, "a poll that read no key leaves none remembered")
    }

    func testAPollThatLandsAfterTheWatchStoppedRemembersNothing() {
        let watch = AutoSwitchWatch()
        watch.start(hats: { [hats] in hats })
        watch.stop()
        var read = UsagePollBatch()
        read.liveCredential = LiveCredential(hat: "work", fingerprint: "abcd1234")

        watch.landed(
            read,
            polled: hats,
            from: .timer
        )

        XCTAssertNil(watch.liveCredential)
    }
}
