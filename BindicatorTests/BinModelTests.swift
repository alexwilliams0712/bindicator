import XCTest
@testable import Bindicator

final class BinModelTests: XCTestCase {

    // MARK: - BinType Classification

    func testClassifyRecycling() {
        XCTAssertEqual(BinType.classify("Empty Standard Recycling"), .recycling)
        XCTAssertEqual(BinType.classify("Mixed Dry Recycling"), .recycling)
        XCTAssertEqual(BinType.classify("Blue Bin"), .recycling)
        XCTAssertEqual(BinType.classify("Dry Recyclables"), .recycling)
        XCTAssertEqual(BinType.classify("Blue Lid Bin"), .recycling)
    }

    func testClassifyGeneralWaste() {
        XCTAssertEqual(BinType.classify("Empty Standard General Waste"), .generalWaste)
        XCTAssertEqual(BinType.classify("Residual Waste"), .generalWaste)
        XCTAssertEqual(BinType.classify("Household Refuse"), .generalWaste)
        XCTAssertEqual(BinType.classify("Non-Recyclable Waste"), .generalWaste)
        XCTAssertEqual(BinType.classify("Black Bin"), .generalWaste)
        XCTAssertEqual(BinType.classify("Grey Bin"), .generalWaste)
        XCTAssertEqual(BinType.classify("Rubbish"), .generalWaste)
    }

    func testClassifyFoodWaste() {
        XCTAssertEqual(BinType.classify("Food Waste"), .foodWaste)
        XCTAssertEqual(BinType.classify("Food Caddy"), .foodWaste)
        XCTAssertEqual(BinType.classify("Organic Waste"), .foodWaste)
    }

    func testClassifyGardenWaste() {
        XCTAssertEqual(BinType.classify("Garden Waste"), .gardenWaste)
        XCTAssertEqual(BinType.classify("Green Waste"), .gardenWaste)
        XCTAssertEqual(BinType.classify("Yard Waste"), .gardenWaste)
    }

    func testClassifyPaperCard() {
        XCTAssertEqual(BinType.classify("Paper and Card"), .paperCard)
        XCTAssertEqual(BinType.classify("Paper & Cardboard"), .paperCard)
        XCTAssertEqual(BinType.classify("Fibre Collection"), .paperCard)
    }

    func testClassifyGlass() {
        XCTAssertEqual(BinType.classify("Glass Collection"), .glass)
        XCTAssertEqual(BinType.classify("Glass Bottles"), .glass)
    }

    func testClassifyOther() {
        XCTAssertEqual(BinType.classify("Something Completely Unknown"), .other)
    }

    // MARK: - BinCollection

    func testDayLabelToday() {
        let today = Calendar.current.startOfDay(for: Date())
        let collection = BinCollection(
            id: UUID(), rawType: "Recycling", binType: .recycling,
            collectionDate: today
        )
        XCTAssertEqual(collection.dayLabel, "Today")
        XCTAssertEqual(collection.daysUntil, 0)
        XCTAssertTrue(collection.isUrgent)
    }

    func testDayLabelTomorrow() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!
        let collection = BinCollection(
            id: UUID(), rawType: "General Waste", binType: .generalWaste,
            collectionDate: tomorrow
        )
        XCTAssertEqual(collection.dayLabel, "Tomorrow")
        XCTAssertEqual(collection.daysUntil, 1)
        XCTAssertTrue(collection.isUrgent)
    }

    func testDayLabelWeekday() {
        // 3 days from now should show day name
        let future = Calendar.current.date(byAdding: .day, value: 3, to: Calendar.current.startOfDay(for: Date()))!
        let collection = BinCollection(
            id: UUID(), rawType: "Food Waste", binType: .foodWaste,
            collectionDate: future
        )
        XCTAssertFalse(collection.isUrgent)
        XCTAssertEqual(collection.daysUntil, 3)
        // Should be a day name like "Monday", "Tuesday", etc.
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        XCTAssertEqual(collection.dayLabel, formatter.string(from: future))
    }

    func testDayLabelFarFuture() {
        // 10 days from now should show date
        let future = Calendar.current.date(byAdding: .day, value: 10, to: Calendar.current.startOfDay(for: Date()))!
        let collection = BinCollection(
            id: UUID(), rawType: "Garden", binType: .gardenWaste,
            collectionDate: future
        )
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        XCTAssertEqual(collection.dayLabel, formatter.string(from: future))
    }

    // MARK: - BinType Properties

    func testBinTypeIcons() {
        XCTAssertEqual(BinType.recycling.icon, "arrow.3.trianglepath")
        XCTAssertEqual(BinType.generalWaste.icon, "trash")
        XCTAssertEqual(BinType.foodWaste.icon, "carrot")
        XCTAssertEqual(BinType.gardenWaste.icon, "leaf")
    }

    func testBinTypeColors() {
        for binType in BinType.allCases {
            let components = binType.colorComponents
            XCTAssertTrue(components.r >= 0 && components.r <= 1)
            XCTAssertTrue(components.g >= 0 && components.g <= 1)
            XCTAssertTrue(components.b >= 0 && components.b <= 1)
        }
    }

    // MARK: - Codable

    func testBinCollectionCodable() throws {
        let collection = BinCollection(
            id: UUID(),
            rawType: "Empty Standard Recycling",
            binType: .recycling,
            collectionDate: Date()
        )
        let data = try JSONEncoder().encode(collection)
        let decoded = try JSONDecoder().decode(BinCollection.self, from: data)
        XCTAssertEqual(collection.rawType, decoded.rawType)
        XCTAssertEqual(collection.binType, decoded.binType)
    }

    func testAddressCodable() throws {
        let address = Address(uprn: "100000123456", address: "1 High Street, N1 2AB")
        let data = try JSONEncoder().encode(address)
        let decoded = try JSONDecoder().decode(Address.self, from: data)
        XCTAssertEqual(address.uprn, decoded.uprn)
        XCTAssertEqual(address.address, decoded.address)
    }
}
