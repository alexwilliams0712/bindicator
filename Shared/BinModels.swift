import Foundation
import SwiftUI
import WidgetKit

// MARK: - Bin Type

enum BinType: String, Codable, CaseIterable, Identifiable {
    case recycling = "Recycling"
    case generalWaste = "General Waste"
    case foodWaste = "Food Waste"
    case gardenWaste = "Garden Waste"
    case paperCard = "Paper & Card"
    case glass = "Glass"
    case other = "Other"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var icon: String {
        switch self {
        case .recycling: return "arrow.3.trianglepath"
        case .generalWaste: return "trash"
        case .foodWaste: return "carrot"
        case .gardenWaste: return "leaf"
        case .paperCard: return "newspaper"
        case .glass: return "wineglass"
        case .other: return "shippingbox"
        }
    }

    var colorComponents: BinColorComponents {
        switch self {
        case .recycling: return BinColorComponents(r: 0.30, g: 0.69, b: 0.31)     // Green
        case .generalWaste: return BinColorComponents(r: 0.47, g: 0.56, b: 0.61)  // Blue-gray
        case .foodWaste: return BinColorComponents(r: 1.00, g: 0.56, b: 0.00)     // Amber
        case .gardenWaste: return BinColorComponents(r: 0.40, g: 0.73, b: 0.42)   // Light green
        case .paperCard: return BinColorComponents(r: 0.26, g: 0.65, b: 0.96)     // Blue
        case .glass: return BinColorComponents(r: 0.61, g: 0.15, b: 0.69)         // Purple
        case .other: return BinColorComponents(r: 0.62, g: 0.62, b: 0.62)         // Gray
        }
    }

    var color: Color {
        let c = colorComponents
        return Color(red: c.r, green: c.g, blue: c.b)
    }

    static func classify(_ rawType: String) -> BinType {
        let lower = rawType.lowercased()

        // Check general waste first (non-recyclable contains "recycl" so must come before recycling)
        if lower.contains("non-recycl") || lower.contains("general") || lower.contains("residual")
            || lower.contains("refuse") || lower.contains("rubbish") || lower.contains("household")
            || lower.contains("black bin") || lower.contains("black lid")
            || lower.contains("grey bin")
        {
            return .generalWaste
        }
        if lower.contains("recycl") || lower.contains("mixed dry") || lower.contains("blue bin")
            || lower.contains("blue lid") || lower.contains("dry recycl")
        {
            return .recycling
        }
        if lower.contains("food") || lower.contains("caddy") || lower.contains("organic") {
            return .foodWaste
        }
        if lower.contains("garden") || lower.contains("green waste") || lower.contains("yard") {
            return .gardenWaste
        }
        if lower.contains("paper") || lower.contains("card") || lower.contains("fibre") {
            return .paperCard
        }
        if lower.contains("glass") || lower.contains("bottle") {
            return .glass
        }
        return .other
    }
}

// MARK: - Color Components (Codable for widget)

struct BinColorComponents: Codable, Equatable {
    let r: Double
    let g: Double
    let b: Double

    var color: Color { Color(red: r, green: g, blue: b) }
}

// MARK: - Bin Collection

struct BinCollection: Codable, Identifiable, Equatable {
    let id: UUID
    let rawType: String
    let binType: BinType
    let collectionDate: Date

    var dayLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(collectionDate) {
            return "Today"
        } else if calendar.isDateInTomorrow(collectionDate) {
            return "Tomorrow"
        } else {
            let formatter = DateFormatter()
            let daysAway = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: collectionDate)).day ?? 0
            if daysAway < 7 {
                formatter.dateFormat = "EEEE"
            } else {
                formatter.dateFormat = "d MMM"
            }
            return formatter.string(from: collectionDate)
        }
    }

    var daysUntil: Int {
        let calendar = Calendar.current
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: Date()),
            to: calendar.startOfDay(for: collectionDate)
        ).day ?? 0
    }

    var isUrgent: Bool { daysUntil <= 1 }
}

// MARK: - Address

struct Address: Codable, Identifiable, Equatable, Hashable {
    let uprn: String
    let address: String

    var id: String { uprn }
}

// MARK: - API Responses

struct CollectionsResponse: Codable {
    let council: String
    let address: String?
    let bins: [BinEntry]
}

struct BinEntry: Codable {
    let type: String
    let collectionDate: String
}

struct AddressResponse: Codable {
    let addresses: [Address]
}

// MARK: - Widget Entry

struct BinEntry_Widget: TimelineEntry {
    let date: Date
    let collections: [BinCollection]
    let boroughName: String
    let isPlaceholder: Bool

    static var placeholder: BinEntry_Widget {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let nextWeek = cal.date(byAdding: .day, value: 5, to: Date()) ?? Date()
        return BinEntry_Widget(
            date: Date(),
            collections: [
                BinCollection(id: UUID(), rawType: "Recycling", binType: .recycling, collectionDate: tomorrow),
                BinCollection(id: UUID(), rawType: "General Waste", binType: .generalWaste, collectionDate: nextWeek),
                BinCollection(id: UUID(), rawType: "Food Waste", binType: .foodWaste, collectionDate: tomorrow),
            ],
            boroughName: "Barnet",
            isPlaceholder: true
        )
    }
}
