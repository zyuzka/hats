import Foundation
import UserNotifications

final class ContextThresholdsChannel {
    private var file: WindowThresholdsFile
    private var lastFileFailure = NoteOnChange()
    private let stages: SessionThresholds
    private let notices: ContextThresholdNotices
    private let log: SessionThresholdsScan.Log

    init(
        root: URL = StateDirectory.url,
        notify: @escaping (UNMutableNotificationContent) -> Void = Notifier.deliver,
        pollEvery: TimeInterval = SessionThresholds.pollSpell,
        log: @escaping SessionThresholdsScan.Log = Journal.log
    ) {
        file = WindowThresholdsFile(root: root)
        stages = SessionThresholds(folder: file.stageFolder, pollEvery: pollEvery, log: log)
        notices = ContextThresholdNotices(notify: notify)
        self.log = log
    }

    func setThresholds(_ thresholds: ContextThresholds, at now: Date) {
        switch file.setThresholds(thresholds, at: now) {
        case .failed(let reason):
            guard lastFileFailure.shouldWrite(reason) else { return }
            log("windowThresholds.notSaved", [
                "reason": reason,
            ])
        case .written, .unchanged:
            lastFileFailure.clear()
        }
    }

    func start(windows: @escaping () -> [SessionWindow]) {
        stages.onRead = { [notices] found in notices.noteARead(found, windows: windows()) }
        stages.start()
    }

    func stop() {
        stages.stop()
    }
}
