import XCTest
@testable import Hats

final class GatewayUsageHeadersTests: XCTestCase {
    private struct Sighting: Equatable {
        let credential: String
        let reading: UsageReading
    }

    private struct Answer {
        let status: Int
        let body: String
        let headers: [String: String]
    }

    private let sightings = Locked<[Sighting]>([])
    private let staged = Locked<NIOTestListener.Answer>(.fixed(
        status: 200,
        headers: [:],
        body: "{}"
    ))
    private var upstream: NIOTestListener!
    private var gateway: GatewayServer!

    private let rateLimits = [
        "Anthropic-Ratelimit-Unified-5h-Utilization": "0.9",
        "anthropic-ratelimit-unified-5h-reset": "1794106800",
        "anthropic-ratelimit-unified-7d-utilization": "0.51",
        "anthropic-ratelimit-unified-7d-reset": "1794574800",
    ]

    private var expectedReading: UsageReading {
        UsageReading(
            session: UsageWindow(
                used: 90,
                limit: 100,
                resetsAt: Date(timeIntervalSince1970: 1_794_106_800)
            ),
            weekly: UsageWindow(
                used: 51,
                limit: 100,
                resetsAt: Date(timeIntervalSince1970: 1_794_574_800)
            )
        )
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        sightings.value = []
        upstream = NIOTestListener()
        upstream.onRequest = { [weak self] _ in
            self?.staged.value ?? .fixed(
                status: 500,
                headers: [:],
                body: ""
            )
        }
        try upstream.start()

        gateway = GatewayServer(
            port: 0,
            refusal: nil,
            usageSink: { [weak self] credential, reading in
                self?.sightings.mutate { $0.append(Sighting(credential: credential, reading: reading)) }
            },
            upstream: URL(string: "http://127.0.0.1:\(upstream.port)")!
        )
        try gateway.start()
    }

    override func tearDown() {
        gateway?.stop()
        upstream?.stop()
        super.tearDown()
    }

    private func getAnswer(for token: String) -> Answer {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(gateway.boundPort ?? 0)/v1/messages")!)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")

        var answer = Answer(
            status: 0,
            body: "",
            headers: [:]
        )
        let waiter = expectation(description: token)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let http = response as? HTTPURLResponse
            var headers: [String: String] = [:]
            for (name, value) in http?.allHeaderFields ?? [:] {
                headers[String(describing: name).lowercased()] = String(describing: value)
            }
            answer = Answer(
                status: http?.statusCode ?? 0,
                body: String(data: data ?? Data(), encoding: .utf8) ?? "",
                headers: headers
            )
            waiter.fulfill()
        }.resume()
        wait(
            for: [
                waiter,
            ],
            timeout: 15
        )

        return answer
    }

    func testTheSinkHearsTheKeyAndTheUsageAndTheClientGetsTheAnswerUnchanged() {
        let body = #"{"id":"msg_1","content":[{"type":"text","text":"ok"}]}"#
        staged.value = .fixed(
            status: 200,
            headers: rateLimits,
            body: body
        )

        let answer = getAnswer(for: "tok-1")

        XCTAssertEqual(
            sightings.value,
            [
                Sighting(credential: GatewayCredential.fingerprint("Bearer tok-1"), reading: expectedReading),
            ],
            "the sink got the fingerprint of the session's own Authorization header and the parsed usage"
        )
        XCTAssertEqual(answer.status, 200)
        XCTAssertEqual(
            answer.body,
            body,
            "the body reached the session unchanged"
        )
        for (name, value) in rateLimits {
            XCTAssertEqual(
                answer.headers[name.lowercased()],
                value,
                "the session still sees \(name)"
            )
        }
    }

    func testARefusalAtTheLimitIsReadTheSameWay() {
        let body = #"{"type":"error","error":{"type":"rate_limit_error"}}"#
        staged.value = .fixed(
            status: 429,
            headers: rateLimits,
            body: body
        )

        let answer = getAnswer(for: "tok-2")

        XCTAssertEqual(sightings.value, [
            Sighting(credential: GatewayCredential.fingerprint("Bearer tok-2"), reading: expectedReading),
        ])
        XCTAssertEqual(
            answer.status,
            429,
            "the session gets the refusal as the server sent it"
        )
        XCTAssertEqual(answer.body, body)
    }

    func testAnAnswerWithoutTheHeadersReachesNoSink() {
        staged.value = .fixed(
            status: 200,
            headers: [
                "Content-Type": "application/json",
            ],
            body: #"{"a":1}"#
        )

        let answer = getAnswer(for: "tok-3")

        XCTAssertEqual(answer.body, #"{"a":1}"#)
        XCTAssertEqual(
            sightings.value,
            [],
            "an answer without the rate-limit headers calls no sink"
        )
    }
}
