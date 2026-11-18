import AppKit

extension AppDelegate {
    func wornMetersForTheJournal() -> MeterReading {
        guard let id = hatsForUsage().first(where: \.isWearing)?.id else { return .unavailable }
        return metersForTheJournal(of: id)
    }

    func metersForTheJournal(of id: String) -> MeterReading {
        MeterReading.of(usage.readings[id], readAt: usage.readAt[id], trouble: usage.troubles[id])
    }

    func afterThePopoverSettles(_ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
}
