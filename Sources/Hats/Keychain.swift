import Foundation

enum Slot {
    static func parked(_ id: String) -> String { "Hats parked \(id)" }

    static func legacyParked(_ id: String) -> String { "TMK acc-switch parked \(id)" }
}

struct KeychainError: LocalizedError {
    let operation: String
    let detail: String
    var errorDescription: String? { "\(operation) failed: \(detail)" }
}

enum Keychain {
    static func read(service: String, account: String) throws -> Data? {
        let result = run(["find-generic-password", "-s", service, "-a", account, "-w"])
        if result.status == 44 { return nil }
        guard result.status == 0 else {
            if result.stderr.contains("could not be found") { return nil }
            throw KeychainError(operation: "read \(service)", detail: result.stderr)
        }
        return result.stdout.data(using: .utf8)
    }

    static func write(service: String, account: String, data: Data) throws {
        guard let value = String(data: data, encoding: .utf8) else {
            throw KeychainError(operation: "write \(service)", detail: "payload is not UTF-8")
        }
        let result = run([
            "add-generic-password",
            "-U",
            "-s", service,
            "-a", account,
            "-w", value,
        ])
        guard result.status == 0 else {
            throw KeychainError(operation: "write \(service)", detail: result.stderr)
        }
    }

    static func delete(service: String, account: String) throws {
        let result = run(["delete-generic-password", "-s", service, "-a", account])
        guard result.status == 0 || result.status == 44 else {
            throw KeychainError(operation: "delete \(service)", detail: result.stderr)
        }
    }

    static func parkedAccountIDs(account: String,
                                 dump: () -> Result = { run(["dump-keychain"]) })
        throws -> [String] {
        let result = dump()
        guard result.status == 0 else {
            throw KeychainError(operation: "list parked logins", detail: result.stderr)
        }
        return parsedParkedIDs(dump: result.stdout, account: account)
    }

    static func parsedParkedIDs(dump: String, account: String) -> [String] {
        let prefixes = [Slot.parked(""), Slot.legacyParked("")]
        var ids: Set<String> = []
        for item in dump.components(separatedBy: "keychain: ") {
            guard quotedAttribute("acct", in: item) == account,
                  let service = quotedAttribute("svce", in: item),
                  let prefix = prefixes.first(where: { service.hasPrefix($0) }) else { continue }
            let id = String(service.dropFirst(prefix.count))
            if !id.isEmpty { ids.insert(id) }
        }
        return Array(ids)
    }

    static func adoptLegacyParked(ids: [String], account: String) {
        for id in ids { adoptLegacyParked(id: id, account: account) }
    }

    static func adoptLegacyParked(id: String, account: String) {
        guard let payload = try? read(service: Slot.legacyParked(id), account: account) else {
            return
        }
        if (try? read(service: Slot.parked(id), account: account)) != nil {
            try? delete(service: Slot.legacyParked(id), account: account)
            return
        }
        guard (try? write(service: Slot.parked(id), account: account, data: payload)) != nil else {
            return
        }
        try? delete(service: Slot.legacyParked(id), account: account)
    }

    static func deleteParked(id: String, account: String) throws {
        try delete(service: Slot.parked(id), account: account)
        try? delete(service: Slot.legacyParked(id), account: account)
    }

    private static func quotedAttribute(_ name: String, in item: String) -> String? {
        let key = "\"\(name)\"<blob>=\""
        for line in item.split(separator: "\n") {
            guard let start = line.range(of: key) else { continue }
            let value = line[start.upperBound...]
            guard let end = value.lastIndex(of: "\"") else { continue }
            return String(value[..<end])
        }
        return nil
    }

    struct Result {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    private static func run(_ arguments: [String]) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        do { try process.run() } catch {
            return Result(status: -1, stdout: "", stderr: error.localizedDescription)
        }

        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return Result(
            status: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
