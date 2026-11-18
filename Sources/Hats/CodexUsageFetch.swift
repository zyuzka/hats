import Foundation

enum CodexUsageOutcome: Equatable {
    case reading(CodexUsageReading)
    case failed(CodexUsageTrouble)
}

enum CodexUsageFetch {
    static let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage") ?? URL(fileURLWithPath: "/")
    static let userAgent = "codex_cli_rs"
    static let budget: TimeInterval = 10
    static let families = ["primary_window", "secondary_window"]

    static func request(token: String, accountID: String, endpoint: URL = endpoint) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = budget
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue(accountID, forHTTPHeaderField: "chatgpt-account-id")
        request.setValue(CodexOAuth.originator, forHTTPHeaderField: "originator")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    static func outcome(status: Int, body: Data?) -> CodexUsageOutcome {
        switch status {
        case 0: return .failed(.unreachable)
        case 200: break
        case 401: return .failed(.loginRefused)
        case 429: return .failed(.busy)
        case 500...599: return .failed(.serverError(status))
        default: return .failed(.refused(status))
        }
        guard let body, let payload = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else {
            return .failed(.unreadable)
        }

        return .reading(reading(in: payload))
    }

    static func reading(in payload: [String: Any]) -> CodexUsageReading {
        let limits = payload["rate_limit"] as? [String: Any] ?? [:]

        let windows = families.compactMap { window(limits[$0]) }

        return CodexUsageReading(windows: windows, plan: payload["plan_type"] as? String)
    }

    static func window(_ value: Any?) -> CodexUsageWindow? {
        guard let window = value as? [String: Any],
              let seconds = whole(window["limit_window_seconds"]), seconds >= 60,
              let used = whole(window["used_percent"])
        else { return nil }
        let reset = whole(window["reset_at"]).map { Date(timeIntervalSince1970: TimeInterval($0)) }

        return CodexUsageWindow(minutes: seconds / 60, percent: min(max(used, 0), 100), resetsAt: reset)
    }

    static func whole(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        guard let double = value as? Double, double.isFinite else { return nil }
        return Int(exactly: double.rounded())
    }
}

extension CodexUsageReading {
    static let fiveHours = 300
    static let week = 10080

    var shown: UsageReading? {
        let reading = UsageReading(
            session: window(minutes: Self.fiveHours).map(Self.usageWindow),
            weekly: window(minutes: Self.week).map(Self.usageWindow)
        )
        return reading.hasAnyWindow ? reading : nil
    }

    var unknownWindows: [CodexUsageWindow] {
        windows.filter { $0.minutes != Self.fiveHours && $0.minutes != Self.week }
    }

    private static func usageWindow(_ window: CodexUsageWindow) -> UsageWindow {
        UsageWindow(used: window.percent, limit: 100, resetsAt: window.resetsAt)
    }
}
