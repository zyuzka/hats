import Foundation
import UserNotifications

struct ThresholdCrossing: Hashable {
    enum Kind: Hashable {
        case warn
        case save
    }

    let session: String
    let kind: Kind
    let round: Int
}

final class ContextThresholdNotices {
    private let notify: (UNMutableNotificationContent) -> Void
    private var told: Set<ThresholdCrossing> = []
    private var awaitingBaseline: Set<String> = []
    private var hasRead = false

    init(notify: @escaping (UNMutableNotificationContent) -> Void) {
        self.notify = notify
    }

    func noteARead(_ read: SessionStagesRead, windows: [SessionWindow]) {
        guard hasRead else {
            hasRead = true
            for stage in read.stages { told.formUnion(Self.getCrossings(of: stage)) }
            awaitingBaseline = read.listed.subtracting(read.stages.map(\.session))
            return
        }
        told = told.filter { read.listed.contains($0.session) }
        awaitingBaseline.formIntersection(read.listed)
        for stage in read.stages {
            guard awaitingBaseline.remove(stage.session) == nil else {
                told.formUnion(Self.getCrossings(of: stage))
                continue
            }
            let title = windows.first { $0.session == stage.session }?.title
            consider(stage, title: title)
        }
    }

    private func consider(_ stage: SessionStage, title: String?) {
        guard let percent = stage.percent else { return }
        let label = HatsCopy.getContextLabel(title: title, cwd: stage.cwd, session: stage.session)
        let heading = HatsCopy.getContextNoticeTitle(label: label, percent: percent)
        let warn = ThresholdCrossing(session: stage.session, kind: .warn, round: stage.warnRound)
        let save = ThresholdCrossing(session: stage.session, kind: .save, round: stage.saveRound)
        if stage.kind != .warned, isNew(save) {
            guard let savePercent = stage.savePercent else { return }
            let body = stage.afterSave == .clear
                ? HatsCopy.getClearNoticeBody(save: savePercent, drainMinutes: stage.drainMinutes)
                : HatsCopy.getAnchorNoticeBody(save: savePercent, drainMinutes: stage.drainMinutes)
            notify(Notifier.createContentShownInFront(title: heading, body: body))
            told.formUnion(Self.getCrossings(of: stage))
            return
        }
        guard stage.kind == .warned, isNew(warn), let warnPercent = stage.warnPercent else { return }
        let body = HatsCopy.getWarnNoticeBody(warn: warnPercent, save: stage.savePercent)
        notify(Notifier.createContentShownInFront(title: heading, body: body))
        told.insert(warn)
    }

    private func isNew(_ crossing: ThresholdCrossing) -> Bool {
        crossing.round > 0 && !told.contains(crossing)
    }

    private static func getCrossings(of stage: SessionStage) -> Set<ThresholdCrossing> {
        let all = [
            ThresholdCrossing(session: stage.session, kind: .warn, round: stage.warnRound),
            ThresholdCrossing(session: stage.session, kind: .save, round: stage.saveRound),
        ]

        return Set(all.filter { $0.round > 0 })
    }
}
