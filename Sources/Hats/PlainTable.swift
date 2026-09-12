import SwiftUI

struct PlainColumn: Equatable {
    let title: String
    let width: CGFloat?

    init(_ title: String, width: CGFloat? = nil) {
        self.title = title
        self.width = width
    }
}

struct PlainTable: View {
    let columns: [PlainColumn]
    let rows: [[String]]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            line(columns.map(\.title), weight: .semibold, tint: .secondary)
            Divider()
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                line(row, weight: .regular, tint: .primary)
                    .background(index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.04))
            }
        }
    }

    private func line(_ cells: [String], weight: Font.Weight, tint: Color) -> some View {
        HStack(spacing: 12) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                cellView(cell, width: columns.indices.contains(index) ? columns[index].width : nil)
            }
        }
        .font(.system(size: 11, weight: weight))
        .foregroundStyle(tint)
        .padding(.vertical, 3)
    }

    @ViewBuilder private func cellView(_ text: String, width: CGFloat?) -> some View {
        if let width {
            Text(text).frame(width: width, alignment: .leading)
        } else {
            Text(text).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
