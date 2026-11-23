import Foundation

enum Slot {
    static func parked(_ id: String) -> String { "Hats parked \(id)" }

    static func legacyParked(_ id: String) -> String { "TMK acc-switch parked \(id)" }

    static func codexParked(_ id: String) -> String { "Hats Codex parked \(id)" }

    static let claudePrefixes = [parked(""), legacyParked("")]

    static let hatsOwnedPrefixes = claudePrefixes + [codexParked("")]
}

struct KeychainError: LocalizedError {
    let operation: String
    let detail: String
    var errorDescription: String? { "\(operation) failed: \(detail)" }
}

enum Keychain {
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

    static func run(_ arguments: [String], input: Data? = nil, executable: String = "/usr/bin/security") -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let out = Pipe()
        let err = Pipe()
        let stdin = Pipe()
        process.standardOutput = out
        process.standardError = err
        if input != nil { process.standardInput = stdin }

        do { try process.run() } catch {
            return Result(status: -1, stdout: "", stderr: error.localizedDescription)
        }
        if let input {
            let writer = stdin.fileHandleForWriting
            _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)
            try? writer.write(contentsOf: input)
            try? writer.close()
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
