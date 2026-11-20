import XCTest
@testable import Hats

final class CodexUsageFetchTests: XCTestCase {
    static func window(percent: Any, seconds: Int, resetAt: Int = 1_800_500_000) -> [String: Any] {
        ["used_percent": percent, "limit_window_seconds": seconds, "reset_after_seconds": 51_633, "reset_at": resetAt]
    }

    static func answer(primary: [String: Any]?, secondary: [String: Any]?, plan: String = "plus") -> Data {
        let limit: [String: Any] = [
            "allowed": true,
            "limit_reached": false,
            "primary_window": primary.map { $0 as Any } ?? NSNull(),
            "secondary_window": secondary.map { $0 as Any } ?? NSNull(),
        ]
        let payload: [String: Any] = [
            "plan_type": plan,
            "rate_limit": limit,
            "credits": ["has_credits": false],
            "additional_rate_limits": [] as [Any],
        ]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }

    static let plus = answer(
        primary: window(percent: 2, seconds: 18000, resetAt: 1_800_010_000),
        secondary: window(percent: 1, seconds: 604_800)
    )
    static let business = answer(primary: window(percent: 17, seconds: 604_800), secondary: nil,
                                 plan: "self_serve_business_prolite")

    func testAPlusAnswerGivesTheFiveHourWindowAndTheWeek() throws {
        let reading = try XCTUnwrap(CodexUsageFetch.outcome(status: 200, body: Self.plus).reading)
        let shown = try XCTUnwrap(reading.shown)

        XCTAssertEqual(shown.session?.percent, 2)
        XCTAssertEqual(shown.session?.resetsAt, Date(timeIntervalSince1970: 1_800_010_000))
        XCTAssertEqual(shown.weekly?.percent, 1)
        XCTAssertEqual(reading.plan, "plus")
    }

    func testABusinessAnswerGivesOnlyTheWeekWhateverTheWindowIsCalled() throws {
        let reading = try XCTUnwrap(CodexUsageFetch.outcome(status: 200, body: Self.business).reading)

        XCTAssertNil(reading.shown?.session)
        XCTAssertEqual(reading.shown?.weekly?.percent, 17, "the primary window is a week by its length")
    }

    func testLengthsInSecondsAreMatchedToMinutes() throws {
        let reading = try XCTUnwrap(CodexUsageFetch.outcome(status: 200, body: Self.plus).reading)

        XCTAssertEqual(reading.windows.map(\.minutes), [300, 10080])
    }

    func testAWindowOfAnotherLengthIsNotShown() throws {
        let body = Self.answer(primary: Self.window(percent: 40, seconds: 86400), secondary: nil)
        let reading = try XCTUnwrap(CodexUsageFetch.outcome(status: 200, body: body).reading)

        XCTAssertNil(reading.shown)
        XCTAssertEqual(reading.unknownWindows.map(\.minutes), [1440])
    }

    func testAFractionalPercentIsRoundedToAWholeOne() throws {
        let body = Self.answer(primary: Self.window(percent: 26.6, seconds: 604_800), secondary: nil)

        XCTAssertEqual(CodexUsageFetch.outcome(status: 200, body: body).reading?.windows.first?.percent, 27)
    }

    func testEachRefusalHasItsOwnTrouble() {
        XCTAssertEqual(CodexUsageFetch.outcome(status: 401, body: nil), .failed(.loginRefused))
        XCTAssertEqual(CodexUsageFetch.outcome(status: 502, body: nil), .failed(.serverError(502)))
        XCTAssertEqual(CodexUsageFetch.outcome(status: 429, body: nil), .failed(.busy))
        XCTAssertEqual(CodexUsageFetch.outcome(status: 0, body: nil), .failed(.unreachable))
        XCTAssertEqual(CodexUsageFetch.outcome(status: 403, body: nil), .failed(.refused(403)))
        XCTAssertEqual(CodexUsageFetch.outcome(status: 200, body: Data("[1]".utf8)), .failed(.unreadable))
        XCTAssertEqual(CodexUsageFetch.outcome(status: 200, body: nil), .failed(.unreadable))
    }

    func testAnAnswerWithoutWindowsIsAReadingWithNothingToShow() throws {
        let nulls = CodexUsageFetch.outcome(status: 200, body: Self.answer(primary: nil, secondary: nil))
        let noLimit = CodexUsageFetch.outcome(status: 200, body: Data(#"{"rate_limit":null}"#.utf8))

        XCTAssertEqual(nulls.reading?.windows, [])
        XCTAssertNil(nulls.reading?.shown)
        XCTAssertEqual(noLimit.reading?.windows, [])
    }

    func testThePercentIsClampedToZeroToAHundred() {
        let over = Self.answer(primary: Self.window(percent: 130, seconds: 18000),
                               secondary: Self.window(percent: -4, seconds: 604_800))

        XCTAssertEqual(CodexUsageFetch.outcome(status: 200, body: over).reading?.windows.map(\.percent), [100, 0])
    }

    func testTheRequestCarriesTheLoginAndTheAccount() {
        let request = CodexUsageFetch.request(token: "tok", accountID: "acct-work")

        XCTAssertEqual(request.url?.absoluteString, "https://chatgpt.com/backend-api/wham/usage")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertEqual(request.value(forHTTPHeaderField: "chatgpt-account-id"), "acct-work")
        XCTAssertEqual(request.value(forHTTPHeaderField: "originator"), "codex_cli_rs")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "User-Agent"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.timeoutInterval, 10)
        XCTAssertEqual(CodexUsageFetch.budget, 10, "the real world gives each read this overall deadline")
    }
}

extension CodexUsageOutcome {
    var reading: CodexUsageReading? {
        guard case .reading(let reading) = self else { return nil }
        return reading
    }
}
