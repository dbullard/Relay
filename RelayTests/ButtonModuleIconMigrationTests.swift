// RelayTests/ButtonModuleIconMigrationTests.swift
import XCTest
@testable import Relay

final class ButtonModuleIconMigrationTests: XCTestCase {

    private func decoded(_ json: String) throws -> ButtonModuleIcon {
        let data = json.data(using: .utf8)!
        return try JSONDecoder().decode(ButtonModuleIcon.self, from: data)
    }

    func test_legacyPreset_migratesTo_symbol_withPresetSystemName() throws {
        let json = """
        {"source":"preset","preset":"play","systemName":"","placement":"leading","size":18}
        """
        let icon = try decoded(json)
        XCTAssertEqual(icon.source, .symbol)
        XCTAssertEqual(icon.systemName, "play.fill")
    }

    func test_legacyCustomSymbol_migratesTo_symbol_retainingSystemName() throws {
        let json = """
        {"source":"customSymbol","preset":"play","systemName":"bolt.heart.fill","placement":"leading","size":18}
        """
        let icon = try decoded(json)
        XCTAssertEqual(icon.source, .symbol)
        XCTAssertEqual(icon.systemName, "bolt.heart.fill")
    }

    func test_noSource_withSystemName_migratesTo_symbol() throws {
        let json = """
        {"systemName":"mic.fill","placement":"leading","size":18}
        """
        let icon = try decoded(json)
        XCTAssertEqual(icon.source, .symbol)
        XCTAssertEqual(icon.systemName, "mic.fill")
    }

    func test_noSource_emptySystemName_migratesTo_none() throws {
        let json = """
        {"systemName":"","placement":"leading","size":18}
        """
        let icon = try decoded(json)
        XCTAssertEqual(icon.source, .none)
    }

    func test_existingSymbol_roundTrips() throws {
        let icon = ButtonModuleIcon(source: .symbol, systemName: "flame.fill")
        let data = try JSONEncoder().encode(icon)
        let decoded = try JSONDecoder().decode(ButtonModuleIcon.self, from: data)
        XCTAssertEqual(decoded.source, .symbol)
        XCTAssertEqual(decoded.systemName, "flame.fill")
    }

    func test_encode_neverWritesPresetOrCustomSymbol() throws {
        let icon = ButtonModuleIcon(source: .symbol, systemName: "star.fill")
        let data = try JSONEncoder().encode(icon)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertFalse(json.contains("\"preset\""))
        XCTAssertFalse(json.contains("customSymbol"))
    }
}
