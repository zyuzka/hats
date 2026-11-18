import Foundation

enum FullDiskAccess {
    static var probes: [URL] {
        let home = URL(fileURLWithPath: NSHomeDirectory())

        return [
            home.appendingPathComponent("Library/Safari/Bookmarks.plist"),
            home.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db"),
        ]
    }

    static func isGranted(probes: [URL] = probes) -> Bool {
        for probe in probes {
            do {
                let handle = try FileHandle(forReadingFrom: probe)
                try? handle.close()
                return true
            } catch let error as NSError where isMissing(error) {
                continue
            } catch {
                return false
            }
        }

        return false
    }

    private static func isMissing(_ error: NSError) -> Bool {
        let missingCodes = [
            NSFileNoSuchFileError,
            NSFileReadNoSuchFileError,
        ]
        let cocoa = error.domain == NSCocoaErrorDomain && missingCodes.contains(error.code)
        let posix = error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT)

        return cocoa || posix
    }
}

extension HatsCopy {
    static let fullDiskAccessBanner = "Hats has no Full Disk Access, so macOS hides the profiles of some "
        + "browsers from it. Give it the access, then quit and open Hats again."
    static let fullDiskAccessButton = "Open Full Disk Access settings"

    static func browserAccessWarning(hasFullDiskAccess: Bool, unreadable: [ChromeChannel]) -> String? {
        guard !hasFullDiskAccess else { return nil }
        let lead = "Hats has no Full Disk Access, so macOS may hide the profiles of your browsers"
        let names = unreadable.map(\.label).joined(separator: ", ")
        let which = names.isEmpty ? "." : " — \(names) is hidden now, only the profiles your hats use are listed."

        return lead + which + " Click here to give Hats Full Disk Access, then open this form again."
    }
}
