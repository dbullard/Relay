import Foundation
import OSLog
// A flexible JSON value type used for dynamic attributes
public enum PCOJSONValue: Decodable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: PCOJSONValue])
    case array([PCOJSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? container.decode(Double.self) {
            self = .number(n)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let obj = try? container.decode([String: PCOJSONValue].self) {
            self = .object(obj)
        } else if let arr = try? container.decode([PCOJSONValue].self) {
            self = .array(arr)
        } else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath,
                      debugDescription: "Unsupported JSON value")
            )
        }
    }
}

public final class PCOClient {
    private static let log = Logger(subsystem: "Relay", category: "PCO")
    private static let requestGate = PCORequestGate()

    private actor PCORequestGate {
        private var lastRequestAt: Date = .distantPast
        private var cooldownUntil: Date?
        private let minInterval: TimeInterval = 0.5

        func waitForTurn() async {
            let now = Date()
            if let cooldownUntil, cooldownUntil > now {
                let delay = cooldownUntil.timeIntervalSince(now)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            let elapsed = now.timeIntervalSince(lastRequestAt)
            if elapsed < minInterval {
                let delay = minInterval - elapsed
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            lastRequestAt = Date()
        }

        func noteRateLimited() {
            cooldownUntil = Date().addingTimeInterval(10.0)
            lastRequestAt = Date()
        }
    }
    private let tokenStore: TokenStore?
    private let oauth: OAuthService?

    public struct Credentials: Codable, Equatable {
        public var appID: String
        public var secret: String
    }

    private let creds: Credentials
    private let session: URLSession

    @available(*, deprecated, message: "Use OAuth-based init instead.")
    public init(credentials: Credentials, session: URLSession = .shared) {
        self.creds = credentials
        self.session = session
        self.tokenStore = nil
        self.oauth = nil
    }

    public init(oauthService: OAuthService, tokenStore: TokenStore, session: URLSession = .shared) {
        self.creds = Credentials(appID: "", secret: "")
        self.session = session
        self.tokenStore = tokenStore
        self.oauth = oauthService
    }

    private func request(_ url: URL, query: [String:String] = [:]) throws -> URLRequest {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw NSError(domain: "PCOClient", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "Could not decompose URL: \(url)"])
        }
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var req = URLRequest(url: comps.url!)
        if let tokenStore = tokenStore, let tokens = tokenStore.loadTokens() {
            req.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        } else {
            let auth = "\(creds.appID):\(creds.secret)".data(using: .utf8)!.base64EncodedString()
            req.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization")
        }
        req.setValue("PCO-MacApp/1.0", forHTTPHeaderField: "User-Agent")
        return req
    }

    private func logPCOError(_ message: String, key: String) {
        Task { @MainActor in
            RelayDiagnosticsStore.shared.recordThrottledError(message, tag: "PCO", key: key, minInterval: 60)
        }
    }

    @preconcurrency
    private func get<T: Decodable>(_ url: URL, query: [String:String] = [:]) async throws -> T {
        var req = try request(url, query: query)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("PCO-MacApp/1.0", forHTTPHeaderField: "User-Agent")

        do {
            await Self.requestGate.waitForTurn()
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                throw NSError(domain: "PCO", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "No HTTP response for \(url.absoluteString)"])
            }
            guard (200..<300).contains(http.statusCode) else {
                if http.statusCode == 401,
                   let oauth = self.oauth,
                   let tokenStore = self.tokenStore,
                   let existingTokens = tokenStore.loadTokens(),
                   let refreshToken = existingTokens.refreshToken {
                    // Attempt refresh once and retry
                    do {
                        let refreshed = try await oauth.refreshTokens(refreshToken: refreshToken)
                        tokenStore.saveTokens(refreshed)
                        // retry once
                        await Self.requestGate.waitForTurn()
                        var retryReq = try self.request(url, query: query)
                        retryReq.setValue("application/json", forHTTPHeaderField: "Accept")
                        retryReq.setValue("PCO-MacApp/1.0", forHTTPHeaderField: "User-Agent")
                        let (retryData, retryResp) = try await self.session.data(for: retryReq)
                        guard let retryHTTP = retryResp as? HTTPURLResponse, (200..<300).contains(retryHTTP.statusCode) else {
                            let bodyText = String(data: retryData, encoding: .utf8) ?? "<non-utf8 \(retryData.count) bytes>"
                            throw NSError(domain: "PCO", code: (retryResp as? HTTPURLResponse)?.statusCode ?? -1,
                                          userInfo: [NSLocalizedDescriptionKey: "HTTP \((retryResp as? HTTPURLResponse)?.statusCode ?? -1) \(url.path)\n\(bodyText)"])
                        }
                        return try JSONDecoder().decode(T.self, from: retryData)
                    } catch {
                        // fallthrough to original error handling
                    }
                }
                let bodyText = String(data: data, encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
                if http.statusCode == 429 {
                    let message = "HTTP 429 \(url.path)\n\(bodyText)"
                    print("[PCO] \(message)")
                    Self.log.error("\(message, privacy: .public)")
                    await Self.requestGate.noteRateLimited()
                }
                logPCOError("HTTP \(http.statusCode) \(url.path)", key: "pco_http_\(http.statusCode)_\(url.path)")
                throw NSError(domain: "PCO", code: http.statusCode,
                              userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode) \(url.path)\n\(bodyText)"])
            }

            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch let DecodingError.dataCorrupted(ctx) {
                throw decodingError("dataCorrupted", ctx, data: data, url: url)
            } catch let DecodingError.keyNotFound(key, ctx) {
                throw decodingError("keyNotFound: \(key.stringValue)", ctx, data: data, url: url)
            } catch let DecodingError.typeMismatch(type, ctx) {
                throw decodingError("typeMismatch: \(type)", ctx, data: data, url: url)
            } catch let DecodingError.valueNotFound(value, ctx) {
                throw decodingError("valueNotFound: \(value)", ctx, data: data, url: url)
            } catch {
                let bodyPreview = String(data: data.prefix(600), encoding: .utf8) ?? "<non-utf8>"
                throw NSError(domain: "PCO", code: -2,
                              userInfo: [NSLocalizedDescriptionKey:
                                "Decode error \(url.path): \(error.localizedDescription)\nBody preview:\n\(bodyPreview)"])
            }
        } catch {
            if let urlErr = error as? URLError {
                if urlErr.code == .cancelled {
                    throw CancellationError()
                }
                logPCOError("Transport error \(urlErr.code.rawValue) \(url.path) — \(urlErr.localizedDescription)", key: "pco_transport_\(urlErr.code.rawValue)_\(url.path)")
                throw NSError(domain: "PCO", code: urlErr.errorCode,
                              userInfo: [NSLocalizedDescriptionKey:
                                "PCO transport error: \(urlErr.localizedDescription) (code \(urlErr.code.rawValue))"])
            }
            throw error
        }
    }

    private func decodingError(_ kind: String, _ ctx: DecodingError.Context, data: Data, url: URL) -> NSError {
        let path = ctx.codingPath.map { $0.stringValue }.joined(separator: " → ")
        let bodyPreview = String(data: data.prefix(600), encoding: .utf8) ?? "<non-utf8>"
        logPCOError("Decode error \(kind) at \(path.isEmpty ? "<root>" : path) for \(url.path)", key: "pco_decode_\(kind)_\(url.path)")
        return NSError(
            domain: "PCO",
            code: -3,
            userInfo: [NSLocalizedDescriptionKey:
                "Decode \(kind) at \(path.isEmpty ? "<root>" : path) for \(url.path)\nReason: \(ctx.debugDescription)\nBody preview:\n\(bodyPreview)"]
        )
    }

    private func relationshipID<T>(in resource: PCOResource<T>, keys: [String]) -> String? where T: Decodable & Hashable {
        guard let relationships = resource.relationships else {
            return nil
        }
        for key in keys {
            if let rel = relationships[key] {
                switch rel.data {
                case let .some(.single(ref)):
                    return ref.id
                default:
                    continue
                }
            }
        }
        return nil
    }

    private func relationshipIDs<T>(in resource: PCOResource<T>, keys: [String]) -> [String] where T: Decodable & Hashable {
        guard let relationships = resource.relationships else {
            return []
        }
        var ids: [String] = []
        for key in keys {
            if let rel = relationships[key] {
                switch rel.data {
                case let .some(.multiple(refs)):
                    ids.append(contentsOf: refs.map { $0.id })
                case let .some(.single(ref)):
                    ids.append(ref.id)
                default:
                    continue
                }
            }
        }
        return ids
    }



    public func fetchServiceTypes() async throws -> [PCOResource<ServiceTypeAttr>] {
        let url = URL(string: "https://api.planningcenteronline.com/services/v2/service_types")!
        let page: PCOCollection<ServiceTypeAttr> = try await get(url, query: [
            "per_page": "200",
            "order": "name"
        ])
        return page.data
    }

    public func fetchServiceTypesWithFolders() async throws -> (
        types: [PCOResource<ServiceTypeAttr>],
        foldersByServiceTypeID: [String: String]
    ) {
        let url = URL(string: "https://api.planningcenteronline.com/services/v2/service_types")!
        let page: PCOCollection<ServiceTypeAttr> = try await get(url, query: [
            "per_page": "200",
            "order": "name",
            "include": "service_type_folder,folder"
        ])

        var folderNamesByFolderID: [String: String] = [:]
        if let included = page.included {
            for item in included {
                let type = item.type.lowercased()
                if !type.contains("folder") {
                    continue
                }
                if case let .string(name) = item.attributes["name"] {
                    folderNamesByFolderID[item.id] = name
                }
            }
        }

        if folderNamesByFolderID.isEmpty {
            do {
                let folders = try await fetchServiceTypeFolders()
                for folder in folders {
                    folderNamesByFolderID[folder.id] = folder.attributes.name
                }
            } catch {
                // Folders are optional; continue with unfiled grouping.
            }
        }

        if folderNamesByFolderID.isEmpty {
            do {
                let folders = try await fetchFolders()
                for folder in folders {
                    folderNamesByFolderID[folder.id] = folder.attributes.name
                }
            } catch {
                // Folders are optional; continue with unfiled grouping.
            }
        }

        var foldersByServiceTypeID: [String: String] = [:]
        for serviceType in page.data {
            if let folderID = relationshipID(in: serviceType, keys: ["parent", "service_type_folder", "folder"]),
               let folderName = folderNamesByFolderID[folderID] {
                foldersByServiceTypeID[serviceType.id] = folderName
            }
        }

        if foldersByServiceTypeID.isEmpty {
            do {
                foldersByServiceTypeID = try await fetchServiceTypeFolderAssignments()
            } catch {
                // Folders are optional; continue with unfiled grouping.
            }
        }

        if foldersByServiceTypeID.isEmpty {
            let includedTypes = (page.included ?? []).map { $0.type }.sorted()
            let relationshipKeys = Set(page.data.compactMap { $0.relationships?.keys }.flatMap { $0 }).sorted()
            let sampleRelationships: [String] = page.data.prefix(3).map { serviceType in
                let keys = serviceType.relationships?.keys.sorted() ?? []
                let refs = keys.compactMap { key -> String? in
                    guard let rel = serviceType.relationships?[key] else { return nil }
                    switch rel.data {
                    case .some(let data):
                        switch data {
                        case let .single(ref):
                            return "\(key)=\(ref.type):\(ref.id)"
                        case let .multiple(refs):
                            let ids = refs.prefix(2).map { "\($0.type):\($0.id)" }.joined(separator: ",")
                            return "\(key)=[\(ids)\(refs.count > 2 ? ",…" : "")]"
                        case PCORelationshipData.none:
                            return "\(key)=nil"
                        }
                    case nil:
                        return "\(key)=nil"
                    }
                }
                let name = serviceType.attributes.name
                return "\(name): \(refs.joined(separator: "; "))"
            }
            let message = "Service type folders unresolved. includedTypes=\(includedTypes) relationshipKeys=\(relationshipKeys) sample=\(sampleRelationships)"
            print("[PCO] \(message)")
            Self.log.info("\(message, privacy: .public)")
        }

        return (types: page.data, foldersByServiceTypeID: foldersByServiceTypeID)
    }

    public func fetchServiceTypeFolders() async throws -> [PCOResource<ServiceTypeFolderAttr>] {
        let url = URL(string: "https://api.planningcenteronline.com/services/v2/service_type_folders")!
        let page: PCOCollection<ServiceTypeFolderAttr> = try await get(url, query: [
            "per_page": "200",
            "order": "name"
        ])
        return page.data
    }

    public func fetchServiceTypeFolderAssignments() async throws -> [String: String] {
        let url = URL(string: "https://api.planningcenteronline.com/services/v2/service_type_folders")!
        let page: PCOCollection<ServiceTypeFolderAttr> = try await get(url, query: [
            "per_page": "200",
            "order": "name",
            "include": "service_types"
        ])

        var map: [String: String] = [:]
        for folder in page.data {
            let serviceTypeIDs = relationshipIDs(in: folder, keys: ["service_types"]) 
            if serviceTypeIDs.isEmpty {
                continue
            }
            let folderName = folder.attributes.name
            for serviceTypeID in serviceTypeIDs {
                map[serviceTypeID] = folderName
            }
        }

        return map
    }

    public func fetchFolders() async throws -> [PCOResource<FolderAttr>] {
        let url = URL(string: "https://api.planningcenteronline.com/services/v2/folders")!
        let page: PCOCollection<FolderAttr> = try await get(url, query: [
            "per_page": "200",
            "order": "name"
        ])
        return page.data
    }

    public func fetchPlans(serviceTypeID: String, perPage: Int = 5) async throws -> [PCOResource<PlanAttr>] {
        let base = "https://api.planningcenteronline.com/services/v2/service_types/\(serviceTypeID)/plans"
        guard let url = URL(string: base) else {
            throw NSError(domain: "PCOClient", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid URL constructed from API data: \(base)"])
        }
        let page: PCOCollection<PlanAttr> = try await get(url, query: [
            "filter": "future",
            "order": "sort_date",
            "per_page": String(perPage)
        ])
        return page.data
    }

    public struct ItemsAndTimes {
        public let items: PCOCollection<ItemAttr>
        public let planTimes: PCOCollection<PlanTimeAttr>
    }

    @MainActor
    public func fetchItemsAndTimes(serviceTypeID: String, planID: String) async throws -> ItemsAndTimes {
        let base = "https://api.planningcenteronline.com/services/v2/service_types/\(serviceTypeID)/plans/\(planID)"
        guard let itemsURL = URL(string: base + "/items") else {
            throw NSError(domain: "PCOClient", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid URL constructed from API data: \(base)/items"])
        }
        guard let timesURL = URL(string: base + "/plan_times") else {
            throw NSError(domain: "PCOClient", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid URL constructed from API data: \(base)/plan_times"])
        }

        let items: PCOCollection<ItemAttr> = try await get(itemsURL, query: ["per_page": "100", "include": "item_times,song,arrangement,item_notes"])
        let times: PCOCollection<PlanTimeAttr> = try await get(timesURL, query: ["per_page": "50"])
        return ItemsAndTimes(items: items, planTimes: times)
    }
    
    public struct TeamMemberSummary: Decodable, Hashable {
        public let id: String
        public let status: String?
        public let positionName: String?
        public let personName: String?
        public let teamName: String?
        /// Optional plan_time id this team member is scheduled for, used to
        /// filter teams by service time.
        public let planTimeID: String?
        /// All plan_time ids associated with this team member when the API
        /// exposes multiple time relationships.
        public let planTimeIDs: [String]
    }

    /// Normalize raw team member status codes/strings from the Services API into
    /// friendly, consistent values. Falls back to the original string when we
    /// don't recognize the status.
    private func normalizeTeamMemberStatus(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        let lower = raw.lowercased()
        switch lower {
        case "confirmed", "accept", "accepted", "c":
            return "confirmed"
        case "declined", "decline", "d":
            return "declined"
        case "pending", "unconfirmed", "needs_response", "u", "p":
            return "pending"
        default:
            // If we don't recognize it, return the original so callers can still
            // display something useful or log for later analysis.
            return raw
        }
    }

    /// Fetch distinct team names present on a plan.
    public func fetchPlanTeamNames(serviceTypeID: String, planID: String) async throws -> [String] {
        let base = "https://api.planningcenteronline.com/services/v2/service_types/\(serviceTypeID)/plans/\(planID)/team_members"
        guard let url = URL(string: base) else {
            throw NSError(domain: "PCOClient", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid URL constructed from API data: \(base)"])
        }
        typealias Page = PCOCollection<PCODynamicAttrs>
        struct PCODynamicAttrs: Decodable, Hashable {}

        // Request include=team to resolve team names in included
        let page: Page = try await get(url, query: ["include": "team", "per_page": "200"])
        // Build included lookup
        let included: [String: PCOIncluded] = Dictionary(uniqueKeysWithValues: (page.included ?? []).map { ("\($0.type)|\($0.id)", $0) })

        var names = Set<String>()
        for tm in page.data {
            if let rel = tm.relationships?["team"],
               case let .single(ref)? = rel.data,
               let inc = included["Team|\(ref.id)"],
               case let .string(name)? = inc.attributes["name"],
               !name.isEmpty {
                names.insert(name)
            }
        }
        return Array(names).sorted { $0.lowercased() < $1.lowercased() }
    }

    /// Fetch team members for a plan with person and team names.
    public func fetchPlanTeamMemberSummaries(serviceTypeID: String, planID: String) async throws -> [TeamMemberSummary] {
        let base = "https://api.planningcenteronline.com/services/v2/service_types/\(serviceTypeID)/plans/\(planID)/team_members"
        guard let url = URL(string: base) else {
            throw NSError(domain: "PCOClient", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid URL constructed from API data: \(base)"])
        }
        struct TeamMemberAttrs: Decodable, Hashable {
            let status: String?
            let team_position_name: String?
        }
        typealias Page = PCOCollection<TeamMemberAttrs>

        // include team/person for display names. Team-member time assignment can
        // arrive under several relationship keys depending on the payload shape
        // (`plan_time`, `plan_times`, `service_times`, `times`), so we inspect
        // the relationships directly rather than assuming one canonical name.
        let page: Page = try await get(url, query: ["include": "person,team,plan_time,plan_times,service_times,times", "per_page": "200"])
        let included: [String: PCOIncluded] = Dictionary(uniqueKeysWithValues: (page.included ?? []).map { ("\($0.type)|\($0.id)", $0) })

        var out: [TeamMemberSummary] = []
        var singlePlanTimeCount = 0
        var multiPlanTimeCount = 0
        var missingPlanTimeCount = 0
        var planTimeRelationshipKeys = Set<String>()
        var missingPlanTimeSamples: [String] = []
        var multiPlanTimeSamples: [String] = []
        for tm in page.data {
            let id = tm.id
            let status: String? = normalizeTeamMemberStatus(tm.attributes.status)
            let positionName: String? = tm.attributes.team_position_name

            var teamName: String? = nil
            if let rel = tm.relationships?["team"], case let .single(ref)? = rel.data,
               let inc = included["Team|\(ref.id)"], case let .string(n)? = inc.attributes["name"] {
                teamName = n
            }

            var personName: String? = nil
            if let rel = tm.relationships?["person"], case let .single(ref)? = rel.data,
               let inc = included["Person|\(ref.id)"],
               case let .string(name)? = (inc.attributes["name"] ?? inc.attributes["full_name"] ?? inc.attributes["display_name"] ?? inc.attributes["preferred_name"]) {
                personName = name
            }

            var planTimeIDs: [String] = []
            for key in ["plan_time", "plan_times", "service_time", "service_times", "time", "times"] {
                guard let rel = tm.relationships?[key], let data = rel.data else { continue }
                planTimeRelationshipKeys.insert(key)
                switch data {
                case let .single(ref):
                    if !planTimeIDs.contains(ref.id) {
                        planTimeIDs.append(ref.id)
                    }
                case let .multiple(refs):
                    for ref in refs where !planTimeIDs.contains(ref.id) {
                        planTimeIDs.append(ref.id)
                    }
                case .none:
                    break
                }
            }
            let planTimeID = planTimeIDs.first
            if planTimeIDs.count > 1 {
                multiPlanTimeCount += 1
                if multiPlanTimeSamples.count < 5 {
                    let sampleName = personName ?? positionName ?? id
                    multiPlanTimeSamples.append("\(sampleName)=\(planTimeIDs.joined(separator: ","))")
                }
            } else if planTimeIDs.count == 1 {
                singlePlanTimeCount += 1
            } else {
                missingPlanTimeCount += 1
                if missingPlanTimeSamples.count < 5 {
                    let sampleName = personName ?? positionName ?? id
                    let keys = tm.relationships?.keys.sorted().joined(separator: ",") ?? "<none>"
                    missingPlanTimeSamples.append("\(sampleName) keys[\(keys)]")
                }
            }

            out.append(
                TeamMemberSummary(
                    id: id,
                    status: status,
                    positionName: positionName,
                    personName: personName,
                    teamName: teamName,
                    planTimeID: planTimeID,
                    planTimeIDs: planTimeIDs
                )
            )
        }
        Self.log.debug(
            """
            team_members summary plan=\(planID, privacy: .public) serviceType=\(serviceTypeID, privacy: .public) total=\(out.count) \
            singlePlanTime=\(singlePlanTimeCount) multiPlanTime=\(multiPlanTimeCount) missingPlanTime=\(missingPlanTimeCount) \
            relationshipKeys=\(planTimeRelationshipKeys.sorted().joined(separator: ","), privacy: .public) \
            multiSamples=\(multiPlanTimeSamples.joined(separator: " | "), privacy: .public) \
            missingSamples=\(missingPlanTimeSamples.joined(separator: " | "), privacy: .public)
            """
        )
        return out
    }
    // MARK: - Plan time helpers

    public struct PlanTimeLabel: Hashable, Equatable {
        public let id: String
        public let label: String
        public let startsAt: Date?
    }

    /// Build human-readable labels for plan_times using the same rules as the UI:
    /// name + " — " + local time, falling back to "Time N" when needed.
    public func buildPlanTimeLabels(from planTimes: PCOCollection<PlanTimeAttr>) -> [PlanTimeLabel] {
        var results: [PlanTimeLabel] = []
        for (index, resource) in planTimes.data.enumerated() {
            let attr = resource.attributes
            let starts: Date?
            if let iso = attr.starts_at {
                starts = parseISOZ(iso)
            } else {
                starts = nil
            }

            let localHM = toLocalHM(starts)
            var parts: [String] = []
            if let name = attr.name, !name.isEmpty {
                parts.append(name)
            }
            if let localHM, !localHM.isEmpty {
                parts.append(localHM)
            }

            let label: String
            if parts.isEmpty {
                label = "Time \(index + 1)"
            } else {
                label = parts.joined(separator: " — ")
            }

            results.append(PlanTimeLabel(id: resource.id, label: label, startsAt: starts))
        }
        return results
    }

    /// Given a selected service-time label, return the matching plan_time ids.
    /// If no label is provided, all plan_time ids are returned. If no match is found for the label, fall back to all plan_time ids.
    public func planTimeIDs(forSelectedLabel label: String?, in planTimes: PCOCollection<PlanTimeAttr>) -> [String] {
        let tuples = buildPlanTimeLabels(from: planTimes)

        // If no specific label was provided, treat all plan_times as selected.
        guard let label, !label.isEmpty else {
            return tuples.map { $0.id }
        }

        let matching = tuples.filter { $0.label == label }.map { $0.id }

        // If we failed to find any plan_times matching the label (for example,
        // if the label formatting changed slightly between UI and client),
        // fall back to all plan_times instead of returning an empty list.
        // This prevents downstream filters from unintentionally excluding
        // all items or team members.
        if matching.isEmpty {
            return tuples.map { $0.id }
        }

        return matching
    }

    private func parseISOZ(_ iso: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }

    private func toLocalHM(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// Fetch distinct team names scheduled for the given service time on a plan.
    /// - Parameters:
    ///   - serviceTypeID: Service Type id
    ///   - planID: Plan id
    ///   - serviceTimeLabel: The human-readable plan_time label (e.g. "9:00 AM" or "Band — 10:30 AM").
    ///                        If nil or empty, teams for all plan_times are returned.
    /// Fetch all team names for a service type (independent of any plan).
    /// This is used to keep team/position pickers stable even when a team has
    /// no scheduled members on the currently selected plan/time.
    public func fetchServiceTypeTeamNames(serviceTypeID: String) async throws -> [String] {
        let base = "https://api.planningcenteronline.com/services/v2/service_types/\(serviceTypeID)/teams"
        guard let url = URL(string: base) else {
            throw NSError(domain: "PCOClient", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid URL constructed from API data: \(base)"])
        }

        struct TeamAttrs: Decodable, Hashable {
            let name: String?
        }
        typealias Page = PCOCollection<TeamAttrs>

        var names = Set<String>()
        let pageSize = 200
        var offset = 0
        while true {
            let page: Page = try await get(url, query: [
                "per_page": String(pageSize),
                "offset": String(offset),
                "order": "name"
            ])

            for t in page.data {
                if let n = t.attributes.name?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
                    names.insert(n)
                }
            }

            if page.data.count < pageSize { break }
            offset += pageSize
        }

        return Array(names).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    public func fetchTeamNamesForServiceTime(
        serviceTypeID: String,
        planID: String,
        serviceTimeLabel: String?
    ) async throws -> [String] {
        // We reuse ItemsAndTimes to resolve plan_time labels, and team member
        // summaries to determine which teams are scheduled at which times.
        let itemsAndTimes = try await fetchItemsAndTimes(serviceTypeID: serviceTypeID, planID: planID)
        let planTimes = itemsAndTimes.planTimes

        let selectedPlanTimeIDs = Set(planTimeIDs(forSelectedLabel: serviceTimeLabel, in: planTimes))

        // If we don't have any plan_time ids (unlikely), fall back to all teams on the plan.
        if selectedPlanTimeIDs.isEmpty {
            return try await fetchPlanTeamNames(serviceTypeID: serviceTypeID, planID: planID)
        }

        let members = try await fetchPlanTeamMemberSummaries(serviceTypeID: serviceTypeID, planID: planID)

        var names = Set<String>()
        for m in members {
            let memberPlanTimeIDs = Set(m.planTimeIDs + (m.planTimeID.map { [$0] } ?? []))
            if !memberPlanTimeIDs.isEmpty, memberPlanTimeIDs.isDisjoint(with: selectedPlanTimeIDs) {
                continue
            }
            if let team = m.teamName, !team.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                names.insert(team)
            }
        }

        if names.isEmpty {
            // If filtering by time produced nothing (e.g. missing plan_time relationships),
            // fall back to all teams so the UI isn't empty.
            return try await fetchPlanTeamNames(serviceTypeID: serviceTypeID, planID: planID)
        }

        // Also include teams that exist on the service type even if no one is scheduled
        // for them on this plan/time (prevents missing positions like "Soprano 2/Alto").
        do {
            let allTeams = try await fetchServiceTypeTeamNames(serviceTypeID: serviceTypeID)
            for t in allTeams { names.insert(t) }
        } catch {
            // Non-fatal; keep scheduled teams only.
        }

        return Array(names).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }


    public struct CurrentUser: Decodable, Equatable {
        public let name: String?
        public let email: String?
    }

    /// Fetch the current user's display name and primary email using the People API.
    /// Requires the same Basic credentials (App ID / Secret) and sufficient permissions.
    public func fetchCurrentUser() async throws -> CurrentUser {
        // The People API exposes the authenticated person at /people/v2/me
        // We'll try to read a couple of likely attribute keys for name/email.
        let url = URL(string: "https://api.planningcenteronline.com/people/v2/me")!
        struct MePage: Decodable {
            let data: PCOResource<PCODynamicAttrs>
            let included: [PCOIncluded]? // may be unused
        }
        typealias PCODynamicAttrs = [String: PCOJSONValue]
        let page: MePage = try await get(url)
        var name: String? = nil
        var email: String? = nil
        // Try common name fields
        if let n = page.data.attributes["name"], case let .string(s) = n { name = s }
        if name == nil, let n = page.data.attributes["full_name"], case let .string(s) = n { name = s }
        if name == nil, let n = page.data.attributes["display_name"], case let .string(s) = n { name = s }
        if name == nil, let n = page.data.attributes["preferred_name"], case let .string(s) = n { name = s }
        // Try common email fields
        if let e = page.data.attributes["email"], case let .string(s) = e { email = s }
        if email == nil, let e = page.data.attributes["primary_email"], case let .string(s) = e { email = s }
        return CurrentUser(name: name, email: email)
    }

    // MARK: - Team Positions (full catalog)
    /// Fetch the full list of available team positions for a service type.
    /// Optionally filter by a set of team names (case-insensitive).
    public func fetchAllTeamPositions(serviceTypeID: String, teamNames: [String] = []) async throws -> [String] {
        // Endpoint: /services/v2/service_types/{id}/team_positions
        // We request include=team to resolve team names if caller wants to filter.
        let base = "https://api.planningcenteronline.com/services/v2/service_types/\(serviceTypeID)/team_positions"
        guard let url = URL(string: base) else {
            throw NSError(domain: "PCOClient", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid URL constructed from API data: \(base)"])
        }

        // Minimal attribute model for a team position
        struct TeamPositionAttrs: Decodable, Hashable {
            let name: String?
            let sequence: Int?
        }
        typealias Page = PCOCollection<TeamPositionAttrs>

        // Build query. We include team to enable filtering by team name when provided.
        let query: [String:String] = [
            "per_page": "200",
            "include": "team"
        ]

        // Fetch all pages using offset pagination (PCOCollection in this project does not decode `links`).
        var allData: [PCOResource<TeamPositionAttrs>] = []
        var allIncluded: [PCOIncluded] = []

        let pageSize = 200
        var offset = 0
        while true {
            var q = query
            q["per_page"] = String(pageSize)
            q["offset"] = String(offset)

            let page: Page = try await get(url, query: q)
            allData.append(contentsOf: page.data)
            if let inc = page.included { allIncluded.append(contentsOf: inc) }

            if page.data.count < pageSize {
                break
            }
            offset += pageSize
        }

        // Build included lookup to map Team id -> name
        let included: [String: PCOIncluded] = Dictionary(uniqueKeysWithValues: allIncluded.map { ("\($0.type)|\($0.id)", $0) })

        // If no filter, just return distinct position names, ordered by sequence if available.
        if teamNames.isEmpty {
            var bestByKey: [String: (name: String, seq: Int?)] = [:]
            for res in allData {
                guard let raw = res.attributes.name?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { continue }
                let key = raw.lowercased()
                let seq = res.attributes.sequence
                if let existing = bestByKey[key] {
                    // Prefer entries with a sequence; otherwise keep the first.
                    if existing.seq == nil, seq != nil {
                        bestByKey[key] = (raw, seq)
                    }
                } else {
                    bestByKey[key] = (raw, seq)
                }
            }

            let ordered = bestByKey.values.sorted { a, b in
                switch (a.seq, b.seq) {
                case let (sa?, sb?):
                    if sa != sb { return sa < sb }
                    return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                }
            }
            return ordered.map { $0.name }
        }

        let filter = Set(teamNames.map { $0.lowercased() })

        // Filter positions to those whose related team has a name in the filter list.
        var bestByKey: [String: (name: String, seq: Int?)] = [:]
        for res in allData {
            // Find team relationship
            if let rel = res.relationships?["team"], case let .single(ref)? = rel.data,
               let inc = included["Team|\(ref.id)"], case let .string(teamName)? = inc.attributes["name"] {
                if !filter.contains(teamName.lowercased()) { continue }
            } else {
                // If we couldn't resolve a team, skip when filtering by team names
                continue
            }

            if let pos = res.attributes.name?.trimmingCharacters(in: .whitespacesAndNewlines), !pos.isEmpty {
                let key = pos.lowercased()
                let seq = res.attributes.sequence
                if let existing = bestByKey[key] {
                    if existing.seq == nil, seq != nil {
                        bestByKey[key] = (pos, seq)
                    }
                } else {
                    bestByKey[key] = (pos, seq)
                }
            }
        }

        let ordered = bestByKey.values.sorted { a, b in
            switch (a.seq, b.seq) {
            case let (sa?, sb?):
                if sa != sb { return sa < sb }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        }
        return ordered.map { $0.name }
    }

    /// Fetch the full list of team positions grouped by Team name.
    /// This is useful when you want:
    ///  - a stable catalog of *all* positions for UI (including unassigned slots)
    ///  - while keeping plan assignments separate (who is scheduled for what)
    ///
    /// - Parameters:
    ///   - serviceTypeID: Service Type id
    ///   - teamNames: Optional list of team names to include. If empty, returns all teams.
    /// - Returns: Dictionary mapping Team name -> ordered array of position names
    public func fetchTeamPositionsByTeamName(serviceTypeID: String, teamNames: [String] = []) async throws -> [String: [String]] {
        let base = "https://api.planningcenteronline.com/services/v2/service_types/\(serviceTypeID)/team_positions"
        guard let url = URL(string: base) else {
            throw NSError(domain: "PCOClient", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid URL constructed from API data: \(base)"])
        }

        struct TeamPositionAttrs: Decodable, Hashable {
            let name: String?
            let sequence: Int?
        }
        typealias Page = PCOCollection<TeamPositionAttrs>

        // Fetch all pages using offset pagination (PCOCollection in this project does not decode `links`).
        var allData: [PCOResource<TeamPositionAttrs>] = []
        var allIncluded: [PCOIncluded] = []

        let pageSize = 200
        var offset = 0
        while true {
            let page: Page = try await get(url, query: [
                "per_page": String(pageSize),
                "offset": String(offset),
                "include": "team"
            ])

            allData.append(contentsOf: page.data)
            if let inc = page.included { allIncluded.append(contentsOf: inc) }

            if page.data.count < pageSize {
                break
            }
            offset += pageSize
        }

        let included: [String: PCOIncluded] = Dictionary(uniqueKeysWithValues: allIncluded.map { ("\($0.type)|\($0.id)", $0) })

        let filter: Set<String> = Set(teamNames.map { $0.lowercased() })
        let shouldFilter = !filter.isEmpty

        // TeamName -> lowercasedPositionName -> (originalName, sequence)
        var buckets: [String: [String: (name: String, seq: Int?)]] = [:]

        for res in allData {
            // Resolve team name
            guard let rel = res.relationships?["team"],
                  case let .single(ref)? = rel.data,
                  let inc = included["Team|\(ref.id)"],
                  case let .string(teamName)? = inc.attributes["name"] else {
                continue
            }

            if shouldFilter, !filter.contains(teamName.lowercased()) {
                continue
            }

            guard let posRaw = res.attributes.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !posRaw.isEmpty else {
                continue
            }

            let posKey = posRaw.lowercased()
            let seq = res.attributes.sequence

            var map = buckets[teamName] ?? [:]
            if let existing = map[posKey] {
                if existing.seq == nil, seq != nil {
                    map[posKey] = (posRaw, seq)
                }
            } else {
                map[posKey] = (posRaw, seq)
            }
            buckets[teamName] = map
        }

        // Sort each team bucket by sequence then name
        var out: [String: [String]] = [:]
        for (team, map) in buckets {
            let ordered = map.values.sorted { a, b in
                switch (a.seq, b.seq) {
                case let (sa?, sb?):
                    if sa != sb { return sa < sb }
                    return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                }
            }
            out[team] = ordered.map { $0.name }
        }

        // If caller requested specific teams but none were returned (e.g. missing includes), provide empty arrays
        if shouldFilter {
            for t in teamNames {
                if out[t] == nil {
                    // Try to match by case-insensitive
                    if out.keys.first(where: { $0.lowercased() == t.lowercased() }) == nil {
                        out[t] = []
                    }
                }
            }
        }

        return out
    }
}
