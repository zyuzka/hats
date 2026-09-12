import Foundation

enum SignInStage: Equatable {
    case starting
    case waitingForTheCode
    case working
}

struct SignInTranscript: Equatable {
    private(set) var text = ""
    private(set) var awaitsTheCode = false

    static let prompt = "Paste code here"
    static let refusal = "Invalid code."
    static let offer = "If the browser didn't open, visit: "

    mutating func read(_ chunk: String) {
        text += chunk
        guard chunk.contains(Self.prompt) || chunk.contains(Self.refusal) else { return }
        awaitsTheCode = true
    }

    mutating func sent(_ code: String) {
        text += code + "\n"
        awaitsTheCode = false
    }

    var stage: SignInStage {
        guard !text.isEmpty else { return .starting }
        return awaitsTheCode ? .waitingForTheCode : .working
    }

    var signInURL: URL? {
        guard let after = text.components(separatedBy: Self.offer).dropFirst().first else { return nil }
        return URL(string: String(after.prefix { !$0.isWhitespace }))
    }
}
