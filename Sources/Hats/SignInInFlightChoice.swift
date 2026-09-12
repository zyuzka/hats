import AppKit

enum SignInInFlightChoice: Equatable {
    case showTheWindow
    case abandonIt
    case leaveItAlone

    static func of(_ response: NSApplication.ModalResponse) -> SignInInFlightChoice {
        switch response {
        case .alertFirstButtonReturn: return .showTheWindow
        case .alertSecondButtonReturn: return .abandonIt
        default: return .leaveItAlone
        }
    }
}
