import Foundation

extension AppDelegate {
    func writeTheHatUsage() {
        switch hatUsage.setRecord(
            from: popover.model.snapshot,
            watch: usage,
            channel: contextChannel,
            at: Date()
        ) {
        case .failed(let reason):
            guard lastHatUsageFailure.shouldWrite(reason) else { return }
            Journal.log("hatUsage.notSaved", [
                "reason": reason,
            ])
        case .written, .unchanged:
            lastHatUsageFailure.clear()
        }
    }
}
