import XCTest
@testable import Relay

@MainActor
final class NDIStreamRegistryBudgetTests: XCTestCase {

    func test_firstAcquire_returnsStream() async {
        let registry = NDIStreamRegistry()
        let model = NDIModuleModel()
        let result = registry.acquireStream(for: model, resolvedInterfaceID: nil, tabID: UUID())
        if case .stream = result { /* pass */ } else {
            XCTFail("Expected .stream, got \(result)")
        }
    }

    func test_secondDistinctAcquireSameTab_returnsStream() async {
        let registry = NDIStreamRegistry()
        let tabID = UUID()
        var m1 = NDIModuleModel(); m1.sourceID = "source-a"
        var m2 = NDIModuleModel(); m2.sourceID = "source-b"
        _ = registry.acquireStream(for: m1, resolvedInterfaceID: nil, tabID: tabID)
        let result = registry.acquireStream(for: m2, resolvedInterfaceID: nil, tabID: tabID)
        if case .stream = result { /* pass */ } else {
            XCTFail("Expected .stream, got \(result)")
        }
    }

    func test_thirdDistinctAcquireSameTab_returnsOverBudget() async {
        let registry = NDIStreamRegistry()
        let tabID = UUID()
        var m1 = NDIModuleModel(); m1.sourceID = "source-a"
        var m2 = NDIModuleModel(); m2.sourceID = "source-b"
        var m3 = NDIModuleModel(); m3.sourceID = "source-c"
        _ = registry.acquireStream(for: m1, resolvedInterfaceID: nil, tabID: tabID)
        _ = registry.acquireStream(for: m2, resolvedInterfaceID: nil, tabID: tabID)
        let result = registry.acquireStream(for: m3, resolvedInterfaceID: nil, tabID: tabID)
        if case .overBudget = result { /* pass */ } else {
            XCTFail("Expected .overBudget, got \(result)")
        }
    }

    func test_duplicateSourceSameTab_sharesStream() async {
        let registry = NDIStreamRegistry()
        let tabID = UUID()
        var m1 = NDIModuleModel(); m1.sourceID = "source-a"
        var m2 = NDIModuleModel(); m2.sourceID = "source-a"
        let r1 = registry.acquireStream(for: m1, resolvedInterfaceID: nil, tabID: tabID)
        let r2 = registry.acquireStream(for: m2, resolvedInterfaceID: nil, tabID: tabID)
        guard case .stream(let s1) = r1, case .stream(let s2) = r2 else {
            XCTFail("Expected both to be .stream"); return
        }
        XCTAssertEqual(s1.id, s2.id)
        XCTAssertEqual(registry.ndiModuleCount(forTab: tabID), 1)
    }

    func test_ndiModuleCount_differentTabs_countedSeparately() async {
        let registry = NDIStreamRegistry()
        let tabA = UUID(), tabB = UUID()
        var m1 = NDIModuleModel(); m1.sourceID = "source-a"
        var m2 = NDIModuleModel(); m2.sourceID = "source-b"
        _ = registry.acquireStream(for: m1, resolvedInterfaceID: nil, tabID: tabA)
        _ = registry.acquireStream(for: m2, resolvedInterfaceID: nil, tabID: tabA)
        _ = registry.acquireStream(for: m1, resolvedInterfaceID: nil, tabID: tabB)
        XCTAssertEqual(registry.ndiModuleCount(forTab: tabA), 2)
        XCTAssertEqual(registry.ndiModuleCount(forTab: tabB), 1)
    }

    func test_release_decrementsCount() async {
        let registry = NDIStreamRegistry()
        let tabID = UUID()
        var model = NDIModuleModel(); model.sourceID = "source-a"
        guard case .stream(let stream) = registry.acquireStream(for: model, resolvedInterfaceID: nil, tabID: tabID) else {
            XCTFail("Expected .stream"); return
        }
        XCTAssertEqual(registry.ndiModuleCount(forTab: tabID), 1)
        registry.release(streamID: stream.id)
        XCTAssertEqual(registry.ndiModuleCount(forTab: tabID), 0)
    }

    func test_differentFpsCap_createsSeparateStreams() async {
        let registry = NDIStreamRegistry()
        let tabID = UUID()
        var m1 = NDIModuleModel(); m1.sourceID = "source-a"; m1.fpsCap = 15
        var m2 = NDIModuleModel(); m2.sourceID = "source-a"; m2.fpsCap = 30
        let r1 = registry.acquireStream(for: m1, resolvedInterfaceID: nil, tabID: tabID)
        let r2 = registry.acquireStream(for: m2, resolvedInterfaceID: nil, tabID: tabID)
        guard case .stream(let s1) = r1, case .stream(let s2) = r2 else {
            XCTFail("Expected both to be .stream"); return
        }
        XCTAssertNotEqual(s1.id, s2.id)
        XCTAssertEqual(registry.ndiModuleCount(forTab: tabID), 2)
    }
}
