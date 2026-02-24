import SwiftUI
import WidgetKit

struct AccessoryCircularWidgetView: View {
    let entry: BinEntry_Widget

    private var nextCollection: BinCollection? {
        entry.collections.first
    }

    var body: some View {
        if let next = nextCollection {
            Gauge(value: Double(max(0, 7 - next.daysUntil)), in: 0...7) {
                Image(systemName: "trash")
            } currentValueLabel: {
                VStack(spacing: 0) {
                    Text("\(next.daysUntil)")
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.bold)
                    Text("day")
                        .font(.system(size: 7))
                }
            }
            .gaugeStyle(.accessoryCircularCapacity)
        } else {
            Image(systemName: "trash")
                .font(.title3)
        }
    }
}
