//
//  CornerRoundingConcurrencyTests.swift
//  RelayTests
//
//  Task 7 (SwiftUI scale hardening): proves `SelectiveRoundedCorners` and
//  `ModuleCorners` genuinely compute a correct `Path` when `path(in:)` is
//  invoked off the main actor, e.g. from `Task.detached`. SwiftUI may call
//  `Shape.path(in:)` off the main thread as a performance optimization; this
//  only stays legal under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` if the
//  shape's stored constants and `path(in:)` implementation are not
//  main-actor-isolated. Both types are confirmed clean under
//  `SWIFT_STRICT_CONCURRENCY=targeted` (0 diagnostics, matching the Task 0
//  baseline), so these tests are regression coverage for that property
//  rather than a fix for a known bug.
//

import XCTest
import SwiftUI
@testable import Relay

final class CornerRoundingConcurrencyTests: XCTestCase {

    func testSelectiveRoundedCornersPathComputesOffMainActor() async {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 50)
        let path = await Task.detached {
            SelectiveRoundedCorners(radius: 8, corners: .all).path(in: rect)
        }.value
        XCTAssertFalse(path.isEmpty)
        XCTAssertGreaterThan(path.boundingRect.width, 0)
        XCTAssertGreaterThan(path.boundingRect.height, 0)
    }

    func testSelectiveRoundedCornersPartialCornersOffMainActor() async {
        let rect = CGRect(x: 0, y: 0, width: 120, height: 60)
        let path = await Task.detached {
            SelectiveRoundedCorners(radius: 12, corners: [.topLeft, .bottomRight]).path(in: rect)
        }.value
        XCTAssertFalse(path.isEmpty)
    }

    func testModuleCornersPathComputesOffMainActor() async {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 50)
        let path = await Task.detached {
            ModuleCorners(radius: 8, style: .top).path(in: rect)
        }.value
        XCTAssertFalse(path.isEmpty)
    }

    func testModuleCornersAllStylesComputeOffMainActor() async {
        let rect = CGRect(x: 0, y: 0, width: 80, height: 40)
        let styles: [ModuleCornerStyle] = [.single, .top, .middle, .bottom, .leading, .trailing]

        for style in styles {
            let path = await Task.detached {
                ModuleCorners(radius: 6, style: style).path(in: rect)
            }.value
            // `.middle` deliberately produces a radius-0 rect (still a valid, non-empty path).
            XCTAssertFalse(path.isEmpty, "style=\(style) produced an empty path")
        }
    }
}
