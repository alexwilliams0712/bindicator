import Foundation

/// Resolves postcodes to addresses with UPRNs using each council's own APIs/websites.
/// No external API keys required - each lookup uses the same infrastructure the council
/// provides for their own waste collection pages.
actor AddressLookupService {
    static let shared = AddressLookupService()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Look up addresses for a postcode within a given borough.
    /// Returns an array of addresses with UPRNs that the user can pick from.
    /// For boroughs that use postcode + house number directly (Hackney, Greenwich, Brent),
    /// this returns an empty array since no UPRN resolution is needed.
    func lookupAddresses(postcode: String, borough: Borough) async throws -> [Address] {
        let cleaned = postcode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !cleaned.isEmpty else { return [] }

        switch borough {
        // Councils using Whitespace platform
        case .lambeth:
            return try await lookupWhitespace(
                postcode: cleaned,
                baseURL: "https://wasteservice.lambeth.gov.uk/WhitespaceComms"
            )

        // Havering uses Azure-fronted Whitespace
        case .havering:
            return try await lookupHavering(postcode: cleaned)

        // Environment Services platform (Camden, Haringey)
        case .camden:
            return try await lookupEnvironmentServices(
                postcode: cleaned,
                baseURL: "https://environmentservices.camden.gov.uk"
            )
        case .haringey:
            return try await lookupEnvironmentServices(
                postcode: cleaned,
                baseURL: "https://wastecollections.haringey.gov.uk"
            )

        // Councils with their own APIs
        case .harrow:
            return try await lookupHarrow(postcode: cleaned)
        case .ealing:
            return try await lookupEaling(postcode: cleaned)
        case .newham:
            return try await lookupNewham(postcode: cleaned)
        case .southwark:
            return try await lookupSouthwark(postcode: cleaned)
        case .wandsworth:
            return try await lookupWandsworth(postcode: cleaned)
        case .islington:
            return try await lookupIslington(postcode: cleaned)
        case .hounslow:
            return try await lookupHounslow(postcode: cleaned)

        // FixMyStreet platform (Merton, Sutton)
        case .merton:
            return try await lookupFixMyStreet(
                postcode: cleaned,
                baseURL: "https://fixmystreet.merton.gov.uk/waste"
            )
        case .sutton:
            return try await lookupFixMyStreet(
                postcode: cleaned,
                baseURL: "https://waste-services.sutton.gov.uk/waste"
            )

        // These already use postcode + house number directly - no UPRN lookup needed
        case .hackney, .greenwich, .brent:
            return []

        default:
            return []
        }
    }

    // MARK: - Harrow

    private func lookupHarrow(postcode: String) async throws -> [Address] {
        let encoded = postcode.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? postcode
        let url = URL(string: "https://www.harrow.gov.uk/ajax/addresses?postcode=\(encoded)")!
        let (data, _) = try await request(url: url)

        // Harrow returns a JSON array of address objects
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return json.compactMap { entry in
            guard let address = entry["address"] as? String,
                  let uprn = extractUPRN(from: entry, keys: ["uprn", "UPRN"])
            else { return nil }
            return Address(uprn: uprn, address: address)
        }.sorted { $0.address < $1.address }
    }

    // MARK: - Ealing

    private func lookupEaling(postcode: String) async throws -> [Address] {
        let url = URL(string: "https://www.ealing.gov.uk/site/custom_scripts/WasteCollectionWS/home/FindAddresses")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["postcode": postcode])

        let (data, _) = try await session.data(for: req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return json.compactMap { entry in
            guard let address = entry["address"] as? String ?? entry["Address"] as? String,
                  let uprn = extractUPRN(from: entry, keys: ["uprn", "UPRN"])
            else { return nil }
            return Address(uprn: uprn, address: address)
        }.sorted { $0.address < $1.address }
    }

    // MARK: - Whitespace platform (Lambeth)

    private func lookupWhitespace(postcode: String, baseURL: String) async throws -> [Address] {
        let url = URL(string: "\(baseURL)/GetAddressesByPostcode")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["postcode": postcode])

        let (data, _) = try await session.data(for: req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return json.compactMap { entry in
            guard let address = entry["Address"] as? String ?? entry["address"] as? String,
                  let uprn = extractUPRN(from: entry, keys: ["Uprn", "uprn", "UPRN"])
            else { return nil }
            return Address(uprn: uprn, address: address)
        }.sorted { $0.address < $1.address }
    }

    // MARK: - Havering (Azure-fronted Whitespace)

    private func lookupHavering(postcode: String) async throws -> [Address] {
        let url = URL(string: "https://lbhapiprod.azure-api.net/whitespace/GetAddressesByPostcode")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("2ea6a75f9ea34bb58d299a0c9f84e72e", forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        let body: [String: Any] = [
            "getAddressesByPostcode": ["postcode": postcode]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await session.data(for: req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = json["getAddressesByPostcodeResponse"] as? [String: Any],
              let result = response["getAddressesByPostcodeResult"] as? [String: Any],
              let addresses = result["Addresses"] as? [[String: Any]]
        else { return [] }

        return addresses.compactMap { entry in
            guard let address = entry["Address"] as? String ?? entry["address"] as? String,
                  let uprn = extractUPRN(from: entry, keys: ["Uprn", "uprn", "UPRN"])
            else { return nil }
            return Address(uprn: uprn, address: address)
        }.sorted { $0.address < $1.address }
    }

    // MARK: - Environment Services platform (Camden, Haringey)

    private func lookupEnvironmentServices(postcode: String, baseURL: String) async throws -> [Address] {
        let encoded = postcode.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? postcode
        let url = URL(string: "\(baseURL)/address/search?postcode=\(encoded)")!
        let (data, _) = try await request(url: url)
        guard let html = String(data: data, encoding: .utf8) else { return [] }
        return parseEnvironmentServicesHTML(html)
    }

    private func parseEnvironmentServicesHTML(_ html: String) -> [Address] {
        var results: [Address] = []
        // Links like <a href="/property/123456789">Address text</a>
        let pattern = "href=\"/property/(\\d+)\"[^>]*>([^<]+)<"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range)
        for match in matches {
            guard let uprnRange = Range(match.range(at: 1), in: html),
                  let addressRange = Range(match.range(at: 2), in: html)
            else { continue }
            let uprn = String(html[uprnRange])
            let address = String(html[addressRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "&amp;", with: "&")
            if !address.isEmpty {
                results.append(Address(uprn: uprn, address: address))
            }
        }
        return results.sorted { $0.address < $1.address }
    }

    // MARK: - Newham

    private func lookupNewham(postcode: String) async throws -> [Address] {
        let encoded = postcode.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? postcode
        let url = URL(string: "https://bincollection.newham.gov.uk/Home/FindAddress?postcode=\(encoded)")!
        let (data, _) = try await request(url: url)
        guard let html = String(data: data, encoding: .utf8) else { return [] }
        // Newham returns a page with address links containing UPRNs in the path
        var results = parseSelectOptionsForAddresses(html: html)
        if results.isEmpty {
            results = parseLinkAddresses(html: html, pattern: "/Details/Index/")
        }
        return results
    }

    // MARK: - Southwark

    private func lookupSouthwark(postcode: String) async throws -> [Address] {
        let encoded = postcode.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? postcode
        let url = URL(string: "https://services.southwark.gov.uk/bins/address-search?postcode=\(encoded)")!
        let (data, _) = try await request(url: url)
        guard let html = String(data: data, encoding: .utf8) else { return [] }
        var results = parseSelectOptionsForAddresses(html: html)
        if results.isEmpty {
            results = parseLinkAddresses(html: html, pattern: "/bins/lookup/")
        }
        return results
    }

    // MARK: - Wandsworth

    private func lookupWandsworth(postcode: String) async throws -> [Address] {
        let encoded = postcode.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? postcode
        let url = URL(string: "https://www.wandsworth.gov.uk/my-property/?PostCode=\(encoded)")!
        let (data, _) = try await request(url: url)
        guard let html = String(data: data, encoding: .utf8) else { return [] }
        // Wandsworth has links with UPRN= in the URL
        var results = parseSelectOptionsForAddresses(html: html)
        if results.isEmpty {
            results = parseLinkAddresses(html: html, pattern: "UPRN=")
        }
        return results
    }

    // MARK: - Islington

    private func lookupIslington(postcode: String) async throws -> [Address] {
        let formatted = formatPostcode(postcode)
        let encoded = formatted.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? formatted
        let url = URL(string: "https://www.islington.gov.uk/your-area?Postcode=\(encoded)")!
        let (data, _) = try await request(url: url)
        guard let html = String(data: data, encoding: .utf8) else { return [] }
        // Look for address links with Uprn= parameter
        var results = parseSelectOptionsForAddresses(html: html)
        if results.isEmpty {
            results = parseIslingtonHTML(html)
        }
        return results
    }

    private func parseIslingtonHTML(_ html: String) -> [Address] {
        var results: [Address] = []
        // Links like href="...Uprn=123456789..."
        let pattern = "Uprn=(\\d+)[^>]*>([^<]+)<"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range)
        for match in matches {
            guard let uprnRange = Range(match.range(at: 1), in: html),
                  let addressRange = Range(match.range(at: 2), in: html)
            else { continue }
            let uprn = String(html[uprnRange])
            let address = String(html[addressRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "&amp;", with: "&")
            if !address.isEmpty && !address.lowercased().contains("select") {
                results.append(Address(uprn: uprn, address: address))
            }
        }
        return results.sorted { $0.address < $1.address }
    }

    // MARK: - Hounslow (session-based multi-step)

    private func lookupHounslow(postcode: String) async throws -> [Address] {
        // Step 1: Get session
        let authURL = URL(string: "https://my.hounslow.gov.uk/authapi/isauthenticated?uri=https%253A%252F%252Fmy.hounslow.gov.uk%252Fservice%252FWaste_and_recycling_collections&hostname=my.hounslow.gov.uk&withCredentials=true")!
        let (authData, _) = try await request(url: authURL)
        guard let authJSON = try? JSONSerialization.jsonObject(with: authData) as? [String: Any],
              let sessionId = authJSON["auth-session"] as? String
        else { return [] }

        // Step 2: Search addresses by postcode
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        let searchURL = URL(string: "https://my.hounslow.gov.uk/apibroker/runLookup?id=5bdf32e3f0b14&repeat_against=&noRetry=true&getOnlyTokens=undefined&log_id=&app_name=AF-Renderer::Self&_=\(ts)&sid=\(sessionId)")!
        var searchReq = URLRequest(url: searchURL)
        searchReq.httpMethod = "POST"
        searchReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        searchReq.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        searchReq.setValue(
            "https://my.hounslow.gov.uk/fillform/?iframe_id=fillform-frame-1&db_id=",
            forHTTPHeaderField: "Referer"
        )
        let searchBody: [String: Any] = [
            "formValues": [
                "Your address": [
                    "postcode": ["value": postcode]
                ]
            ]
        ]
        searchReq.httpBody = try JSONSerialization.data(withJSONObject: searchBody)
        let (searchData, _) = try await session.data(for: searchReq)

        guard let searchJSON = try? JSONSerialization.jsonObject(with: searchData) as? [String: Any],
              let integration = searchJSON["integration"] as? [String: Any],
              let transformed = integration["transformed"] as? [String: Any],
              let rowsData = transformed["rows_data"] as? [String: Any]
        else { return [] }

        var results: [Address] = []
        for (_, value) in rowsData {
            guard let row = value as? [String: Any],
                  let address = row["AddressLine"] as? String ?? row["addressLine"] as? String,
                  let uprn = extractUPRN(from: row, keys: ["UPRN", "uprn", "Uprn"])
            else { continue }
            results.append(Address(uprn: uprn, address: address))
        }
        return results.sorted { $0.address < $1.address }
    }

    // MARK: - FixMyStreet platform (Merton, Sutton)

    private func lookupFixMyStreet(postcode: String, baseURL: String) async throws -> [Address] {
        let formatted = formatPostcode(postcode).replacingOccurrences(of: " ", with: "+")
        let url = URL(string: "\(baseURL)?postcode=\(formatted)")!
        var req = URLRequest(url: url)
        req.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, _) = try await session.data(for: req)
        guard let html = String(data: data, encoding: .utf8) else { return [] }
        return parseSelectOptionsForAddresses(html: html)
    }

    // MARK: - HTML Parsing Helpers

    /// Parse <option value="UPRN_NUMBER">Address text</option> from HTML select elements.
    /// This is the most common pattern across council websites.
    private func parseSelectOptionsForAddresses(html: String) -> [Address] {
        var results: [Address] = []
        let pattern = "<option\\s+value=\"(\\d+)\"[^>]*>([^<]+)</option>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return []
        }
        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range)
        for match in matches {
            guard let uprnRange = Range(match.range(at: 1), in: html),
                  let addressRange = Range(match.range(at: 2), in: html)
            else { continue }
            let uprn = String(html[uprnRange])
            let address = String(html[addressRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "&amp;", with: "&")

            // Skip placeholder options
            let lower = address.lowercased()
            if lower.contains("select") || lower.contains("choose") || address.isEmpty {
                continue
            }
            results.append(Address(uprn: uprn, address: address))
        }
        return results.sorted { $0.address < $1.address }
    }

    /// Parse links containing a UPRN in the URL path, e.g. /Details/Index/123456
    private func parseLinkAddresses(html: String, pattern urlPattern: String) -> [Address] {
        var results: [Address] = []
        let escaped = NSRegularExpression.escapedPattern(for: urlPattern)
        let pattern = "\(escaped)(\\d+)[^>]*>([^<]+)<"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range)
        for match in matches {
            guard let uprnRange = Range(match.range(at: 1), in: html),
                  let addressRange = Range(match.range(at: 2), in: html)
            else { continue }
            let uprn = String(html[uprnRange])
            let address = String(html[addressRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "&amp;", with: "&")
            if !address.isEmpty {
                results.append(Address(uprn: uprn, address: address))
            }
        }
        return results.sorted { $0.address < $1.address }
    }

    // MARK: - Utilities

    /// Extract a UPRN string from a JSON dictionary, trying multiple key names.
    /// Handles both String and Int values.
    private func extractUPRN(from dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let str = dict[key] as? String, !str.isEmpty {
                return str
            }
            if let num = dict[key] as? Int {
                return String(num)
            }
            if let num = dict[key] as? Int64 {
                return String(num)
            }
        }
        return nil
    }

    /// Format a postcode with proper spacing (e.g. "N12AB" -> "N1 2AB")
    private func formatPostcode(_ postcode: String) -> String {
        let cleaned = postcode.replacingOccurrences(of: " ", with: "").uppercased()
        guard cleaned.count >= 5 else { return cleaned }
        let inward = cleaned.suffix(3)
        let outward = cleaned.dropLast(3)
        return "\(outward) \(inward)"
    }

    private func request(url: URL) async throws -> (Data, URLResponse) {
        var req = URLRequest(url: url)
        req.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        return try await session.data(for: req)
    }
}
