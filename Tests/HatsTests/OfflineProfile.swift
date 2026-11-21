@testable import Hats

enum OfflineProfile {
    static let fetch: (String) -> ProfileFetch = { _ in .unreachable }
}
