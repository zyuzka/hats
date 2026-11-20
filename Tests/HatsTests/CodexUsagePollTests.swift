import XCTest
@testable import Hats

final class CodexUsagePollTests: XCTestCase {
    private let now = CodexFixture.now
    private let utc = TimeZone(identifier: "UTC") ?? .current
    private let home = CodexFixture.home()
    private let keychain = FakeKeychain()
    private let server = FakeCodexServer()
    private let work = CodexFixture.ticket("hat-work", CodexFixture.work)
    private let personal = CodexFixture.ticket("hat-personal", CodexFixture.personal)
    private var logged: [(String, [String: String])] = []
    private var clock = CodexFixture.now
    private var heldRuns: [() -> Void] = []
    private var holdsUsageRuns = false

    override func tearDown() {
        try? FileManager.default.removeItem(at: home.url)
    }

    private func poll() -> CodexUsagePoll {
        var world = server.world(home: home, keychain: keychain, now: now)
        world.now = { [unowned self] in self.clock }
        world.runUsage = { [unowned self] work in
            if self.holdsUsageRuns { self.heldRuns.append(work) } else { work() }
        }
        let poll = CodexUsagePoll(desk: CodexDesk(world: world))
        poll.log = { [unowned self] in self.logged.append(($0, $1)) }
        return poll
    }

    private func reading(_ windows: (minutes: Int, percent: Int)...) -> CodexUsageReading {
        CodexUsageReading(windows: windows.map { CodexUsageWindow(minutes: $0.minutes, percent: $0.percent,
                                                                   resetsAt: nil) }, plan: nil)
    }

    private func sighting(_ reading: CodexUsageReading, at: Date, _ source: CodexUsageSource) -> CodexUsageSighting {
        CodexUsageSighting(reading: reading, at: at, source: source)
    }

    private func hat(_ id: String) -> Account {
        var hat = Account(id: id, email: "\(id)@example.com", name: id)
        hat.tool = .codex
        hat.hasStoredCredentials = true
        hat.codexOwner = CodexFixture.work.owner
        hat.accessExpiresAt = now.addingTimeInterval(5 * 86400)
        return hat
    }

    private func row(_ id: String, worn: Bool = false, book: CodexUsageBook) throws -> HatRowState {
        try XCTUnwrap(ClaudeDoors.codexRows([hat(id)], worn: worn ? id : nil, usage: book, now: now).first)
    }

    private func lines(_ row: HatRowState, handover: String? = nil) -> [String] {
        RowDetail.lines(of: row, display: .percent, handover: handover, timeZone: utc, now: now).compactMap {
            guard case .text(let text, _) = $0 else { return nil }
            return text
        }
    }

    private static func bearer(_ request: URLRequest) -> String {
        String((request.value(forHTTPHeaderField: "Authorization") ?? "").dropFirst("Bearer ".count))
    }

    private func read(_ id: String, _ outcome: CodexUsageOutcome, at: Date) -> CodexUsageRead {
        CodexUsageRead(id: id, sentAt: at, outcome: outcome)
    }

    func testEveryHatIsReadWithItsOwnLoginTheWornOneFromTheLiveFile() throws {
        try CodexFixture.login(CodexFixture.work, refresh: "w").write(to: home.auth)
        keychain.contents[Slot.codexParked(personal.id)] = CodexFixture.login(CodexFixture.personal, refresh: "p")
        server.answers = [(200, CodexUsageFetchTests.plus), (200, CodexUsageFetchTests.business)]
        let poll = poll()
        var redrawn = 0

        poll.poll([work, personal], worn: work.id) { redrawn += 1 }

        XCTAssertEqual(redrawn, 1)
        XCTAssertEqual(server.sent.map { $0.value(forHTTPHeaderField: "chatgpt-account-id") },
                       ["acct-work", "acct-personal"])
        XCTAssertEqual(server.sent.map { CodexJWT.payload(Self.bearer($0)) }.map { $0?["tag"] as? String },
                       ["w", "p"])
        XCTAssertEqual(poll.book.sightings[work.id]?.source, .wham)
        XCTAssertEqual(poll.book.sightings[work.id]?.at, now)
        XCTAssertEqual(poll.book.sightings[personal.id]?.reading.shown?.weekly?.percent, 17)
    }

    func testAnEmptySlotIsNotStoredAndNothingIsSent() {
        let poll = poll()

        poll.poll([personal], worn: nil) {}

        XCTAssertTrue(server.sent.isEmpty)
        XCTAssertEqual(poll.book.troubles[personal.id], .notStored)
    }

    func testAnUnreadableSlotIsItsOwnTroubleAndKeepsTheEarlierReading() throws {
        keychain.readFailures = [Slot.codexParked(personal.id)]
        let poll = poll()
        poll.note(sighting(reading((10080, 17)), at: now.addingTimeInterval(-600), .wham), for: personal.id)

        poll.poll([personal], worn: nil) {}

        XCTAssertTrue(server.sent.isEmpty)
        XCTAssertEqual(poll.book.troubles[personal.id], .loginUnreadable)
        XCTAssertEqual(try row(personal.id, book: poll.book).usage?.weekly?.percent, 17)
    }

    func testAnIncompleteStoredLoginNeedsLoginWithoutAskingTheServer() throws {
        keychain.contents[Slot.codexParked(personal.id)] = Data(#"{"auth_mode":"chatgpt","tokens":{}}"#.utf8)
        let poll = poll()

        poll.poll([personal], worn: nil) {}

        XCTAssertTrue(server.sent.isEmpty)
        XCTAssertEqual(poll.book.troubles[personal.id], .loginIncomplete)
        XCTAssertFalse(CodexUsageTrouble.loginIncomplete.onTheRow.contains("did not accept"))
    }

    func testAnExpiredTokenIsNotSent() {
        keychain.contents[Slot.codexParked(personal.id)] = CodexFixture.login(
            CodexFixture.personal, refresh: "p", expiresAt: now.addingTimeInterval(-60))
        let poll = poll()

        poll.poll([personal], worn: nil) {}

        XCTAssertTrue(server.sent.isEmpty)
        XCTAssertEqual(poll.book.troubles[personal.id], .awaitingRenewal)
    }

    func testAnExpiredTokenWithoutARefreshTokenNeedsLogin() throws {
        let expired = CodexFixture.login(CodexFixture.personal, refresh: "p", expiresAt: now.addingTimeInterval(-60))
        var auth = try XCTUnwrap(CodexAuth(data: expired)).root
        var tokens = auth["tokens"] as? [String: Any] ?? [:]
        tokens.removeValue(forKey: "refresh_token")
        auth["tokens"] = tokens
        keychain.contents[Slot.codexParked(personal.id)] = try JSONSerialization.data(withJSONObject: auth)
        let poll = poll()

        poll.poll([personal], worn: nil) {}

        XCTAssertTrue(server.sent.isEmpty)
        XCTAssertEqual(poll.book.troubles[personal.id], .needsLogin)
    }

    func testAParkedHatThatNeedsSigningInIsNotRead() {
        keychain.contents[Slot.codexParked(personal.id)] = CodexFixture.login(CodexFixture.personal, refresh: "p")
        let blocked = CodexTicket(id: personal.id, owner: personal.owner, title: "p", needsSignIn: true)
        let poll = poll()

        poll.poll([blocked], worn: nil) {}

        XCTAssertTrue(server.sent.isEmpty)
        XCTAssertEqual(poll.book.troubles[personal.id], .needsLogin)
    }

    func testAWornHatThatNeedsSigningInIsStillReadFromTheLiveFile() throws {
        try CodexFixture.login(CodexFixture.work, refresh: "w").write(to: home.auth)
        server.answers = [(200, CodexUsageFetchTests.plus)]
        let blocked = CodexTicket(id: work.id, owner: work.owner, title: "w", needsSignIn: true)
        let poll = poll()

        poll.poll([blocked], worn: work.id) {}

        XCTAssertEqual(server.sent.count, 1)
        XCTAssertEqual(poll.book.sightings[work.id]?.reading.shown?.session?.percent, 2)
    }

    func testALiveLoginOfAnotherAccountIsNotShownAsTheWornHats() throws {
        try CodexFixture.login(CodexFixture.personal, refresh: "p").write(to: home.auth)
        let poll = poll()

        poll.poll([work], worn: work.id) {}

        XCTAssertTrue(server.sent.isEmpty)
        XCTAssertEqual(poll.book.troubles[work.id], .anotherAccountLive)
        XCTAssertNil(try row(work.id, worn: true, book: poll.book).usage)
    }

    func testAPlusHatShowsBothWindowsAndABusinessHatOnlyTheWeek() throws {
        var book = CodexUsageBook()
        book.record(CodexUsageFetch.outcome(status: 200, body: CodexUsageFetchTests.plus), for: "plus", sentAt: now,
                    every: 60)
        book.record(CodexUsageFetch.outcome(status: 200, body: CodexUsageFetchTests.business), for: "biz",
                    sentAt: now, every: 60)

        let plus = lines(try row("plus", book: book))
        let business = lines(try row("biz", book: book))

        XCTAssertEqual(plus.count, 2)
        XCTAssertTrue(plus[0].hasPrefix("5h: 2%"), plus[0])
        XCTAssertTrue(plus[1].hasPrefix("week: 1%"), plus[1])
        XCTAssertEqual(business.count, 1)
        XCTAssertTrue(business[0].hasPrefix("week: 17%"), business[0])
    }

    func testTheWornBusinessHatShowsOnlyTheWeekToo() throws {
        var book = CodexUsageBook()
        book.note(sighting(reading((10080, 27)), at: now, .gateway), for: "biz")

        let shown = lines(try row("biz", worn: true, book: book))

        XCTAssertEqual(shown.count, 1)
        XCTAssertTrue(shown[0].hasPrefix("week: 27%"), shown[0])
    }

    func testAnAnswerWithoutWindowsShowsNothingAndNoTrouble() throws {
        var book = CodexUsageBook()
        let body = CodexUsageFetchTests.answer(primary: nil, secondary: nil)
        book.record(CodexUsageFetch.outcome(status: 200, body: body), for: "hat", sentAt: now, every: 60)

        XCTAssertNil(book.troubles["hat"])
        XCTAssertTrue(lines(try row("hat", book: book)).isEmpty)
    }

    func testAWindowOfAnotherLengthIsLoggedOnceAndNotShown() throws {
        let poll = poll()
        let odd = sighting(reading((1440, 40)), at: now, .wham)

        poll.note(odd, for: "hat")
        poll.note(odd, for: "hat")

        XCTAssertEqual(logged.map(\.0), ["codexUsage.unknownWindow"])
        XCTAssertEqual(logged.first?.1["minutes"], "1440")
        XCTAssertTrue(lines(try row("hat", book: poll.book)).isEmpty)
    }

    func testARefusedLoginShowsItsTroubleAndNotTheEarlierReading() throws {
        var book = CodexUsageBook()
        book.note(sighting(reading((300, 50), (10080, 60)), at: now, .wham), for: "hat")
        book.record(.failed(.loginRefused), for: "hat", sentAt: now, every: 60)

        let row = try row("hat", book: book)

        XCTAssertNil(row.usage)
        XCTAssertNil(row.weekSighting)
        XCTAssertEqual(lines(row), [CodexUsageTrouble.loginRefused.onTheRow])
        XCTAssertTrue(lines(row)[0].contains("Codex"))
    }

    func testNoConnectionKeepsTheEarlierReadingMarkedWithItsAge() throws {
        var book = CodexUsageBook()
        let earlier = now.addingTimeInterval(-600)
        book.note(sighting(reading((300, 50), (10080, 60)), at: earlier, .wham), for: "hat")
        book.record(.failed(.unreachable), for: "hat", sentAt: now, every: 60)

        let row = try row("hat", book: book)
        let shown = lines(row)

        XCTAssertEqual(row.usage?.session?.percent, 50)
        XCTAssertEqual(row.weekSighting?.isConfirmed, false)
        XCTAssertEqual(shown.last, "no connection to the Codex server — reading taken at "
            + UsageReading.clock(earlier, timeZone: utc))
    }

    func testAParkedBusinessHatWithoutConnectionShowsTheWeekAndTheFullAge() throws {
        var book = CodexUsageBook()
        let earlier = now.addingTimeInterval(-2 * 86400)
        book.note(sighting(reading((10080, 17)), at: earlier, .wham), for: "biz")
        book.record(.failed(.unreachable), for: "biz", sentAt: now, every: 60)

        let shown = lines(try row("biz", book: book))

        XCTAssertEqual(shown.count, 2)
        XCTAssertEqual(shown[0], "no connection to the Codex server — reading taken "
            + UsageReading.when(earlier, sameDayAs: now, timeZone: utc))
        XCTAssertTrue(shown[0].contains(" on "), shown[0])
        XCTAssertTrue(shown[1].hasPrefix("week: 17%?"), shown[1])
    }

    func testTheFresherOfTheTwoSourcesWins() {
        var book = CodexUsageBook()
        let gateway = sighting(reading((300, 30)), at: now, .gateway)
        let olderWham = sighting(reading((300, 10)), at: now.addingTimeInterval(-5), .wham)
        let newerWham = sighting(reading((300, 35)), at: now.addingTimeInterval(5), .wham)

        XCTAssertEqual(book.note(gateway, for: "hat"), .taken)
        XCTAssertEqual(book.note(olderWham, for: "hat"), .olderThanHeld)
        XCTAssertEqual(book.sightings["hat"], gateway)
        XCTAssertEqual(book.note(newerWham, for: "hat"), .taken)
        XCTAssertEqual(book.sightings["hat"], newerWham)
    }

    func testAWhamFailureSentBeforeANewerGatewaySightingChangesNothing() {
        var book = CodexUsageBook()
        book.note(sighting(reading((300, 30)), at: now.addingTimeInterval(5), .gateway), for: "hat")
        let before = book

        book.record(.failed(.unreachable), for: "hat", sentAt: now, every: 60)
        book.record(.failed(.busy), for: "hat", sentAt: now, every: 60)

        XCTAssertEqual(book, before)
    }

    func testAWhamAnswerIsStampedAtSendTimeAndLosesToAGatewaySightingDuringTheRequest() throws {
        try CodexFixture.login(CodexFixture.work, refresh: "w").write(to: home.auth)
        server.answers = [(200, CodexUsageFetchTests.plus)]
        let poll = poll()
        let gateway = sighting(reading((300, 44)), at: now.addingTimeInterval(1), .gateway)
        server.duringSend = { [unowned self] in
            poll.note(gateway, for: self.work.id)
            self.clock = self.now.addingTimeInterval(2)
        }

        poll.poll([work], worn: work.id) {}

        XCTAssertEqual(poll.book.sightings[work.id], gateway)
    }

    func testAGatewaySightingClearsAnEarlierTrouble() {
        var book = CodexUsageBook()
        book.record(.failed(.unreachable), for: "hat", sentAt: now, every: 60)
        book.note(sighting(reading((300, 30)), at: now, .gateway), for: "hat")

        XCTAssertNil(book.troubles["hat"])
    }

    func testAFreshGatewaySightingSkipsTheWhamRead() throws {
        try CodexFixture.login(CodexFixture.work, refresh: "w").write(to: home.auth)
        let poll = poll()
        poll.note(sighting(reading((300, 30)), at: now.addingTimeInterval(-30), .gateway), for: work.id)

        poll.poll([work], worn: work.id) {}
        XCTAssertTrue(server.sent.isEmpty)

        clock = now.addingTimeInterval(31)
        poll.poll([work], worn: work.id) {}
        XCTAssertEqual(server.sent.count, 1, "a gateway sighting a minute old no longer holds the read back")
    }

    func testA429PausesTheHatLongerEachTimeAndIsLoggedOnce() {
        let poll = poll()

        poll.record(read("hat", .failed(.busy), at: now))
        XCTAssertFalse(poll.book.allowsReading("hat", at: now.addingTimeInterval(53)))
        XCTAssertTrue(poll.book.allowsReading("hat", at: now.addingTimeInterval(54)))

        poll.record(read("hat", .failed(.busy), at: now.addingTimeInterval(60)))
        XCTAssertFalse(poll.book.allowsReading("hat", at: now.addingTimeInterval(60 + 113)))
        XCTAssertTrue(poll.book.allowsReading("hat", at: now.addingTimeInterval(60 + 114)))

        XCTAssertEqual(logged.map(\.0), ["codexUsage.busy"])
        poll.record(read("hat", .reading(reading((300, 1))), at: now.addingTimeInterval(200)))
        poll.record(read("hat", .failed(.busy), at: now.addingTimeInterval(300)))
        XCTAssertEqual(logged.map(\.0), ["codexUsage.busy", "codexUsage.busy"], "a new series is logged again")
    }

    func testA429ThenNoConnectionKeepsTheSeriesAndPauses() {
        let poll = poll()

        poll.record(read("hat", .failed(.busy), at: now))
        poll.record(read("hat", .failed(.unreachable), at: now.addingTimeInterval(60)))
        XCTAssertFalse(poll.book.allowsReading("hat", at: now.addingTimeInterval(60 + 113)))
        XCTAssertTrue(poll.book.allowsReading("hat", at: now.addingTimeInterval(60 + 114)))

        poll.record(read("hat", .failed(.busy), at: now.addingTimeInterval(180)))
        XCTAssertEqual(logged.map(\.0), ["codexUsage.busy"], "the 429 series went on through the lost connection")
    }

    func testAServerErrorPausesAndIsNotCalledARefusal() {
        var book = CodexUsageBook()

        book.record(CodexUsageFetch.outcome(status: 502, body: nil), for: "hat", sentAt: now, every: 60)

        XCTAssertEqual(book.troubles["hat"], .serverError(502))
        XCTAssertFalse(book.allowsReading("hat", at: now.addingTimeInterval(53)))
        XCTAssertTrue(book.allowsReading("hat", at: now.addingTimeInterval(54)))
        XCTAssertTrue(CodexUsageTrouble.serverError(502).short.hasPrefix("Codex server error (502)"))
        XCTAssertFalse(CodexUsageTrouble.serverError(502).short.contains("refused"))
    }

    func testAPausedHatIsNotAsked() throws {
        try CodexFixture.login(CodexFixture.work, refresh: "w").write(to: home.auth)
        let poll = poll()
        poll.record(read(work.id, .failed(.busy), at: now))

        poll.poll([work], worn: work.id) {}

        XCTAssertTrue(server.sent.isEmpty)
    }

    func testASecondPollWhileOneRunsIsRefused() throws {
        try CodexFixture.login(CodexFixture.work, refresh: "w").write(to: home.auth)
        server.answers = [(200, CodexUsageFetchTests.plus)]
        holdsUsageRuns = true
        let poll = poll()

        poll.poll([work], worn: work.id) {}
        poll.poll([work], worn: work.id) {}

        XCTAssertEqual(heldRuns.count, 1)
        XCTAssertTrue(poll.isReading)
        heldRuns.forEach { $0() }
        XCTAssertFalse(poll.isReading)
        XCTAssertEqual(server.sent.count, 1)
    }

    func testKeepPrunesEverythingAndDropsTheAnswerOfAHatRemovedMeanwhile() throws {
        try CodexFixture.login(CodexFixture.work, refresh: "w").write(to: home.auth)
        server.answers = [(200, CodexUsageFetchTests.plus)]
        holdsUsageRuns = true
        let poll = poll()
        poll.note(sighting(reading((1440, 5)), at: now.addingTimeInterval(-600), .wham), for: "gone")
        poll.record(read("gone", .failed(.busy), at: now))

        poll.poll([work], worn: work.id) {}
        poll.keep([])
        heldRuns.forEach { $0() }

        XCTAssertEqual(poll.book, CodexUsageBook())
        XCTAssertTrue(poll.loggedUnknown.isEmpty)
    }

    func testTheBusyTextNamesCodexAndTheRetry() {
        XCTAssertEqual(CodexUsageTrouble.busy.onTheRow,
                       "limits unknown — the Codex server refused (429), Hats will ask again later")
    }

    func testTheGatewayStampsItsReadingAndPassesItOn() {
        let state = CodexGatewayState()
        var passed: [(String, CodexUsageSighting)] = []
        state.onReading = { passed.append(($0, $1)) }

        state.noteReading(reading((300, 21), (10080, 0)), for: "hat-plus", at: now)

        XCTAssertEqual(state.sighting(for: "hat-plus")?.at, now)
        XCTAssertEqual(passed.map(\.0), ["hat-plus"])
        XCTAssertEqual(passed.first?.1.source, .gateway)
    }

    func testASecondStartReplacesTheTimersInsteadOfAddingThem() {
        let hats = CodexHats(world: server.world(home: home, keychain: keychain))
        defer { hats.stop() }

        hats.start(every: 300) {}
        hats.startReadingUsage(every: 60) {}
        hats.start(every: 300) {}
        hats.startReadingUsage(every: 60) {}

        XCTAssertEqual(hats.repeatingCount, 2)
    }
}
