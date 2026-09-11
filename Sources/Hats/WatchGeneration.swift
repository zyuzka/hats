import Foundation

struct WatchGeneration: Equatable {
    private var started = 0
    private var onDuty = 0
    private var polling = 0

    var dutyHolder: Int { onDuty }
    var pollHolder: Int { polling }

    mutating func take() -> Int {
        started += 1
        onDuty = started
        polling = started
        return started
    }

    func isOnDuty(_ generation: Int) -> Bool { onDuty == generation }

    func isTheCurrent(_ generation: Int) -> Bool { started == generation }

    mutating func standDown(_ generation: Int) {
        guard onDuty == generation else { return }
        onDuty = 0
    }

    mutating func stopPolling(_ generation: Int) {
        guard polling == generation else { return }
        polling = 0
    }
}
