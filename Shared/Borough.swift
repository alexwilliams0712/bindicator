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

    /// What input this borough's API needs
    var inputRequirement: BoroughInputRequirement {
        switch self {
        case .brent, .greenwich, .hackney:
            return .postcodeAndNumber
        case .islington:
            return .postcodeAndUPRN
        case .ealing, .haringey, .harrow, .havering, .hounslow, .lambeth,
             .camden, .merton, .newham, .southwark, .sutton, .wandsworth:
            return .uprn
        default:
            return .uprn
        }
    }

    static var supported: [Borough] {
        allCases.filter(\.isSupported).sorted { $0.displayName < $1.displayName }
    }

    static var unsupported: [Borough] {
        allCases.filter { !$0.isSupported }.sorted { $0.displayName < $1.displayName }
    }
}

enum BoroughInputRequirement: String, Codable {
    case uprn               // Needs UPRN only
    case postcodeAndUPRN    // Needs postcode + UPRN
    case postcodeAndNumber  // Needs postcode + house number

    var needsPostcode: Bool { self != .uprn }
    var needsUPRN: Bool { self == .uprn || self == .postcodeAndUPRN }
    var needsHouseNumber: Bool { self == .postcodeAndNumber }
}
