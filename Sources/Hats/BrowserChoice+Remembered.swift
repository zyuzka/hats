import Foundation

struct BrowserList {
    let choices: [BrowserChoice]
    let unreadable: [ChromeChannel]
}

extension BrowserChoice {
    static let fullDiskAccessSettings = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
    )

    static func available(remembered: [BrowserChoice]) -> BrowserList {
        var unreadable: [ChromeChannel] = []
        var choices = ChromeChannel.allCases.flatMap { channel -> [BrowserChoice] in
            let readable = channel.readableProfiles
            if readable == nil { unreadable.append(channel) }

            return chromeChoices(channel: channel, readable: readable, remembered: remembered)
        }
        if FileManager.default.fileExists(atPath: "/Applications/Firefox.app") {
            choices.append(.firefox)
        }
        choices.append(.safari)

        return BrowserList(choices: choices, unreadable: unreadable)
    }

    static func chromeChoices(
        channel: ChromeChannel,
        readable: [String]?,
        remembered: [BrowserChoice]
    ) -> [BrowserChoice] {
        guard let profiles = readable ?? rememberedProfiles(of: channel, in: remembered) else { return [] }

        return profiles.map { .chrome(channel, $0) }
    }

    private static func rememberedProfiles(of channel: ChromeChannel, in remembered: [BrowserChoice]) -> [String]? {
        let known = remembered.compactMap { choice -> String? in
            guard case .chrome(let owner, let profile) = choice, owner == channel else { return nil }

            return profile
        }

        return Array(Set(known + ["Default"])).sorted()
    }
}
