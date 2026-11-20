import Darwin
import Foundation

enum CodexSwap: Equatable {
    case write
    case keep
}

extension CodexHome {
    @discardableResult
    func swap(in incoming: Data, deciding decide: (Data?) throws -> CodexSwap) throws -> Bool {
        try requireFileStore()
        return try withLocks {
            let before = try readLiveChecked()
            guard try decide(before) == .write else {
                Journal.log("codex.live.kept", ["live": Journal.fingerprint(before)])
                return false
            }
            do {
                try writeAtomically(incoming)
            } catch {
                Journal.log("codex.live.notWritten", ["reason": error.localizedDescription])
                throw error
            }
            let back = try? Data(contentsOf: auth)
            guard back == incoming, permissions() == 0o600 else {
                try rollBack(to: before, ours: incoming, cause: "the file read back differently")
                return false
            }
            Journal.log("codex.live.written", [
                "before": Journal.fingerprint(before),
                "now": Journal.fingerprint(incoming),
            ])

            return true
        }
    }

    func rollBack(to before: Data?, ours: Data, cause: String) throws {
        let now = try? Data(contentsOf: auth)
        guard now == ours else {
            Journal.log("codex.live.leftAlone", ["reason": cause, "live": Journal.fingerprint(now)])
            throw CodexError.leftAlone(cause)
        }
        do {
            if let before {
                try writeAtomically(before)
            } else {
                try FileManager.default.removeItem(at: auth)
            }
        } catch {
            Journal.log("codex.live.rollbackFailed", ["reason": cause, "rollback": error.localizedDescription])
            throw CodexError.rollbackFailed(cause: cause, rollback: error.localizedDescription)
        }
        Journal.log("codex.live.rolledBack", ["reason": cause, "restored": Journal.fingerprint(before)])
        throw CodexError.rolledBack(cause)
    }

    func writeAtomically(_ data: Data) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let temporary = url.appendingPathComponent(".auth-hats-\(UUID().uuidString)")
        let fd = Darwin.open(temporary.path, O_CREAT | O_EXCL | O_WRONLY, 0o600)
        guard fd >= 0 else { throw CodexError.writeFailed(String(cString: strerror(errno))) }
        var failure: String?
        data.withUnsafeBytes { raw in
            var sent = 0
            while sent < raw.count {
                let count = Darwin.write(fd, raw.baseAddress?.advanced(by: sent), raw.count - sent)
                guard count > 0 else {
                    failure = String(cString: strerror(errno))
                    return
                }
                sent += count
            }
        }
        if failure == nil, fchmod(fd, 0o600) != 0 || fsync(fd) != 0 { failure = String(cString: strerror(errno)) }
        Darwin.close(fd)
        do {
            if let failure { throw CodexError.writeFailed(failure) }
            try rename(temporary, auth)
        } catch {
            unlink(temporary.path)
            throw error
        }
    }

    func withLocks<Result>(_ body: () throws -> Result) throws -> Result {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var held: [Int32] = []
        defer {
            for fd in held.reversed() {
                flock(fd, LOCK_UN)
                Darwin.close(fd)
            }
        }
        for lock in locks {
            let fd = Darwin.open(lock.path, O_RDWR | O_CREAT, 0o600)
            guard fd >= 0 else { throw CodexError.writeFailed(String(cString: strerror(errno))) }
            held.append(fd)
            let deadline = Date().addingTimeInterval(lockWait)
            while flock(fd, LOCK_EX | LOCK_NB) != 0 {
                guard Date() < deadline else {
                    Journal.log("codex.live.lockTimedOut", ["lock": lock.lastPathComponent])
                    throw CodexError.lockTimedOut(lock.lastPathComponent)
                }
                usleep(50_000)
            }
        }

        return try body()
    }
}
