import Foundation

extension AppDelegate {
    func listenToUsageHeaders() {
        GatewayProcess.usageSink = { [weak self] credential, reading in
            DispatchQueue.main.async { self?.noticeUsageHeaders(credential: credential, reading: reading) }
        }
    }

    private func noticeUsageHeaders(credential: String, reading: UsageReading) {
        let world = HeaderSightingWorld(
            policy: settings.autoSwitch,
            wearing: popover.model.snapshot.wearing?.id,
            liveCredential: usage.liveCredential,
            readings: usage.readings,
            interval: usage.interval
        )
        let sighting = pollsOnHeaders.getDecision(
            credential: credential,
            reading: reading,
            world: world,
            at: Date()
        )
        guard sighting == .pollNow else { return }
        Journal.log("usage.pollOnHeaders", [
            "limit": settings.autoSwitch.crossedLimits(in: reading).map(\.0.rawValue).joined(separator: ","),
            "usage": reading.journalLine,
        ])
        usage.poll(hatsForUsage())
    }
}
