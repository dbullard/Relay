//
//  CornerMask.swift
//  Relay
//
//  Created by David Bullard on 12/2/25.
//


import SwiftUI

// MARK: - Corner Masks

// `Sendable` (a plain `Int`-backed value type, safe to share) + `nonisolated` on every member:
// without these, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` makes the static constants below
// implicitly main-actor-isolated. That didn't show up as an intra-module diagnostic (this type
// and its `SelectiveRoundedCorners`/`ModuleCorners` consumers all live in the same target), but
// it broke `RelayTests/CornerRoundingConcurrencyTests.swift`, which references `.all` /
// `.topLeft` / etc. from inside `Task.detached` via `@testable import Relay` -- a real
// cross-module boundary where the isolation mismatch is enforced. `Shape.path(in:)` itself
// (in `SelectiveRoundedCorners`/`ModuleCorners` below) is unaffected: SwiftUI declares that
// protocol requirement `nonisolated`, so conforming implementations inherit that regardless of
// this module's default-isolation setting -- confirmed by 0 diagnostics for those two types
// both before and after this change.
public struct CornerMask: OptionSet, Sendable {
    public let rawValue: Int

    nonisolated public static let topLeft     = CornerMask(rawValue: 1 << 0)
    nonisolated public static let topRight    = CornerMask(rawValue: 1 << 1)
    nonisolated public static let bottomLeft  = CornerMask(rawValue: 1 << 2)
    nonisolated public static let bottomRight = CornerMask(rawValue: 1 << 3)

    nonisolated public static let all: CornerMask = [.topLeft, .topRight, .bottomLeft, .bottomRight]

    nonisolated public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}

// MARK: - Selective Rounded Rectangle Shape

public struct SelectiveRoundedCorners: Shape {
    let radius: CGFloat
    let corners: CornerMask

    public init(radius: CGFloat, corners: CornerMask) {
        self.radius = radius
        self.corners = corners
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()

        let r = min(radius, min(rect.width, rect.height) / 2)

        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY

        let tl = (corners.rawValue & CornerMask.topLeft.rawValue) != 0 ? r : 0
        let tr = (corners.rawValue & CornerMask.topRight.rawValue) != 0 ? r : 0
        let bl = (corners.rawValue & CornerMask.bottomLeft.rawValue) != 0 ? r : 0
        let br = (corners.rawValue & CornerMask.bottomRight.rawValue) != 0 ? r : 0

        // Start at top-left, shifted in by the top-left radius
        path.move(to: CGPoint(x: minX + tl, y: minY))

        // Top edge and top-right corner
        path.addLine(to: CGPoint(x: maxX - tr, y: minY))
        if tr > 0 {
            path.addArc(center: CGPoint(x: maxX - tr, y: minY + tr),
                        radius: tr,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(0),
                        clockwise: false)
        }

        // Right edge and bottom-right corner
        path.addLine(to: CGPoint(x: maxX, y: maxY - br))
        if br > 0 {
            path.addArc(center: CGPoint(x: maxX - br, y: maxY - br),
                        radius: br,
                        startAngle: .degrees(0),
                        endAngle: .degrees(90),
                        clockwise: false)
        }

        // Bottom edge and bottom-left corner
        path.addLine(to: CGPoint(x: minX + bl, y: maxY))
        if bl > 0 {
            path.addArc(center: CGPoint(x: minX + bl, y: maxY - bl),
                        radius: bl,
                        startAngle: .degrees(90),
                        endAngle: .degrees(180),
                        clockwise: false)
        }

        // Left edge and top-left corner
        path.addLine(to: CGPoint(x: minX, y: minY + tl))
        if tl > 0 {
            path.addArc(center: CGPoint(x: minX + tl, y: minY + tl),
                        radius: tl,
                        startAngle: .degrees(180),
                        endAngle: .degrees(270),
                        clockwise: false)
        }

        path.closeSubpath()
        return path
    }
}



// MARK: - Module Corner Style

public enum ModuleCornerStyle {
    case single
    case top
    case middle
    case bottom
    case leading
    case trailing
}

// MARK: - Module Shape Wrapper

public struct ModuleCorners: Shape {
    let radius: CGFloat
    let style: ModuleCornerStyle

    public init(radius: CGFloat, style: ModuleCornerStyle) {
        self.radius = radius
        self.style = style
    }

    public func path(in rect: CGRect) -> Path {
        switch style {
        case .single:
            return SelectiveRoundedCorners(radius: radius, corners: .all)
                .path(in: rect)

        case .top:
            return SelectiveRoundedCorners(radius: radius,
                                           corners: [.topLeft, .topRight])
                .path(in: rect)

        case .middle:
            return SelectiveRoundedCorners(radius: 0, corners: [])
                .path(in: rect)

        case .bottom:
            return SelectiveRoundedCorners(radius: radius,
                                           corners: [.bottomLeft, .bottomRight])
                .path(in: rect)

        case .leading:
            return SelectiveRoundedCorners(radius: radius,
                                           corners: [.topLeft, .bottomLeft])
                .path(in: rect)

        case .trailing:
            return SelectiveRoundedCorners(radius: radius,
                                           corners: [.topRight, .bottomRight])
                .path(in: rect)
        }
    }
}
