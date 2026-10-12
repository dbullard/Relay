//
//  TimecodeModuleView.swift
//  Relay
//
//  Created by David Bullard on 11/19/25.
//

import SwiftUI
import Combine
import CoreMIDI

struct TimecodeModuleView: View {
    @Binding var config: TimecodeModuleConfig

    @Environment(\.tileTextFormatting) private var tileTextFormatting
    @Environment(\.tileCornerRadius) private var tileCornerRadius

    // Local mirror of the shared TimecodeService so we avoid wrapper/dynamicMember issues.
    @State private var timecodeString: String = "--:--:--:--"
    @State private var isTimecodeLocked: Bool = false
    @State private var frameRateLabel: String = "Unknown"

    // MARK: - Text Formatting Helpers

    /// Base font size for this tile; other sizes are scaled from here.
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

    /// Font for the main time display (big numbers).
    private var timeFont: Font {
        .system(size: baseFontSize * 1.3, weight: primaryFontWeight, design: .rounded)
    }

    /// Font for labels like "Timecode".
    private var sectionHeaderFont: Font {
        .system(size: baseFontSize * 0.85, weight: primaryFontWeight)
    }

    /// Font for secondary info like frame rate.
    private var captionFont: Font {
        .system(size: baseFontSize * 0.7, weight: .regular)
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
            if config.showHeader {
                HStack {
                    Text(applyCapitalization("Timecode"))
                        .font(sectionHeaderFont)
                        .foregroundStyle(resolvedSecondaryColor)

                    Spacer()
                }
            }

            ZStack(alignment: resolvedHorizontalAlignment) {
                Text("88:88:88:88")
                    .font(timeFont)
                    .monospacedDigit()
                    .opacity(0)
                Text(timecodeString)
                    .font(timeFont)
                    .monospacedDigit()
                    .foregroundStyle(isTimecodeLocked ? resolvedPrimaryColor : Color.red)
            }

            // Show detected frame rate when we know it and have lock.
            if isTimecodeLocked && frameRateLabel != "Unknown" {
                Text("\(frameRateLabel) fps")
                    .font(captionFont)
                    .foregroundStyle(resolvedSecondaryColor)
            }
        }
        .multilineTextAlignment(resolvedTextAlignment)
        .frame(maxWidth: .infinity, alignment: resolvedHorizontalAlignment)
        .clipShape(RoundedRectangle(cornerRadius: tileCornerRadius))
        .onReceive(TimecodeService.shared.$timecodeString) { value in
            timecodeString = value
        }
        .onReceive(TimecodeService.shared.$isLocked) { value in
            isTimecodeLocked = value
        }
        .onReceive(TimecodeService.shared.$frameRateLabel) { value in
            frameRateLabel = value
        }
    }
}

private struct MIDISourceOption: Identifiable, Hashable {
    let id: Int
    let name: String
}

private enum MIDIInputDiscovery {
    static func currentSources() -> [MIDISourceOption] {
        let count = MIDIGetNumberOfSources()
        var result: [MIDISourceOption] = []
        result.reserveCapacity(Int(count))

        for i in 0..<count {
            let endpoint = MIDIGetSource(i)
            guard endpoint != 0 else { continue }

            var uniqueID: Int32 = 0
            MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID)

            var nameRef: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &nameRef)
            let name = (nameRef?.takeRetainedValue() as String?) ?? "MIDI Source \(i)"

            result.append(MIDISourceOption(id: Int(uniqueID), name: name))
        }

        // Sort alphabetically for UX.
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

private struct TimecodeSettingsView: View {
    @Binding var config: TimecodeModuleConfig
    let onPersist: () -> Void

    @State private var sources: [MIDISourceOption] = MIDIInputDiscovery.currentSources()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Timecode")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("MIDI input", selection: Binding(
                get: { config.timecodeMIDISourceID },
                set: { newValue in
                    config.timecodeMIDISourceID = newValue

                    let id32: Int32? = (newValue == -1) ? nil : Int32(newValue)
                    TimecodeService.shared.preferredMIDISourceChanged(uniqueID: id32)

                    onPersist()
                }
            )) {
                Text("Automatic").tag(-1)
                ForEach(sources) { src in
                    Text(src.name).tag(src.id)
                }
            }

            Button("Refresh MIDI devices") {
                sources = MIDIInputDiscovery.currentSources()
            }
            .dashboardLinkButtonStyle()
        }
        .padding(.top, 6)
    }
}

extension TimecodeService {
    /// Hook called by the Timecode module settings UI when the preferred MIDI source changes.
    /// Implement the actual switching logic inside `TimecodeService` (or observe the posted notification).
    func preferredMIDISourceChanged(uniqueID: Int32?) {
        NotificationCenter.default.post(
            name: .timecodeModulePreferredMIDISourceChanged,
            object: uniqueID
        )
    }
}

extension Notification.Name {
    static let timecodeModulePreferredMIDISourceChanged = Notification.Name("timecode_module_preferred_midi_source_changed")
}

enum TimecodeModulePlugin: DashboardModulePlugin {
    static var kind: DashboardModuleKind { .timecode }

    static func tileView(
        tab: Binding<DashboardTab>,
        tile: Binding<DashboardTileModel>,
        module: Binding<DashboardModuleModel>,
        isLiveMode: Bool
    ) -> AnyView {
        let configBinding = Binding<TimecodeModuleConfig>(
            get: { module.wrappedValue.timecodeConfig ?? TimecodeModuleConfig.default() },
            set: { newValue in
                var updated = module.wrappedValue
                updated.timecodeConfig = newValue
                module.wrappedValue = updated
            }
        )
        return AnyView(TimecodeModuleView(config: configBinding))
    }

    static func settingsView(
        showsHeader: Binding<Bool>,
        onPersist: @escaping () -> Void
    ) -> AnyView {
        _ = showsHeader
        return AnyView(TimecodeModuleSettingsHost(
            config: .constant(TimecodeModuleConfig.default()),
            onPersist: onPersist
        ))
    }
}

struct TimecodeModuleSettingsHost: View {
    @Binding var config: TimecodeModuleConfig
    let onPersist: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Show header", isOn: Binding(
                get: { config.showHeader },
                set: { newValue in
                    config.showHeader = newValue
                    onPersist()
                }
            ))

            TimecodeSettingsView(config: $config, onPersist: onPersist)
        }
        .toggleStyle(.switch)
        .padding(.vertical, 6)
    }
}
