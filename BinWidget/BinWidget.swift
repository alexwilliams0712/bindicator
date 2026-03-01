import SwiftUI
import WidgetKit

struct BinfluencerProvider: TimelineProvider {
    func placeholder(in context: Context) -> BinEntry_Widget {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (BinEntry_Widget) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        Task {
            let entry = await fetchEntry()
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BinEntry_Widget>) -> Void) {
        Task {
            let entry = await fetchEntry()

            // Refresh every 4 hours; also at midnight for day label updates
            let refreshDate = Calendar.current.date(byAdding: .hour, value: 4, to: Date()) ?? Date()
            let midnight = Calendar.current.startOfDay(
                for: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            )
            let nextRefresh = min(refreshDate, midnight)

            let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
            completion(timeline)
        }
    }

    private func fetchEntry() async -> BinEntry_Widget {
        guard let borough = BinStore.loadBorough() else { return .placeholder }

        // Try cached data first
        if let cached = BinStore.loadCollections(), !cached.isEmpty {
            let valid = cached.filter { $0.collectionDate >= Calendar.current.startOfDay(for: Date()) }
            if !valid.isEmpty {
                return BinEntry_Widget(
                    date: Date(),
                    collections: valid,
                    boroughName: borough.displayName,
                    isPlaceholder: false
                )
            }
        }

        // Fetch fresh data
        let postcode = BinStore.loadPostcode() ?? ""
        let uprn = BinStore.loadUPRN()
        let houseNumber = BinStore.loadHouseNumber()

        do {
            let collections = try await BinCollectionService.shared.fetchCollections(
                borough: borough,
                postcode: postcode,
                uprn: uprn,
                houseNumber: houseNumber
            )
            return BinEntry_Widget(
                date: Date(),
                collections: collections,
                boroughName: borough.displayName,
                isPlaceholder: false
            )
        } catch {
            return BinEntry_Widget(
                date: Date(),
                collections: BinStore.loadCollections() ?? [],
                boroughName: borough.displayName,
                isPlaceholder: false
            )
        }
    }
}

struct BinfluencerWidget: Widget {
    let kind = "BinfluencerWidget"

    private var supportedFamilies: [WidgetFamily] {
        [.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular]
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BinfluencerProvider()) { entry in
            BinWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Bindicator")
        .description("Your upcoming bin collection days")
        .supportedFamilies(supportedFamilies)
    }
}
