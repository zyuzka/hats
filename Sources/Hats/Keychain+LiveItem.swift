import Foundation

extension Keychain {
    static let interactiveCommandLimit = 4032

    static func writeLiveItem(
        service: String,
        account: String,
        data: Data,
        runInteractive: (Data) -> Result = { run(["-i"], input: $0) }
    ) throws {
        let command = try createInteractiveAddCommand(service: service, account: account, data: data)
        let result = runInteractive(Data(command.utf8))
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
        let hex = data.map { String(format: "%02x", $0) }.joined()
        let command = "add-generic-password -U -a \"\(account)\" -s \"\(service)\" -X \"\(hex)\"\n"
        guard command.utf8.count <= interactiveCommandLimit else {
            throw KeychainError(
                operation: "write \(service)",
                detail: "the security -i command is \(command.utf8.count) characters, "
                    + "over the limit of \(interactiveCommandLimit); nothing was written"
            )
        }

        return command
    }

    private static func hasUnquotableCharacter(_ name: String) -> Bool {
        name.contains { "\"\\\n\r".contains($0) }
    }
}
