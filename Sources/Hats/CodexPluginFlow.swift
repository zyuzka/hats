import Foundation

final class CodexPluginFlow {
    let own: String
    private let perform: (@escaping (PluginWorld) -> Void) -> Void
    private let onMain: (@escaping () -> Void) -> Void
    private let ask: (HatPrompt) -> Bool
    private let inform: (_ title: String, _ text: String) -> Void
    private let show: () -> Void
    private let journal: (_ operation: String, _ details: [String: String]) -> Void
    private(set) var row = CodexPluginRow()

    init(
        own: String,
        perform: @escaping (@escaping (PluginWorld) -> Void) -> Void,
        onMain: @escaping (@escaping () -> Void) -> Void,
        ask: @escaping (HatPrompt) -> Bool,
        inform: @escaping (_ title: String, _ text: String) -> Void,
        show: @escaping () -> Void,
        journal: @escaping (_ operation: String, _ details: [String: String]) -> Void = Journal.log
    ) {
        self.own = own
        self.perform = perform
        self.onMain = onMain
        self.ask = ask
        self.inform = inform
        self.show = show
        self.journal = journal
    }

    static func real(_ own: String, show: @escaping () -> Void) -> CodexPluginFlow {
        let work = SessionHandoffWork(world: .real)

        return CodexPluginFlow(
            own: own,
            perform: { job in work.perform(job) },
            onMain: { DispatchQueue.main.async(execute: $0) },
            ask: { PromptWindow.ask($0) == 0 },
            inform: { HatDialogs.inform($0, $1) },
            show: show
        )
    }

    func refresh(then settled: ((CodexPluginFace) -> Void)?) {
        guard !row.isBusy else { return }
        settle(nil, isBusy: true)
        perform { [weak self] world in
            let face = CodexPluginSteps.findFace(in: world)
            self?.onMain {
                self?.noteTrouble(face)
                self?.settle(face, isBusy: false)
                settled?(face)
            }
        }
    }

    func install() {
        start(.install, isAllowed: row.face.canInstall)
    }

    func update() {
        start(.update, isAllowed: row.offer != nil)
    }

    func refreshCopy() {
        start(.refresh, isAllowed: row.face.canRefresh)
    }

    func remove() {
        start(.remove, isAllowed: row.face.canRemove)
    }

    private func start(_ action: CodexPluginAction, isAllowed: Bool) {
        guard !row.isBusy, isAllowed else { return }
        settle(nil, isBusy: true)
        perform { [weak self, own] world in
            let preparation = CodexPluginSteps.getPreparation(action, own: own, in: world)
            self?.onMain { self?.consider(preparation, action: action) }
        }
    }

    private func consider(_ preparation: CodexPluginPreparation, action: CodexPluginAction) {
        switch preparation {
        case .refused(let reason, let face):
            journal("codexPlugin.refused", [
                "action": action.rawValue,
                "reason": reason,
            ])
            settle(face, isBusy: false)
            inform(CodexPluginText.getFailureTitle(action), reason)
        case .settled(let face):
            settle(face, isBusy: false)
            inform(CodexPluginText.nothingToDoTitle, "Nothing to do. " + CodexPluginText.getStatus(face))
        case .ready(let plan, let face):
            settle(face, isBusy: true)
            guard ask(CodexPluginPrompts.create(plan, own: own)) else {
                settle(nil, isBusy: false)
                return
            }
            run(plan)
        }
    }

    private func run(_ plan: CodexPluginPlan) {
        journal("codexPlugin." + CodexPluginText.getJournalVerb(plan.action), [
            "codex": plan.target.cli,
            "codexHome": plan.target.codexHome,
            "commands": plan.commands.map { $0.joined(separator: " ") }.joined(separator: "; "),
        ])
        perform { [weak self, own] world in
            let report = CodexPluginSteps.getChange(plan, own: own, in: world)
            self?.onMain { self?.apply(report) }
        }
    }

    private func apply(_ report: CodexPluginReport) {
        settle(report.face, isBusy: false)
        if report.isChanged {
            journal("codexPlugin.changed", [
                "state": CodexPluginText.getStatus(row.face),
            ])
        } else {
            journal("codexPlugin.notChanged", [
                "reason": report.text,
            ])
        }
        inform(report.title, report.text)
    }

    private func noteTrouble(_ face: CodexPluginFace) {
        guard face != row.face, !(row.face == .unread && face == .noCodex) else { return }
        switch face {
        case .noCodex, .unknown:
            journal("codexPlugin.refused", [
                "reason": CodexPluginText.getStatus(face),
            ])
        case .unread, .notInstalled, .installed, .fromFolder, .notOurs:
            break
        }
    }

    private func settle(_ face: CodexPluginFace?, isBusy: Bool) {
        if let face {
            row.face = face
            row.offer = face.findOffer(own: own)
        }
        row.isBusy = isBusy
        show()
    }
}
