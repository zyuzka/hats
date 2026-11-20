import Foundation

extension AutoSwitchWorld {
    static func of(snapshot: HatsSnapshot, watch: AutoSwitchWatch, from call: AutoSwitchCall) -> AutoSwitchWorld {
        of(
            snapshot: snapshot,
            readings: watch.readings,
            missed: watch.missed,
            fresh: watch.freshInTheLastPoll,
            weeklyEverRead: watch.weeklyEverRead,
            from: call
        )
    }
}
