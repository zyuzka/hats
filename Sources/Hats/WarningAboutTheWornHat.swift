import Foundation

struct DeadEndBanner: Equatable {
    let line: String
    let signInTo: ShutOutHat?
}

extension HatsSnapshot {
    var warningAboutTheWornHat: AutoSwitchWarning? {
        guard settings.autoSwitch.isOn, hasOnlyHatsThatAreStillHere(autoSwitchWarning) else { return nil }
        return autoSwitchWarning
    }

    var showsAWarningAboutTheWornHat: Bool { warningAboutTheWornHat != nil }

    func deadEndBanner(now: Date, timeZone: TimeZone = .current) -> DeadEndBanner? {
        guard case .nowhereToGoAtALimit(let limit, let by) = warningAboutTheWornHat else {
            return nil
        }
        let line = HatsCopy.nowhereToGo(
            of: wearing?.title ?? "This hat",
            limit: limit,
            strandedBy: by,
            now: now,
            timeZone: timeZone
        ).1

        return DeadEndBanner(line: line, signInTo: theOneHatToSignInTo(by))
    }

    func hasOnlyHatsThatAreStillHere(_ warning: AutoSwitchWarning?) -> Bool {
        guard case .nowhereToGoAtALimit(_, .othersNeedSigningIn(let first, let also)) = warning else {
            return true
        }

        return ([first] + also).allSatisfy { named in rows.contains { $0.id == named.id } }
    }

    private func theOneHatToSignInTo(_ by: AutoSwitchDeadEnd.StrandedBy) -> ShutOutHat? {
        guard case .othersNeedSigningIn(let only, let also) = by, also.isEmpty else { return nil }

        return only
    }
}
