import Foundation

final class SessionHandoffFlow {
    static let notInstalledTitle = "The plugin was not installed"
    static let notRemovedTitle = "The plugin was not removed"

    let own: String
    private let perform: (@escaping (PluginWorld) -> Void) -> Void
    private let onMain: (@escaping () -> Void) -> Void
    private let ask: (HatPrompt) -> Bool
    private let inform: (_ title: String, _ text: String) -> Void
    private let show: () -> Void
    private(set) var row = SessionHandoffRow()

    init(
        own: String,
        perform: @escaping (@escaping (PluginWorld) -> Void) -> Void,
        onMain: @escaping (@escaping () -> Void) -> Void,
        ask: @escaping (HatPrompt) -> Bool,
        inform: @escaping (_ title: String, _ text: String) -> Void,
        show: @escaping () -> Void
    ) {
        self.own = own
        self.perform = perform
        self.onMain = onMain
        self.ask = ask
        self.inform = inform
        self.show = show
    }

    func refresh(then settled: ((SessionHandoffFace) -> Void)?) {
        guard !row.isBusy else { return }
        settle(nil, isBusy: true)
        perform { [weak self] world in
            let face = SessionHandoffSteps.findFace(in: world)
            self?.onMain {
                self?.settle(face, isBusy: false)
                settled?(face)
            }
        }
    }

    func install() {
        guard !row.isBusy else { return }
        settle(nil, isBusy: true)
        perform { [weak self] world in
            let preparation = SessionHandoffSteps.getPreparation(in: world)
            self?.onMain { self?.consider(preparation) }
        }
    }

    func update() {
        guard !row.isBusy, row.offer != nil else { return }
        settle(nil, isBusy: true)
        perform { [weak self, own] world in
            let preparation = SessionHandoffUpdateSteps.getPreparation(own: own, in: world)
            self?.onMain { self?.consider(preparation) }
        }
    }

    func remove() {
        guard !row.isBusy, row.face.canRemove else { return }
        settle(nil, isBusy: true)
        perform { [weak self] world in
            let found = SessionHandoffTargets.find(in: world)
            self?.onMain { self?.confirmRemove(found) }
        }
    }

    private func confirmRemove(_ found: Result<SessionHandoffTarget, SessionHandoffRefusal>) {
        let folder: String
        switch found {
        case .failure(let refusal):
            apply(SessionHandoffChange(refusal: refusal), doneTitle: "Removed", failureTitle: Self.notRemovedTitle)
            return
        case .success(let target): folder = target.configFolder
        }
        guard ask(SessionHandoffPrompts.createRemove(folder: folder)) else {
            settle(nil, isBusy: false)
            return
        }
        Journal.log("sessionHandoff.removing")
        perform { [weak self] world in
            let change = SessionHandoffSteps.getRemoveChange(folder: folder, in: world)
            self?.onMain { self?.apply(change, doneTitle: "Removed", failureTitle: Self.notRemovedTitle) }
        }
    }

    private func consider(_ preparation: SessionHandoffPreparation) {
        switch preparation {
        case .refused(let refusal):
            let text = SessionHandoffCopy.getText(refusal)
            Journal.log("sessionHandoff.refused", [
                "reason": text,
            ])
            settle(nil, isBusy: false)
            inform(Self.notInstalledTitle, text)
        case .settled(let face):
            settle(face, isBusy: false)
            inform(face.canRemove ? "Already installed" : Self.notInstalledTitle, SessionHandoffCopy.getStatus(face))
        case .ready(let plan, let face):
            settle(face, isBusy: true)
            guard ask(SessionHandoffPrompts.createInstall(plan)) else {
                settle(nil, isBusy: false)
                return
            }
            Journal.log("sessionHandoff.installing", [
                "source": plan.source,
                "settings": plan.target.configFolder,
            ])
            perform { [weak self] world in
                let change = SessionHandoffSteps.getInstallChange(plan, in: world)
                self?.onMain { self?.apply(change, doneTitle: "Installed", failureTitle: Self.notInstalledTitle) }
            }
        }
    }

    private func consider(_ preparation: SessionHandoffUpdatePreparation) {
        switch preparation {
        case .refused(let refusal):
            settle(nil, isBusy: false)
            report(SessionHandoffUpdateCopy.notUpdatedTitle, SessionHandoffCopy.getText(refusal))
        case .settled(.unknown(let reason)):
            settle(.unknown(reason), isBusy: false)
            report(SessionHandoffUpdateCopy.notUpdatedTitle, reason)
        case .settled(let face):
            settle(face, isBusy: false)
            report(SessionHandoffUpdateCopy.notUpdatedTitle, "Nothing to update. " + SessionHandoffCopy.getStatus(face))
        case .ready(let plan, let face):
            settle(face, isBusy: true)
            guard ask(SessionHandoffPrompts.createUpdate(plan)) else {
                settle(nil, isBusy: false)
                return
            }
            Journal.log("sessionHandoff.updating", [
                "from": plan.installed,
                "own": plan.own,
                "settings": plan.target.configFolder,
            ])
            row.isUpdating = true
            show()
            perform { [weak self] world in
                let report = SessionHandoffUpdateSteps.getChange(plan, in: world)
                self?.onMain {
                    self?.row.isUpdating = false
                    self?.settle(report.face, isBusy: false)
                    self?.report(report.title, report.text)
                }
            }
        }
    }

    private func report(_ title: String, _ text: String) {
        Journal.log("sessionHandoff.updateReported", [
            "title": title,
            "text": text,
        ])
        inform(title, text)
    }

    private func apply(_ change: SessionHandoffChange, doneTitle: String, failureTitle: String) {
        settle(change.face, isBusy: false)
        if let trouble = change.refusal.map(SessionHandoffCopy.getText) ?? change.failure {
            Journal.log("sessionHandoff.notChanged", [
                "reason": trouble,
            ])
            inform(failureTitle, trouble)
            return
        }
        Journal.log("sessionHandoff.changed", [
            "state": SessionHandoffCopy.getStatus(row.face),
        ])
        guard let notice = change.notice else { return }
        inform(doneTitle, notice)
    }

    private func settle(_ face: SessionHandoffFace?, isBusy: Bool) {
        if let face {
            row.face = face
            row.offer = face.findOffer(own: own)
        }
        row.isBusy = isBusy
        show()
    }
}
