import Foundation

enum AfterSave: String, Codable, Equatable, CaseIterable {
    case tell
    case offerClear = "offer_clear"
    case offerExit = "offer_exit"
    case clear
}

struct ContextThresholds: Codable, Equatable {
    static let defaultWarn = 60
    static let defaultSave = 70
    static let warnRange = 10...94
    static let saveRange = 11...95
    static let defaultDrainMinutes = 10
    static let drainMinutesRange = 1...60

    var warnPercent: Int? = ContextThresholds.defaultWarn
    var savePercent: Int? = ContextThresholds.defaultSave
    var afterSave = AfterSave.offerClear
    var drain = false
    var drainMinutes = ContextThresholds.defaultDrainMinutes

    enum CodingKeys: String, CodingKey {
        case warnPercent
        case savePercent
        case afterSave
        case drain
        case drainMinutes
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(warnPercent, forKey: .warnPercent)
        try c.encode(savePercent, forKey: .savePercent)
        try c.encode(afterSave, forKey: .afterSave)
        try c.encode(drain, forKey: .drain)
        try c.encode(drainMinutes, forKey: .drainMinutes)
    }

    private static func findPair(in c: KeyedDecodingContainer<CodingKeys>) throws -> (warn: Int?, save: Int?) {
        let warn = try findPercent(in: c, forKey: .warnPercent, fallback: defaultWarn)
        let save = try findPercent(in: c, forKey: .savePercent, fallback: defaultSave)

        return (warn, save)
    }

    private static func findPercent(
        in c: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys,
        fallback: Int
    ) throws -> Int? {
        guard c.contains(key) else { return fallback }
        if try c.decodeNil(forKey: key) { return nil }

        return try c.decode(Int.self, forKey: key)
    }

    static func isAUsablePair(warn: Int?, save: Int?) -> Bool {
        if let warn, !warnRange.contains(warn) { return false }
        if let save, !saveRange.contains(save) { return false }
        guard let warn, let save else { return true }

        return warn < save
    }

    func getWarnRange() -> ClosedRange<Int> {
        guard let savePercent else { return Self.warnRange }

        return Self.warnRange.lowerBound...min(Self.warnRange.upperBound, savePercent - 1)
    }

    func getSaveRange() -> ClosedRange<Int> {
        guard let warnPercent else { return Self.saveRange }

        return max(Self.saveRange.lowerBound, warnPercent + 1)...Self.saveRange.upperBound
    }

    mutating func setWarn(isOn: Bool) {
        warnPercent = isOn ? getWarnRange().getClamped(Self.defaultWarn) : nil
    }

    mutating func setSave(isOn: Bool) {
        savePercent = isOn ? getSaveRange().getClamped(Self.defaultSave) : nil
    }

    mutating func setWarn(_ percent: Int) {
        guard warnPercent != nil else { return }
        warnPercent = getWarnRange().getClamped(percent)
    }

    mutating func setSave(_ percent: Int) {
        guard savePercent != nil else { return }
        savePercent = getSaveRange().getClamped(percent)
    }

    func canDrain(limits: LimitThresholds) -> Bool {
        savePercent != nil || limits.savePercent != nil
    }

    mutating func setDrainMinutes(_ minutes: Int) {
        drainMinutes = Self.drainMinutesRange.getClamped(minutes)
    }

    private static func findDrainMinutes(in c: KeyedDecodingContainer<CodingKeys>) -> Int {
        guard let minutes = try? c.decodeIfPresent(Int.self, forKey: .drainMinutes),
              drainMinutesRange.contains(minutes)
        else { return defaultDrainMinutes }

        return minutes
    }
}

extension ContextThresholds {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let pair = try? Self.findPair(in: c), Self.isAUsablePair(warn: pair.warn, save: pair.save) {
            warnPercent = pair.warn
            savePercent = pair.save
        }
        afterSave = (try? c.decodeIfPresent(AfterSave.self, forKey: .afterSave)) ?? .offerClear
        drain = (try? c.decodeIfPresent(Bool.self, forKey: .drain)) ?? false
        drainMinutes = Self.findDrainMinutes(in: c)
    }
}

extension ClosedRange where Bound == Int {
    func getClamped(_ value: Int) -> Int {
        Swift.min(upperBound, Swift.max(lowerBound, value))
    }
}
