import Foundation

struct LimitThresholds: Codable, Equatable {
    static let defaultWarn = 70
    static let defaultSave = 80
    static let range = 10...95

    var warnPercent: Int? = LimitThresholds.defaultWarn
    var savePercent: Int? = LimitThresholds.defaultSave

    enum CodingKeys: String, CodingKey {
        case warnPercent
        case savePercent
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(warnPercent, forKey: .warnPercent)
        try c.encode(savePercent, forKey: .savePercent)
    }

    fileprivate static func findPair(in c: KeyedDecodingContainer<CodingKeys>) throws -> (warn: Int?, save: Int?) {
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
        if let warn, !range.contains(warn) { return false }
        if let save, !range.contains(save) { return false }
        guard let warn, let save else { return true }

        return warn < save
    }

    func getWarnRange() -> ClosedRange<Int> {
        guard let savePercent else { return Self.range }
        let high = min(Self.range.upperBound, savePercent - 1)

        return Self.range.lowerBound...max(Self.range.lowerBound, high)
    }

    func getSaveRange() -> ClosedRange<Int> {
        guard let warnPercent else { return Self.range }
        let low = max(Self.range.lowerBound, warnPercent + 1)

        return min(low, Self.range.upperBound)...Self.range.upperBound
    }

    mutating func setWarn(isOn: Bool) {
        guard isOn else {
            warnPercent = nil
            return
        }
        let percent = getWarnRange().getClamped(Self.defaultWarn)
        warnPercent = Self.isAUsablePair(warn: percent, save: savePercent) ? percent : nil
    }

    mutating func setSave(isOn: Bool) {
        guard isOn else {
            savePercent = nil
            return
        }
        let percent = getSaveRange().getClamped(Self.defaultSave)
        savePercent = Self.isAUsablePair(warn: warnPercent, save: percent) ? percent : nil
    }

    mutating func setWarn(_ percent: Int) {
        guard warnPercent != nil else { return }
        let clamped = getWarnRange().getClamped(percent)
        guard Self.isAUsablePair(warn: clamped, save: savePercent) else { return }
        warnPercent = clamped
    }

    mutating func setSave(_ percent: Int) {
        guard savePercent != nil else { return }
        let clamped = getSaveRange().getClamped(percent)
        guard Self.isAUsablePair(warn: warnPercent, save: clamped) else { return }
        savePercent = clamped
    }
}

extension LimitThresholds {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let pair = try? Self.findPair(in: c), Self.isAUsablePair(warn: pair.warn, save: pair.save) else { return }
        warnPercent = pair.warn
        savePercent = pair.save
    }
}
