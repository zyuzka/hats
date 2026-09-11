import Foundation

struct MeterReading: Equatable {
    let line: String
    let age: String
    let trouble: String?

    static let unavailable = MeterReading(line: "unavailable", age: "-", trouble: nil)

    static func of(_ reading: UsageReading?,
                   readAt: Date?,
                   trouble: UsageTrouble?,
                   now: Date = Date()) -> MeterReading {
        guard let reading, let readAt else {
            return MeterReading(line: trouble?.journalLine ?? "unavailable", age: "-", trouble: nil)
        }
        return MeterReading(
            line: reading.journalLine,
            age: "\(Int(now.timeIntervalSince(readAt)))s",
            trouble: trouble?.journalLine
        )
    }
}
