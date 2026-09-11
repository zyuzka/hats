import XCTest
@testable import Hats

final class ReleaseNotesTests: XCTestCase {
    private let sample = """
    # Hats — what changed

    Newest first.

    ## 0.7.2 — 2026-09-01

    - The Live sessions window closes when you click away.
    - Its minimise button is gone.

    ## 0.7.0 — 2026-09-01

    - A quit button at the foot of the popover.

    ## 0.2.0 — 2026-08-21

    - First version handed to anyone.
    """

    func testEveryVersionHeadingBecomesAnEntry() {
        let notes = ReleaseNotes.parse(sample)
        XCTAssertEqual(notes.map(\.version), ["0.7.2", "0.7.0", "0.2.0"])
    }

    func testTheOrderOfTheFileIsKept() {
        let notes = ReleaseNotes.parse(sample)
        XCTAssertEqual(notes.first?.version, "0.7.2",
                       "the file is newest first and the window must not reorder it")
    }

    func testTheDateSurvivesWithoutItsDash() {
        XCTAssertEqual(ReleaseNotes.parse(sample).first?.dateline, "2026-09-01")
    }

    func testTheLinesOfAnEntryStopAtTheNextHeading() {
        let notes = ReleaseNotes.parse(sample)
        XCTAssertEqual(notes.first?.lines, [
            "- The Live sessions window closes when you click away.",
            "- Its minimise button is gone.",
        ])
        XCTAssertEqual(notes.last?.lines, ["- First version handed to anyone."])
    }

    func testThePreambleBeforeTheFirstHeadingIsNotAnEntry() {
        let notes = ReleaseNotes.parse(sample)
        XCTAssertFalse(notes.contains { $0.lines.contains { $0.contains("Newest first") } },
                       "everything above the first version heading belongs to nobody")
    }

    func testAHeadingThatIsNotAVersionIsNotAnEntry() {
        let notes = ReleaseNotes.parse("""
        ## Known problems

        - something

        ## 0.1.0 — 2026-01-01

        - first
        """)
        XCTAssertEqual(notes.map(\.version), ["0.1.0"])
        XCTAssertEqual(notes.first?.lines, ["- first"],
                       "a prose heading must not swallow the entry that follows it")
    }

    func testOnlyASecondLevelHeadingStartsAnEntry() {
        let notes = ReleaseNotes.parse("""
        # 0.9.0

        - a title that happens to be a version

        ## 0.8.0 — 2026-09-02

        - the real entry
        ### 0.8.0-rc1
        - a subheading inside it
        """)
        XCTAssertEqual(notes.map(\.version), ["0.8.0"],
                       "an H1 title and an H3 subheading are not releases, whatever they are named")
        XCTAssertEqual(notes.first?.lines.count, 3,
                       "the subheading stays inside the entry it belongs to rather than starting a new one")
    }

    func testWhatCountsAsAVersion() {
        XCTAssertTrue(ReleaseNotes.isAVersion("0.7.2"))
        XCTAssertTrue(ReleaseNotes.isAVersion("1.0"))
        XCTAssertTrue(ReleaseNotes.isAVersion("10.20.30"))
        XCTAssertFalse(ReleaseNotes.isAVersion("Known"))
        XCTAssertFalse(ReleaseNotes.isAVersion("0"), "a single number is a heading word, not a version")
        XCTAssertFalse(ReleaseNotes.isAVersion("0.7.x"))
        XCTAssertFalse(ReleaseNotes.isAVersion("0..1"))
        XCTAssertFalse(ReleaseNotes.isAVersion(""))
    }

    func testAnEmptyFileIsNoEntriesRatherThanACrash() {
        XCTAssertTrue(ReleaseNotes.parse("").isEmpty)
        XCTAssertTrue(ReleaseNotes.parse("# Title only").isEmpty)
    }

    func testTheShippedChangelogParsesAndCoversTheRunningVersion() throws {
        let here = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("CHANGELOG.md")
        let text = try String(contentsOf: here, encoding: .utf8)
        let notes = ReleaseNotes.parse(text)
        XCTAssertFalse(notes.isEmpty, "the file in the repository is what the app ships")
        XCTAssertGreaterThanOrEqual(notes.reduce(0) { $0 + $1.lines.count }, 40,
                                    "counting headings stopped meaning anything when the private line was "
                                        + "folded into one entry; what still means something is that the "
                                        + "entries carry text the app can show")
        XCTAssertEqual(notes.map(\.version).count, Set(notes.map(\.version)).count,
                       "two headings for one version would render twice")
        XCTAssertTrue(notes.allSatisfy { !$0.lines.isEmpty },
                      "a version with a heading and nothing under it reads as a version that changed nothing")

        let script = here.deletingLastPathComponent().appendingPathComponent("Build/build-app.sh")
        let stamp = try NSRegularExpression(
            pattern: #"CFBundleShortVersionString</key>\s*<string>([^<]+)</string>"#
        )
        let scriptText = try String(contentsOf: script, encoding: .utf8)
        let match = try XCTUnwrap(stamp.firstMatch(
            in: scriptText, range: NSRange(scriptText.startIndex..., in: scriptText)
        ))
        let stampedRange = try XCTUnwrap(Range(match.range(at: 1), in: scriptText))
        let stamped = String(scriptText[stampedRange])

        XCTAssertTrue(notes.contains { $0.version == stamped },
                      "the second half of this test's name was a claim nothing here checked: the "
                          + "version the build script stamps is the one the releases window looks "
                          + "for, and a bump with no entry renders an empty window. Dev/changelog-check.sh "
                          + "holds the same property, but only when somebody runs it")
    }

    func testAVersionIsASCIIDigitsAndNotAnyNumeralUnicodeKnows() {
        XCTAssertTrue(ReleaseNotes.isAVersion("0.7.2"))
        for numeral in ["２.７.２", "٢.٧.٢", "Ⅶ.2", "½.2"] {
            XCTAssertFalse(ReleaseNotes.isAVersion(numeral),
                           "\(numeral) can never equal the ASCII plist value, so accepting it "
                               + "renders a heading that is silently never the running one")
        }
    }

    func testTheMissingNotesSentenceDoesNotPickOneOfThreeCauses() {
        let said = HatsCopy.releaseNotesMissing(running: "0.8.0")

        XCTAssertTrue(said.contains("0.8.0"))
        XCTAssertTrue(said.contains("missing, unreadable, or carries no version heading"),
                      "the empty list has three causes and the sentence used to assert one of them, "
                          + "sending a reader after a packaging omission when the file was malformed")
    }
}
