import Foundation

extension Keychain {
    static let interactiveCommandLimit = 4032

    static func writeLiveItem(
        service: String,
        account: String,
        data: Data,
        runInteractive: (Data) -> Result = { run(["-i"], input: $0) },
        runArguments: ([String]) -> Result = { run($0) }
    ) throws {
        let command = try createInteractiveAddCommand(service: service, account: account, data: data)
        let result = command.utf8.count <= interactiveCommandLimit
            ? runInteractive(Data(command.utf8))
            : runArguments(["add-generic-password", "-U", "-a", account, "-s", service, "-X", hexString(data)])
        guard result.status == 0 else {
            throw KeychainError(operation: "write \(service)", detail: result.stderr)
        }
    }

    static func createInteractiveAddCommand(service: String, account: String, data: Data) throws -> String {
        guard !hasUnquotableCharacter(service), !hasUnquotableCharacter(account) else {
            throw KeychainError(
                operation: "write \(service)",
                detail: "the item name cannot be quoted for security -i; nothing was written"
            )
        }

        return "add-generic-password -U -a \"\(account)\" -s \"\(service)\" -X \"\(hexString(data))\"\n"
    }

    private static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private static func hasUnquotableCharacter(_ name: String) -> Bool {
        name.unicodeScalars.contains { "\"\\\n\r".unicodeScalars.contains($0) }
    }
}
