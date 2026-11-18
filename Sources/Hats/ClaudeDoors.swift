import Foundation

enum ClaudeDoors {
    static func hatsForUsage(_ accounts: [Account], live: String?) -> [(id: String, isWearing: Bool)] {
        accounts.filter(\.isClaude).map { hat in
            (hat.id, isWorn(hat, live: live))
        }
    }

    static func claudeRows(
        _ accounts: [Account],
        live: String?,
        row: (Account, Bool) -> HatRowState
    ) -> [HatRowState] {
        accounts.filter(\.isClaude).map { row($0, isWorn($0, live: live)) }
    }

    static func isWorn(_ hat: Account, live: String?) -> Bool {
        live.map { Account.sameAddress(hat.email, $0) } ?? false
    }

    enum Route: Equatable {
        case claude
        case codex
    }

    static func route(ofAClickOn id: String, among accounts: [Account]) -> Route {
        accounts.contains { $0.id == id && $0.wornTool == .codex } ? .codex : .claude
    }

    static func codexRows(
        _ accounts: [Account],
        worn: String?,
        chromeNames: [String: String] = [:],
        now: Date = Date()
    ) -> [HatRowState] {
        accounts.filter { $0.wornTool == .codex }.map { hat in
            HatRowState(
                hat: hat,
                isWearing: hat.id == worn,
                usage: nil,
                usageTrouble: nil,
                chromeNames: chromeNames,
                now: now
            )
        }
    }
}
