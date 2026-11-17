import Foundation
import UserNotifications

final class ContextThresholdsChannel {
    private var file: WindowThresholdsFile
    private var lastFileFailure = NoteOnChange()
    private let stages: SessionThresholds
    private let notices: ContextThresholdNotices
    private let limitNotices: LimitThresholdNotices
    private let log: SessionThresholdsScan.Log

    init(
        root: URL = StateDirectory.url,
        launchedAt: Date,
        notify: @escaping (UNMutableNotificationContent) -> Void = Notifier.deliver,
        pollEvery: TimeInterval = SessionThresholds.pollSpell,
        log: @escaping SessionThresholdsScan.Log = Journal.log
    ) {
        file = WindowThresholdsFile(root: root)
        stages = SessionThresholds(folder: file.stageFolder, pollEvery: pollEvery, log: log)
        notices = ContextThresholdNotices(notify: notify)
        limitNotices = LimitThresholdNotices(
            root: root,
            launchedAt: launchedAt,
            notify: notify,
            log: log,
            now: Date.init
        )
        self.log = log
    }

    func setThresholds(_ thresholds: ContextThresholds, limits: LimitThresholds, at now: Date) {
        switch file.setThresholds(thresholds, limits: limits, at: now) {
        case .failed(let reason):
            guard lastFileFailure.shouldWrite(reason) else { return }
            log("windowThresholds.notSaved", [
                "reason": reason,
            ])
        case .written, .unchanged:
            lastFileFailure.clear()
        }
    }

    var hatTitle: (String) -> String {
        get { limitNotices.hatTitle }
        set { limitNotices.hatTitle = newValue }
    }

    func start(windows: @escaping () -> [SessionWindow]) {
        stages.onRead = { [notices, limitNotices] found in
            notices.noteARead(found, windows: windows())
            limitNotices.noteARead(found)
        }
        stages.start()
    }

    func stop() {
        stages.stop()
    }
}
