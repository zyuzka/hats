import Foundation

struct ShellTarget: Equatable {
    let path: String
    let dialect: ShellDialect
}

enum ShellProfile {
    typealias FileCheck = (String) -> Bool

    static func loginShell() -> String? {
        guard let entry = getpwuid(getuid()), let raw = entry.pointee.pw_shell else {
            return ProcessInfo.processInfo.environment["SHELL"]
        }
        let shell = String(cString: raw)
        return shell.isEmpty ? ProcessInfo.processInfo.environment["SHELL"] : shell
    }

    static func target(
        shell: String?,
        home: String,
        zdotdir: String? = nil,
        exists: FileCheck
    ) -> ShellTarget? {
        guard let shell, !shell.isEmpty else { return nil }
        let name = (shell as NSString).lastPathComponent

        switch name {
        case "zsh":
            let directory = zdotdir.flatMap { $0.isEmpty ? nil : $0 } ?? home
            return ShellTarget(path: directory + "/.zshrc", dialect: .posix)
        case "bash":
            let candidates = [
                home + "/.bash_profile",
                home + "/.bash_login",
                home + "/.profile",
            ]
            let chosen = candidates.first(where: exists) ?? candidates[0]
            return ShellTarget(path: chosen, dialect: .posix)
        case "fish":
            return ShellTarget(path: home + "/.config/fish/config.fish", dialect: .fish)
        case "ksh", "sh", "dash":
            return ShellTarget(path: home + "/.profile", dialect: .posix)
        case "tcsh", "csh":
            return ShellTarget(path: home + "/.\(name)rc", dialect: .csh)
        default:
            return nil
        }
    }

    static func currentTarget() -> ShellTarget? {
        target(
            shell: loginShell(),
            home: NSHomeDirectory(),
            zdotdir: ProcessInfo.processInfo.environment["ZDOTDIR"],
            exists: { FileManager.default.fileExists(atPath: $0) }
        )
    }
}
