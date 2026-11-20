import Foundation

struct PercentNeighbour: Equatable {
    let label: String
    let percent: Int
}

struct PercentBound: Equatable {
    let percent: Int
    let neighbour: PercentNeighbour?
}

struct PercentBounds: Equatable {
    let lower: PercentBound
    let upper: PercentBound

    init(lower: PercentBound, upper: PercentBound) {
        self.lower = lower
        self.upper = upper
    }

    init(_ range: ClosedRange<Int>, below: PercentNeighbour? = nil, above: PercentNeighbour? = nil) {
        let lowerNeighbour = Self.getNeighbourAtEdge(above, at: range.lowerBound - 1)
        let upperNeighbour = Self.getNeighbourAtEdge(below, at: range.upperBound + 1)
        lower = PercentBound(percent: range.lowerBound, neighbour: lowerNeighbour)
        upper = PercentBound(percent: range.upperBound, neighbour: upperNeighbour)
    }

    private static func getNeighbourAtEdge(_ neighbour: PercentNeighbour?, at percent: Int) -> PercentNeighbour? {
        guard let neighbour, neighbour.percent == percent else { return nil }

        return neighbour
    }

    func getStepRange() -> ClosedRange<Int> {
        lower.percent...upper.percent
    }
}
