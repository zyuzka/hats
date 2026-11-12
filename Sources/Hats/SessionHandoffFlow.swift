import Foundation

final class SessionHandoffFlow {
    static let notInstalledTitle = "The plugin was not installed"
    static let notRemovedTitle = "The plugin was not removed"

    private let perform: (@escaping (PluginWorld) -> Void) -> Void
    private let onMain: (@escaping () -> Void) -> Void
    private let ask: (HatPrompt) -> Bool
    private let inform: (_ title: String, _ text: String) -> Void
    private let show: () -> Void
    private(set) var row = SessionHandoffRow()

    init(
        perform: @escaping (@escaping (PluginWorld) -> Void) -> Void,
        onMain: @escaping (@escaping () -> Void) -> Void,
        ask: @escaping (HatPrompt) -> Bool,
        inform: @escaping (_ title: String, _ text: String) -> Void,
        show: @escaping () -> Void
    ) {
        self.perform = perform
        self.onMain = onMain
        self.ask = ask
        self.inform = inform
        self.show = show
    }

    func refresh() {
        guard !row.isBusy else { return }
        settle(nil, isBusy: true)
        perform { [weak self] world in
            let face = SessionHandoffSteps.findFace(in: world)
            self?.onMain { self?.settle(face, isBusy: false) }
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

    func remove() {
        guard !row.isBusy, row.face.canRemove else { return }
        settle(nil, isBusy: true)
        onMain { [weak self] in
            guard let self else { return }
            guard self.ask(SessionHandoffPrompts.createRemove()) else {
                self.settle(nil, isBusy: false)
                return
            }
            Journal.log("sessionHandoff.removing")
            self.perform { [weak self] world in
                let change = SessionHandoffSteps.getRemoveChange(in: world)
                self?.onMain { self?.apply(change, doneTitle: "Removed", failureTitle: Self.notRemovedTitle) }
            }
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
        if let face { row.face = face }
        row.isBusy = isBusy
        show()
    }
}
