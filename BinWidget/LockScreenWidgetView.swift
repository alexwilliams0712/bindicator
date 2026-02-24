import SwiftUI
import WidgetKit

struct LockScreenWidgetView: View {
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
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "trash")
                    .font(.caption2)
                Text("Bins")
                    .font(.caption2)
                    .fontWeight(.semibold)
            }
            .widgetAccentable()

            ForEach(uniqueCollections.prefix(2), id: \.1.id) { binType, collection in
                HStack(spacing: 4) {
                    Image(systemName: binType.icon)
                        .font(.system(size: 8))
                    Text(binType.displayName)
                        .font(.system(size: 10))
                    Spacer()
                    Text(collection.dayLabel)
                        .font(.system(size: 10, design: .monospaced))
                        .fontWeight(.bold)
                }
            }
        }
    }
}
