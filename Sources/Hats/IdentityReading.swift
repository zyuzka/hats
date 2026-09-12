import Foundation

struct IdentityDisagreement: Codable, Equatable {
    let cliSays: String
    let stateFileSays: String?
    let seenAt: Date
}

struct IdentityReading {
    let identity: CLIIdentity?
    let disagreement: IdentityDisagreement?

    static func of(cliSays: String, stateFile: CLIIdentity?, at now: Date = Date()) -> IdentityReading {
        if let stateFile, stateFile.matches(cliSays) {
            return IdentityReading(identity: stateFile, disagreement: nil)
        }

        return IdentityReading(
            identity: nil,
            disagreement: IdentityDisagreement(
                cliSays: cliSays,
                stateFileSays: stateFile?.email,
                seenAt: now
            )
        )
    }
}
