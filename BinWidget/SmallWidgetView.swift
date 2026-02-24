import SwiftUI
import WidgetKit

struct SmallWidgetView: View {
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
        VStack(alignment: .leading, spacing: 4) {
            Text("BINS")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.green)

            Spacer(minLength: 0)

            if uniqueCollections.isEmpty {
                Text("No data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(uniqueCollections.prefix(3), id: \.1.id) { binType, collection in
                    binRow(binType, collection)
                }
            }

            Spacer(minLength: 0)

            if !entry.isPlaceholder {
                Text(entry.boroughName)
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(2)
    }

    private func binRow(_ binType: BinType, _ collection: BinCollection) -> some View {
        HStack(spacing: 6) {
            Image(systemName: binType.icon)
                .font(.system(size: 10))
                .foregroundStyle(binType.color)
                .frame(width: 14)

            Text(binType.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Text(collection.dayLabel)
                .font(.system(.caption2, design: .monospaced))
                .fontWeight(.bold)
                .foregroundStyle(collection.isUrgent ? binType.color : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
