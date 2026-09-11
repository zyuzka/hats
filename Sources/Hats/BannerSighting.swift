import Foundation

enum BannerSighting: Equatable {
    case notYet
    case seen

    static func of(popoverShown: Bool, popoverClosing: Bool, hasBanner: Bool) -> BannerSighting {
        guard hasBanner, popoverShown, !popoverClosing else { return .notYet }
        return .seen
    }
}
