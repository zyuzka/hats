import Foundation

extension AppDelegate {
    func writeTheHatUsage() {
        let record = HatUsageRecord.create(from: popover.model.snapshot, watch: usage)
        switch hatUsage.setRecord(record, at: Date()) {
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
