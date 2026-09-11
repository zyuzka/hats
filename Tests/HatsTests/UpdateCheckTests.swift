import XCTest
@testable import Hats

final class UpdateCheckTests: XCTestCase {
    private func payload(
        tag: String = "v0.2.0",
        draft: Bool = false,
        prerelease: Bool = false,
        assets: String = #"[{"name":"Hats-0.2.0.dmg","browser_download_url":"https://example.test/Hats.dmg"}]"#
    ) -> Data {
        Data("""
        {"tag_name":"\(tag)","draft":\(draft),"prerelease":\(prerelease),
         "html_url":"https://example.test/releases/\(tag)","assets":\(assets)}
        """.utf8)
    }

    func testAVersionIsComparedByItsNumbersRatherThanItsText() {
        XCTAssertTrue(UpdateCheck.isNewer("0.2.0", than: "0.1.0"))
        XCTAssertTrue(UpdateCheck.isNewer("0.10.0", than: "0.9.0"),
                      "10 is above 9; comparing the text would put it below")
        XCTAssertFalse(UpdateCheck.isNewer("0.1.0", than: "0.1.0"))
        XCTAssertFalse(UpdateCheck.isNewer("0.1.0", than: "0.2.0"))
        XCTAssertTrue(UpdateCheck.isNewer("1.0", than: "0.9.9"),
                      "a two-part tag is still a version")
    }

    func testTheLeadingVeeOnATagIsNotPartOfTheVersion() {
        XCTAssertEqual(UpdateCheck.normalised("v0.2.0"), "0.2.0")
        XCTAssertEqual(UpdateCheck.normalised(" V1.4.0 "), "1.4.0")
        XCTAssertEqual(UpdateCheck.normalised("0.2.0"), "0.2.0")
    }

    func testAReleaseCarriesItsPageAndItsDiskImage() throws {
        let release = try XCTUnwrap(UpdateCheck.release(from: payload()))

        XCTAssertEqual(release.version, "0.2.0")
        XCTAssertEqual(release.page.absoluteString, "https://example.test/releases/v0.2.0")
        XCTAssertEqual(release.asset?.absoluteString, "https://example.test/Hats.dmg")
    }

    func testAReleaseWithoutADiskImageIsStillARelease() throws {
        let release = try XCTUnwrap(UpdateCheck.release(from: payload(assets: "[]")))

        XCTAssertEqual(release.version, "0.2.0")
        XCTAssertNil(release.asset, "the page is still worth opening; the download is not there yet")
    }

    func testDraftsAndPrereleasesAreNotOffered() {
        XCTAssertNil(UpdateCheck.release(from: payload(draft: true)))
        XCTAssertNil(UpdateCheck.release(from: payload(prerelease: true)),
                     "a prerelease is not what someone running the app should be pushed to")
    }

    func testTheVerdictSeparatesSilenceFromRefusalFromAnAnswer() {
        XCTAssertEqual(UpdateCheck.verdict(status: 0, body: nil, running: "0.1.0"), .unreachable,
                       "no answer is not the same as no update")
        XCTAssertEqual(UpdateCheck.verdict(status: 404, body: nil, running: "0.1.0"), .unreadable,
                       "a private repository answers 404, and that is not up to date")
        XCTAssertEqual(UpdateCheck.verdict(status: 200, body: Data("{".utf8), running: "0.1.0"),
                       .unreadable)
    }

    func testAnOlderOrEqualReleaseReadsAsUpToDate() {
        XCTAssertEqual(UpdateCheck.verdict(status: 200, body: payload(tag: "v0.1.0"), running: "0.1.0"),
                       .upToDate(running: "0.1.0"))
        XCTAssertEqual(UpdateCheck.verdict(status: 200, body: payload(tag: "v0.0.9"), running: "0.1.0"),
                       .upToDate(running: "0.1.0"))
    }

    func testANewerReleaseIsOffered() throws {
        let verdict = UpdateCheck.verdict(status: 200, body: payload(), running: "0.1.0")

        guard case .available(let release) = verdict else {
            return XCTFail("0.2.0 is newer than 0.1.0, so it has to be offered")
        }
        XCTAssertEqual(release.version, "0.2.0")
    }

    func testTheRequestAsksGitHubForTheDocumentedShape() {
        let request = UpdateCheck.request(endpoint: UpdateCheck.endpoint(for: "owner/app"))

        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-GitHub-Api-Version"), "2022-11-28")
        XCTAssertEqual(request.url?.absoluteString,
                       "https://api.github.com/repos/owner/app/releases/latest")
    }

    func testTheRepositoryComesFromTheBundleRatherThanTheSource() {
        XCTAssertEqual(UpdateCheck.repository(in: ["HatsUpdateRepository": "owner/app"]), "owner/app")
        XCTAssertEqual(UpdateCheck.repository(in: ["HatsUpdateRepository": "  owner/app  "]), "owner/app")
        XCTAssertNil(UpdateCheck.repository(in: [:]), "a build without the key asks nobody")
        XCTAssertNil(UpdateCheck.repository(in: ["HatsUpdateRepository": ""]))
        XCTAssertNil(UpdateCheck.repository(in: ["HatsUpdateRepository": "app"]),
                     "owner/name or nothing — a bare word would build a URL that answers about "
                         + "something else entirely")
        XCTAssertNil(UpdateCheck.repository(in: ["HatsUpdateRepository": "/app"]))
        XCTAssertNil(UpdateCheck.repository(in: ["HatsUpdateRepository": "owner/"]))
    }

    func testTheBuildScriptStampsTheRepositoryIntoTheBundle() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Build/build-app.sh")
        let text = try String(contentsOf: script, encoding: .utf8)

        XCTAssertTrue(text.contains("<key>\(UpdateCheck.repositoryKey)</key>"),
                      "the key moved out of the source so that a bundle carries it; a build that "
                          + "stops stamping it turns Check for Updates into a dead menu item")
    }
}
