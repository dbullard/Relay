import XCTest
import SwiftUI
@testable import Relay

/// Covers the identity-by-id fix in `DashboardRostersManagerView`'s roster
/// spreadsheet grid: after a mid-list column/row deletion shifts array
/// positions, the surviving cells' bindings must still read the data that
/// actually belongs to them (not whatever now happens to sit at their old
/// numeric index).
///
/// These tests construct the view with a roster that already reflects the
/// *post*-deletion state (mirroring exactly what `deleteColumn`/`deleteRow`
/// produce — including stripping the removed column's key from the
/// remaining rows' `values` dictionaries) rather than calling those private
/// mutators on a live instance: `@State` writes made after `init()` are not
/// observable outside a real SwiftUI view-graph host, so a bare
/// `DashboardRostersManagerView()` in XCTest can't reliably exercise them.
/// `columnTitleBinding(for:)` / `cellBinding(rowIndex:columnIndex:)` are the
/// same index-based lookups the live `ForEach` body resolves via
/// `firstIndex(where: { $0.id == element.id })!` before calling into — this
/// exercises exactly the read path that fix protects.
@MainActor
final class DashboardRostersManagerIdentityTests: XCTestCase {

    func testColumnAndCellBindingsResolveCorrectDataAfterMidListDeletion() {
        // Original layout: columns [A, B, C], rows [row1, row2, row3].
        // Simulated mutation: column A deleted, row2 deleted — mirrors
        // `deleteColumn(at: 0)` followed by `deleteRow(at: 1)`.
        let columnB = DashboardRosterColumn(title: "B")
        let columnC = DashboardRosterColumn(title: "C")

        let row1 = DashboardRosterRow(values: [
            columnB.id.uuidString: "B1",
            columnC.id.uuidString: "C1"
        ])
        let row3 = DashboardRosterRow(values: [
            columnB.id.uuidString: "B3",
            columnC.id.uuidString: "C3"
        ])

        let postDeleteRoster = DashboardRoster(
            name: "Test Roster",
            kind: .general,
            columns: [columnB, columnC],
            rows: [row1, row3]
        )
        let tab = DashboardTab(name: "Test Tab", tiles: [], attachedRosterIDs: [postDeleteRoster.id])

        // `initialSelectedRosterID` seeds `@State` through `State(initialValue:)`
        // in `init`, the same mechanism `draftRosters`/`draftTabs` already use —
        // this is the one State write that reliably takes effect without a live
        // view-graph host.
        let view = DashboardRostersManagerView(
            rosters: .constant([postDeleteRoster]),
            tabs: .constant([tab]),
            selectedTabIndex: .constant(0),
            initialSelectedRosterID: postDeleteRoster.id
        )

        // Column headers: index 0 is now B, index 1 is now C — not A, B.
        XCTAssertEqual(view.columnTitleBinding(for: 0).wrappedValue, "B")
        XCTAssertEqual(view.columnTitleBinding(for: 1).wrappedValue, "C")

        // row1/columnB now sits at (rowIndex: 0, columnIndex: 0).
        XCTAssertEqual(view.cellBinding(rowIndex: 0, columnIndex: 0).wrappedValue, "B1")
        // row1/columnC now sits at (rowIndex: 0, columnIndex: 1).
        XCTAssertEqual(view.cellBinding(rowIndex: 0, columnIndex: 1).wrappedValue, "C1")
        // row3/columnB (originally row index 2) now sits at (rowIndex: 1, columnIndex: 0).
        XCTAssertEqual(view.cellBinding(rowIndex: 1, columnIndex: 0).wrappedValue, "B3")
        // row3/columnC (originally rowIndex 2, columnIndex 2) now sits at (1, 1).
        XCTAssertEqual(view.cellBinding(rowIndex: 1, columnIndex: 1).wrappedValue, "C3")

        // Roster attachment survives the same roster being re-selected.
        XCTAssertTrue(view.isSelectedRosterAttached(toTabAt: 0))
    }

    func testCanDeleteRowForbidsRemovingTheFirstRowOnly() {
        let roster = DashboardRoster(name: "Test Roster", kind: .general, columns: [], rows: [])
        let tab = DashboardTab(name: "Test Tab", tiles: [])

        let view = DashboardRostersManagerView(
            rosters: .constant([roster]),
            tabs: .constant([tab]),
            selectedTabIndex: .constant(0),
            initialSelectedRosterID: roster.id
        )

        XCTAssertFalse(view.canDeleteRow(at: 0))
        XCTAssertTrue(view.canDeleteRow(at: 1))
        XCTAssertTrue(view.canDeleteRow(at: 2))
    }
}
