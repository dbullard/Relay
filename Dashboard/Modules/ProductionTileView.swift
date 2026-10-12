//
//  ProductionTilePlaceholderView.swift
//  Relay
//
//  Created by David Bullard on 11/16/25.
//


import SwiftUI

struct ProductionTileView: View {
    @Environment(\.tileTextFormatting) private var tileTextFormatting
    @Environment(\.tileCornerRadius) private var tileCornerRadius
    // MARK: - Text Formatting Helpers

    private var baseFontSize: CGFloat {
        CGFloat(tileTextFormatting?.fontSize ?? 24)
    }

    private var primaryFontWeight: Font.Weight {
        (tileTextFormatting?.fontWeight ?? .semibold).swiftUIFontWeight
    }

    private var resolvedPrimaryColor: Color {
        tileTextFormatting?.textColor?.swiftUIColor ?? Color.white
    }

    private var resolvedSecondaryColor: Color {
        resolvedPrimaryColor.opacity(0.7)
    }

    /// Resolved text alignment based on the tile's justification setting.
    private var resolvedTextAlignment: TextAlignment {
        switch tileTextFormatting?.justification ?? .leading {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }

    /// Resolved horizontal alignment for frames based on justification.
    private var resolvedHorizontalAlignment: Alignment {
        switch tileTextFormatting?.justification ?? .leading {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }

    private var headerFont: Font {
        .system(size: baseFontSize * 0.85, weight: primaryFontWeight)
    }

    private var captionFont: Font {
        .system(size: baseFontSize * 0.6, weight: .regular)
    }

    private func applyCapitalization(_ string: String) -> String {
        switch tileTextFormatting?.capitalization ?? .normal {
        case .normal:
            return string
        case .uppercase:
            return string.uppercased()
        case .lowercase:
            return string.lowercased()
        case .titlecase:
            return string.capitalized
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(applyCapitalization("Production Tile"))
                .font(headerFont)
                .foregroundStyle(resolvedPrimaryColor)
            Text(applyCapitalization("Wireless / console / gear status."))
                .font(captionFont)
                .foregroundStyle(resolvedSecondaryColor)
        }
        .padding(16)
        // Background removed — tile container supplies background
        .multilineTextAlignment(resolvedTextAlignment)
        .frame(maxWidth: .infinity, alignment: resolvedHorizontalAlignment)
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(RoundedRectangle(cornerRadius: tileCornerRadius))
    }
}
