import Foundation

struct SignInCommand: Equatable {
    let executable: String
    let arguments: [String]
    let environment: [String: String]

    static func of(
        executable: String? = CLI.executable,
        email: String?,
        browser: BrowserChoice?
    ) throws -> SignInCommand {
        guard let executable else { throw SwitchError.cliNotFound }
        var arguments = ["auth", "login"]
        if let email, !email.isEmpty {
            arguments.append("--email")
            arguments.append(email)
        }
        var environment = ProcessInfo.processInfo.environment
        if let wrapper = try browser?.wrapperScript() {
            environment["BROWSER"] = wrapper.path
        }

        return SignInCommand(executable: executable, arguments: arguments, environment: environment)
    }
}
