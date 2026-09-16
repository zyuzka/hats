import Foundation
@testable import Hats

final class FakeSystem {
    var home: String
    var variables: [String: String] = [:]
    var status: CLI.Status?
    var table: ([String]) -> String? = { _ in "" }
    var environmentOf: (Int32) -> ProcessEnvironmentRead = { _ in .processGone }
    var trusts: (Int32) -> Bool? = { _ in false }

    var processTables: [[String]] = []
    var budgets: [TimeInterval] = []
    var environmentsRead: [Int32] = []
    var keysWanted: [Set<String>?] = []
    var trustAsked: [Int32] = []
    var statusAsked = 0
    var homeAsked = 0

    init(home: String) { self.home = home }

    func world() -> SystemWorld {
        SystemWorld(
            processTable: { [self] arguments, budget in
                self.processTables.append(arguments)
                self.budgets.append(budget)

                return self.table(arguments)
            },
            processEnvironment: { [self] pid, wanted in
                self.environmentsRead.append(pid)
                self.keysWanted.append(wanted)

                return self.environmentOf(pid)
            },
            isTheRealCLI: { [self] pid in
                self.trustAsked.append(pid)

                return self.trusts(pid)
            },
            cliStatus: { [self] in
                self.statusAsked += 1

                return self.status
            },
            ownEnvironment: { [self] in self.variables },
            home: { [self] in
                self.homeAsked += 1

                return self.home
            }
        )
    }
}

func loggedIn(as email: String) -> CLI.Status {
    CLI.Status(loggedIn: true, email: email, orgName: nil, subscriptionType: nil, authMethod: nil)
}
