import SwiftUI

struct UsageBarView: View {
    let bar: UsageBar
    let secondary: Color
    let lit: Bool

    static let labelWidth: CGFloat = 30
    static let trackWidth: CGFloat = 60
    static let trackHeight: CGFloat = 5
    static let resetsColumnWidth: CGFloat = widestResets(font: .monospacedDigitSystemFont(ofSize: 11, weight: .regular))

    static func widestResets(font: NSFont) -> CGFloat {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let days = formatter.shortWeekdaySymbols ?? []
        let months = formatter.shortMonthSymbols ?? []
        let widths = days.flatMap { day in
            months.map { month in
                NSAttributedString(string: "\(day) 28 \(month) 00:00", attributes: [.font: font]).size().width
            }
        }

        return ceil(widths.max() ?? 0)
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(bar.label).font(.system(size: 11)).foregroundStyle(secondary)
                .frame(width: Self.labelWidth, alignment: .leading)
            track
                .frame(width: Self.trackWidth, height: Self.trackHeight)
            Text(bar.resets ?? "").font(.system(size: 11)).monospacedDigit().foregroundStyle(secondary)
                .lineLimit(1).fixedSize()
                .frame(width: Self.resetsColumnWidth, alignment: .leading)
        }
        .frame(height: 14)
    }

    @ViewBuilder private var track: some View {
        if bar.fill == .emptyDashed {
            Capsule().strokeBorder(secondary, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
        } else {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(secondary.opacity(0.25))
                    Capsule().fill(tint)
                        .frame(width: geometry.size.width * CGFloat(bar.percent) / 100)
                }
            }
            .opacity(bar.fill == .faint ? 0.4 : 1)
        }
    }

    private var tint: Color {
        if lit { return secondary }
        switch bar.tone {
        case .neutral: return secondary
        case .warning: return .orange
        case .critical: return .red
        }
    }
}
