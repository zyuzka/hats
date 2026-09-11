import XCTest
@testable import Hats

final class JournalLineTests: XCTestCase {
    func testAValueCannotForgeALineOfItsOwn() {
        let forged = "attacker@example.com\n2026-09-09T00:00:00Z activate.done target=someone-else"

        let flattened = Journal.onOneLine(forged)

        XCTAssertFalse(flattened.contains("\n"),
                       "the account address comes straight off the renewal answer and the journal "
                           + "is the plain-text file a person reads to diagnose a switch; a newline "
                           + "in it writes entries indistinguishable from real ones")
        XCTAssertTrue(flattened.hasPrefix("attacker@example.com "), flattened)
    }

    func testEveryControlCharacterIsFlattened() {
        for scalar in [0x00, 0x07, 0x09, 0x0A, 0x0D, 0x1B, 0x7F] {
            let value = "a\(Character(UnicodeScalar(scalar)!))b"

            XCTAssertEqual(Journal.onOneLine(value), "a b",
                           "scalar \(scalar) has to go: a carriage return rewrites the line in a "
                               + "terminal just as a newline splits it, and an escape can colour it")
        }
    }

    func testOrdinaryProseIsLeftExactlyAsItIs() {
        let real = "the list of Claude Code sessions running now could not be read — try again"

        XCTAssertEqual(Journal.onOneLine(real), real,
                       "the longest real value in this log is a sentence of this shape, so no "
                           + "length cap was added: every number that would truncate it is chosen "
                           + "rather than measured")
    }

    func testTheRenderedLineIsOneLineWhateverTheValueCarries() {
        let forged = "attacker@example.com\n2026-09-09T00:00:00Z activate.done target=someone-else"

        let line = Journal.line("renew.done", ["account": forged], at: "2026-09-09T18:00:00Z")

        XCTAssertEqual(line.filter { $0.isNewline }.count, 1,
                       "driven through the real rendering rather than through onOneLine, because "
                           + "the first version of this check called the sanitiser directly and a "
                           + "mutant that simply stopped calling it from log() survived the whole "
                           + "suite — a seam the product does not use is not evidence about it")
        XCTAssertTrue(line.hasSuffix("\n"), line)
        XCTAssertTrue(line.contains("account=attacker@example.com 2026-09-09T00:00:00Z"), line)
    }

    func testTheRenderedLineKeepsTheShapeTheJournalAlreadyHas() {
        let line = Journal.line("renew.done", ["slot": "Hats parked D0582D9E", "account": "a@b.c"],
                                at: "2026-09-09T18:00:00Z")

        XCTAssertEqual(line, "2026-09-09T18:00:00Z renew.done account=a@b.c slot=Hats parked D0582D9E\n",
                       "the keys stay sorted and the separator stays a single space, because six "
                           + "days of this log are already parsed by eye in that shape")
    }
}
