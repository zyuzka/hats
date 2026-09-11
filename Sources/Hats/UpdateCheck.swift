import Foundation

struct ReleaseOnGitHub: Equatable {
    let version: String
    let page: URL
    let asset: URL?
}

enum UpdateVerdict: Equatable {
    case upToDate(running: String)
    case available(ReleaseOnGitHub)
    case unreadable
    case unreachable
    case notConfigured
}

enum UpdateCheck {
    static let repositoryKey = "HatsUpdateRepository"

    static let budget: TimeInterval = 6

    static func repository(in info: [String: Any]? = Bundle.main.infoDictionary) -> String? {
        guard let raw = info?[repositoryKey] as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("/"), !trimmed.hasPrefix("/"), !trimmed.hasSuffix("/") else { return nil }

        return trimmed
    }

    static func endpoint(for repository: String) -> URL {
        URL(string: "https://api.github.com/repos/\(repository)/releases/latest")
            ?? URL(fileURLWithPath: "/")
    }

    static func request(endpoint: URL) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = budget
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return request
    }

    static func release(from body: Data?) -> ReleaseOnGitHub? {
        guard let body,
              let payload = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              payload["draft"] as? Bool != true,
              payload["prerelease"] as? Bool != true,
              let tag = payload["tag_name"] as? String,
              let page = (payload["html_url"] as? String).flatMap(URL.init(string:))
        else { return nil }

        return ReleaseOnGitHub(version: normalised(tag), page: page, asset: diskImage(in: payload))
    }

    static func verdict(status: Int, body: Data?, running: String) -> UpdateVerdict {
        guard status != 0 else { return .unreachable }
        guard status == 200, let release = release(from: body) else { return .unreadable }
        guard isNewer(release.version, than: running) else { return .upToDate(running: running) }

        return .available(release)
    }

    static func normalised(_ tag: String) -> String {
        var trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") { trimmed.removeFirst() }

        return trimmed
    }

    static func isNewer(_ candidate: String, than running: String) -> Bool {
        parts(running).lexicographicallyPrecedes(parts(candidate))
    }

    private static func parts(_ version: String) -> [Int] {
        let numbers = normalised(version).split(separator: ".").map { Int($0) ?? 0 }

        return numbers + Array(repeating: 0, count: max(0, 3 - numbers.count))
    }

    private static func diskImage(in payload: [String: Any]) -> URL? {
        guard let assets = payload["assets"] as? [[String: Any]] else { return nil }
        for asset in assets {
            guard let name = asset["name"] as? String, name.hasSuffix(".dmg"),
                  let link = (asset["browser_download_url"] as? String).flatMap(URL.init(string:))
            else { continue }
            return link
        }

        return nil
    }
}
