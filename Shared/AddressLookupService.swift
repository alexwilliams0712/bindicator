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

    // MARK: - Borough Detection

    enum BoroughLookupError: LocalizedError {
        case invalidPostcode
        case networkError(Error)
        case unsupportedArea(String)
        case unknownArea(String)

        var errorDescription: String? {
            switch self {
            case .invalidPostcode:
                return "That doesn't look like a valid postcode. Please check and try again."
            case .networkError:
                return "Could not look up your postcode. Check your connection and try again."
            case .unsupportedArea(let district):
                return "\(district) is not yet supported. We currently support 16 London boroughs."
            case .unknownArea(let district):
                return "Could not determine a London borough for this postcode (area: \(district))."
            }
        }
    }

    /// Determine the borough for a given postcode using the postcodes.io API.
    /// Returns the Borough if the postcode maps to a supported London borough.
    /// Throws BoroughLookupError if the postcode is invalid, the area is unsupported, etc.
    func lookupBorough(postcode: String) async throws -> Borough {
        let cleaned = postcode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? postcode

        guard let url = URL(string: "https://api.postcodes.io/postcodes/\(cleaned)") else {
            throw BoroughLookupError.invalidPostcode
        }

        let data: Data
        do {
            let (responseData, response) = try await session.data(for: URLRequest(url: url))
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 404 {
                throw BoroughLookupError.invalidPostcode
            }
            data = responseData
        } catch let error as BoroughLookupError {
            throw error
        } catch {
            throw BoroughLookupError.networkError(error)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? Int, status == 200,
              let result = json["result"] as? [String: Any],
              let adminDistrict = result["admin_district"] as? String
        else {
            throw BoroughLookupError.invalidPostcode
        }

        guard let borough = Borough.fromAdminDistrict(adminDistrict) else {
            throw BoroughLookupError.unknownArea(adminDistrict)
        }

        guard borough.isSupported else {
            throw BoroughLookupError.unsupportedArea(borough.displayName)
        }

        return borough
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
        // Lambeth (LLPG address search)
        case .lambeth:
            return try await lookupLambeth(postcode: cleaned)

        // Havering uses Azure-fronted Whitespace
        case .havering:
            return try await lookupHavering(postcode: cleaned)

        // Environment Services platform (Camden, Haringey) - AJAX property search
        case .camden:
            return try await lookupEnvironmentServicesAjax(
                postcode: cleaned,
                baseURL: "https://environmentservices.camden.gov.uk"
            )
        case .haringey:
            return try await lookupEnvironmentServicesAjax(
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

    // MARK: - Harrow (session-based, requires CSRF token exchange)

    private func lookupHarrow(postcode: String) async throws -> [Address] {
        // Step 1: Load the bin collections page to get a session cookie and harrow_uid
        let pageURL = URL(string: "https://www.harrow.gov.uk/bins-waste-recycling/bin-collections/2")!
        var pageReq = URLRequest(url: pageURL)
        pageReq.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        let (pageData, _) = try await session.data(for: pageReq)
        guard let pageHTML = String(data: pageData, encoding: .utf8) else { return [] }

        // Extract the harrow_uid from the page
        let uidPattern = "harrow-uid-[a-f0-9]+"
        guard let uidRegex = try? NSRegularExpression(pattern: uidPattern),
              let uidMatch = uidRegex.firstMatch(in: pageHTML, range: NSRange(pageHTML.startIndex..., in: pageHTML)),
              let uidRange = Range(uidMatch.range, in: pageHTML)
        else { return [] }
        let harrowUid = String(pageHTML[uidRange])

        // Step 2: POST to /ajax/address with the session cookies and harrow_uid
        let url = URL(string: "https://www.harrow.gov.uk/ajax/address")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.setValue(
            "https://www.harrow.gov.uk/bins-waste-recycling/bin-collections/2",
            forHTTPHeaderField: "Referer"
        )
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        let encoded = postcode.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? postcode
        req.httpBody = "q=\(encoded)&harrow_uid=\(harrowUid)&n=0&submit=Go".data(using: .utf8)

        let (data, _) = try await session.data(for: req)

        // Harrow returns {"results": [...], "harrowUid": "..."}
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]]
        else { return [] }

        return results.compactMap { entry in
            guard let address = entry["address"] as? String ?? entry["Address"] as? String,
                  let uprn = extractUPRN(from: entry, keys: ["uprn", "UPRN", "id", "Id"])
            else { return nil }
            return Address(uprn: uprn, address: address)
        }.sorted { $0.address < $1.address }
    }

    // MARK: - Ealing

    private func lookupEaling(postcode: String) async throws -> [Address] {
        // Ealing uses form-encoded POST to /home/GetAddress (not FindAddresses which no longer exists).
        // The parameter name is "Postcode" (capital P) matching the jQuery $.ajax call on their page.
        // Response is JSON: {param1: bool, param2: [{Value: "UPRN", Text: "Address"}, ...], param3: bool}
        let url = URL(string: "https://www.ealing.gov.uk/site/custom_scripts/WasteCollectionWS/home/GetAddress")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let encoded = postcode.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? postcode
        req.httpBody = "Postcode=\(encoded)".data(using: .utf8)

        let (data, _) = try await session.data(for: req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let addresses = json["param2"] as? [[String: Any]]
        else { return [] }

        return addresses.compactMap { entry in
            guard let text = entry["Text"] as? String,
                  let value = entry["Value"] as? String,
                  !value.isEmpty,
                  value != "0000000000000000" // Skip the "Select address" placeholder
            else { return nil }
            let address = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !address.isEmpty else { return nil }
            return Address(uprn: value, address: address)
        }.sorted { $0.address < $1.address }
    }

    // MARK: - Lambeth (LLPG address search)

    private func lookupLambeth(postcode: String) async throws -> [Address] {
        // Lambeth moved from Whitespace to an LLPG-based address search.
        // POST JSON to /LLPG/addressSearch with postcode and optional filters.
        // Response: {payload: {results: [{UPRN, STREET, PAO_START_NUMBER, PAO_TEXT, SAO_TEXT, POSTCODE, ...}]}}
        let url = URL(string: "https://wasteservice.lambeth.gov.uk/LLPG/addressSearch")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "postcode": postcode,
            "number": "",
            "street": "",
            "name": "",
            "ignorePostal": true
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await session.data(for: req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = json["payload"] as? [String: Any],
              let results = payload["results"] as? [[String: Any]]
        else { return [] }

        return results.compactMap { entry in
            guard let uprn = entry["UPRN"] as? String, !uprn.isEmpty else { return nil }
            let address = buildLambethAddress(from: entry)
            guard !address.isEmpty else { return nil }
            return Address(uprn: uprn, address: address)
        }.sorted { $0.address < $1.address }
    }

    /// Build a readable address string from Lambeth LLPG fields.
    private func buildLambethAddress(from entry: [String: Any]) -> String {
        var parts: [String] = []

        // SAO (secondary addressable object) e.g. "FLAT 1"
        if let sao = entry["SAO_TEXT"] as? String, !sao.isEmpty {
            parts.append(sao)
        }

        // PAO (primary addressable object) e.g. "LAMBETH TOWN HALL" or number "2"
        let paoText = entry["PAO_TEXT"] as? String ?? ""
        let paoNumber = entry["PAO_START_NUMBER"] as? String ?? ""
        let paoSuffix = entry["PAO_START_SUFFIX"] as? String ?? ""
        let paoEnd = entry["PAO_END_NUMBER"] as? String ?? ""

        if !paoText.isEmpty {
            parts.append(paoText)
        }
        if !paoNumber.isEmpty {
            var num = paoNumber + paoSuffix
            if !paoEnd.isEmpty {
                num += "-\(paoEnd)"
            }
            parts.append(num)
        }

        // Street
        if let street = entry["STREET"] as? String, !street.isEmpty {
            parts.append(street)
        }

        // Post town and postcode
        if let town = entry["POST_TOWN"] as? String, !town.isEmpty {
            parts.append(town)
        }
        if let postcode = entry["POSTCODE"] as? String, !postcode.isEmpty {
            parts.append(postcode)
        }

        return parts.joined(separator: ", ")
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

    /// Both Camden and Haringey now use an AJAX POST to /property/ with form-encoded data.
    /// The old /address/search?postcode=X endpoint no longer exists.
    /// Response is JSON: {status: "OK", result: "<ul><li><a href='/property/UPRN'>Address text</li>..."}
    private func lookupEnvironmentServicesAjax(postcode: String, baseURL: String) async throws -> [Address] {
        let url = URL(string: "\(baseURL)/property/")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        let encoded = postcode.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? postcode
        req.httpBody = "search_property=\(encoded)&aj=true".data(using: .utf8)

        let (data, _) = try await session.data(for: req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? String, status == "OK",
              let resultHTML = json["result"] as? String
        else { return [] }

        return parseEnvironmentServicesHTML(resultHTML)
    }

    private func parseEnvironmentServicesHTML(_ html: String) -> [Address] {
        var results: [Address] = []
        // Links like <a href="/property/123456789">Address text</a>
        // or <a href="property/123456789">Address text</a> (without leading slash)
        let pattern = "href=\"/?property/(\\d+)\"?[^>]*>([^<]+)<"
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
                .replacingOccurrences(of: "\\/", with: "/")
            if !address.isEmpty {
                results.append(Address(uprn: uprn, address: address))
            }
        }
        return results.sorted { $0.address < $1.address }
    }

    // MARK: - Newham

    private func lookupNewham(postcode: String) async throws -> [Address] {
        // Newham changed from a dedicated address endpoint to a single form that takes
        // a combined address + postcode string. POSTing just the postcode still works
        // and returns matching addresses in an HTML table with /Details/Index/UPRN links.
        let url = URL(string: "https://bincollection.newham.gov.uk/")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        let encoded = postcode.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? postcode
        req.httpBody = "Address=\(encoded)&btnSearch=Search".data(using: .utf8)

        let (data, _) = try await session.data(for: req)
        guard let html = String(data: data, encoding: .utf8) else { return [] }

        // Newham returns an HTML table with rows like:
        // <td><a href="/Details/Index/UPRN">Select</a></td>
        // <td>ADDRESS LINE 1</td><td>ADDRESS LINE 2</td><td>POSTCODE</td>
        return parseNewhamHTML(html)
    }

    /// Parse Newham's HTML table format where each row has a Select link with UPRN
    /// and address columns (Address Line 1, Address Line 2, Postcode).
    private func parseNewhamHTML(_ html: String) -> [Address] {
        var results: [Address] = []
        // Match table rows containing /Details/Index/UPRN links
        let rowPattern = "<tr>\\s*<td><a[^>]*href=\"/Details/Index/(\\d+)\"[^>]*>[^<]*</a></td>\\s*<td>([^<]*)</td>\\s*<td>([^<]*)</td>\\s*<td>([^<]*)</td>\\s*</tr>"
        guard let regex = try? NSRegularExpression(pattern: rowPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            // Fallback to the simpler link-based parser
            return parseLinkAddresses(html: html, pattern: "/Details/Index/")
        }
        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range)
        for match in matches {
            guard let uprnRange = Range(match.range(at: 1), in: html),
                  let line1Range = Range(match.range(at: 2), in: html),
                  let line2Range = Range(match.range(at: 3), in: html),
                  let postcodeRange = Range(match.range(at: 4), in: html)
            else { continue }
            let uprn = String(html[uprnRange])
            let line1 = String(html[line1Range]).trimmingCharacters(in: .whitespacesAndNewlines)
            let line2 = String(html[line2Range]).trimmingCharacters(in: .whitespacesAndNewlines)
            let postcode = String(html[postcodeRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = [line1, line2, postcode].filter { !$0.isEmpty }
            let address = parts.joined(separator: ", ")
            if !address.isEmpty {
                results.append(Address(uprn: uprn, address: address))
            }
        }
        if results.isEmpty {
            // Fallback to simpler link parser
            return parseLinkAddresses(html: html, pattern: "/Details/Index/")
        }
        return results.sorted { $0.address < $1.address }
    }

    // MARK: - Southwark

    private func lookupSouthwark(postcode: String) async throws -> [Address] {
        // Southwark uses an LLPG lookup endpoint at /llpg/lookup.
        // The old /bins/address-search endpoint no longer exists.
        // Response is JSONP-wrapped: ([{Uprn, AddressLine1, Locality, PostalCode, ...}]);
        // classification=R filters for residential properties only.
        let formatted = formatPostcode(postcode)
        let encoded = formatted.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? formatted
        let url = URL(string: "https://services.southwark.gov.uk/llpg/lookup?postcode=\(encoded)&classification=R")!
        var req = URLRequest(url: url)
        req.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, _) = try await session.data(for: req)
        guard var text = String(data: data, encoding: .utf8) else { return [] }

        // Strip JSONP wrapper: the response is ([...]);  or callbackName([...]);
        // Remove everything up to and including the first '(' and the trailing ');'
        if let openParen = text.firstIndex(of: "(") {
            text = String(text[text.index(after: openParen)...])
        }
        if text.hasSuffix(");") {
            text = String(text.dropLast(2))
        }

        guard let jsonData = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]]
        else { return [] }

        return json.compactMap { entry in
            guard let uprn = entry["Uprn"] as? String, !uprn.isEmpty else { return nil }
            var parts: [String] = []
            if let line1 = entry["AddressLine1"] as? String, !line1.isEmpty {
                parts.append(line1)
            }
            if let line2 = entry["AddressLine2"] as? String, !line2.isEmpty {
                parts.append(line2)
            }
            if let locality = entry["Locality"] as? String, !locality.isEmpty {
                parts.append(locality)
            }
            if let postcode = entry["PostalCode"] as? String, !postcode.isEmpty {
                parts.append(postcode)
            }
            let address = parts.joined(separator: ", ")
            guard !address.isEmpty else { return nil }
            return Address(uprn: uprn, address: address)
        }.sorted { $0.address < $1.address }
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
