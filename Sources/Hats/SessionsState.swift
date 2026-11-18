import Foundation

enum SessionsState: Equatable {
    case unknown
    case counted([Session])

    var count: Int? {
        if case .counted(let live) = self { return live.count }
        return nil
    }
}
