import Foundation
import NIOCore

final class CodexServiceIdleWait {
    let thread: String
    let promise: EventLoopPromise<Void>
    var hasSeenActive = false

    init(thread: String, promise: EventLoopPromise<Void>) {
        self.thread = thread
        self.promise = promise
    }
}

extension CodexServiceRPC {
    func expectIdleAfterActive(of thread: String, on channel: Channel, within: TimeAmount) -> EventLoopFuture<Void> {
        let loop = channel.eventLoop
        let promise = loop.makePromise(of: Void.self)
        loop.execute {
            guard !self.isClosed else { return promise.fail(CodexServiceError.closed) }
            self.waits.append(CodexServiceIdleWait(thread: thread, promise: promise))
            let timeout = loop.scheduleTask(in: within) {
                promise.fail(CodexServiceError.timedOut("idle status"))
            }
            promise.futureResult.whenComplete { _ in
                timeout.cancel()
                self.waits.removeAll { $0.promise.futureResult === promise.futureResult }
            }
        }

        return promise.futureResult
    }

    func noteStatus(_ params: [String: Any]) {
        guard let thread = params["threadId"] as? String,
              let type = (params["status"] as? [String: Any])?["type"] as? String
        else { return }
        for wait in waits where wait.thread == thread {
            if type != CodexThreadState.idle {
                wait.hasSeenActive = true
            } else if wait.hasSeenActive {
                wait.promise.succeed(())
            }
        }
    }
}
