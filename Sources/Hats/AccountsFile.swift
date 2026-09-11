import Foundation

struct AccountsFile {
    let osAccount: String

    var url: URL { StateDirectory.url.appendingPathComponent("accounts.json") }

    struct Contents: Codable {
        var accounts: [Account]
        var activeID: String?
    }

    enum Loaded {
        case contents(Contents)
        case nothingYet
        case unusable(SwitchError)
    }

    func load() -> Loaded {
        let path = url.path
        let exists = FileManager.default.fileExists(atPath: path)
        if !exists {
            let parked: [String]
            do {
                parked = try Keychain.parkedAccountIDs(account: osAccount)
            } catch {
                return .unusable(.keychainUnlistable(path, cause: error.localizedDescription))
            }

            return parked.isEmpty ? .nothingYet : .unusable(.indexLost(path))
        }
        guard let data = try? Data(contentsOf: url) else { return .unusable(.indexUnreadable(path)) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let contents = try? decoder.decode(Contents.self, from: data) else {
            return .unusable(.indexUnreadable(path))
        }

        return .contents(contents)
    }

    func save(_ contents: Contents) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(contents).write(to: url, options: .atomic)
    }
}
