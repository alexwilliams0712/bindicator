import Foundation
import SwiftUI
import WidgetKit

final class BinStore: ObservableObject {
    private static let boroughKey = "selectedBorough"
    private static let postcodeKey = "selectedPostcode"
    private static let uprnKey = "selectedUPRN"
    private static let houseNumberKey = "selectedHouseNumber"
    private static let collectionsKey = "cachedCollections"
    private static let lastFetchKey = "lastFetchDate"

    @Published var selectedBorough: Borough? {
        didSet {
            guard let borough = selectedBorough else {
                KeychainStore.remove(forKey: Self.boroughKey)
                return
            }
            KeychainStore.set(borough.rawValue, forKey: Self.boroughKey)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    @Published var postcode: String {
        didSet { KeychainStore.set(postcode, forKey: Self.postcodeKey) }
    }

    @Published var uprn: String {
        didSet { KeychainStore.set(uprn, forKey: Self.uprnKey) }
    }

    @Published var houseNumber: String {
        didSet { KeychainStore.set(houseNumber, forKey: Self.houseNumberKey) }
    }

    @Published var collections: [BinCollection] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(collections) {
                KeychainStore.setData(data, forKey: Self.collectionsKey)
            }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    var isConfigured: Bool {
        guard let borough = selectedBorough else { return false }
        switch borough.inputRequirement {
        case .postcodeAndAddressSelect:
            return !postcode.isEmpty && !uprn.isEmpty
        case .postcodeAndNumber:
            return !postcode.isEmpty
        }
    }

    // MARK: - Init

    init() {
        self.selectedBorough = Self.loadBorough()
        self.postcode = Self.loadPostcode() ?? ""
        self.uprn = KeychainStore.get(forKey: Self.uprnKey) ?? ""
        self.houseNumber = KeychainStore.get(forKey: Self.houseNumberKey) ?? ""
        self.collections = Self.loadCollections() ?? []
    }

    // MARK: - Static loaders (for widget)

    static func loadBorough() -> Borough? {
        guard let raw = KeychainStore.get(forKey: boroughKey) else { return nil }
        return Borough(rawValue: raw)
    }

    static func loadPostcode() -> String? {
        KeychainStore.get(forKey: postcodeKey)
    }

    static func loadUPRN() -> String? {
        KeychainStore.get(forKey: uprnKey)
    }

    static func loadHouseNumber() -> String? {
        KeychainStore.get(forKey: houseNumberKey)
    }

    static func loadCollections() -> [BinCollection]? {
        guard let data = KeychainStore.getData(forKey: collectionsKey) else { return nil }
        return try? JSONDecoder().decode([BinCollection].self, from: data)
    }

    func updateLastFetch() {
        KeychainStore.set(ISO8601DateFormatter().string(from: Date()), forKey: Self.lastFetchKey)
    }

    func clearAll() {
        selectedBorough = nil
        postcode = ""
        uprn = ""
        houseNumber = ""
        collections = []
    }
}
