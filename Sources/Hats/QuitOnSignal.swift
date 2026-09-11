import AppKit

enum QuitOnSignal {
    static let signals: [Int32] = [SIGTERM, SIGINT]

    private static var sources: [DispatchSourceSignal] = []

    static func install() {
        sources = signals.map { number in
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            return source
        }
    }
}
