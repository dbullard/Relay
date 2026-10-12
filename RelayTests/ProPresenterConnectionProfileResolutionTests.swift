import XCTest
@testable import Relay

final class ProPresenterConnectionProfileResolutionTests: XCTestCase {
    func testResolvesExplicitProfileIdWhenItExists() {
        let defaults = UserDefaults(suiteName: #file)!
        defer { defaults.removePersistentDomain(forName: #file) }
        defaults.removePersistentDomain(forName: #file)
        let profile = ProPresenterConnectionProfile(id: UUID(), name: "Test Profile", host: "127.0.0.1", port: 1025, transportRaw: "http", password: "")
        let data = try! JSONEncoder().encode([profile])
        defaults.set(data, forKey: ProPresenterProfilesStore.profilesKey)

        let resolved = ProPresenterProfilesStore.resolvedProfileIdentity(configuredProfileId: profile.id, from: defaults)

        XCTAssertEqual(resolved, profile.id)
    }

    func testFallsBackToActiveProfileWhenConfiguredIdIsNil() {
        let defaults = UserDefaults(suiteName: #file)!
        defer { defaults.removePersistentDomain(forName: #file) }
        defaults.removePersistentDomain(forName: #file)
        let activeId = UUID()
        let profile = ProPresenterConnectionProfile(id: activeId, name: "Active Profile", host: "127.0.0.1", port: 1025, transportRaw: "http", password: "")
        let data = try! JSONEncoder().encode([profile])
        defaults.set(data, forKey: ProPresenterProfilesStore.profilesKey)
        defaults.set(activeId.uuidString, forKey: ProPresenterProfilesStore.activeProfileIDKey)

        let resolved = ProPresenterProfilesStore.resolvedProfileIdentity(configuredProfileId: nil, from: defaults)

        XCTAssertEqual(resolved, activeId)
    }

    func testFallsBackToActiveProfileWhenConfiguredIdDoesNotExist() {
        let defaults = UserDefaults(suiteName: #file)!
        defer { defaults.removePersistentDomain(forName: #file) }
        defaults.removePersistentDomain(forName: #file)
        let activeId = UUID()
        let profile = ProPresenterConnectionProfile(id: activeId, name: "Active Profile", host: "127.0.0.1", port: 1025, transportRaw: "http", password: "")
        let data = try! JSONEncoder().encode([profile])
        defaults.set(data, forKey: ProPresenterProfilesStore.profilesKey)
        defaults.set(activeId.uuidString, forKey: ProPresenterProfilesStore.activeProfileIDKey)

        let resolved = ProPresenterProfilesStore.resolvedProfileIdentity(configuredProfileId: UUID(), from: defaults)

        XCTAssertEqual(resolved, activeId)
    }

    func testFallsBackToNilWhenActiveProfileIdIsStaleAndNoLongerExists() {
        let defaults = UserDefaults(suiteName: #file)!
        defer { defaults.removePersistentDomain(forName: #file) }
        defaults.removePersistentDomain(forName: #file)
        let staleActiveId = UUID()
        defaults.set(staleActiveId.uuidString, forKey: ProPresenterProfilesStore.activeProfileIDKey)
        // Deliberately do NOT add a profile with staleActiveId to profilesKey -- this
        // simulates deleteProfiles(at:) removing the active profile without clearing
        // activeProfileIDKey (DashboardProPresenterSettingsView.swift:296-305).

        let resolved = ProPresenterProfilesStore.resolvedProfileIdentity(configuredProfileId: nil, from: defaults)

        XCTAssertNil(resolved)
    }
}
