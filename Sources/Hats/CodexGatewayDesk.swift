import Foundation

final class CodexGatewayDesk: CodexGatewayBroker {
    let desk: CodexDesk
    let state: CodexGatewayState
    var onWorn: ((String, CodexWorn, [CodexRenewed]) -> Void)?
    var onLogin: ((String, Data) -> Void)?
    var onNeedsSignIn: ((String, String) -> Void)?
    var onAllAtLimit: (() -> Void)?

    static let allAtLimitQuiet: TimeInterval = 600

    private var lastToldAllAtLimit: Date?
    private let hatsLock = NSLock()
    private var storedHats = CodexGatewayHats()

    init(desk: CodexDesk, state: CodexGatewayState) {
        self.desk = desk
        self.state = state
        desk.onLiveWritten = { [weak state] id, data in state?.wear(hatID: id, auth: data) }
    }

    var hats: CodexGatewayHats {
        get {
            hatsLock.lock()
            defer { hatsLock.unlock() }
            return storedHats
        }
        set {
            hatsLock.lock()
            defer { hatsLock.unlock() }
            storedHats = newValue
        }
    }

    private var world: CodexWorld { desk.world }

    func unauthorized(_ refused: CodexGatewayLogin, then: @escaping (CodexGatewayRecovery) -> Void) {
        world.run { [self] in
            if let current = state.login, current.hatID != refused.hatID { return then(.retry(current)) }
            guard let hat = hats.all.first(where: { $0.id == refused.hatID }) else { return then(.needsSignIn) }
            switch desk.renewWornNow(hat, refused: refused.accessToken) {
            case .fresh(let data), .notDue(let data):
                let login = state.wear(hatID: hat.id, auth: data)
                world.onMain { self.onLogin?(hat.id, data) }
                then(login.map(CodexGatewayRecovery.retry) ?? .unreachable)
            case .needsSignIn(let why):
                world.onMain { self.onNeedsSignIn?(hat.id, why) }
                then(.needsSignIn)
            case .elsewhere, .failed:
                then(.unreachable)
            }
        }
    }

    func usageLimit(_ refused: CodexGatewayLogin, tried: Set<String>, then: @escaping (CodexGatewayLogin?) -> Void) {
        world.run { [self] in
            guard let current = state.login else { return then(nil) }
            let hats = self.hats
            guard current.shift == refused.shift else {
                guard tried.contains(current.hatID) else { return then(current) }
                tellAllAtLimit(hats, tried: tried)
                return then(nil)
            }
            let expected = hats.all.first { $0.id == refused.hatID }?.owner
            for hat in hats.next(after: refused.hatID, skipping: tried) {
                do {
                    let worn = try desk.wearNow(hat, among: hats.all, over: expected)
                    Journal.log("codexGateway.autoWorn", [
                        "from": String(refused.hatID.prefix(8)),
                        "to": String(hat.id.prefix(8)),
                    ])
                    var renewed: [CodexRenewed] = []
                    if case .worn(_, let outgoing?, _) = worn,
                       let parked = hats.all.first(where: { $0.id == outgoing }) {
                        renewed = desk.renewOne(parked, forced: true).map { [$0] } ?? []
                    }
                    world.onMain { self.onWorn?(hat.id, worn, renewed) }
                    return then(state.login)
                } catch CodexError.liveMoved {
                    Journal.log("codexGateway.liveMovedAtLimit", ["from": String(refused.hatID.prefix(8))])
                    readTheLiveFile()
                    guard let now = state.login, !tried.contains(now.hatID) else { return then(nil) }
                    return then(now)
                } catch {
                    Journal.log("codexGateway.autoWearRefused", [
                        "to": String(hat.id.prefix(8)),
                        "reason": error.localizedDescription,
                    ])
                }
            }
            tellAllAtLimit(hats, tried: tried.union([refused.hatID]))
            then(nil)
        }
    }

    private func tellAllAtLimit(_ hats: CodexGatewayHats, tried: Set<String>) {
        guard hats.hasEveryoneRefused(tried) else { return }
        let now = world.now()
        Journal.log("codexGateway.allAtLimit", ["tried": String(tried.count)])
        if let told = lastToldAllAtLimit, now.timeIntervalSince(told) < Self.allAtLimitQuiet { return }
        lastToldAllAtLimit = now
        world.onMain { self.onAllAtLimit?() }
    }

    func refusedAgain(_ login: CodexGatewayLogin) {
        world.onMain { self.onNeedsSignIn?(login.hatID, "the upstream refused the renewed login") }
    }

    func renewTheWorn(_ hat: CodexTicket) {
        world.run { [self] in
            switch desk.renewWornNow(hat) {
            case .fresh(let data):
                state.wear(hatID: hat.id, auth: data)
                world.onMain { self.onLogin?(hat.id, data) }
            case .needsSignIn(let why):
                world.onMain { self.onNeedsSignIn?(hat.id, why) }
            case .notDue, .elsewhere, .failed:
                break
            }
        }
    }

    func noticeTheLiveFile() {
        world.run { [self] in readTheLiveFile() }
    }

    private func readTheLiveFile() {
        guard let live = try? world.home.readLiveChecked(), let owner = CodexAuth(data: live)?.owner,
              let hat = hats.all.first(where: { $0.owner == owner }) else {
            if state.login != nil { Journal.log("codexGateway.nothingWorn") }
            state.takeOff()
            return
        }
        let before = state.login
        guard let login = state.wear(hatID: hat.id, auth: live) else {
            Journal.log("codexGateway.loginUnusable", ["hat": String(hat.id.prefix(8))])
            state.takeOff()
            return
        }
        guard login != before else { return }
        Journal.log("codexGateway.loginRead", ["hat": String(hat.id.prefix(8)), "shift": String(login.shift)])
    }
}
