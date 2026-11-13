import XCTest
@testable import Hats

final class SessionWindowsWiringTests: XCTestCase {
    private func sourceOf(_ name: String) -> String {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Hats/\(name)")

        return (try? String(contentsOf: source, encoding: .utf8)) ?? ""
    }

    private func getBody(of function: String, in source: String) throws -> Substring {
        let start = try XCTUnwrap(source.range(of: function), "\(function) is gone")
        let rest = source[start.upperBound...]
        let end = rest.range(of: "\n    }\n")?.lowerBound ?? rest.endIndex

        return rest[..<end]
    }

    func testEveryRedrawShowsTheContextRowsAndWritesTheHatUsage() throws {
        let redraw = try getBody(of: "func redraw() {", in: sourceOf("AppDelegate+Redraw.swift"))

        XCTAssertTrue(redraw.contains("snapshot.contextRows = SessionWindow.getMenuRows(sessionWindows.windows, now: Date())"),
                      "the field has a default, so dropping this line compiles and the block never shows")
        XCTAssertTrue(redraw.contains("popover.model.snapshot = snapshot\n        writeTheHatUsage()"),
                      "the usage file is written from the snapshot just shown, after every redraw")
    }

    func testAFolderChangeUpdatesOnlyTheContextRowsOfTheShownSnapshot() throws {
        let main = sourceOf("main.swift")
        let show = try getBody(of: "func showTheContextRows() {", in: sourceOf("AppDelegate+Redraw.swift"))

        XCTAssertTrue(main.contains("sessionWindows.onChange = { [weak self] in self?.showTheContextRows() }"),
                      "a folder change must not run a full redraw, which reads the process table with the menu open")
        XCTAssertTrue(main.contains("sessionWindows.start()"), "without start nothing is read or watched")
        XCTAssertTrue(show.contains("popover.model.snapshot.contextRows = SessionWindow.getMenuRows(sessionWindows.windows, "
                                        + "now: Date())"))
    }

    func testTheMenuShowsTheBlockBetweenTheHatsAndTheBottomRow() {
        let view = sourceOf("HatListView.swift")

        XCTAssertTrue(view.contains("if snapshot.rows.isEmpty { empty } else { list }\n"
                                        + "            if !snapshot.contextRows.isEmpty { context }\n"
                                        + "            Divider().padding(.vertical, 4)"))
        XCTAssertTrue(view.contains("ForEach(snapshot.contextRows)"))
    }

    func testAFailedUsageWriteIsToldOncePerReasonAndForgottenOnSuccess() throws {
        let write = try getBody(of: "func writeTheHatUsage() {", in: sourceOf("AppDelegate+HatUsage.swift"))

        XCTAssertTrue(write.contains("guard lastHatUsageFailure.shouldWrite(reason) else { return }"),
                      "without the guard every redraw would add a journal line")
        XCTAssertTrue(write.contains("case .written, .unchanged:\n            lastHatUsageFailure.clear()"),
                      "a success forgets the reason, so the same failure later is told again")
    }
}
