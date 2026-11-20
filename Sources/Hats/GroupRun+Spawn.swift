import Darwin
import Foundation

struct GroupRunRefusal: Error {
    let text: String
}

extension GroupRun {
    static func createChild(
        _ line: PluginCommandLine,
        output: Int32,
        errors: Int32
    ) -> Result<pid_t, GroupRunRefusal> {
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(
            &actions,
            0,
            "/dev/null",
            O_RDONLY,
            0
        )
        posix_spawn_file_actions_adddup2(
            &actions,
            output,
            1
        )
        posix_spawn_file_actions_adddup2(
            &actions,
            errors,
            2
        )
        posix_spawn_file_actions_addchdir_np(&actions, "/")

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        setFreshGroup(&attributes)

        let arguments = [line.executable] + line.arguments
        let environment = line.environment.map { "\($0.key)=\($0.value)" }.sorted()
        var pid: pid_t = 0
        let code = getResult(withCStrings: arguments) { argv in
            getResult(withCStrings: environment) { envp in
                posix_spawn(
                    &pid,
                    line.executable,
                    &actions,
                    &attributes,
                    argv,
                    envp
                )
            }
        }
        guard code == 0 else { return .failure(GroupRunRefusal(text: String(cString: strerror(code)))) }

        return .success(pid)
    }

    private static func setFreshGroup(_ attributes: inout posix_spawnattr_t?) {
        let flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK
        posix_spawnattr_setflags(&attributes, Int16(flags))
        posix_spawnattr_setpgroup(&attributes, 0)
        var everySignal = sigset_t()
        sigfillset(&everySignal)
        posix_spawnattr_setsigdefault(&attributes, &everySignal)
        var noSignal = sigset_t()
        sigemptyset(&noSignal)
        posix_spawnattr_setsigmask(&attributes, &noSignal)
    }

    private static func getResult<Result>(
        withCStrings strings: [String],
        _ body: ([UnsafeMutablePointer<CChar>?]) -> Result
    ) -> Result {
        let pointers: [UnsafeMutablePointer<CChar>?] = strings.map { strdup($0) } + [nil]
        defer { pointers.forEach { free($0) } }

        return body(pointers)
    }
}
