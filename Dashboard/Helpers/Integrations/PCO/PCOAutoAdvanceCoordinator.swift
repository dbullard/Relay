import Foundation
import OSLog
import Combine

struct PCOAutoAdvanceUpdate: Equatable {
    let planID: String
    let planTitle: String?
    let planDateLabel: String?
    let allPositionAssignments: [String: String]
    let positionAssignmentCandidates: [String: [String]]?
    let positionToTeamName: [String: String]?
    let teamPositionsByTeamName: [String: [String]]?
    let rundownSnapshotTitles: [String]
    let snapshotKey: String
    let cachedRundownRows: [PCORundownRow]
    let cachedTeamAssignments: [PCOTeamAssignmentRow]
}

@MainActor
final class PCOAutoAdvanceCoordinator: ObservableObject {
    private static let log = Logger(subsystem: "Relay", category: "PCO")
    private static let tickInterval: TimeInterval = 60

    private var loopTask: Task<Void, Never>?
    private var tabs: [DashboardTab] = []
    private var isPaused = false
    private var lastScheduledCheckKeyByTabID: [UUID: String] = [:]
    private var onAdvance: ((UUID, PCOAutoAdvanceUpdate) -> Void)?

    deinit {
        loopTask?.cancel()
    }

    func configure(
        tabs: [DashboardTab],
        isPaused: Bool,
        onAdvance: @escaping (UUID, PCOAutoAdvanceUpdate) -> Void
    ) {
        self.tabs = tabs
        self.isPaused = isPaused
        self.onAdvance = onAdvance

        ensureLoop()

        Task { [weak self] in
            await self?.evaluateEnabledTabs(force: false)
        }
    }

    func advanceIfNeeded(tab: DashboardTab, force: Bool = true) async -> Bool {
        guard !isPaused || force else { return false }
        return await evaluate(tab: tab, force: force)
    }

    private func ensureLoop() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.evaluateEnabledTabs(force: false)
                do {
                    try await Task.sleep(nanoseconds: UInt64(Self.tickInterval * 1_000_000_000))
                } catch {
                    break
                }
            }
        }
    }

    private func evaluateEnabledTabs(force: Bool) async {
        guard !isPaused else { return }
        let snapshot = tabs

        for tab in snapshot where tab.pcoAutoAdvanceEnabled {
            if Task.isCancelled { return }
            _ = await evaluate(tab: tab, force: force)
        }
    }

    private func evaluate(tab: DashboardTab, force: Bool) async -> Bool {
        guard tab.pcoAutoAdvanceEnabled,
              let serviceTypeID = tab.serviceTypeID,
              let currentPlanID = tab.planID else { return false }

        let now = Date()
        let scheduledCheckDate: Date
        if force {
            scheduledCheckDate = now
        } else {
            guard let checkDate = currentScheduledCheckpoint(for: tab, at: now) else { return false }
            let checkKey = "\(tab.id.uuidString)|\(Int(checkDate.timeIntervalSince1970))"
            guard lastScheduledCheckKeyByTabID[tab.id] != checkKey else { return false }
            lastScheduledCheckKeyByTabID[tab.id] = checkKey
            scheduledCheckDate = checkDate
        }

        let plans: [PCOResource<PlanAttr>]
        do {
            plans = try await makeClient().fetchPlans(serviceTypeID: serviceTypeID, perPage: 20)
        } catch is CancellationError {
            return false
        } catch {
            Self.log.error("Auto-advance plan fetch failed: \(error.localizedDescription, privacy: .public)")
            return false
        }

        guard var update = Self.nextPlanUpdate(
            plans: plans,
            currentPlanID: currentPlanID,
            thresholdDate: scheduledCheckDate
        ) else { return false }

        do {
            update = try await hydratedUpdate(update, for: tab)
        } catch is CancellationError {
            return false
        } catch {
            Self.log.error("Auto-advance snapshot refresh failed: \(error.localizedDescription, privacy: .public)")
        }

        onAdvance?(tab.id, update)
        return true
    }

    private func hydratedUpdate(_ update: PCOAutoAdvanceUpdate, for tab: DashboardTab) async throws -> PCOAutoAdvanceUpdate {
        guard let serviceTypeID = tab.serviceTypeID else { return update }

        let client = makeClient()
        let itemsAndTimes = try await client.fetchItemsAndTimes(
            serviceTypeID: serviceTypeID,
            planID: update.planID
        )
        let members = try await client.fetchPlanTeamMemberSummaries(
            serviceTypeID: serviceTypeID,
            planID: update.planID
        )

        let selectedPlanTimeIDs = selectedPlanTimeIDs(
            client: client,
            itemsAndTimes: itemsAndTimes,
            rawSelectedLabels: tab.serviceTimeName
        )
        let timeFiltered = members.filter { member in
            let memberPlanTimeIDs = Set(member.planTimeIDs + (member.planTimeID.map { [$0] } ?? []))
            if !memberPlanTimeIDs.isEmpty,
               memberPlanTimeIDs.isDisjoint(with: selectedPlanTimeIDs) {
                return false
            }
            return true
        }

        var allMap: [String: String] = [:]
        var assignmentCandidates: [String: [String]] = [:]
        var positionToTeam: [String: String] = [:]
        for member in timeFiltered {
            let position = (member.positionName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let person = (member.personName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let team = (member.teamName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            if !position.isEmpty, !team.isEmpty, positionToTeam[position] == nil {
                positionToTeam[position] = team
            }

            guard !position.isEmpty, !person.isEmpty else { continue }
            if allMap[position] == nil {
                allMap[position] = person
            }

            let keys = team.isEmpty ? [position] : ["\(team)||\(position)", position]
            for key in keys {
                var names = assignmentCandidates[key] ?? []
                if !names.contains(where: { $0.compare(person, options: .caseInsensitive) == .orderedSame }) {
                    names.append(person)
                }
                assignmentCandidates[key] = names
            }
        }

        let teamNames = try await teamNamesForSelectedTimes(
            client: client,
            serviceTypeID: serviceTypeID,
            planID: update.planID,
            rawSelectedLabels: tab.serviceTimeName
        )
        let positionsByTeamName = try await client.fetchTeamPositionsByTeamName(
            serviceTypeID: serviceTypeID,
            teamNames: teamNames
        )
        let rundownRows = PCOTileView.makeTabSnapshotRundownRows(
            itemsAndTimes: itemsAndTimes,
            rawSelectedLabels: tab.serviceTimeName
        )
        let teamRows = PCOTileView.buildTeamAssignmentRows(
            members: timeFiltered,
            itemsAndTimes: itemsAndTimes,
            client: client,
            rawSelectedLabels: tab.serviceTimeName
        )

        return PCOAutoAdvanceUpdate(
            planID: update.planID,
            planTitle: update.planTitle,
            planDateLabel: update.planDateLabel,
            allPositionAssignments: allMap,
            positionAssignmentCandidates: assignmentCandidates.isEmpty ? nil : assignmentCandidates,
            positionToTeamName: positionToTeam.isEmpty ? nil : positionToTeam,
            teamPositionsByTeamName: positionsByTeamName.isEmpty ? nil : positionsByTeamName,
            rundownSnapshotTitles: PCOTileView.snapshotTitles(from: rundownRows),
            snapshotKey: PCOTileView.makeTabSnapshotKey(
                serviceTypeID: tab.serviceTypeID,
                planID: update.planID,
                serviceTimeName: tab.serviceTimeName
            ),
            cachedRundownRows: rundownRows,
            cachedTeamAssignments: teamRows
        )
    }

    private static func nextPlanUpdate(
        plans: [PCOResource<PlanAttr>],
        currentPlanID: String,
        thresholdDate: Date
    ) -> PCOAutoAdvanceUpdate? {
        let sorted = plans.sorted { a, b in
            let ad = planDate(a)
            let bd = planDate(b)
            switch (ad, bd) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil):
                let at = a.attributes.title ?? ""
                let bt = b.attributes.title ?? ""
                return at.localizedCaseInsensitiveCompare(bt) == .orderedAscending
            }
        }

        if let current = sorted.first(where: { $0.id == currentPlanID }),
           let currentDate = planDate(current),
           currentDate >= thresholdDate {
            return nil
        }

        guard let next = sorted.first(where: { planDate($0).map { $0 >= thresholdDate } ?? false }),
              next.id != currentPlanID else { return nil }

        return PCOAutoAdvanceUpdate(
            planID: next.id,
            planTitle: next.attributes.title,
            planDateLabel: formatPlanDateLabel(for: next),
            allPositionAssignments: [:],
            positionAssignmentCandidates: nil,
            positionToTeamName: nil,
            teamPositionsByTeamName: nil,
            rundownSnapshotTitles: [],
            snapshotKey: "",
            cachedRundownRows: [],
            cachedTeamAssignments: []
        )
    }

    private func selectedPlanTimeIDs(
        client: PCOClient,
        itemsAndTimes: PCOClient.ItemsAndTimes,
        rawSelectedLabels: String?
    ) -> Set<String> {
        let labels = (rawSelectedLabels ?? "")
            .components(separatedBy: "||")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if labels.isEmpty {
            return Set(client.planTimeIDs(forSelectedLabel: nil, in: itemsAndTimes.planTimes))
        }

        var ids = Set<String>()
        for label in labels {
            ids.formUnion(client.planTimeIDs(forSelectedLabel: label, in: itemsAndTimes.planTimes))
        }
        return ids
    }

    private func teamNamesForSelectedTimes(
        client: PCOClient,
        serviceTypeID: String,
        planID: String,
        rawSelectedLabels: String?
    ) async throws -> [String] {
        let labels = (rawSelectedLabels ?? "")
            .components(separatedBy: "||")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var names = Set<String>()
        if labels.isEmpty {
            names.formUnion(try await client.fetchTeamNamesForServiceTime(
                serviceTypeID: serviceTypeID,
                planID: planID,
                serviceTimeLabel: nil
            ))
        } else {
            for label in labels {
                names.formUnion(try await client.fetchTeamNamesForServiceTime(
                    serviceTypeID: serviceTypeID,
                    planID: planID,
                    serviceTimeLabel: label
                ))
            }
        }

        return Array(names).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func currentScheduledCheckpoint(for tab: DashboardTab, at now: Date, calendar: Calendar = .current) -> Date? {
        let weekday = (1...7).contains(tab.pcoAutoAdvanceCheckWeekday)
            ? tab.pcoAutoAdvanceCheckWeekday
            : 2
        let timeMinutes = max(0, min(tab.pcoAutoAdvanceCheckTimeMinutes, (24 * 60) - 1))
        let todayStart = calendar.startOfDay(for: now)
        let todayWeekday = calendar.component(.weekday, from: todayStart)
        let delta = (todayWeekday - weekday + 7) % 7
        guard let checkDay = calendar.date(byAdding: .day, value: -delta, to: todayStart),
              let checkDate = calendar.date(byAdding: .minute, value: timeMinutes, to: checkDay),
              checkDate <= now else {
            return nil
        }
        return checkDate
    }

    private static func planDate(_ plan: PCOResource<PlanAttr>) -> Date? {
        guard let sortDate = plan.attributes.sort_date else { return nil }
        return parseISOZ(sortDate)
    }

    private static func parseISOZ(_ iso: String) -> Date? {
        if let date = Formatters.iso8601WithFractional.date(from: iso) {
            return date
        }
        return Formatters.iso8601Basic.date(from: iso)
    }

    private static func formatPlanDateLabel(for plan: PCOResource<PlanAttr>) -> String? {
        guard let date = planDate(plan) else { return nil }
        return Formatters.planDate.string(from: date)
    }

    private func makeClient() -> PCOClient {
        let tokenStore = KeychainTokenStore()
        let oauth = OAuthService(
            clientID: "740fe16ab8a3025b6920a7290b5f244f4416d5bfb0ea88826521dc10101e8d9d",
            tokenStore: tokenStore
        )
        return PCOClient(oauthService: oauth, tokenStore: tokenStore)
    }

    private enum Formatters {
        static let iso8601WithFractional: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()

        static let iso8601Basic: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter
        }()

        static let planDate: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter
        }()
    }
}
