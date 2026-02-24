import Foundation
import SwiftUI

enum BinServiceError: LocalizedError {
    case unsupportedBorough(String)
    case networkError(Error)
    case parsingError(String)
    case noCollectionsFound
    case missingInput(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedBorough(let name): return "\(name) is not yet supported."
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        case .parsingError(let msg): return "Could not read collection data: \(msg)"
        case .noCollectionsFound: return "No upcoming collections found."
        case .missingInput(let field): return "Please provide your \(field)."
        }
    }
}

actor BinCollectionService {
    static let shared = BinCollectionService()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    func fetchCollections(
        borough: Borough,
        postcode: String,
        uprn: String?,
        houseNumber: String?
    ) async throws -> [BinCollection] {
        guard borough.isSupported else {
            throw BinServiceError.unsupportedBorough(borough.displayName)
        }

        let raw: [BinCollection]
        switch borough {
        case .harrow:       raw = try await fetchHarrow(uprn: uprn ?? "")
        case .ealing:       raw = try await fetchEaling(uprn: uprn ?? "")
        case .lambeth:      raw = try await fetchLambeth(uprn: uprn ?? "")
        case .havering:     raw = try await fetchHavering(uprn: uprn ?? "")
        case .camden:       raw = try await fetchCamden(uprn: uprn ?? "")
        case .haringey:     raw = try await fetchHaringey(uprn: uprn ?? "")
        case .newham:       raw = try await fetchNewham(uprn: uprn ?? "")
        case .southwark:    raw = try await fetchSouthwark(uprn: uprn ?? "")
        case .wandsworth:   raw = try await fetchWandsworth(uprn: uprn ?? "")
        case .merton:       raw = try await fetchMerton(uprn: uprn ?? "")
        case .sutton:       raw = try await fetchSutton(uprn: uprn ?? "")
        case .islington:    raw = try await fetchIslington(postcode: postcode, uprn: uprn ?? "")
        case .hounslow:     raw = try await fetchHounslow(uprn: uprn ?? "")
        case .hackney:      raw = try await fetchHackney(postcode: postcode, houseNumber: houseNumber ?? "")
        case .greenwich:    raw = try await fetchGreenwich(postcode: postcode, houseNumber: houseNumber ?? "")
        case .brent:        raw = try await fetchBrent(postcode: postcode, houseNumber: houseNumber ?? "")
        default:
            throw BinServiceError.unsupportedBorough(borough.displayName)
        }

        let today = Calendar.current.startOfDay(for: Date())
        let filtered = raw.filter { $0.collectionDate >= today }
            .sorted { $0.collectionDate < $1.collectionDate }

        if filtered.isEmpty {
            throw BinServiceError.noCollectionsFound
        }
        return filtered
    }

    // MARK: - Harrow (cleanest JSON API)

    private func fetchHarrow(uprn: String) async throws -> [BinCollection] {
        guard !uprn.isEmpty else { throw BinServiceError.missingInput("UPRN") }
        let url = URL(string: "https://www.harrow.gov.uk/ajax/bins?u=\(uprn)&r=\(Int.random(in: 10000...99999))")!
        let (data, _) = try await request(url: url)
        return try parseHarrowJSON(data)
    }

    private func parseHarrowJSON(_ data: Data) throws -> [BinCollection] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [String: Any],
              let collections = results["collections"] as? [String: Any],
              let all = collections["all"] as? [[String: Any]]
        else { throw BinServiceError.parsingError("Unexpected Harrow response format") }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let altFormatter = DateFormatter()
        altFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"

        return all.compactMap { entry in
            guard let binType = entry["binType"] as? String,
                  let dateStr = entry["eventTime"] as? String,
                  let date = formatter.date(from: dateStr) ?? altFormatter.date(from: dateStr)
            else { return nil }
            return BinCollection(id: UUID(), rawType: binType, binType: BinType.classify(binType), collectionDate: date)
        }
    }

    // MARK: - Ealing (JSON POST)

    private func fetchEaling(uprn: String) async throws -> [BinCollection] {
        guard !uprn.isEmpty else { throw BinServiceError.missingInput("UPRN") }
        let url = URL(string: "https://www.ealing.gov.uk/site/custom_scripts/WasteCollectionWS/home/FindCollection")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["uprn": uprn])
        let (data, _) = try await session.data(for: req)
        return try parseEalingJSON(data)
    }

    private func parseEalingJSON(_ data: Data) throws -> [BinCollection] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let param2 = json["param2"] as? [[String: Any]]
        else { throw BinServiceError.parsingError("Unexpected Ealing response format") }

        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"

        return param2.compactMap { entry in
            guard let service = entry["Service"] as? String,
                  let dateStr = entry["collectionDateString"] as? String,
                  let date = formatter.date(from: dateStr)
            else { return nil }
            return BinCollection(id: UUID(), rawType: service, binType: BinType.classify(service), collectionDate: date)
        }
    }

    // MARK: - Lambeth (JSON POST)

    private func fetchLambeth(uprn: String) async throws -> [BinCollection] {
        guard !uprn.isEmpty else { throw BinServiceError.missingInput("UPRN") }
        let url = URL(string: "https://wasteservice.lambeth.gov.uk/WhitespaceComms/GetServicesByUprn")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["uprn": uprn, "includeEventTypes": false, "includeFlags": true]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await session.data(for: req)
        return try parseLambethJSON(data)
    }

    private func parseLambethJSON(_ data: Data) throws -> [BinCollection] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let services = json["SiteServices"] as? [[String: Any]]
        else { throw BinServiceError.parsingError("Unexpected Lambeth response format") }

        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"

        return services.compactMap { service in
            guard let dateStr = service["NextCollectionDate"] as? String,
                  let date = formatter.date(from: dateStr),
                  let container = service["Container"] as? [String: Any]
            else { return nil }

            let displayPhrase = (container["DisplayPhrase"] as? String) ?? ""
            let name = (container["Name"] as? String) ?? displayPhrase
            if displayPhrase.lowercased().contains("commercial") { return nil }
            return BinCollection(id: UUID(), rawType: name, binType: BinType.classify(name), collectionDate: date)
        }
    }

    // MARK: - Havering (Azure API)

    private func fetchHavering(uprn: String) async throws -> [BinCollection] {
        guard !uprn.isEmpty else { throw BinServiceError.missingInput("UPRN") }
        let url = URL(string: "https://lbhapiprod.azure-api.net/whitespace/GetCollectionByUprnAndDate")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("2ea6a75f9ea34bb58d299a0c9f84e72e", forHTTPHeaderField: "Ocp-Apim-Subscription-Key")

        let dateStr = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let body: [String: Any] = [
            "getCollectionByUprnAndDate": [
                "getCollectionByUprnAndDateInput": [
                    "uprn": uprn,
                    "nextCollectionFromDate": String(dateStr)
                ]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await session.data(for: req)
        return try parseHaveringJSON(data)
    }

    private func parseHaveringJSON(_ data: Data) throws -> [BinCollection] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = json["getCollectionByUprnAndDateResponse"] as? [String: Any],
              let result = response["getCollectionByUprnAndDateResult"] as? [String: Any],
              let collections = result["Collections"] as? [[String: Any]]
        else { throw BinServiceError.parsingError("Unexpected Havering response format") }

        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy HH:mm:ss"

        return collections.compactMap { entry in
            guard let service = entry["service"] as? String,
                  let dateStr = entry["date"] as? String,
                  let date = formatter.date(from: dateStr)
            else { return nil }
            return BinCollection(id: UUID(), rawType: service, binType: BinType.classify(service), collectionDate: date)
        }
    }

    // MARK: - Camden (HTML scraper)

    private func fetchCamden(uprn: String) async throws -> [BinCollection] {
        guard !uprn.isEmpty else { throw BinServiceError.missingInput("UPRN") }
        let url = URL(string: "https://environmentservices.camden.gov.uk/property/\(uprn)")!
        let (data, _) = try await request(url: url)
        guard let html = String(data: data, encoding: .utf8) else {
            throw BinServiceError.parsingError("Invalid HTML response")
        }
        return parseCamdenHTML(html)
    }

    private func parseCamdenHTML(_ html: String) -> [BinCollection] {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        var results: [BinCollection] = []

        let serviceBlocks = html.components(separatedBy: "service-name")
        for block in serviceBlocks.dropFirst() {
            guard let nameEnd = block.range(of: "</h3>") ?? block.range(of: "</H3>"),
                  let nameStart = block.range(of: ">")
            else { continue }

            let name = String(block[nameStart.upperBound..<nameEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

            if let dateMatch = block.range(of: "\\d{2}/\\d{2}/\\d{4}", options: .regularExpression) {
                let dateStr = String(block[dateMatch])
                if let date = formatter.date(from: dateStr) {
                    results.append(BinCollection(id: UUID(), rawType: name, binType: BinType.classify(name), collectionDate: date))
                }
            }
        }
        return results
    }

    // MARK: - Haringey (HTML scraper)

    private func fetchHaringey(uprn: String) async throws -> [BinCollection] {
        guard !uprn.isEmpty else { throw BinServiceError.missingInput("UPRN") }
        let url = URL(string: "https://wastecollections.haringey.gov.uk/property/\(uprn)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        let (data, _) = try await session.data(for: req)
        guard let html = String(data: data, encoding: .utf8) else {
            throw BinServiceError.parsingError("Invalid HTML response")
        }
        return parseCamdenHTML(html) // Same HTML structure as Camden
    }

    // MARK: - Newham (HTML scraper)

    private func fetchNewham(uprn: String) async throws -> [BinCollection] {
        guard !uprn.isEmpty else { throw BinServiceError.missingInput("UPRN") }
        let url = URL(string: "https://bincollection.newham.gov.uk/Details/Index/\(uprn)")!
        let (data, _) = try await request(url: url)
        guard let html = String(data: data, encoding: .utf8) else {
            throw BinServiceError.parsingError("Invalid HTML response")
        }
        return parseNewhamHTML(html)
    }

    private func parseNewhamHTML(_ html: String) -> [BinCollection] {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        var results: [BinCollection] = []

        let cards = html.components(separatedBy: "card h-100")
        for card in cards.dropFirst() {
            var name = "Unknown"
            if card.contains("card-recycling") || card.lowercased().contains("recycling") {
                name = "Recycling"
            } else if card.lowercased().contains("domestic") || card.lowercased().contains("general") {
                name = "General Waste"
            } else if card.lowercased().contains("food") {
                name = "Food Waste"
            } else if card.lowercased().contains("garden") {
                name = "Garden Waste"
            }

            if let headerRange = card.range(of: "<b>"),
               let headerEnd = card.range(of: "</b>", range: headerRange.upperBound..<card.endIndex) {
                let headerText = String(card[headerRange.upperBound..<headerEnd.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !headerText.isEmpty { name = headerText }
            }

            if let dateMatch = card.range(of: "\\d{2}/\\d{2}/\\d{4}", options: .regularExpression) {
                let dateStr = String(card[dateMatch])
                if let date = formatter.date(from: dateStr) {
                    results.append(BinCollection(id: UUID(), rawType: name, binType: BinType.classify(name), collectionDate: date))
                }
            }
        }
        return results
    }

    // MARK: - Southwark (HTML scraper)

    private func fetchSouthwark(uprn: String) async throws -> [BinCollection] {
        guard !uprn.isEmpty else { throw BinServiceError.missingInput("UPRN") }
        let url = URL(string: "https://services.southwark.gov.uk/bins/lookup/\(uprn)")!
        let (data, _) = try await request(url: url)
        guard let html = String(data: data, encoding: .utf8) else {
            throw BinServiceError.parsingError("Invalid HTML response")
        }
        return parseSouthwarkHTML(html)
    }

    private func parseSouthwarkHTML(_ html: String) -> [BinCollection] {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, d MMMM yyyy"
        formatter.locale = Locale(identifier: "en_GB")
        var results: [BinCollection] = []

        let sections: [(String, String)] = [
            ("recyclingCollectionTitle", "Recycling"),
            ("refuseCollectionTitle", "General Waste"),
            ("domesticFoodCollectionTitle", "Food Waste"),
            ("communalFoodCollectionTitle", "Communal Food Waste"),
            ("recyclingCommunalCollectionTitle", "Communal Recycling"),
            ("refuseCommunalCollectionTitle", "Communal General Waste"),
        ]

        for (sectionId, name) in sections {
            guard html.contains(sectionId) else { continue }
            if let sectionRange = html.range(of: sectionId) {
                let after = String(html[sectionRange.upperBound...])
                // Look for date pattern like "Wed, 15 March 2025"
                if let dateMatch = after.range(of: "[A-Z][a-z]{2}, \\d{1,2} [A-Z][a-z]+ \\d{4}", options: .regularExpression) {
                    let dateStr = String(after[dateMatch])
                    if let date = formatter.date(from: dateStr) {
                        results.append(BinCollection(id: UUID(), rawType: name, binType: BinType.classify(name), collectionDate: date))
                    }
                }
            }
        }
        return results
    }

    // MARK: - Wandsworth (HTML scraper)

    private func fetchWandsworth(uprn: String) async throws -> [BinCollection] {
        guard !uprn.isEmpty else { throw BinServiceError.missingInput("UPRN") }
        let url = URL(string: "https://www.wandsworth.gov.uk/my-property/?UPRN=\(uprn)")!
        let (data, _) = try await request(url: url)
        guard let html = String(data: data, encoding: .utf8) else {
            throw BinServiceError.parsingError("Invalid HTML response")
        }
        return parseWandsworthHTML(html)
    }

    private func parseWandsworthHTML(_ html: String) -> [BinCollection] {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMMM yyyy"
        formatter.locale = Locale(identifier: "en_GB")
        var results: [BinCollection] = []

        let headings = html.components(separatedBy: "collection-heading")
        for heading in headings.dropFirst() {
            guard let nameEnd = heading.range(of: "</h4>") ?? heading.range(of: "</H4>"),
                  let nameStart = heading.range(of: ">")
            else { continue }

            let name = String(heading[nameStart.upperBound..<nameEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

            // Look for date: "Wednesday 15 March 2025"
            if let dateMatch = heading.range(of: "[A-Z][a-z]+ \\d{1,2} [A-Z][a-z]+ \\d{4}", options: .regularExpression) {
                let dateStr = String(heading[dateMatch])
                if let date = formatter.date(from: dateStr) {
                    // Name might be slash-separated like "Recycling/Food"
                    let binNames = name.components(separatedBy: "/")
                    for binName in binNames {
                        let trimmed = binName.trimmingCharacters(in: .whitespaces)
                        results.append(BinCollection(id: UUID(), rawType: trimmed, binType: BinType.classify(trimmed), collectionDate: date))
                    }
                }
            }
        }
        return results
    }

    // MARK: - Merton (HTML with polling)

    private func fetchMerton(uprn: String) async throws -> [BinCollection] {
        guard !uprn.isEmpty else { throw BinServiceError.missingInput("UPRN") }
        let url = URL(string: "https://fixmystreet.merton.gov.uk/waste/\(uprn)?page_loading=1")!
        var req = URLRequest(url: url)
        req.setValue("fetch", forHTTPHeaderField: "x-requested-with")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

        var html = ""
        for _ in 0..<10 {
            let (data, _) = try await session.data(for: req)
            html = String(data: data, encoding: .utf8) ?? ""
            if !html.contains("loading-indicator") && !html.contains("Loading your bin days") { break }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        return parseMertonHTML(html)
    }

    private func parseMertonHTML(_ html: String) -> [BinCollection] {
        var results: [BinCollection] = []
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")

        let serviceBlocks = html.components(separatedBy: "waste-service-name")
        for block in serviceBlocks.dropFirst() {
            guard let nameEnd = block.range(of: "</h3>") ?? block.range(of: "</H3>"),
                  let nameStart = block.range(of: ">")
            else { continue }

            let name = String(block[nameStart.upperBound..<nameEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

            // Look for "Next collection" followed by date
            if let nextRange = block.range(of: "Next collection", options: .caseInsensitive) {
                let after = String(block[nextRange.upperBound...])
                // Try "Saturday 15 November" format
                if let dateMatch = after.range(of: "[A-Z][a-z]+ \\d{1,2} [A-Z][a-z]+", options: .regularExpression) {
                    let dateStr = String(after[dateMatch])
                    formatter.dateFormat = "EEEE d MMMM"
                    if var date = formatter.date(from: dateStr) {
                        // Add current year
                        let year = Calendar.current.component(.year, from: Date())
                        date = Calendar.current.date(bySetting: .year, value: year, of: date) ?? date
                        if date < Calendar.current.startOfDay(for: Date()) {
                            date = Calendar.current.date(bySetting: .year, value: year + 1, of: date) ?? date
                        }
                        results.append(BinCollection(id: UUID(), rawType: name, binType: BinType.classify(name), collectionDate: date))
                    }
                }
            }
        }
        return results
    }

    // MARK: - Sutton (HTML with polling)

    private func fetchSutton(uprn: String) async throws -> [BinCollection] {
        guard !uprn.isEmpty else { throw BinServiceError.missingInput("UPRN") }
        let url = URL(string: "https://waste-services.sutton.gov.uk/waste/\(uprn)")!
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        var html = ""
        var delay: UInt64 = 2_000_000_000
        for _ in 0..<5 {
            let (data, _) = try await session.data(for: req)
            html = String(data: data, encoding: .utf8) ?? ""
            if !html.contains("Loading your bin days") { break }
            try await Task.sleep(nanoseconds: delay)
            delay *= 2
        }
        return parseSuttonHTML(html)
    }

    private func parseSuttonHTML(_ html: String) -> [BinCollection] {
        // Same structure as Merton
        return parseMertonHTML(html)
    }

    // MARK: - Islington (HTML with day-of-week)

    private func fetchIslington(postcode: String, uprn: String) async throws -> [BinCollection] {
        guard !postcode.isEmpty else { throw BinServiceError.missingInput("postcode") }
        let encoded = postcode.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? postcode
        let url = URL(string: "https://www.islington.gov.uk/your-area?Postcode=\(encoded)&Uprn=\(uprn)")!
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await session.data(for: req)
        guard let html = String(data: data, encoding: .utf8) else {
            throw BinServiceError.parsingError("Invalid HTML response")
        }
        return parseIslingtonHTML(html)
    }

    private func parseIslingtonHTML(_ html: String) -> [BinCollection] {
        var results: [BinCollection] = []
        let days = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]

        // Look for waste collection section
        guard let wasteRange = html.range(of: "Waste and recycling", options: .caseInsensitive) else {
            return results
        }
        let after = String(html[wasteRange.upperBound...])

        // Find list items describing collection days
        let items = after.components(separatedBy: "<li")
        for item in items.prefix(10) {
            let text = item.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .lowercased()

            var binName = "Unknown"
            if text.contains("recycl") { binName = "Recycling" }
            else if text.contains("food") { binName = "Food Waste" }
            else if text.contains("garden") { binName = "Garden Waste" }
            else if text.contains("general") || text.contains("refuse") || text.contains("rubbish") { binName = "General Waste" }
            else { continue }

            for day in days {
                if text.contains(day) {
                    if let nextDate = nextOccurrence(of: day) {
                        results.append(BinCollection(id: UUID(), rawType: binName, binType: BinType.classify(binName), collectionDate: nextDate))
                    }
                    break
                }
            }
        }
        return results
    }

    // MARK: - Hounslow (session-based multi-step)

    private func fetchHounslow(uprn: String) async throws -> [BinCollection] {
        guard !uprn.isEmpty else { throw BinServiceError.missingInput("UPRN") }

        // Step 1: Get session ID
        let authURL = URL(string: "https://my.hounslow.gov.uk/authapi/isauthenticated?uri=https%253A%252F%252Fmy.hounslow.gov.uk%252Fservice%252FWaste_and_recycling_collections&hostname=my.hounslow.gov.uk&withCredentials=true")!
        let (authData, _) = try await request(url: authURL)
        guard let authJSON = try? JSONSerialization.jsonObject(with: authData) as? [String: Any],
              let sessionId = authJSON["auth-session"] as? String
        else { throw BinServiceError.parsingError("Could not get Hounslow session") }

        // Step 2: Get Bartec token
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        let tokenURL = URL(string: "https://my.hounslow.gov.uk/apibroker/runLookup?id=655f4290810cf&repeat_against=&noRetry=true&getOnlyTokens=undefined&log_id=&app_name=AF-Renderer::Self&_=\(ts)&sid=\(sessionId)")!
        var tokenReq = URLRequest(url: tokenURL)
        tokenReq.httpMethod = "POST"
        tokenReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        tokenReq.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        tokenReq.setValue("https://my.hounslow.gov.uk/fillform/?iframe_id=fillform-frame-1&db_id=", forHTTPHeaderField: "Referer")
        tokenReq.httpBody = "{}".data(using: .utf8)
        let (tokenData, _) = try await session.data(for: tokenReq)

        guard let tokenJSON = try? JSONSerialization.jsonObject(with: tokenData) as? [String: Any],
              let integration = tokenJSON["integration"] as? [String: Any],
              let transformed = integration["transformed"] as? [String: Any],
              let rowsData = transformed["rows_data"] as? [String: Any],
              let row0 = rowsData["0"] as? [String: Any],
              let bartecToken = row0["bartecToken"] as? String
        else { throw BinServiceError.parsingError("Could not get Hounslow Bartec token") }

        // Step 3: Get collections
        let ts2 = Int(Date().timeIntervalSince1970 * 1000)
        let collURL = URL(string: "https://my.hounslow.gov.uk/apibroker/runLookup?id=659eb39b66d5a&repeat_against=&noRetry=false&getOnlyTokens=undefined&log_id=&app_name=AF-Renderer::Self&_=\(ts2)&sid=\(sessionId)")!
        var collReq = URLRequest(url: collURL)
        collReq.httpMethod = "POST"
        collReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        collReq.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        collReq.setValue("https://my.hounslow.gov.uk/fillform/?iframe_id=fillform-frame-1&db_id=", forHTTPHeaderField: "Referer")

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let fromDate = dateFormatter.string(from: Date())
        let toDate = dateFormatter.string(from: Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date())

        let collBody: [String: Any] = [
            "formValues": [
                "Your address": [
                    "searchUPRN": ["value": uprn],
                    "bartecToken": ["value": bartecToken],
                    "searchFromDate": ["value": fromDate],
                    "searchToDate": ["value": toDate]
                ]
            ]
        ]
        collReq.httpBody = try JSONSerialization.data(withJSONObject: collBody)
        let (collData, _) = try await session.data(for: collReq)

        guard let collJSON = try? JSONSerialization.jsonObject(with: collData) as? [String: Any],
              let integ = collJSON["integration"] as? [String: Any],
              let trans = integ["transformed"] as? [String: Any],
              let rows = trans["rows_data"] as? [String: Any],
              let r0 = rows["0"] as? [String: Any],
              let jobsStr = r0["jobsJSON"] as? String,
              let jobsData = jobsStr.data(using: .utf8),
              let jobs = try? JSONSerialization.jsonObject(with: jobsData) as? [[String: Any]]
        else { throw BinServiceError.parsingError("Could not parse Hounslow collections") }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        return jobs.compactMap { job in
            guard let jobType = job["jobType"] as? String,
                  let dateStr = job["jobDate"] as? String,
                  let date = df.date(from: dateStr)
            else { return nil }
            return BinCollection(id: UUID(), rawType: jobType, binType: BinType.classify(jobType), collectionDate: date)
        }
    }

    // MARK: - Hackney (multi-step API)

    private func fetchHackney(postcode: String, houseNumber: String) async throws -> [BinCollection] {
        guard !postcode.isEmpty else { throw BinServiceError.missingInput("postcode") }

        let baseURL = "https://waste-api-hackney-live.ieg4.net/f806d91c-e133-43a6-ba9a-c0ae4f4cccf6"

        // Step 1: Address search
        let searchURL = URL(string: "\(baseURL)/property/opensearch")!
        var searchReq = URLRequest(url: searchURL)
        searchReq.httpMethod = "POST"
        searchReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        searchReq.httpBody = try JSONSerialization.data(withJSONObject: ["Postcode": postcode])
        let (searchData, _) = try await session.data(for: searchReq)

        guard let searchJSON = try? JSONSerialization.jsonObject(with: searchData) as? [String: Any],
              let addresses = searchJSON["addressSummaries"] as? [[String: Any]]
        else { throw BinServiceError.parsingError("Could not search Hackney addresses") }

        // Find matching address
        let match = addresses.first { addr in
            guard let summary = addr["summary"] as? String else { return false }
            return houseNumber.isEmpty || summary.lowercased().contains(houseNumber.lowercased())
        } ?? addresses.first

        guard let systemId = match?["systemId"] as? String else {
            throw BinServiceError.parsingError("No matching address found in Hackney")
        }

        // Step 2: Get property bins
        let propURL = URL(string: "\(baseURL)/alloywastepages/getproperty/\(systemId)")!
        let (propData, _) = try await request(url: propURL)
        guard let propJSON = try? JSONSerialization.jsonObject(with: propData) as? [String: Any],
              let fields = propJSON["providerSpecificFields"] as? [String: Any],
              let binIds = (fields["attributes_wasteContainersAssignableWasteContainers"] as? String)?.components(separatedBy: ",")
        else { throw BinServiceError.parsingError("Could not get Hackney property bins") }

        // Step 3+4+5: For each bin, get type and schedule
        var results: [BinCollection] = []
        for binId in binIds {
            let trimmedId = binId.trimmingCharacters(in: .whitespaces)

            // Get bin type
            let binURL = URL(string: "\(baseURL)/alloywastepages/getbin/\(trimmedId)")!
            let (binData, _) = try await request(url: binURL)
            let binJSON = try? JSONSerialization.jsonObject(with: binData) as? [String: Any]
            let binName = (binJSON?["subTitle"] as? String) ?? "Unknown"

            // Get collection schedule
            let collURL = URL(string: "\(baseURL)/alloywastepages/getcollection/\(trimmedId)")!
            let (collData, _) = try await request(url: collURL)
            guard let collJSON = try? JSONSerialization.jsonObject(with: collData) as? [String: Any],
                  let schedules = collJSON["scheduleCodeWorkflowIDs"] as? [String],
                  let workflowId = schedules.first
            else { continue }

            // Get workflow dates
            let wfURL = URL(string: "\(baseURL)/alloywastepages/getworkflow/\(workflowId)")!
            let (wfData, _) = try await request(url: wfURL)
            guard let wfJSON = try? JSONSerialization.jsonObject(with: wfData) as? [String: Any],
                  let trigger = wfJSON["trigger"] as? [String: Any],
                  let dates = trigger["dates"] as? [String]
            else { continue }

            let isoFormatter = ISO8601DateFormatter()
            let today = Calendar.current.startOfDay(for: Date())
            for dateStr in dates {
                if let date = isoFormatter.date(from: dateStr), date >= today {
                    results.append(BinCollection(id: UUID(), rawType: binName, binType: BinType.classify(binName), collectionDate: date))
                    break // Just the next one
                }
            }
        }
        return results
    }

    // MARK: - Greenwich (multi-step)

    private func fetchGreenwich(postcode: String, houseNumber: String) async throws -> [BinCollection] {
        guard !postcode.isEmpty else { throw BinServiceError.missingInput("postcode") }

        let encoded = postcode.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? postcode
        let searchURL = URL(string: "https://www.royalgreenwich.gov.uk/site/custom_scripts/apps/waste-collection/new2023/source.php?term=\(encoded)")!
        var searchReq = URLRequest(url: searchURL)
        searchReq.setValue("https://www.royalgreenwich.gov.uk/", forHTTPHeaderField: "Origin")
        searchReq.setValue("https://www.royalgreenwich.gov.uk/info/200171/recycling_and_rubbish/100/bin_collection_days", forHTTPHeaderField: "Referer")
        searchReq.setValue("Mozilla/5.0 (Windows NT 6.1; Win64; x64)", forHTTPHeaderField: "User-Agent")

        let (searchData, _) = try await session.data(for: searchReq)
        guard let addresses = try? JSONSerialization.jsonObject(with: searchData) as? [String] else {
            throw BinServiceError.parsingError("Could not search Greenwich addresses")
        }

        let match = addresses.first { addr in
            houseNumber.isEmpty || addr.lowercased().contains(houseNumber.lowercased())
        } ?? addresses.first

        guard let addressStr = match else {
            throw BinServiceError.parsingError("No matching address found in Greenwich")
        }

        let detailURL = URL(string: "https://www.royalgreenwich.gov.uk/site/custom_scripts/repo/apps/waste-collection/new2023/ajax-response-uprn.php")!
        var detailReq = URLRequest(url: detailURL)
        detailReq.httpMethod = "POST"
        detailReq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        detailReq.setValue("https://www.royalgreenwich.gov.uk/", forHTTPHeaderField: "Origin")
        detailReq.setValue("Mozilla/5.0 (Windows NT 6.1; Win64; x64)", forHTTPHeaderField: "User-Agent")
        detailReq.httpBody = "address=\(addressStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? addressStr)".data(using: .utf8)

        let (detailData, _) = try await session.data(for: detailReq)
        guard let detailJSON = try? JSONSerialization.jsonObject(with: detailData) as? [String: Any],
              let day = detailJSON["Day"] as? String
        else { throw BinServiceError.parsingError("Could not get Greenwich collection day") }

        // Greenwich returns day + frequency. Calculate next dates.
        var results: [BinCollection] = []
        if let nextDate = nextOccurrence(of: day.lowercased()) {
            results.append(BinCollection(id: UUID(), rawType: "Recycling", binType: .recycling, collectionDate: nextDate))
            results.append(BinCollection(id: UUID(), rawType: "Food Waste", binType: .foodWaste, collectionDate: nextDate))
            // General waste is typically fortnightly
            results.append(BinCollection(id: UUID(), rawType: "General Waste", binType: .generalWaste, collectionDate: nextDate))
        }
        return results
    }

    // MARK: - Brent (multi-step with polling)

    private func fetchBrent(postcode: String, houseNumber: String) async throws -> [BinCollection] {
        guard !postcode.isEmpty else { throw BinServiceError.missingInput("postcode") }

        // Step 1: POST postcode to get address list
        let searchURL = URL(string: "https://recyclingservices.brent.gov.uk/waste")!
        var searchReq = URLRequest(url: searchURL)
        searchReq.httpMethod = "POST"
        searchReq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        searchReq.httpBody = "postcode=\(postcode.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? postcode)".data(using: .utf8)

        let (searchData, _) = try await session.data(for: searchReq)
        guard let searchHTML = String(data: searchData, encoding: .utf8) else {
            throw BinServiceError.parsingError("Invalid Brent search response")
        }

        // Extract address IDs from <option> tags
        let options = searchHTML.components(separatedBy: "<option")
        var addressId = ""
        for option in options {
            if !houseNumber.isEmpty && option.lowercased().contains(houseNumber.lowercased()) {
                if let valueRange = option.range(of: "value=\""),
                   let endRange = option.range(of: "\"", range: valueRange.upperBound..<option.endIndex) {
                    addressId = String(option[valueRange.upperBound..<endRange.lowerBound])
                    break
                }
            } else if addressId.isEmpty {
                if let valueRange = option.range(of: "value=\""),
                   let endRange = option.range(of: "\"", range: valueRange.upperBound..<option.endIndex) {
                    let val = String(option[valueRange.upperBound..<endRange.lowerBound])
                    if !val.isEmpty && val != "" { addressId = val }
                }
            }
        }

        guard !addressId.isEmpty else {
            throw BinServiceError.parsingError("No addresses found in Brent for this postcode")
        }

        // Step 2: Get collection data with polling
        let detailURL = URL(string: "https://recyclingservices.brent.gov.uk/waste/\(addressId)")!
        var html = ""
        for _ in 0..<20 {
            let (data, _) = try await request(url: detailURL)
            html = String(data: data, encoding: .utf8) ?? ""
            if !html.contains("Loading your bin days") { break }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }

        return parseBrentHTML(html)
    }

    private func parseBrentHTML(_ html: String) -> [BinCollection] {
        var results: [BinCollection] = []

        let serviceBlocks = html.components(separatedBy: "waste-service-name")
        for block in serviceBlocks.dropFirst() {
            guard let nameEnd = block.range(of: "</h3>"),
                  let nameStart = block.range(of: ">")
            else { continue }

            let name = String(block[nameStart.upperBound..<nameEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

            if let nextRange = block.range(of: "Next collection", options: .caseInsensitive) {
                let after = String(block[nextRange.upperBound...])
                // Try various date formats - strip ordinals first
                let cleaned = after.replacingOccurrences(of: "(\\d)(st|nd|rd|th)", with: "$1", options: .regularExpression)
                if let dateMatch = cleaned.range(of: "[A-Z][a-z]+day,? \\d{1,2} [A-Z][a-z]+", options: .regularExpression) {
                    let dateStr = String(cleaned[dateMatch])
                    let formatter = DateFormatter()
                    formatter.locale = Locale(identifier: "en_GB")
                    for fmt in ["EEEE, d MMMM", "EEEE d MMMM"] {
                        formatter.dateFormat = fmt
                        if var date = formatter.date(from: dateStr) {
                            let year = Calendar.current.component(.year, from: Date())
                            date = Calendar.current.date(bySetting: .year, value: year, of: date) ?? date
                            if date < Calendar.current.startOfDay(for: Date()) {
                                date = Calendar.current.date(bySetting: .year, value: year + 1, of: date) ?? date
                            }
                            results.append(BinCollection(id: UUID(), rawType: name, binType: BinType.classify(name), collectionDate: date))
                            break
                        }
                    }
                }
            }
        }
        return results
    }

    // MARK: - Helpers

    private func request(url: URL) async throws -> (Data, URLResponse) {
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        do {
            return try await session.data(for: req)
        } catch {
            throw BinServiceError.networkError(error)
        }
    }

    private func nextOccurrence(of dayName: String) -> Date? {
        let calendar = Calendar.current
        let dayMap = ["monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7, "sunday": 1]
        guard let targetWeekday = dayMap[dayName.lowercased()] else { return nil }

        let today = calendar.startOfDay(for: Date())
        let todayWeekday = calendar.component(.weekday, from: today)

        var daysToAdd = targetWeekday - todayWeekday
        if daysToAdd < 0 { daysToAdd += 7 }
        if daysToAdd == 0 { daysToAdd = 0 } // Today counts

        return calendar.date(byAdding: .day, value: daysToAdd, to: today)
    }
}
