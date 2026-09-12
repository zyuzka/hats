import Foundation

final class SignInRun {
    enum Ending: Equatable {
        case signedIn
        case failed(Int32)
        case cancelled
    }

    static var logURL: URL { StateDirectory.url.appendingPathComponent("last-sign-in.log") }

    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var wasCancelled = false
    private var hasEnded = false

    private(set) var transcript = SignInTranscript()
    private(set) var ending: Ending?
    private(set) var hasStarted = false

    var isInFlight: Bool { hasStarted && ending == nil }
    var hasSignedIn: Bool { ending == .signedIn }

    var changed: (SignInTranscript) -> Void = { _ in Journal.log("signIn.outputIgnored") }
    var ended: (Ending) -> Void = { _ in Journal.log("signIn.endingIgnored") }

    var isRunning: Bool { process.isRunning }

    func start(_ command: SignInCommand) throws {
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        process.environment = command.environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.read(chunk) }
        }
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            DispatchQueue.main.async { self?.finish(status: status) }
        }

        try process.run()
        hasStarted = true
    }

    func send(_ code: String) {
        guard process.isRunning, let data = (code + "\n").data(using: .utf8) else { return }
        try? input.fileHandleForWriting.write(contentsOf: data)
        transcript.sent(code)
        changed(transcript)
    }

    func cancel() {
        wasCancelled = true
        guard process.isRunning else { return finish(status: process.terminationStatus) }
        process.terminate()
    }

    private func read(_ chunk: String) {
        transcript.read(chunk)
        changed(transcript)
    }

    private func finish(status: Int32) {
        guard !hasEnded else { return }
        hasEnded = true
        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        try? output.fileHandleForWriting.close()
        if let rest = try? output.fileHandleForReading.readToEnd(),
           let chunk = String(data: rest, encoding: .utf8), !chunk.isEmpty {
            transcript.read(chunk)
            changed(transcript)
        }
        try? transcript.text.write(to: Self.logURL, atomically: true, encoding: .utf8)
        let ending = endingOf(status: status)
        self.ending = ending
        Journal.log("signIn.ended", ["ending": String(describing: ending)])
        self.ended(ending)
    }

    private func endingOf(status: Int32) -> Ending {
        guard !wasCancelled else { return .cancelled }
        return status == 0 ? .signedIn : .failed(status)
    }
}
