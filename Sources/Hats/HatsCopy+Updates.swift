import Foundation

extension HatsCopy {
static func updateVerdict(_ verdict: UpdateVerdict) -> (message: String, detail: String) {
        switch verdict {
        case .upToDate(let running):
            return ("Hats \(running) is the newest release", "Nothing to install.")
        case .available(let release):
            return ("Hats \(release.version) is out",
                    release.asset == nil
                        ? "The release page has the details."
                        : "Download the disk image, then drag Hats to Applications over the old one.")
        case .unreadable:
            return ("Cannot tell whether there is an update",
                    "GitHub answered with something this build cannot read. While the repository is "
                        + "private it answers 404 to anyone not signed in, which looks the same from here.")
        case .unreachable:
            return ("Cannot reach GitHub", "No answer within \(Int(UpdateCheck.budget)) seconds.")
        case .notConfigured:
            return ("This build does not know where to look",
                    "It carries no \(UpdateCheck.repositoryKey) in its Info.plist, which is what names "
                        + "the repository to ask. A bundle built by Build/build-app.sh carries it.")
        }
    }
}
