//
//  TimeModuleView.swift
//  Relay
//
//  Created by David Bullard on 11/19/25.
//

import SwiftUI
import Combine

struct TimeModuleView: View {
    @Binding var config: TimeModuleConfig
    let moduleID: UUID
    let isLiveMode: Bool

    private var selectedMode: TimeDisplayMode {
        TimeDisplayMode(rawValue: config.modeRaw) ?? .clock
    }
    enum TimeDisplayMode: String, CaseIterable, Identifiable, Codable {
        case clock
        case countdown
        case timer

        var title: String {
            switch self {
            case .clock:      return "Clock"
            case .countdown:  return "Countdown"
            case .timer:      return "Timer"
            }
        }
        var id: String { rawValue }
    }

    @Environment(\.tileTextFormatting) private var tileTextFormatting
    @Environment(\.tileCornerRadius) private var tileCornerRadius
    @Environment(\.dashboardIsTextInputActive) private var isTextInputActive
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
            .monospacedDigit()
    }

    /// Font for labels like "Countdown", "Timer", "Stopwatch".
    private var sectionHeaderFont: Font {
        .system(size: baseFontSize * 0.85, weight: primaryFontWeight)
    }

    /// Font for secondary info like the date, duration label, etc.
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

    // Clock
    @State private var now: Date = Date()
    @State private var clockTimeString: String = "--:--"
    @State private var clockDateString: String = ""

    private let sharedTick = SharedSecondTicker.shared.publisher

    private struct CountdownRuntimeState {
        var remainingSeconds: Int
        var isRunning: Bool
    }

    private struct TimerRuntimeState {
        var elapsedSeconds: Int
        var isRunning: Bool
    }

    private final class CountdownRuntimeStore {
        static let shared = CountdownRuntimeStore()

        private var states: [UUID: CountdownRuntimeState] = [:]

        func state(for moduleID: UUID) -> CountdownRuntimeState? {
            states[moduleID]
        }

        func setState(_ state: CountdownRuntimeState, for moduleID: UUID) {
            states[moduleID] = state
        }
    }

    private final class TimerRuntimeStore {
        static let shared = TimerRuntimeStore()

        private var states: [UUID: TimerRuntimeState] = [:]

        func state(for moduleID: UUID) -> TimerRuntimeState? {
            states[moduleID]
        }

        func setState(_ state: TimerRuntimeState, for moduleID: UUID) {
            states[moduleID] = state
        }
    }

    // DateFormatter cache (DateFormatter is expensive to create; do NOT allocate it in `body`).
    private final class FormatterCache {
        static let shared = FormatterCache()
        private init() {}

        private var timeFormatters: [String: DateFormatter] = [:]
        private var dateFormatters: [String: DateFormatter] = [:]

        func timeFormatter(format: String, locale: Locale, timeZone: TimeZone) -> DateFormatter {
            if let existing = timeFormatters[format] {
                existing.locale = locale
                existing.timeZone = timeZone
                return existing
            }
            let df = DateFormatter()
            df.locale = locale
            df.timeZone = timeZone
            df.dateFormat = format
            timeFormatters[format] = df
            return df
        }

        func dateFormatter(format: String, locale: Locale, timeZone: TimeZone) -> DateFormatter {
            if let existing = dateFormatters[format] {
                existing.locale = locale
                existing.timeZone = timeZone
                return existing
            }
            let df = DateFormatter()
            df.locale = locale
            df.timeZone = timeZone
            df.dateFormat = format
            dateFormatters[format] = df
            return df
        }
    }

    private func updateClockStrings(for date: Date) {
        let locale = Locale.current
        let tz = TimeZone.current

        let resolvedTimeFormat: String
        let trimmed = clockTimeFormat.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            resolvedTimeFormat = trimmed
        } else {
            resolvedTimeFormat = "h:mm a"
        }

        let tf = FormatterCache.shared.timeFormatter(format: resolvedTimeFormat, locale: locale, timeZone: tz)
        clockTimeString = tf.string(from: date)

        if clockShowsDate {
            let df = FormatterCache.shared.dateFormatter(format: clockDateFormat, locale: locale, timeZone: tz)
            clockDateString = df.string(from: date)
        } else {
            clockDateString = ""
        }
    }

    // Countdown
    private var countdownSeconds: Int { config.countdownSeconds }
    private var autoStartCountdownInLiveMode: Bool { config.autoStartCountdownInLiveMode }
    private var hidesCountdownStartButtonInLiveMode: Bool {
        isLiveMode && autoStartCountdownInLiveMode
    }
    @State private var remainingSeconds: Int = 300
    @State private var isCountdownRunning: Bool = false

    // Clock settings

    private var clockShowsDate: Bool { config.clockShowsDate }

    /// Stores a date format string (e.g. "EEE, MMM d").
    private var clockDateFormat: String { config.clockDateFormat }

    /// Stores a time format string (e.g. "HH:mm" or "h:mm a").
    /// When empty, we fall back to the 12/24h toggle defaults.
    private var clockTimeFormat: String { config.clockTimeFormat }

    // Timer (count up)
    private var autoStartTimerInLiveMode: Bool { config.autoStartTimerInLiveMode }
    private var timerElapsedAlertThresholdSeconds: Int? { config.timerElapsedAlertThresholdSeconds }
    private var timerElapsedAlertColor: Color { config.timerElapsedAlertColor.swiftUIColor }
    private var hidesTimerStartButtonInLiveMode: Bool {
        isLiveMode && autoStartTimerInLiveMode
    }
    private var resolvedTimerColor: Color {
        if let threshold = timerElapsedAlertThresholdSeconds,
           threshold > 0,
           timerSeconds >= threshold {
            return timerElapsedAlertColor
        }
        return resolvedPrimaryColor
    }
    @State private var timerSeconds: Int = 0
    @State private var isTimerRunning: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch selectedMode {
            case .clock:
                clockView
            case .countdown:
                countdownView
            case .timer:
                timerView
            }
        }
        .multilineTextAlignment(resolvedTextAlignment)
        .frame(maxWidth: .infinity, alignment: resolvedHorizontalAlignment)
        .clipShape(RoundedRectangle(cornerRadius: tileCornerRadius))
        // Timer receives moved to per-mode subviews for performance.
        .onChange(of: countdownSeconds, initial: false) { _, newValue in
            // When the configured countdown duration changes (from the Tile Edit view),
            // update the remaining time if the countdown is not currently running.
            if !isCountdownRunning {
                remainingSeconds = newValue
            }
        }
        .onAppear {
            restoreCountdownRuntimeStateIfNeeded()
            restoreTimerRuntimeStateIfNeeded()
            handleLiveModeChange(isLiveMode)
        }
        .onChange(of: isLiveMode, initial: false) { _, newValue in
            handleLiveModeChange(newValue)
        }
        .onChange(of: autoStartCountdownInLiveMode, initial: false) { _, newValue in
            guard selectedMode == .countdown else { return }
            if newValue, isLiveMode {
                startCountdownForLiveModeEntry()
            } else if !newValue, !isCountdownRunning {
                remainingSeconds = countdownSeconds
            }
        }
        .onChange(of: autoStartTimerInLiveMode, initial: false) { _, newValue in
            guard selectedMode == .timer else { return }
            if newValue, isLiveMode {
                startTimerForLiveModeEntry()
            }
        }
        .onChange(of: remainingSeconds, initial: false) { _, _ in
            persistCountdownRuntimeState()
        }
        .onChange(of: isCountdownRunning, initial: false) { _, _ in
            persistCountdownRuntimeState()
        }
        .onChange(of: timerSeconds, initial: false) { _, _ in
            persistTimerRuntimeState()
        }
        .onChange(of: isTimerRunning, initial: false) { _, _ in
            persistTimerRuntimeState()
        }
    }

    // MARK: - Subviews

    private var clockView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(clockTimeString)
                .font(timeFont)
                .foregroundStyle(resolvedPrimaryColor)

            if clockShowsDate {
                Text(clockDateString)
                    .font(captionFont)
                    .foregroundStyle(resolvedSecondaryColor)
            }
        }
        .multilineTextAlignment(resolvedTextAlignment)
        .frame(maxWidth: .infinity, alignment: resolvedHorizontalAlignment)
        .onAppear {
            updateClockStrings(for: now)
        }
        .onReceive(sharedTick) { date in
            guard !isTextInputActive else { return }
            now = date
            updateClockStrings(for: date)
        }
        .onChange(of: clockTimeFormat, initial: false) { _, _ in
            updateClockStrings(for: now)
        }
        .onChange(of: clockDateFormat, initial: false) { _, _ in
            updateClockStrings(for: now)
        }
        .onChange(of: clockShowsDate, initial: false) { _, _ in
            updateClockStrings(for: now)
        }
    }

    private var countdownView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if config.showHeader {
                Text(applyCapitalization("Countdown"))
                    .font(sectionHeaderFont)
                    .foregroundStyle(resolvedPrimaryColor)
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(formatSeconds(remainingSeconds))
                    .font(timeFont)
                    .foregroundStyle(resolvedPrimaryColor)

                Spacer()

                if !hidesCountdownStartButtonInLiveMode {
                    Button(isCountdownRunning ? "Pause" : "Start") {
                        if remainingSeconds <= 0 {
                            remainingSeconds = countdownSeconds
                        }
                        isCountdownRunning.toggle()
                    }
                    .buttonStyle(.bordered)
                }

                Button("Reset") {
                    isCountdownRunning = false
                    remainingSeconds = countdownSeconds
                }
            }
        }
        .multilineTextAlignment(resolvedTextAlignment)
        .frame(maxWidth: .infinity, alignment: resolvedHorizontalAlignment)
        .onAppear {
            if remainingSeconds <= 0 || remainingSeconds > countdownSeconds {
                remainingSeconds = countdownSeconds
            }
        }
        .onReceive(sharedTick) { _ in
            guard !isTextInputActive else { return }
            guard selectedMode == .countdown else { return }
            guard isCountdownRunning, remainingSeconds > 0 else { return }
            remainingSeconds -= 1
            if remainingSeconds <= 0 {
                isCountdownRunning = false
            }
        }
    }

    private var timerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if config.showHeader {
                    Text(applyCapitalization("Timer"))
                        .font(sectionHeaderFont)
                        .foregroundStyle(resolvedPrimaryColor)
                }
                Spacer()
                if !hidesTimerStartButtonInLiveMode {
                    Button(isTimerRunning ? "Pause" : "Start") {
                        isTimerRunning.toggle()
                    }
                    .buttonStyle(.bordered)
                }

                Button("Reset") {
                    isTimerRunning = false
                    timerSeconds = 0
                }
            }

            Text(formatSeconds(timerSeconds))
                .font(timeFont)
                .foregroundStyle(resolvedTimerColor)
        }
        .multilineTextAlignment(resolvedTextAlignment)
        .frame(maxWidth: .infinity, alignment: resolvedHorizontalAlignment)
        .onReceive(sharedTick) { _ in
            guard !isTextInputActive else { return }
            guard selectedMode == .timer else { return }
            guard isTimerRunning else { return }
            timerSeconds += 1
        }
    }

    // MARK: - Helpers

    private func formatSeconds(_ value: Int) -> String {
        let hours = value / 3600
        let minutes = (value % 3600) / 60
        let seconds = value % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    private func restoreCountdownRuntimeStateIfNeeded() {
        guard selectedMode == .countdown else { return }
        guard let state = CountdownRuntimeStore.shared.state(for: moduleID) else {
            persistCountdownRuntimeState()
            return
        }
        remainingSeconds = state.remainingSeconds
        isCountdownRunning = state.isRunning
    }

    private func persistCountdownRuntimeState() {
        CountdownRuntimeStore.shared.setState(
            CountdownRuntimeState(
                remainingSeconds: remainingSeconds,
                isRunning: isCountdownRunning
            ),
            for: moduleID
        )
    }

    private func restoreTimerRuntimeStateIfNeeded() {
        guard selectedMode == .timer else { return }
        guard let state = TimerRuntimeStore.shared.state(for: moduleID) else {
            persistTimerRuntimeState()
            return
        }
        timerSeconds = state.elapsedSeconds
        isTimerRunning = state.isRunning
    }

    private func persistTimerRuntimeState() {
        TimerRuntimeStore.shared.setState(
            TimerRuntimeState(
                elapsedSeconds: timerSeconds,
                isRunning: isTimerRunning
            ),
            for: moduleID
        )
    }

    private func handleLiveModeChange(_ isLiveMode: Bool) {
        switch selectedMode {
        case .countdown:
            guard autoStartCountdownInLiveMode else { return }
            if isLiveMode {
                startCountdownForLiveModeEntry()
            } else {
                isCountdownRunning = false
            }
        case .timer:
            guard autoStartTimerInLiveMode else { return }
            if isLiveMode {
                startTimerForLiveModeEntry()
            } else {
                isTimerRunning = false
            }
        case .clock:
            return
        }
    }

    private func startCountdownForLiveModeEntry() {
        if remainingSeconds <= 0 || remainingSeconds > countdownSeconds {
            remainingSeconds = countdownSeconds
        }
        isCountdownRunning = countdownSeconds > 0
    }

    private func startTimerForLiveModeEntry() {
        isTimerRunning = true
    }

    // formattedClockTime(_:) and formattedClockDate(_:) removed: replaced by formatter cache and precomputed strings.
}
private struct TimeModePicker: View {
    @Binding var config: TimeModuleConfig
    let onPersist: () -> Void

    private var selectedMode: TimeModuleView.TimeDisplayMode {
        TimeModuleView.TimeDisplayMode(rawValue: config.modeRaw) ?? .clock
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Mode")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(
                "Mode",
                selection: Binding(
                    get: { selectedMode },
                    set: { newValue in
                        config.modeRaw = newValue.rawValue
                        onPersist()
                    }
                )
            ) {
                ForEach(TimeModuleView.TimeDisplayMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}
private struct ClockSettingsView: View {
    @Binding var config: TimeModuleConfig
    let onPersist: () -> Void

    private let commonFormats: [(label: String, format: String)] = [
        ("Wed, Nov 19", "EEE, MMM d"),
        ("Wednesday, Nov 19", "EEEE, MMM d"),
        ("Nov 19, 2025", "MMM d, yyyy"),
        ("11/19/2025", "MM/dd/yyyy"),
        ("2025-11-19", "yyyy-MM-dd")
    ]

    private let commonTimeFormats: [(label: String, format: String)] = [
        ("14:30", "HH:mm"),
        ("14:30:05", "HH:mm:ss"),
        ("2:30 PM", "h:mm a"),
        ("2:30:05 PM", "h:mm:ss a")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Clock")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Time format", selection: Binding(
                get: {
                    if config.clockTimeFormat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return "h:mm a"
                    }
                    return config.clockTimeFormat
                },
                set: { newValue in
                    config.clockTimeFormat = newValue
                    onPersist()
                }
            )) {
                ForEach(commonTimeFormats, id: \.format) { item in
                    Text(item.label).tag(item.format)
                }
            }

            Toggle("Show date", isOn: Binding(
                get: { config.clockShowsDate },
                set: { newValue in
                    config.clockShowsDate = newValue
                    onPersist()
                }
            ))

            if config.clockShowsDate {
                Picker("Date format", selection: Binding(
                    get: { config.clockDateFormat },
                    set: { newValue in
                        config.clockDateFormat = newValue
                        onPersist()
                    }
                )) {
                    ForEach(commonFormats, id: \.format) { item in
                        Text(item.label).tag(item.format)
                    }
                }
            }
        }
        .padding(.top, 6)
    }
}

private struct CountdownSettingsView: View {
    @Binding var config: TimeModuleConfig
    let onPersist: () -> Void

    private var minutesBinding: Binding<Int> {
        Binding(
            get: { max(0, config.countdownSeconds / 60) },
            set: { newMinutes in
                let clamped = max(0, newMinutes)
                config.countdownSeconds = clamped * 60
                onPersist()
            }
        )
    }

    private let presets: [(label: String, minutes: Int)] = [
        ("1m", 1),
        ("2m", 2),
        ("5m", 5),
        ("10m", 10),
        ("15m", 15)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Countdown")
                .font(.caption)
                .foregroundStyle(.secondary)

            Stepper(value: minutesBinding, in: 0...240) {
                Text("Start time: \(max(0, config.countdownSeconds / 60)) min")
            }

            HStack(spacing: 8) {
                ForEach(presets, id: \.label) { p in
                    Button(p.label) {
                        config.countdownSeconds = p.minutes * 60
                        onPersist()
                    }
                    .buttonStyle(.bordered)
                }
            }

            Toggle("Auto start in live mode", isOn: Binding(
                get: { config.autoStartCountdownInLiveMode },
                set: { newValue in
                    config.autoStartCountdownInLiveMode = newValue
                    onPersist()
                }
            ))
        }
        .padding(.top, 6)
    }
}

private struct TimerSettingsView: View {
    @Binding var config: TimeModuleConfig
    let onPersist: () -> Void

    private var alertEnabledBinding: Binding<Bool> {
        Binding(
            get: { config.timerElapsedAlertThresholdSeconds != nil },
            set: { newValue in
                config.timerElapsedAlertThresholdSeconds = newValue ? max(60, config.timerElapsedAlertThresholdSeconds ?? 600) : nil
                onPersist()
            }
        )
    }

    private var alertMinutesBinding: Binding<Int> {
        Binding(
            get: { max(1, (config.timerElapsedAlertThresholdSeconds ?? 600) / 60) },
            set: { newMinutes in
                config.timerElapsedAlertThresholdSeconds = max(1, newMinutes) * 60
                onPersist()
            }
        )
    }

    private var alertSecondsBinding: Binding<Int> {
        Binding(
            get: {
                let totalSeconds = config.timerElapsedAlertThresholdSeconds ?? 600
                return totalSeconds % 60
            },
            set: { newSeconds in
                let clampedSeconds = min(max(0, newSeconds), 59)
                let minutes = max(0, (config.timerElapsedAlertThresholdSeconds ?? 600) / 60)
                config.timerElapsedAlertThresholdSeconds = (minutes * 60) + clampedSeconds
                onPersist()
            }
        )
    }

    private var alertColorBinding: Binding<Color> {
        Binding(
            get: { config.timerElapsedAlertColor.swiftUIColor },
            set: { newValue in
                config.timerElapsedAlertColor = CodableColor(newValue)
                onPersist()
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Timer")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Auto start in live mode", isOn: Binding(
                get: { config.autoStartTimerInLiveMode },
                set: { newValue in
                    config.autoStartTimerInLiveMode = newValue
                    onPersist()
                }
            ))

            Toggle("Change color after elapsed time", isOn: alertEnabledBinding)

            if config.timerElapsedAlertThresholdSeconds != nil {
                Stepper(value: alertMinutesBinding, in: 0...240) {
                    let totalSeconds = config.timerElapsedAlertThresholdSeconds ?? 600
                    let minutes = totalSeconds / 60
                    let seconds = totalSeconds % 60
                    Text(String(format: "Alert after: %d:%02d", minutes, seconds))
                }

                HStack(spacing: 10) {
                    Stepper(value: alertSecondsBinding, in: 0...59) {
                        Text("Seconds: \(alertSecondsBinding.wrappedValue)")
                    }
                }

                HStack(spacing: 10) {
                    Text("Alert color")
                    ColorPicker("", selection: alertColorBinding, supportsOpacity: false)
                        .labelsHidden()
                }
            }
        }
        .padding(.top, 6)
    }
}

enum TimeModulePlugin: DashboardModulePlugin {
    static var kind: DashboardModuleKind { .time }

    static func tileView(
        tab: Binding<DashboardTab>,
        tile: Binding<DashboardTileModel>,
        module: Binding<DashboardModuleModel>,
        isLiveMode: Bool
    ) -> AnyView {
        let configBinding = Binding<TimeModuleConfig>(
            get: { module.wrappedValue.timeConfig ?? TimeModuleConfig.default() },
            set: { newValue in
                var updated = module.wrappedValue
                updated.timeConfig = newValue
                module.wrappedValue = updated
            }
        )
        return AnyView(TimeModuleView(
            config: configBinding,
            moduleID: module.wrappedValue.id,
            isLiveMode: isLiveMode
        ))
    }

    static func settingsView(
        showsHeader: Binding<Bool>,
        onPersist: @escaping () -> Void
    ) -> AnyView {
        _ = showsHeader
        return AnyView(TimeModuleSettingsHost(
            config: .constant(TimeModuleConfig.default()),
            onPersist: onPersist
        ))
    }
}
struct TimeModuleSettingsHost: View {
    @Binding var config: TimeModuleConfig
    let onPersist: () -> Void

    private var selectedMode: TimeModuleView.TimeDisplayMode {
        TimeModuleView.TimeDisplayMode(rawValue: config.modeRaw) ?? .clock
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Show header", isOn: Binding(
                get: { config.showHeader },
                set: { newValue in
                    config.showHeader = newValue
                    onPersist()
                }
            ))

            TimeModePicker(config: $config, onPersist: onPersist)

            switch selectedMode {
            case .clock:
                ClockSettingsView(config: $config, onPersist: onPersist)
            case .countdown:
                CountdownSettingsView(config: $config, onPersist: onPersist)
            case .timer:
                TimerSettingsView(config: $config, onPersist: onPersist)
            }
        }
        .toggleStyle(.switch)
        .padding(.vertical, 6)
    }
}
