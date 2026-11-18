import Foundation

enum Slot {
    static func parked(_ id: String) -> String { "Hats parked \(id)" }

    static func legacyParked(_ id: String) -> String { "TMK acc-switch parked \(id)" }

    static func codexParked(_ id: String) -> String { "Hats Codex parked \(id)" }

    static let claudePrefixes = [parked(""), legacyParked("")]
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
        return storedValue(printed: result.stdout)
    }

    static func storedValue(printed: String) -> Data {
        let digits = Array(printed.utf8)
        guard !digits.isEmpty, digits.count % 2 == 0, digits.allSatisfy(isLowerHexDigit) else {
            return Data(printed.utf8)
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(digits.count / 2)
        for index in stride(from: 0, to: digits.count, by: 2) {
            bytes.append(hexValue(digits[index]) << 4 | hexValue(digits[index + 1]))
        }
        guard bytes.contains(where: isNotPrintable) else { return Data(printed.utf8) }

        return Data(bytes)
    }

    private static func isLowerHexDigit(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte)
    }

    private static func hexValue(_ digit: UInt8) -> UInt8 {
        digit <= UInt8(ascii: "9") ? digit - UInt8(ascii: "0") : digit - UInt8(ascii: "a") + 10
    }

    private static func isNotPrintable(_ byte: UInt8) -> Bool {
        byte < 0x20 || byte == 0x7f
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

    static func parkedAccountIDs(
        account: String,
        prefixes: [String] = Slot.claudePrefixes,
        dump: () -> Result = { run(["dump-keychain"]) }
    ) throws -> [String] {
        let result = dump()
        guard result.status == 0 else {
            throw KeychainError(operation: "list parked logins", detail: result.stderr)
        }
        return parsedParkedIDs(dump: result.stdout, account: account, prefixes: prefixes)
    }

    static func parsedParkedIDs(
        dump: String,
        account: String,
        prefixes: [String] = Slot.claudePrefixes
    ) -> [String] {
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
