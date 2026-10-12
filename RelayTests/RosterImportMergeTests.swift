import XCTest
@testable import Relay

final class RosterImportMergeTests: XCTestCase {

    func testReplaceModeReturnsImportedDataAsIs() {
        let existingColumns = [DashboardRosterColumn(title: "Old")]
        let existingRows = [DashboardRosterRow(values: ["x": "y"])]
        let importedColumns = [DashboardRosterColumn(title: "Name"), DashboardRosterColumn(title: "Role")]
        let importedRows = [DashboardRosterRow(values: [importedColumns[0].id.uuidString: "Alice"])]

        let result = RosterImportMerge.apply(
            mode: .replace,
            existingColumns: existingColumns,
            existingRows: existingRows,
            importedColumns: importedColumns,
            importedRows: importedRows
        )

        XCTAssertEqual(result.columns, importedColumns)
        XCTAssertEqual(result.rows, importedRows)
    }

    func testReplaceModeCapsAtColumnAndRowLimits() {
        let manyColumns = (1...20).map { DashboardRosterColumn(title: "Col \($0)") }
        let manyRows = (1...300).map { _ in DashboardRosterRow() }

        let result = RosterImportMerge.apply(
            mode: .replace,
            existingColumns: [],
            existingRows: [],
            importedColumns: manyColumns,
            importedRows: manyRows
        )

        XCTAssertEqual(result.columns.count, 12)
        XCTAssertEqual(result.rows.count, 250)
    }

    func testAppendModeMergesColumnsAndFillsBlanksOnBothSides() {
        let existingColumn = DashboardRosterColumn(title: "Existing")
        let existingRow = DashboardRosterRow(values: [existingColumn.id.uuidString: "old value"])
        let importedColumn = DashboardRosterColumn(title: "Imported")
        let importedRow = DashboardRosterRow(values: [importedColumn.id.uuidString: "new value"])

        let result = RosterImportMerge.apply(
            mode: .append,
            existingColumns: [existingColumn],
            existingRows: [existingRow],
            importedColumns: [importedColumn],
            importedRows: [importedRow]
        )

        XCTAssertEqual(result.columns, [existingColumn, importedColumn])
        XCTAssertEqual(result.rows.count, 2)

        // The pre-existing row gains a blank entry for the new column.
        let mergedExistingRow = result.rows[0]
        XCTAssertEqual(mergedExistingRow.values[existingColumn.id.uuidString], "old value")
        XCTAssertEqual(mergedExistingRow.values[importedColumn.id.uuidString], "")

        // The appended row gains a blank entry for the pre-existing column.
        let appendedRow = result.rows[1]
        XCTAssertEqual(appendedRow.values[existingColumn.id.uuidString], "")
        XCTAssertEqual(appendedRow.values[importedColumn.id.uuidString], "new value")
    }

    func testAppendModeRespectsRemainingColumnSlots() {
        let existingColumns = (1...11).map { DashboardRosterColumn(title: "Existing \($0)") }
        let importedColumns = [DashboardRosterColumn(title: "A"), DashboardRosterColumn(title: "B")]

        let result = RosterImportMerge.apply(
            mode: .append,
            existingColumns: existingColumns,
            existingRows: [],
            importedColumns: importedColumns,
            importedRows: []
        )

        // Only 1 slot remains (12 - 11), so only the first imported column fits.
        XCTAssertEqual(result.columns.count, 12)
        XCTAssertEqual(result.columns.last, importedColumns[0])
    }

    func testAppendModeBlankFillsOnlyForColumnsThatActuallyFitUnderTheCap() {
        let existingColumns = (1...11).map { DashboardRosterColumn(title: "Existing \($0)") }
        let existingRow = DashboardRosterRow(values: [existingColumns[0].id.uuidString: "keep me"])
        let importedColumns = [DashboardRosterColumn(title: "Fits"), DashboardRosterColumn(title: "Dropped")]

        let result = RosterImportMerge.apply(
            mode: .append,
            existingColumns: existingColumns,
            existingRows: [existingRow],
            importedColumns: importedColumns,
            importedRows: []
        )

        // Only 1 slot remains (12 - 11), so only the first imported column fits.
        XCTAssertEqual(result.columns.count, 12)

        let mergedExistingRow = result.rows[0]
        // Pre-existing value is untouched.
        XCTAssertEqual(mergedExistingRow.values[existingColumns[0].id.uuidString], "keep me")
        // Blank-filled for the column that fit under the cap.
        XCTAssertEqual(mergedExistingRow.values[importedColumns[0].id.uuidString], "")
        // No entry at all for the column that didn't fit -- confirms the blank-fill loop
        // uses the capped column set, not the full imported column set.
        XCTAssertNil(mergedExistingRow.values[importedColumns[1].id.uuidString])
    }

    func testAppendModeRespectsRemainingRowSlots() {
        let existingRows = (1...249).map { _ in DashboardRosterRow() }
        let importedRows = [DashboardRosterRow(), DashboardRosterRow()]

        let result = RosterImportMerge.apply(
            mode: .append,
            existingColumns: [],
            existingRows: existingRows,
            importedColumns: [],
            importedRows: importedRows
        )

        // Only 1 slot remains (250 - 249), so only 1 of the 2 imported rows fits.
        XCTAssertEqual(result.rows.count, 250)
    }
}
