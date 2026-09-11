import Foundation

enum OneShotRequest {
    private static let redirects = OneShotRedirects()
    private static let session = URLSession(configuration: .ephemeral,
                                            delegate: redirects,
                                            delegateQueue: nil)

    static func answer<Outcome>(
        to request: URLRequest,
        within budget: TimeInterval,
        unreachable: Outcome,
        reading: @escaping (Int, Data?) -> Outcome
    ) -> Outcome {
        let lock = NSLock()
        var result = unreachable
        let done = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: request) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let answer = reading(status, data)
            lock.lock()
            result = answer
            lock.unlock()
            done.signal()
        }
        task.resume()
        if done.wait(timeout: .now() + budget + 0.5) == .timedOut { task.cancel() }
        lock.lock()
        defer { lock.unlock() }
        return result
    }
}
