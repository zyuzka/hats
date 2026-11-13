import Foundation

struct ContextRow: Identifiable, Equatable {
    let id: String
    let label: String
    let value: String
}

extension SessionWindow {
    static let menuLimit = 5

    static func getMenuRows(_ windows: [SessionWindow], now: Date) -> [ContextRow] {
        let rows = getRowsAsNamed(windows, now: now)
        let repeated = Set(Dictionary(grouping: rows, by: \.label).filter { $0.value.count > 1 }.keys)

        return rows.map { row in
            guard repeated.contains(row.label) else { return row }
            return ContextRow(
                id: row.id,
                label: HatsCopy.getContextLabel(row.label, telling: row.id),
                value: row.value
            )
        }
    }

    private static func getRowsAsNamed(_ windows: [SessionWindow], now: Date) -> [ContextRow] {
        windows
            .filter { $0.isRecent(at: now) }
            .sorted(by: isShownBefore)
            .prefix(menuLimit)
            .map { window in
                ContextRow(
                    id: window.session,
                    label: HatsCopy.getContextLabel(
                        title: window.title,
                        cwd: window.cwd,
                        session: window.session
                    ),
                    value: HatsCopy.getContextValue(window)
                )
            }
    }

    static func isShownBefore(_ first: SessionWindow, _ second: SessionWindow) -> Bool {
        switch (first.percent, second.percent) {
        case let (one?, other?) where one != other:
            return one > other
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            guard first.measuredAt == second.measuredAt else { return first.measuredAt > second.measuredAt }
            return first.session < second.session
        }
    }
}
