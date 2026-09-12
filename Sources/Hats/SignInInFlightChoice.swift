import Foundation

enum SignInInFlightChoice: Equatable {
    case showTheWindow
    case abandonIt
    case leaveItAlone

    static func of(_ chosen: Int) -> SignInInFlightChoice {
        switch chosen {
        case 0: return .showTheWindow
        case 1: return .abandonIt
        default: return .leaveItAlone
        }
    }
}
