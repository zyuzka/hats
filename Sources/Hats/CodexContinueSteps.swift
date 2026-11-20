import Foundation
import NIOCore

struct CodexThreadState: Equatable {
    let status: String
    let isEphemeral: Bool
    let hasPath: Bool
    let isRoot: Bool

    static let idle = "idle"

    static func of(_ result: [String: Any]) -> CodexThreadState? {
        guard let thread = result["thread"] as? [String: Any],
              let status = (thread["status"] as? [String: Any])?["type"] as? String
        else { return nil }
        let path = thread["path"] as? String

        return CodexThreadState(
            status: status,
            isEphemeral: thread["ephemeral"] as? Bool ?? true,
            hasPath: !(path ?? "").isEmpty,
            isRoot: thread["parentThreadId"] as? String == nil
        )
    }

    var refusal: String? {
        if status == "notLoaded" { return "notLoaded" }
        if isEphemeral { return "ephemeral" }
        if !hasPath { return "noPath" }
        if !isRoot { return "notRoot" }

        return status == Self.idle ? nil : status
    }
}

protocol CodexServiceLink: AnyObject {
    func read(_ thread: String) throws -> CodexThreadState
    func compact(_ thread: String, within: TimeInterval) throws -> CodexCompaction
    func startTurn(_ thread: String, text: String) throws
    func close()
}

enum CodexCompaction: Equatable {
    case idle
    case timedOut
    case lost(CodexServiceError)
}

enum CodexContinueOutcome: Equatable {
    case done
    case skipped(String, detail: String? = nil)
    case failed(String, detail: String)
}

enum CodexContinueSteps {
    static let text = "Hats: this thread was compacted at the save threshold. Continue the task from your resume note. "
        + "If the note says the task is done, say so in one line and stop."
    static let compactWait: TimeInterval = 60

    static func run(_ thread: String, on link: CodexServiceLink) -> (outcome: CodexContinueOutcome, compacted: Bool) {
        if let stop = check(thread, on: link) { return (stop, false) }
        if let stop = check(thread, on: link) { return (stop, false) }
        do {
            switch try link.compact(thread, within: compactWait) {
            case .idle:
                break
            case .timedOut:
                return (.failed("compactTimeout", detail: "no idle within \(Int(compactWait)) s"), true)
            case .lost(let error):
                return (failure("compactLost", error), true)
            }
        } catch {
            return (failure("compactRefused", error), false)
        }
        if let stop = check(thread, on: link) { return (stop, true) }
        do {
            try link.startTurn(thread, text: text)
        } catch {
            return (failure("turnRefused", error), true)
        }

        return (.done, true)
    }

    private static func check(_ thread: String, on link: CodexServiceLink) -> CodexContinueOutcome? {
        do {
            return try link.read(thread).refusal.map { .skipped($0) }
        } catch let error as CodexServiceError where error.reason == "refused" {
            return .skipped("notLoaded", detail: error.detail)
        } catch {
            return failure("readFailed", error)
        }
    }

    private static func failure(_ reason: String, _ error: Error) -> CodexContinueOutcome {
        let detail = (error as? CodexServiceError).map { "\($0.reason): \($0.detail)" } ?? String(describing: error)

        return .failed(reason, detail: detail)
    }
}

final class CodexServiceSession: CodexServiceLink {
    static let callWait: TimeAmount = .seconds(10)

    private let client: CodexServiceClient

    init(client: CodexServiceClient) {
        self.client = client
    }

    func read(_ thread: String) throws -> CodexThreadState {
        let result = try client.call("thread/read", ["threadId": thread], within: Self.callWait)
        guard let state = CodexThreadState.of(result) else { throw CodexServiceError.badAnswer("thread/read") }

        return state
    }

    func compact(_ thread: String, within: TimeInterval) throws -> CodexCompaction {
        let idle = client.expectIdleAfterActive(of: thread, within: .seconds(Int64(within)))
        _ = try client.call("thread/compact/start", ["threadId": thread], within: Self.callWait)
        do {
            try idle.wait()
        } catch CodexServiceError.timedOut {
            return .timedOut
        } catch {
            return .lost(error as? CodexServiceError ?? .badAnswer(String(describing: error)))
        }

        return .idle
    }

    func startTurn(_ thread: String, text: String) throws {
        let input: [[String: Any]] = [["type": "text", "text": text]]
        _ = try client.call("turn/start", ["threadId": thread, "input": input], within: Self.callWait)
    }

    func close() {
        client.close()
    }
}
