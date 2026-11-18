import Foundation

struct CodexTicket: Equatable {
    let id: String
    let owner: CodexOwner
    let title: String
    let needsSignIn: Bool
}

struct CodexWorld {
    var home: CodexHome
    var keychain: KeychainWorld
    var send: (URLRequest) -> (status: Int, body: Data?)
    var now: () -> Date
    var run: (@escaping () -> Void) -> Void
    var onMain: (@escaping () -> Void) -> Void
    var pause: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    var waitForCodex: TimeInterval = 30

    static func real(keychain: KeychainWorld) -> CodexWorld {
        let queue = DispatchQueue(label: "hats.codex", qos: .utility)
        return CodexWorld(
            home: .real,
            keychain: keychain,
            send: { request in
                OneShotRequest.answer(to: request, within: CodexOAuth.budget, unreachable: (0, nil)) { ($0, $1) }
            },
            now: Date.init,
            run: { queue.async(execute: $0) },
            onMain: { DispatchQueue.main.async(execute: $0) }
        )
    }
}

enum CodexRenewed: Equatable {
    case renewed(String, Data)
    case needsSignIn(String, String)
    case failed(String, String)
    case notSaved(String)
}

enum CodexWorn: Equatable {
    case worn(target: String, outgoing: String?, parked: Data?)
    case alreadyWorn(String)
}
