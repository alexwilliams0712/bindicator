import XCTest
@testable import Bindicator

final class BoroughTests: XCTestCase {
    func testAllBoroughsHaveDisplayNames() {
        for borough in Borough.allCases {
            XCTAssertFalse(borough.displayName.isEmpty, "\(borough) should have a display name")
        }
    }

    func testBoroughCount() {
        XCTAssertEqual(Borough.allCases.count, 33, "Should have 33 London boroughs including City of London")
    }

    func testSupportedBoroughCount() {
        // 16 HTTP-based boroughs
        XCTAssertEqual(Borough.supported.count, 16)
    }

    func testUnsupportedBoroughCount() {
        // 33 - 16 = 17 unsupported
        XCTAssertEqual(Borough.unsupported.count, 17)
    }

    func testBoroughCodable() throws {
        let borough = Borough.barnet
        let data = try JSONEncoder().encode(borough)
        let decoded = try JSONDecoder().decode(Borough.self, from: data)
        XCTAssertEqual(borough, decoded)
    }

    func testBoroughDisplayNames() {
        XCTAssertEqual(Borough.barkingAndDagenham.displayName, "Barking and Dagenham")
        XCTAssertEqual(Borough.kensingtonAndChelsea.displayName, "Kensington and Chelsea")
        XCTAssertEqual(Borough.cityOfLondon.displayName, "City of London")
    }

    func testSupportedBoroughs() {
        let expected: [Borough] = [
            .brent, .ealing, .greenwich, .hackney, .haringey, .harrow,
            .havering, .hounslow, .lambeth, .camden, .islington, .merton,
            .newham, .southwark, .sutton, .wandsworth
        ]
        for borough in expected {
            XCTAssertTrue(borough.isSupported, "\(borough.displayName) should be supported")
        }
    }

    func testSeleniumOnlyBoroughsAreUnsupported() {
        let seleniumOnly: [Borough] = [
            .barkingAndDagenham, .barnet, .bexley, .bromley, .croydon,
            .enfield, .hillingdon, .kingstonUponThames, .lewisham,
            .redbridge, .richmondUponThames, .walthamForest
        ]
        for borough in seleniumOnly {
            XCTAssertFalse(borough.isSupported, "\(borough.displayName) should be unsupported (Selenium)")
        }
    }

    func testMissingBoroughsAreUnsupported() {
        let missing: [Borough] = [
            .towerHamlets, .westminster, .kensingtonAndChelsea,
            .hammersmithAndFulham, .cityOfLondon
        ]
        for borough in missing {
            XCTAssertFalse(borough.isSupported, "\(borough.displayName) should be unsupported (missing)")
        }
    }

    func testInputRequirements() {
        // UPRN-only boroughs
        XCTAssertEqual(Borough.harrow.inputRequirement, .uprn)
        XCTAssertEqual(Borough.ealing.inputRequirement, .uprn)
        XCTAssertEqual(Borough.lambeth.inputRequirement, .uprn)
        XCTAssertEqual(Borough.camden.inputRequirement, .uprn)

        // Postcode + UPRN boroughs
        XCTAssertEqual(Borough.islington.inputRequirement, .postcodeAndUPRN)

        // Postcode + house number boroughs
        XCTAssertEqual(Borough.brent.inputRequirement, .postcodeAndNumber)
        XCTAssertEqual(Borough.greenwich.inputRequirement, .postcodeAndNumber)
        XCTAssertEqual(Borough.hackney.inputRequirement, .postcodeAndNumber)
    }

    func testSortedBoroughs() {
        let supported = Borough.supported
        for i in 1..<supported.count {
            XCTAssertTrue(supported[i-1].displayName < supported[i].displayName,
                          "Supported boroughs should be sorted alphabetically")
        }
    }
}
