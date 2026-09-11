import XCTest
@testable import Hats

final class LiveSlotChangeTests: XCTestCase {
    private let first = Data("first login".utf8)
    private let second = Data("login issued by the re-login".utf8)

    func testANewCredentialInTheSlotIsAChange() {
        XCTAssertTrue(LiveSlotNow.hasChanged(from: .holding(first), to: .holding(second)))
    }

    func testTheSameCredentialIsNotAChange() {
        XCTAssertFalse(LiveSlotNow.hasChanged(from: .holding(first), to: .holding(first)))
    }

    func testASlotFilledOrEmptiedIsAChange() {
        XCTAssertTrue(LiveSlotNow.hasChanged(from: .empty, to: .holding(first)))
        XCTAssertTrue(LiveSlotNow.hasChanged(from: .holding(first), to: .empty))
    }

    func testAnEmptySlotStayingEmptyIsNotAChange() {
        XCTAssertFalse(LiveSlotNow.hasChanged(from: .empty, to: .empty))
    }

    func testASlotThatCouldNotBeReadOnEitherSideIsNotAChange() {
        XCTAssertFalse(LiveSlotNow.hasChanged(from: .unreadable, to: .holding(second)))
        XCTAssertFalse(LiveSlotNow.hasChanged(from: .holding(first), to: .unreadable))
        XCTAssertFalse(LiveSlotNow.hasChanged(from: .unreadable, to: .unreadable))
    }
}
