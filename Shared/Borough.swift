import Foundation
import SwiftUI

enum Borough: String, Codable, CaseIterable, Identifiable {
    // Inner London
    case camden = "Camden"
    case greenwich = "Greenwich"
    case hackney = "Hackney"
    case hammersmithAndFulham = "Hammersmith and Fulham"
    case islington = "Islington"
    case kensingtonAndChelsea = "Kensington and Chelsea"
    case lambeth = "Lambeth"
    case lewisham = "Lewisham"
    case southwark = "Southwark"
    case towerHamlets = "Tower Hamlets"
    case wandsworth = "Wandsworth"
    case westminster = "Westminster"

    // Outer London
    case barkingAndDagenham = "Barking and Dagenham"
    case barnet = "Barnet"
    case bexley = "Bexley"
    case brent = "Brent"
    case bromley = "Bromley"
    case croydon = "Croydon"
    case ealing = "Ealing"
    case enfield = "Enfield"
    case haringey = "Haringey"
    case harrow = "Harrow"
    case havering = "Havering"
    case hillingdon = "Hillingdon"
    case hounslow = "Hounslow"
    case kingstonUponThames = "Kingston upon Thames"
    case merton = "Merton"
    case newham = "Newham"
    case redbridge = "Redbridge"
    case richmondUponThames = "Richmond upon Thames"
    case sutton = "Sutton"
    case walthamForest = "Waltham Forest"

    // City of London
    case cityOfLondon = "City of London"

    var id: String { rawValue }
    var displayName: String { rawValue }

    /// Whether this borough has a direct HTTP API (no Selenium/browser needed)
    var isSupported: Bool {
        switch self {
        // HTTP-based councils (16 boroughs)
        case .brent, .ealing, .greenwich, .hackney, .haringey, .harrow,
             .havering, .hounslow, .lambeth, .camden, .islington, .merton,
             .newham, .southwark, .sutton, .wandsworth:
            return true
        // Selenium-only or not in UKBinCollectionData
        default:
            return false
        }
    }

    /// What input this borough's API needs from the user.
    /// All boroughs now use postcode-based input - no manual UPRN entry required.
    var inputRequirement: BoroughInputRequirement {
        switch self {
        case .brent, .greenwich, .hackney:
            // These councils accept postcode + house number directly
            return .postcodeAndNumber
        case .ealing, .haringey, .harrow, .havering, .hounslow, .lambeth,
             .camden, .islington, .merton, .newham, .southwark, .sutton, .wandsworth:
            // These councils need a UPRN internally, but we resolve it
            // automatically via address lookup from the user's postcode
            return .postcodeAndAddressSelect
        default:
            return .postcodeAndAddressSelect
        }
    }

    static var supported: [Borough] {
        allCases.filter(\.isSupported).sorted { $0.displayName < $1.displayName }
    }

    static var unsupported: [Borough] {
        allCases.filter { !$0.isSupported }.sorted { $0.displayName < $1.displayName }
    }

    /// Attempt to match an `admin_district` string from the postcodes.io API to a Borough case.
    /// The API typically returns names like "Ealing", "Camden", "Tower Hamlets" which match
    /// our rawValues directly. This also handles known edge cases.
    static func fromAdminDistrict(_ district: String) -> Borough? {
        // Direct match by rawValue first (covers most cases)
        if let borough = Borough(rawValue: district) {
            return borough
        }

        // Normalised matching for edge cases
        let normalised = district.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // The postcodes.io API may return "Royal Borough of ..." or "London Borough of ..."
        // prefixes in some edge cases, so strip those.
        let stripped = normalised
            .replacingOccurrences(of: "royal borough of ", with: "")
            .replacingOccurrences(of: "london borough of ", with: "")
            .trimmingCharacters(in: .whitespaces)

        for borough in Borough.allCases {
            if borough.rawValue.lowercased() == stripped {
                return borough
            }
        }

        // Handle specific known mismatches
        switch stripped {
        case "city of london":
            return .cityOfLondon
        default:
            return nil
        }
    }
}

enum BoroughInputRequirement: String, Codable {
    case postcodeAndAddressSelect  // Enter postcode, pick address from list (resolves UPRN automatically)
    case postcodeAndNumber         // Enter postcode + house number directly

    var needsPostcode: Bool { true }
    var needsAddressSelection: Bool { self == .postcodeAndAddressSelect }
    var needsHouseNumber: Bool { self == .postcodeAndNumber }
}
