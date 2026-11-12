import Foundation

struct SessionHandoffPlan: Equatable {
    let target: SessionHandoffTarget
    let source: String
    let folder: String?
    let python: SessionHandoffPythonFound

    var arguments: [String] {
        [
            "plugin",
            "install",
            SessionHandoffProvenance.pluginName,
            "--marketplace",
            source,
            "--scope",
            SessionHandoffProvenance.userScope,
            "--json",
        ]
    }
}

enum SessionHandoffPreparation: Equatable {
    case ready(SessionHandoffPlan, SessionHandoffFace)
    case refused(SessionHandoffRefusal)
    case settled(SessionHandoffFace)
}

struct SessionHandoffChange: Equatable {
    let refusal: SessionHandoffRefusal?
    let failure: String?
    let notice: String?
    let face: SessionHandoffFace?

    init(
        refusal: SessionHandoffRefusal? = nil,
        failure: String? = nil,
        notice: String? = nil,
        face: SessionHandoffFace? = nil
    ) {
        self.refusal = refusal
        self.failure = failure
        self.notice = notice
        self.face = face
    }

    static func createJudged(
        _ answer: PluginChangeAnswer,
        command: String,
        after: SessionHandoffFace,
        isReached: Bool
    ) -> SessionHandoffChange {
        guard isReached else {
            let failure = answer.isDone ? SessionHandoffCopy.getNotReached(command, after: after) : answer.message
            return SessionHandoffChange(failure: failure, face: after)
        }
        let notice = answer.isDone
            ? nil
            : SessionHandoffCopy.getReachedAnyway(command, answer: answer.message, after: after)

        return SessionHandoffChange(notice: notice, face: after)
    }
}

struct SessionHandoffReading: Equatable {
    let face: SessionHandoffFace
    let source: SessionHandoffSource?
}
