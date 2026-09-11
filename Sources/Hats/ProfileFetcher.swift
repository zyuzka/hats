import Foundation

enum ProfileFetcher {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/profile")
        ?? URL(fileURLWithPath: "/")
    static let budget: TimeInterval = 4
    static let refusals: Set<Int> = [401, 403]
    static func request(token: String, endpoint: URL = endpoint) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = budget
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        return request
    }

    static func outcome(status: Int, body: Data?) -> ProfileFetch {
        guard status != 0 else { return .unreachable }
        guard status == 200 else {
            return Self.refusals.contains(status) ? .refused(status) : .errored(status)
        }
        guard let body,
              let payload = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let identity = TokenIdentity.parsed(payload)
        else { return .unreadable }
        return .identity(identity)
    }

    static func fetch(token: String, endpoint: URL = endpoint) -> ProfileFetch {
        OneShotRequest.answer(
            to: request(token: token, endpoint: endpoint),
            within: budget,
            unreachable: .unreachable,
            reading: { status, body in outcome(status: status, body: body) }
        )
    }
}

enum ProfileFetch: Equatable {
    case identity(TokenIdentity)
    case refused(Int)
    case errored(Int)
    case unreadable
    case unreachable

    var identity: TokenIdentity? {
        guard case .identity(let identity) = self else { return nil }
        return identity
    }

    var trouble: String? {
        switch self {
        case .identity: return nil
        case .refused(let status): return "refused \(status)"
        case .errored(let status): return "http \(status)"
        case .unreadable: return "unreadable"
        case .unreachable: return "unreachable"
        }
    }
}
