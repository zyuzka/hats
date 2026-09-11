import XCTest
@testable import Hats

final class ShellTakeoverTests: XCTestCase {
    private let url = "http://127.0.0.1:8787"
    private let block = ShellEnvironment.block(baseURL: "http://127.0.0.1:8787", dialect: .posix)

    private func takenOver(_ profile: String, _ dialect: ShellDialect = .posix) -> String? {
        ShellEnvironment.takenOver(profile: profile, baseURL: url, dialect: dialect)
    }

    func testAForeignLineThatIsOnlyTheAssignmentIsReplacedByOurBlock() {
        let profile = "export PATH=/usr/bin\nexport ANTHROPIC_BASE_URL=https://proxy.internal # old\nalias ll='ls -la'\n"
        XCTAssertEqual(takenOver(profile),
                       "export PATH=/usr/bin\nalias ll='ls -la'\n\n" + block + "\n",
                       "the user's other lines stay byte for byte; only the assignment goes, our block comes")
    }

    func testTheSameInFishAndCsh() {
        XCTAssertEqual(takenOver("set -gx ANTHROPIC_BASE_URL https://p\nset -gx EDITOR vim\n", .fish),
                       "set -gx EDITOR vim\n\n"
                           + ShellEnvironment.block(baseURL: url, dialect: .fish) + "\n")
        XCTAssertEqual(takenOver("setenv ANTHROPIC_BASE_URL https://p\n", .csh),
                       ShellEnvironment.block(baseURL: url, dialect: .csh) + "\n",
                       "a profile that was only the foreign line becomes only our block")
    }

    func testALineThatAssignsMoreThanOursIsNotTakenOver() {
        XCTAssertNil(takenOver("export PATH=/usr/bin ANTHROPIC_BASE_URL=https://p\n"),
                     "deleting this line would take PATH with it; the user edits it by hand")
        XCTAssertNil(takenOver("ANTHROPIC_BASE_URL=https://p LANG=C\n"))
    }

    func testNothingForeignMeansNothingToTakeOver() {
        XCTAssertNil(takenOver("export PATH=/usr/bin\n"), "absent is not foreign")
        XCTAssertNil(takenOver(block + "\n"), "our own block is not foreign either")
        XCTAssertNil(takenOver("source ~/.env; export ANTHROPIC_BASE_URL=https://p\n"),
                     "an assignment this parser cannot read is not one it may delete")
    }

    func testAnAssignmentInsideAConstructIsLeftAloneRatherThanLeavingAnEmptyBody() {
        XCTAssertNil(takenOver("if [ \"$USE_PROXY\" = 1 ]; then\n  export ANTHROPIC_BASE_URL=https://p\nfi\n"),
                     "deleting the body leaves `if …; then fi`, which no shell parses")
        XCTAssertNil(takenOver("if [ -f ~/.env ]\nthen\nexport ANTHROPIC_BASE_URL=https://p\nfi\n"),
                     "the opener may stand on its own line")
        XCTAssertNil(takenOver("  export ANTHROPIC_BASE_URL=https://p\n"), "an indented line belongs to something")
        XCTAssertNil(takenOver("if test -f ~/.env\n    set -gx ANTHROPIC_BASE_URL https://p\nend\n", .fish))
        XCTAssertNil(takenOver("proxy() {\nexport ANTHROPIC_BASE_URL=https://p\n}\n"))
        XCTAssertNil(takenOver("if [ -f ~/.env ]; then # only at work\nexport ANTHROPIC_BASE_URL=https://p\nfi\n"),
                     "a comment after the opener does not make the body top-level")
        XCTAssertNotNil(takenOver("# the proxy, if you want it\nexport ANTHROPIC_BASE_URL=https://p\n"),
                        "a comment above is not a construct")
        XCTAssertNotNil(takenOver("export PATH=/usr/bin\n\nexport ANTHROPIC_BASE_URL=https://p\n"),
                        "a blank line between is not a construct either")
    }

    func testALineThatDoesMoreThanAssignIsNotOnlyAnAssignmentEvenWithoutSpaces() {
        XCTAssertNil(takenOver("export ANTHROPIC_BASE_URL=https://p;do_something\n"),
                     "deleting this line would delete do_something with it")
        XCTAssertNil(takenOver("export ANTHROPIC_BASE_URL=https://p|tee ~/log\n"))
        XCTAssertNil(takenOver("export ANTHROPIC_BASE_URL=https://p&\n"))
        XCTAssertNil(takenOver("export ANTHROPIC_BASE_URL=\"https://p\n"), "an unbalanced quote is not a plain word")
        XCTAssertNotNil(takenOver("export ANTHROPIC_BASE_URL=\"https://p;q\"\n"),
                        "inside quotes a semicolon is text, and the line is still only the assignment")
        XCTAssertNotNil(takenOver("export ANTHROPIC_BASE_URL='https://p'\n"))
        XCTAssertNil(takenOver("export ANTHROPIC_BASE_URL=`get-proxy`\n"), "a backtick runs a command")
        XCTAssertNil(takenOver("export ANTHROPIC_BASE_URL=\"`get-proxy`\"\n"), "and so does one inside double quotes")
        XCTAssertNotNil(takenOver("export ANTHROPIC_BASE_URL='a`b'\n"), "inside single quotes it is a character")
        XCTAssertNil(takenOver("set -gx ANTHROPIC_BASE_URL https://p;rm x\n", .fish))
        XCTAssertNil(takenOver("setenv ANTHROPIC_BASE_URL https://p;rm x\n", .csh))
    }

    func testTheResultReadsAsOursAfterwards() throws {
        let after = try XCTUnwrap(takenOver("export ANTHROPIC_BASE_URL=https://p\n"))
        XCTAssertEqual(ShellEnvironment.verdict(profile: after, baseURL: url, dialect: .posix, serving: true),
                       .ours)
    }
}
