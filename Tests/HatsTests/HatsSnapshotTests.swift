import XCTest
@testable import Hats

final class HatsSnapshotTests: XCTestCase {
    private func facts(current: Int, retired: Int? = nil,
                       serving: Bool = true, settle: Int = 35) -> GatewayFacts {
        GatewayFacts(addresses: .of(currentPort: current, retiredPort: retired),
                     isServing: serving, settleSeconds: settle)
    }

    private func hat(_ id: String, _ name: String?, switchable: Bool = true) -> Account {
        var hat = Account(id: id, email: "\(id)@company.com", browser: nil)
        hat.name = name
        hat.hasStoredCredentials = switchable
        if switchable { hat.identity = CLIIdentity(oauthAccount: [:], userID: nil) }
        return hat
    }

    private func snapshot(wearing: String?, hats: [Account], order: [String]) -> HatsSnapshot {
        var snapshot = HatsSnapshot()
        snapshot.rows = hats.map { HatRowState(hat: $0, isWearing: $0.id == wearing, usage: nil, usageTrouble: nil) }
        snapshot.settings.autoSwitch.order = order
        return snapshot
    }

    func testTheRowCarriesTheTitleTheListShows() {
        let row = HatRowState(hat: hat("work", "Work"), isWearing: true, usage: nil, usageTrouble: nil)
        XCTAssertEqual(row.title, "Work")
        XCTAssertEqual(row.address, "work@company.com")
        XCTAssertTrue(row.isWearing)
        XCTAssertNil(row.blocker)
    }

    func testTheLoginButtonSaysAgainOnlyForAHatThatHasLoggedInBefore() {
        XCTAssertEqual(HatRowState(hat: hat("work", "Work"), isWearing: false, usage: nil, usageTrouble: nil).loginAction, "Log in again…")
        let fresh = HatRowState(hat: hat("new", "New", switchable: false), isWearing: false, usage: nil, usageTrouble: nil)
        XCTAssertEqual(fresh.blocker, "needs login")
        XCTAssertEqual(fresh.loginAction, "Log in…", "a hat that never logged in cannot log in again")
    }

    func testNextInLineFollowsTheOrderAndSkipsWhatCannotBeWorn() {
        let hats = [hat("work", "Work"), hat("personal", "Personal"), hat("team", "Team", switchable: false)]
        let snapshot = snapshot(wearing: "work", hats: hats, order: ["team", "personal"])
        XCTAssertEqual(snapshot.nextInLine, "personal", "Team is first in order but cannot be worn")
        XCTAssertEqual(snapshot.title(of: "personal"), "Personal")
        XCTAssertEqual(snapshot.title(of: "gone"), "gone", "an id with no row is shown as itself, not as a crash")
    }

    func testNextInLineFallsBackToTheShownOrderAndIsNothingOnlyWhenNoOtherHatCanBeWorn() {
        let hats = [hat("work", "Work"), hat("personal", "Personal")]
        XCTAssertEqual(snapshot(wearing: "work", hats: hats, order: ["work"]).nextInLine, "personal")
        XCTAssertEqual(snapshot(wearing: "work", hats: hats, order: []).nextInLine, "personal",
                       "an order nobody touched is the order the panel shows, not no order")
        let alone = [hat("work", "Work"), hat("personal", "Personal", switchable: false)]
        XCTAssertNil(snapshot(wearing: "work", hats: alone, order: []).nextInLine)
    }

    func testTheWearingRowIsTheOneMarked() {
        let hats = [hat("work", "Work"), hat("personal", "Personal")]
        XCTAssertEqual(snapshot(wearing: "personal", hats: hats, order: []).wearing?.title, "Personal")
        XCTAssertNil(snapshot(wearing: nil, hats: hats, order: []).wearing)
    }

    func testASessionRowSaysHowItMovesAndNeverInventsWhoItIs() {
        let url = "http://127.0.0.1:8787"
        let live = [
            Session(pid: 42, elapsed: "2h 14m", isInteractive: true, route: .pointedAt(url)),
            Session(pid: 43, elapsed: "5m", isInteractive: true, route: .direct),
            Session(pid: 44, elapsed: "1m", isInteractive: true, route: .pointedAt("http://127.0.0.1:8786")),
            Session(pid: 45, elapsed: "1m", isInteractive: true),
        ]
        let rows = LiveSessionRow.rows(sessions: live, wearingTitle: "Work", gateway: facts(current: 8787),
                                       horizon: "at its next token renewal")
        XCTAssertEqual(rows.map(\.moves), [
            "through the gateway — at its first request 35 s after a switch, about 45 s in practice",
            "direct — at its next token renewal",
            "points at http://127.0.0.1:8786 — not this gateway",
            "unknown — its environment could not be read",
        ])
        XCTAssertEqual(rows.map(\.wearing), ["Work", "—", "—", "—"],
                       "only a session the gateway moves is known to wear the current hat; "
                           + "the others wear whatever they started on, and nobody here knows what that was")

        let off = LiveSessionRow.rows(sessions: Array(live.prefix(2)), wearingTitle: "Work",
                                      gateway: facts(current: 8787, serving: false),
                                      horizon: "at its next token renewal")
        XCTAssertEqual(off.map(\.moves), [
            "through the gateway, which is off — stuck until it serves again",
            "direct — at its next token renewal",
        ])
        XCTAssertEqual(off.map(\.wearing), ["—", "—"], "with the gateway off nothing moves anybody, so nothing is known")
    }

    func testASessionOnTheRetiredListenerIsOursAndSaysSo() {
        let live = [
            Session(pid: 1, elapsed: "3h", isInteractive: true, route: .pointedAt("http://127.0.0.1:8787")),
            Session(pid: 2, elapsed: "5m", isInteractive: true, route: .pointedAt("http://127.0.0.1:8788")),
        ]
        let rows = LiveSessionRow.rows(sessions: live, wearingTitle: "Work",
                                       gateway: facts(current: 8788, retired: 8787),
                                       horizon: "")
        XCTAssertEqual(rows.map(\.moves), [
            "through the gateway on the port it started with, still served — that listener "
                + "closes once no session needs it",
            "through the gateway — at its first request 35 s after a switch, about 45 s in practice",
        ], "a port change keeps the old listener alive, so a session on it is going through us; "
            + "calling it 'not this gateway' is the report contradicting the feature")
        XCTAssertEqual(rows.map(\.wearing), ["Work", "Work"],
                       "both are moved by a switch, so both are known to wear the current hat")

        let withoutRetired = LiveSessionRow.rows(sessions: live, wearingTitle: "Work", gateway: facts(current: 8788),
                                                 horizon: "")
        XCTAssertEqual(withoutRetired.first?.moves, "points at http://127.0.0.1:8787 — not this gateway",
                       "with no retired listener the old port really is somebody else's")
        XCTAssertEqual(withoutRetired.map(\.wearing), ["—", "Work"])
    }

    func testTheSnapshotOffersBothOfOurPortsWhileAListenerIsRetiring() {
        var snapshot = HatsSnapshot()
        var settings = AppSettings()
        settings.gatewayPort = 8788
        snapshot.settings = settings
        XCTAssertEqual(snapshot.gatewayAddresses.all, ["http://127.0.0.1:8788"])
        XCTAssertNil(snapshot.gatewayAddresses.retired)
        snapshot.retiredPort = 8787
        XCTAssertEqual(snapshot.gatewayAddresses.all, ["http://127.0.0.1:8788", "http://127.0.0.1:8787"])
        XCTAssertEqual(snapshot.gatewayAddresses.current, "http://127.0.0.1:8788")
        XCTAssertEqual(snapshot.gatewayAddresses.retired, "http://127.0.0.1:8787")
    }

    func testAForeignBaseURLIsShownAsOneBoundedLine() {
        let hostile = "http://evil.example/" + String(repeating: "a", count: 200) + "\nSECOND LINE\u{7}"
        let shown = LiveSessionRow.shown(hostile)
        XCTAssertFalse(shown.contains("\n"))
        XCTAssertFalse(shown.contains("\u{7}"))
        XCTAssertEqual(shown.count, 61, "sixty characters and an ellipsis")
        XCTAssertEqual(LiveSessionRow.shown("http://127.0.0.1:8786"), "http://127.0.0.1:8786")
    }

    func testTheGatewayIsMatchedOnTheSettingsPortNotTheDefault() {
        let live = [Session(pid: 1, elapsed: "1m", isInteractive: true, route: .pointedAt("http://127.0.0.1:9000"))]
        let onNine = LiveSessionRow.rows(sessions: live, wearingTitle: "Work", gateway: facts(current: 9000),
                                         horizon: "")
        XCTAssertEqual(onNine.first?.moves, "through the gateway — at its first request 35 s after a switch, about 45 s in practice")
        let onDefault = LiveSessionRow.rows(sessions: live, wearingTitle: "Work", gateway: facts(current: 8787),
                                            horizon: "")
        XCTAssertEqual(onDefault.first?.moves, "points at http://127.0.0.1:9000 — not this gateway")
    }

    func testTwoRowsSharingAnIdDoNotBringTheAppDown() {
        var snapshot = HatsSnapshot()
        let reading = UsageReading(session: UsageWindow(used: 5, limit: 100, resetsAt: nil), weekly: nil)
        let twin = hat("same", "Twin")
        snapshot.rows = [
            HatRowState(hat: twin, isWearing: true, usage: reading, usageTrouble: nil),
            HatRowState(hat: twin, isWearing: false, usage: reading, usageTrouble: nil),
        ]

        XCTAssertEqual(snapshot.readingByHat.count, 1,
                       "Dictionary(uniqueKeysWithValues:) traps on a duplicate key, and a corrupt "
                           + "accounts file would have taken the whole menu bar down from a helper "
                           + "that only draws a row")
    }
}
