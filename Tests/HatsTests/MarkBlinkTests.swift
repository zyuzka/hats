import AppKit
import XCTest
@testable import Hats

final class MarkBlinkTests: XCTestCase {
    private var blink: MarkBlink!

    override func setUp() {
        super.setUp()
        blink = MarkBlink(button: nil)
        blink.reducesMotion = { false }
    }

    override func tearDown() {
        blink.stop()
        blink = nil
        super.tearDown()
    }

    private func pixels(_ state: MarkState, cursorVisible: Bool) throws -> Data {
        try XCTUnwrap(Mark.image(state: state, cursorVisible: cursorVisible).tiffRepresentation)
    }

    func testOnlyTheCursorGoesAwayAndTheLettersAndMeterStay() throws {
        for state in [MarkState.idle, .wearing(percent: nil), .wearing(percent: 85), .attention] {
            XCTAssertNotEqual(try pixels(state, cursorVisible: true),
                              try pixels(state, cursorVisible: false),
                              "the two phases of \(state) have to differ or nothing blinks")
        }

        XCTAssertEqual(try pixels(.idle, cursorVisible: false),
                       try pixels(.wearing(percent: nil), cursorVisible: false),
                       "hollow and solid are both cursor, so with the cursor gone these are the "
                           + "same three letters — which is what proves only the cursor was removed")
        XCTAssertEqual(try pixels(.attention, cursorVisible: false),
                       try pixels(.idle, cursorVisible: false))

        XCTAssertNotEqual(try pixels(.wearing(percent: 85), cursorVisible: false),
                          try pixels(.wearing(percent: nil), cursorVisible: false),
                          "the usage meter is steady: it is still drawn while the cursor is off")
        XCTAssertNotEqual(try pixels(.wearing(percent: 85), cursorVisible: false),
                          try pixels(.wearing(percent: 95), cursorVisible: false),
                          "and it still tracks the reading")
    }

    func testTheImageWithACursorIsExactlyWhatTheAppDrewBeforeThisFeature() throws {
        for state in [MarkState.idle, .wearing(percent: 85), .attention] {
            XCTAssertEqual(try pixels(state, cursorVisible: true),
                           try XCTUnwrap(Mark.image(state: state).tiffRepresentation),
                           "the default is the old drawing, so a user who turns the blink off sees "
                               + "no other change")
        }
    }

    func testTheBlinkIsOffWheneverTheSystemOrTheUserAsksForLessMovement() {
        for setting in [true, false] {
            for reduce in [true, false] {
                for awake in [true, false] {
                    let wanted = MarkBlink.isBlinkingWanted(setting: setting,
                                                            reduceMotion: reduce,
                                                            awake: awake)
                    XCTAssertEqual(wanted, setting && !reduce && awake,
                                   "setting=\(setting) reduceMotion=\(reduce) awake=\(awake)")
                }
            }
        }
    }

    func testARedrawWithAnUnchangedStateDoesNotResetThePhase() {
        blink.show(.wearing(percent: nil), blinking: true)
        XCTAssertTrue(blink.isShowingCursor)
        blink.advanceTheBlink()
        XCTAssertFalse(blink.isShowingCursor)

        blink.show(.wearing(percent: nil), blinking: true)
        XCTAssertFalse(blink.isShowingCursor,
                       "usage is polled every 300 s and every poll redraws; a cursor that jumped "
                           + "back to visible each time would stutter, which is worse than not blinking")
    }

    func testARedrawDoesNotRestartTheTimerEither() {
        blink.show(.idle, blinking: true)
        XCTAssertEqual(blink.timersStarted, 1)
        blink.show(.idle, blinking: true)
        blink.show(.wearing(percent: 40), blinking: true)
        XCTAssertEqual(blink.timersStarted, 1,
                       "a timer recreated on every redraw pushes its next tick half a second out "
                           + "each time, which is the same stutter one step further from view")

        blink.show(.idle, blinking: false)
        blink.show(.idle, blinking: true)
        XCTAssertEqual(blink.timersStarted, 2, "turning it off and on again is a real restart")
    }

    func testAStateChangeKeepsThePhaseToo() {
        blink.show(.idle, blinking: true)
        blink.advanceTheBlink()
        XCTAssertFalse(blink.isShowingCursor)
        blink.show(.wearing(percent: 85), blinking: true)
        XCTAssertFalse(blink.isShowingCursor, "the new state's images are used from the next tick")
    }

    func testTurningTheBlinkOffLeavesTheCursorShowing() {
        blink.show(.attention, blinking: true)
        blink.advanceTheBlink()
        XCTAssertFalse(blink.isShowingCursor)

        blink.show(.attention, blinking: false)
        XCTAssertTrue(blink.isShowingCursor,
                      "a mark left mid-blink would hide the attention dot for good")
    }

    func testReduceMotionTurnedOnAtRuntimeStopsTheBlinkWithoutARelaunch() {
        blink.show(.wearing(percent: nil), blinking: true)
        blink.advanceTheBlink()
        XCTAssertFalse(blink.isShowingCursor)

        blink.reducesMotion = { true }
        blink.show(.wearing(percent: nil), blinking: true)
        XCTAssertTrue(blink.isShowingCursor,
                      "someone who asked the system for less movement has asked for this too")
    }

    func testSleepStopsTheBlinkAndWakingResumesIt() {
        blink.show(.wearing(percent: nil), blinking: true)
        blink.advanceTheBlink()
        XCTAssertFalse(blink.isShowingCursor)

        blink.pause(.machineAsleep)
        XCTAssertTrue(blink.isShowingCursor,
                      "a half-second timer must not keep the process busy while the machine sleeps "
                          + "or the screen is locked")
        blink.resume(.machineAsleep)
        blink.advanceTheBlink()
        XCTAssertFalse(blink.isShowingCursor, "and it comes back")
    }

    func testWakingDoesNotResumeTheBlinkWhileTheScreenIsStillLocked() {
        blink.show(.wearing(percent: nil), blinking: true)
        blink.pause(.screenLocked)
        blink.pause(.machineAsleep)
        blink.resume(.machineAsleep)
        XCTAssertTrue(blink.isPaused,
                      "lock, then sleep, then wake: one flag for both would have the half-second "
                          + "timer running on the lock screen the observer exists to stop")
        blink.resume(.screenLocked)
        XCTAssertFalse(blink.isPaused)
    }

    func testEveryPauseReasonIsIndependentOfTheOthers() {
        blink.show(.idle, blinking: true)
        for reason in MarkBlink.Pause.allCases {
            blink.pause(reason)
            XCTAssertTrue(blink.isPaused, "\(reason) pauses")
        }
        for reason in MarkBlink.Pause.allCases.dropLast() {
            blink.resume(reason)
            XCTAssertTrue(blink.isPaused, "still paused while \(MarkBlink.Pause.allCases.last!) holds")
        }
        blink.resume(MarkBlink.Pause.allCases.last!)
        XCTAssertFalse(blink.isPaused)
    }

    func testWatchingTheSystemTwiceDoesNotLeaveTwoSetsOfObservers() {
        blink.watchTheSystem()
        let once = blink.observerCount
        XCTAssertGreaterThan(once, 0)
        blink.watchTheSystem()
        XCTAssertEqual(blink.observerCount, once)

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        let delivered = expectation(description: "the sleep notification reaches its observers")
        DispatchQueue.main.async { delivered.fulfill() }
        wait(for: [delivered], timeout: 2)
        XCTAssertEqual(blink.signalsHandled, 1,
                       "reassigning the arrays without removing what was there leaves the first set "
                           + "registered, and every sleep then fires twice")

        blink.stop()
        XCTAssertEqual(blink.observerCount, 0)
    }

    func testTheImagePaintedIsTheOneForTheCurrentPhase() throws {
        let state = MarkState.wearing(percent: 85)
        blink.show(state, blinking: true)
        let visible = try XCTUnwrap(blink.lastPainted?.tiffRepresentation)
        XCTAssertEqual(visible, try pixels(state, cursorVisible: true))
        blink.advanceTheBlink()
        XCTAssertEqual(try XCTUnwrap(blink.lastPainted?.tiffRepresentation),
                       try pixels(state, cursorVisible: false))
    }

    func testASettingsFileWrittenBeforeThisFeatureBlinks() throws {
        let older = Data(#"{"gatewayPort":8787}"#.utf8)
        XCTAssertTrue(try JSONDecoder().decode(AppSettings.self, from: older).blinksTheCursorInTheMenuBar)
    }
}
