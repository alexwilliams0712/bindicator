import SwiftUI
import WidgetKit

struct MediumWidgetView: View {
    let entry: BinEntry_Widget

    private var uniqueCollections: [(BinType, BinCollection)] {
        var seen = Set<BinType>()
        return entry.collections.compactMap { c in
            guard !seen.contains(c.binType) else { return nil }
            seen.insert(c.binType)
            return (c.binType, c)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("BINS")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
                Spacer()
                Text(entry.boroughName)
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }

            if uniqueCollections.isEmpty {
                Spacer()
                Text("No collection data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                let columns = splitColumns(uniqueCollections)

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(columns.0, id: \.1.id) { binType, collection in
                            binRow(binType, collection)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if !columns.1.isEmpty {
                        Rectangle()
                            .fill(Color.green.opacity(0.3))
                            .frame(width: 1)

                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(columns.1, id: \.1.id) { binType, collection in
                                binRow(binType, collection)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private func splitColumns(
        _ items: [(BinType, BinCollection)]
    ) -> ([(BinType, BinCollection)], [(BinType, BinCollection)]) {
        let mid = (items.count + 1) / 2
        let left = Array(items.prefix(mid))
        let right = Array(items.dropFirst(mid))
        return (left, right)
    }

    private func binRow(_ binType: BinType, _ collection: BinCollection) -> some View {
        HStack(spacing: 6) {
            Image(systemName: binType.icon)
                .font(.system(size: 12))
                .foregroundStyle(binType.color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(binType.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(collection.dayLabel)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundStyle(collection.isUrgent ? binType.color : .primary)
            }
        }
    }
}
