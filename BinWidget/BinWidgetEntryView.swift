import SwiftUI
import WidgetKit

struct BinWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: BinEntry_Widget

    var body: some View {
        switch family {
        case .accessoryRectangular:
            LockScreenWidgetView(entry: entry)
        case .accessoryCircular:
            AccessoryCircularWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}
