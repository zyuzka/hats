import AppKit
import Foundation

enum Automation {
    enum Verdict: Equatable {
        case granted
        case denied
        case targetNotRunning
        case needsUsageDescription
        case cannotAsk(OSStatus)

        static func of(status: OSStatus) -> Verdict {
            switch status {
            case noErr: return .granted
            case OSStatus(errAEEventNotPermitted): return .denied
            case OSStatus(procNotFound): return .targetNotRunning
            case OSStatus(errAEEventWouldRequireUserConsent): return .needsUsageDescription
            default: return .cannotAsk(status)
            }
        }
    }

    static func requestPermission(toAutomate bundleID: String) -> Verdict {
        var target = AEAddressDesc()
        let idBytes = Array(bundleID.utf8)

        let created = AECreateDesc(
            typeApplicationBundleID,
            idBytes,
            idBytes.count,
            &target
        )
        guard created == noErr else { return .cannotAsk(OSStatus(created)) }
        defer { AEDisposeDesc(&target) }

        let status = AEDeterminePermissionToAutomateTarget(
            &target,
            typeWildCard,
            typeWildCard,
            true
        )

        return Verdict.of(status: status)
    }

    static func isSettled(_ verdict: Verdict) -> Bool {
        if case .targetNotRunning = verdict { return false }
        return true
    }

    static func explanation(for verdict: Verdict, appName: String = "Hats") -> String? {
        switch verdict {
        case .granted:
            return nil
        case .denied:
            return "macOS is blocking \(appName) from controlling Terminal, so the "
                + "sign-in window has to be closed by hand. To change that: System Settings "
                + "\u{2192} Privacy & Security \u{2192} Automation \u{2192} \(appName) \u{2192} Terminal."
        case .targetNotRunning:
            return "Terminal is not running, so macOS had nothing to ask about. Any sign-in "
                + "window still open has to be closed by hand."
        case .needsUsageDescription:
            return "macOS would not ask about controlling Terminal, because \(appName) does not "
                + "declare why it needs to, so the sign-in window has to be closed by hand. "
                + "This is a defect in the app bundle rather than a choice you made."
        case .cannotAsk(let status):
            return "macOS would not ask about controlling Terminal (error \(status)), so the "
                + "sign-in window has to be closed by hand. What that error means here is not "
                + "known — the number is worth quoting in a report."
        }
    }
}

enum WindowOutcome: Equatable {
    case counted(Int)
    case couldNotAsk

    static func parsed(status: Int32, output: String) -> WindowOutcome {
        guard status == 0 else { return .couldNotAsk }
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let count = Int(text) else { return .couldNotAsk }
        return .counted(count)
    }
}

enum TerminalWindow {
    static func closeLoginWindow(scriptName: String) -> WindowOutcome {
        run(script: """
        if application "Terminal" is running then
            tell application "Terminal"
                set victims to (every window whose name contains "\(scriptName)")
                repeat with w in victims
                    close w saving no
                end repeat
                return (count of victims)
            end tell
        else
            return 0
        end if
        """)
    }

    private static func run(script: String) -> WindowOutcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()

        do { try process.run() } catch { return .couldNotAsk }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return WindowOutcome.parsed(
            status: process.terminationStatus,
            output: String(data: data, encoding: .utf8) ?? ""
        )
    }
}
