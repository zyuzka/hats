import AppKit
import ServiceManagement
import XCTest
@testable import Hats

final class LoginItemTests: XCTestCase {
    func testARegisteredItemIsCheckedAndClickable() {
        let face = LoginItem.face(for: .enabled)
        XCTAssertEqual(face.state, .on)
        XCTAssertTrue(face.isEnabled)
    }

    func testAnUnregisteredItemIsUncheckedAndClickable() {
        let face = LoginItem.face(for: .notRegistered)
        XCTAssertEqual(face.state, .off)
        XCTAssertTrue(face.isEnabled)
    }

    func testAnItemAwaitingApprovalSaysWhereToApproveIt() {
        let face = LoginItem.face(for: .requiresApproval)
        XCTAssertEqual(face.state, .mixed)
        XCTAssertTrue(face.isEnabled)
        XCTAssertTrue(face.title.contains("System Settings"))
    }

    func testAnUnfoundItemIsAnUnregisteredOneAndStaysClickable() {
        let face = LoginItem.face(for: .notFound)
        XCTAssertTrue(face.isEnabled)
        XCTAssertEqual(face.state, .off)
        XCTAssertEqual(face.action, .register)
        XCTAssertEqual(face.title, "Start at login")
    }

    func testTheActionSurvivesTheRoundTripThroughRepresentedObject() {
        let item = NSMenuItem()
        item.representedObject = LoginItem.Action.unregister
        XCTAssertEqual(item.representedObject as? LoginItem.Action, .unregister)
    }

    func testTheClickDoesWhatTheCheckmarkPromised() {
        XCTAssertEqual(LoginItem.face(for: .enabled).action, .unregister)
        XCTAssertEqual(LoginItem.face(for: .notRegistered).action, .register)
        XCTAssertEqual(LoginItem.face(for: .requiresApproval).action, .openApproval)
    }
}
