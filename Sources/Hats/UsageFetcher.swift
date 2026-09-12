import Foundation

enum UsageFetcher {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")
        ?? URL(fileURLWithPath: "/")
    static let betaHeader = "oauth-2025-04-20"
    static let budget: TimeInterval = 4
    static let refusals: Set<Int> = [401, 403]

    static func request(token: String, endpoint: URL = endpoint) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = budget
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue(betaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    static func outcome(status: Int, body: Data?) -> UsageFetch {
        guard status != 0 else { return .unreachable }
        guard status == 200 else { return Self.refusals.contains(status) ? .refused(status) : .errored(status) }
        guard let body,
              let payload = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let reading = UsageReading.parsed(payload)
        else { return .unreadable }
        return .reading(reading)
    }

    static func reading(status: Int, body: Data?) -> UsageReading? {
        outcome(status: status, body: body).reading
    }

    static func fetch(token: String, endpoint: URL = endpoint) -> UsageFetch {
        OneShotRequest.answer(
            to: request(token: token, endpoint: endpoint),
            within: budget,
            unreachable: .unreachable,
            reading: { status, body in outcome(status: status, body: body) }
        )
    }
}

enum UsageFetch: Equatable {
    case reading(UsageReading)
    case refused(Int)
    case errored(Int)
    case unreadable
    case unreachable

    var reading: UsageReading? {
        guard case .reading(let reading) = self else { return nil }
        return reading
    }

    var needsAWait: Bool {
        switch self {
        case .refused: return true
        case .errored(let status): return status == 429
        case .reading, .unreachable, .unreadable: return false
        }
    }

    var refusedAuthorization: Bool {
        guard case .refused(let status) = self else { return false }

        return status == 401
    }

    var trouble: String? {
        switch self {
        case .reading: return nil
        case .refused(let status): return "refused \(status)"
        case .errored(let status): return "http \(status)"
        case .unreadable: return "unreadable"
        case .unreachable: return "unreachable"
        }
    }
}
