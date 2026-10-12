import SwiftUI

private struct AudioInputsSizingModifier: ViewModifier {
    let presentationStyle: AudioInputsConfigView.PresentationStyle

    func body(content: Content) -> some View {
        switch presentationStyle {
        case .standalone:
            content.frame(
                minWidth: AudioInputsConfigView.Layout.sheetWidth,
                idealWidth: AudioInputsConfigView.Layout.sheetWidth,
                maxWidth: AudioInputsConfigView.Layout.sheetWidth,
                minHeight: AudioInputsConfigView.Layout.sheetHeight,
                idealHeight: AudioInputsConfigView.Layout.sheetHeight,
                maxHeight: AudioInputsConfigView.Layout.sheetHeight,
                alignment: .topLeading
            )
        case .embedded:
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - AudioInputsConfigView

struct AudioInputsConfigView: View {
    enum Tab { case measurement, transcription }
    enum PresentationStyle { case standalone, embedded }

    enum Layout {
        static let sidebarWidth: CGFloat = 240
        static let sheetWidth: CGFloat = 960
        static let sheetHeight: CGFloat = 700
    }

    @State private var store = AudioInputsConfigStore.shared
    @State private var availableDevices: [DbReaderAudioDevice] = []
    @State private var inputPendingDelete: AudioInputConfig?
    @State private var selectedTab: Tab
    @State private var selectedMeasurementID: UUID?
    @State private var selectedTranscriptionID: UUID?
    @State private var transcriptionInputPendingDelete: TranscriptionInputConfig?
    @State private var transcriptionStore = TranscriptionInputsConfigStore.shared
    private let presentationStyle: PresentationStyle
    @Environment(\.dismiss) private var dismiss

    init(initialTab: Tab = .measurement, presentationStyle: PresentationStyle = .standalone) {
        _selectedTab = State(initialValue: initialTab)
        self.presentationStyle = presentationStyle
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Toolbar ──────────────────────────────────────────────────────
            HStack(spacing: 10) {
                Text("Audio Inputs")
                    .font(.headline)
                Spacer()
                Button {
                    addInput()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .help("Add Input")
                .accessibilityLabel("Add Input")
                if presentationStyle == .standalone {
                    Button("Done") { dismiss() }
                        .buttonStyle(.bordered)
                }
            }
            .padding(12)

            Divider()

            // ── Split layout ─────────────────────────────────────────────────
            HStack(spacing: 0) {
                // Left: tab picker + list
                VStack(spacing: 0) {
                    Picker("", selection: $selectedTab) {
                        Text("Measurement").tag(Tab.measurement)
                        Text("Transcription").tag(Tab.transcription)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    Divider()

                    switch selectedTab {
                    case .measurement: measurementList
                    case .transcription: transcriptionList
                    }
                }
                .frame(width: Layout.sidebarWidth)
                .frame(maxHeight: .infinity, alignment: .top)

                Divider()

                // Right: inline detail
                NavigationStack {
                    detailContent
                }
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
            }
        }
        .modifier(AudioInputsSizingModifier(presentationStyle: presentationStyle))
        .onAppear { availableDevices = DbReaderAudioDevices.microphones() }
        // ── Alerts ────────────────────────────────────────────────────────────
        .alert("Delete \"\(inputPendingDelete?.name ?? "Input")\"?",
               isPresented: Binding(
                get: { inputPendingDelete != nil },
                set: { if !$0 { inputPendingDelete = nil } }
               )) {
            Button("Delete", role: .destructive) {
                if let input = inputPendingDelete,
                   let idx = store.inputs.firstIndex(where: { $0.id == input.id }) {
                    if selectedMeasurementID == input.id { selectedMeasurementID = nil }
                    store.remove(at: IndexSet(integer: idx))
                }
                inputPendingDelete = nil
            }
            Button("Cancel", role: .cancel) { inputPendingDelete = nil }
        } message: {
            Text("This will remove the input from all modules that reference it.")
        }
        .alert("Delete \"\(transcriptionInputPendingDelete?.name ?? "Input")\"?",
               isPresented: Binding(
                get: { transcriptionInputPendingDelete != nil },
                set: { if !$0 { transcriptionInputPendingDelete = nil } }
               )) {
            Button("Delete", role: .destructive) {
                if let input = transcriptionInputPendingDelete,
                   let idx = transcriptionStore.inputs.firstIndex(where: { $0.id == input.id }) {
                    if selectedTranscriptionID == input.id { selectedTranscriptionID = nil }
                    transcriptionStore.remove(at: IndexSet(integer: idx))
                }
                transcriptionInputPendingDelete = nil
            }
            Button("Cancel", role: .cancel) { transcriptionInputPendingDelete = nil }
        } message: {
            Text("This will remove the transcription input.")
        }
    }

    // MARK: - Add helper

    private func addInput() {
        switch selectedTab {
        case .measurement:
            store.add()
            selectedMeasurementID = store.inputs.last?.id
        case .transcription:
            transcriptionStore.add()
            selectedTranscriptionID = transcriptionStore.inputs.last?.id
        }
    }

    // MARK: - Detail (right pane)

    @ViewBuilder
    private var detailContent: some View {
        switch selectedTab {
        case .measurement:
            if let id = selectedMeasurementID,
               let idx = store.inputs.firstIndex(where: { $0.id == id }) {
                AudioInputDetailView(input: $store.inputs[idx], availableDevices: availableDevices)
            } else {
                ContentUnavailableView(
                    "Select an Input",
                    systemImage: "mic",
                    description: Text("Choose a measurement input from the list to edit its settings.")
                )
            }
        case .transcription:
            if let id = selectedTranscriptionID,
               let idx = transcriptionStore.inputs.firstIndex(where: { $0.id == id }) {
                TranscriptionInputDetailView(input: $transcriptionStore.inputs[idx], availableDevices: availableDevices)
            } else {
                ContentUnavailableView(
                    "Select an Input",
                    systemImage: "waveform.badge.mic",
                    description: Text("Choose a transcription input from the list to edit its settings.")
                )
            }
        }
    }

    // MARK: - Measurement list (left pane)

    @ViewBuilder
    private var measurementList: some View {
        List(selection: $selectedMeasurementID) {
            if store.inputs.isEmpty {
                Text("No measurement inputs. Tap + to add one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(store.inputs) { input in
                    inputRow(for: input)
                        .tag(input.id)
                }
                .onDelete { offsets in
                    if let idx = offsets.first { inputPendingDelete = store.inputs[idx] }
                }
                .onMove { store.inputs.move(fromOffsets: $0, toOffset: $1) }
            }
        }
        .listStyle(.sidebar)

        loggingSection
    }

    private func inputRow(for input: AudioInputConfig) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(input.color.swiftUIColor)
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 2) {
                Text(input.name)
                    .foregroundStyle(.primary)
                    .font(.body)
                Text(deviceLabel(for: input))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(role: .destructive) {
                inputPendingDelete = input
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red.opacity(0.7))
                    .font(.body)
            }
            .buttonStyle(.plain)
            .help("Delete \(input.name)")
        }
        .contentShape(Rectangle())
    }

    // MARK: - Transcription list (left pane)

    @ViewBuilder
    private var transcriptionList: some View {
        List(selection: $selectedTranscriptionID) {
            if transcriptionStore.inputs.isEmpty {
                Text("No transcription inputs. Tap + to add one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(transcriptionStore.inputs) { input in
                    transcriptionRow(for: input)
                        .tag(input.id)
                }
                .onDelete { offsets in
                    if let idx = offsets.first { transcriptionInputPendingDelete = transcriptionStore.inputs[idx] }
                }
                .onMove { transcriptionStore.inputs.move(fromOffsets: $0, toOffset: $1) }
            }
        }
        .listStyle(.sidebar)

        Divider()
        Text("Transcription inputs have independent auto-gain from measurement inputs.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }

    private func transcriptionRow(for input: TranscriptionInputConfig) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(input.color.swiftUIColor)
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 2) {
                Text(input.name)
                    .foregroundStyle(.primary)
                    .font(.body)
                Text(transcriptionSubtitle(for: input))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(role: .destructive) {
                transcriptionInputPendingDelete = input
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red.opacity(0.7))
                    .font(.body)
            }
            .buttonStyle(.plain)
            .help("Delete \(input.name)")
        }
        .contentShape(Rectangle())
    }

    private func transcriptionSubtitle(for input: TranscriptionInputConfig) -> String {
        var parts: [String] = []
        if let uid = input.deviceUID,
           let device = availableDevices.first(where: { $0.uid == uid }) {
            parts.append("\(device.name) · ch \(input.channelIndex + 1)")
        } else {
            parts.append("Default device · ch \(input.channelIndex + 1)")
        }
        parts.append(input.autoGainEnabled ? "Auto-gain" : "Fixed gain")
        switch input.enginePreference {
        case .auto: break
        case .onDevice: parts.append("On-Device")
        case .cloud: parts.append("Cloud")
        }
        return parts.joined(separator: " · ")
    }

    private func deviceLabel(for input: AudioInputConfig) -> String {
        if let uid = input.deviceUID,
           let device = availableDevices.first(where: { $0.uid == uid }) {
            return "\(device.name) · ch \(input.channelIndex + 1)"
        } else if input.deviceUID != nil {
            // UID stored but not currently enumerated (device disconnected)
            return "Device unavailable · ch \(input.channelIndex + 1)"
        } else {
            return "Default device · ch \(input.channelIndex + 1)"
        }
    }

    // MARK: - Logging Section

    @ViewBuilder
    private var loggingSection: some View {
        let manager = SPLLoggingManager.shared
        Divider()
        VStack(alignment: .leading, spacing: 8) {
            Text("SPL Logging")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.top, 10)

            // Folder row
            HStack(spacing: 8) {
                Text("Folder")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                let displayPath = manager.settings.folderPath.isEmpty
                    ? SPLInputLogger.defaultFolderURL().path
                    : manager.settings.folderPath
                Text(displayPath)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Spacer()
                #if os(macOS)
                Button("Choose…") { chooseLogFolder() }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                #endif
            }
            .padding(.horizontal, 12)

            // Folder access error banner
            if let errorMsg = manager.folderAccessError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(errorMsg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
            }

            // Start / Stop button + status
            HStack(spacing: 12) {
                Button {
                    Task {
                        if manager.settings.isLogging {
                            await manager.stopLogging()
                        } else {
                            await manager.startLogging()
                        }
                    }
                } label: {
                    Label(
                        manager.settings.isLogging ? "Stop Logging" : "Start Logging",
                        systemImage: manager.settings.isLogging ? "stop.circle.fill" : "record.circle"
                    )
                }
                .buttonStyle(.bordered)
                .tint(manager.settings.isLogging ? .red : .green)

                if manager.settings.isLogging {
                    let count = AudioInputsConfigStore.shared.inputs.count
                    Label(
                        "Recording \(count) input\(count == 1 ? "" : "s")…",
                        systemImage: "circle.fill"
                    )
                    .foregroundStyle(.red)
                    .font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    #if os(macOS)
    private func chooseLogFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Log Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Security-scoped bookmarks only work in sandboxed builds.
        // For non-sandboxed (Beta/Release) builds, .withSecurityScope throws and
        // bookmarkData stays nil — file access is governed by TCC instead.
        let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
        var bookmarkData: Data? = nil
        if isSandboxed {
            bookmarkData = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }

        SPLLoggingManager.shared.settings.folderPath = url.path
        SPLLoggingManager.shared.settings.folderBookmarkData = bookmarkData
        SPLLoggingManager.shared.folderAccessError = nil
        SPLLoggingManager.shared.settings.save()
    }
    #endif
}

// MARK: - InputLevelBar

/// A compact horizontal level meter used inside audio input detail views.
private struct InputLevelBar: View {
    let level: Double
    let peak: Double

    private func meterColor() -> Color {
        peak >= 0.30 ? .red : peak >= 0.18 ? .yellow : .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Input Level")
                .font(.caption)
                .foregroundStyle(.secondary)
            GeometryReader { geo in
                let width = max(0, geo.size.width)
                let fillWidth = CGFloat(min(1.0, max(0.0, level))) * width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(meterColor())
                        .frame(width: max(4, fillWidth), height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - AudioInputDetailView

private struct AudioInputDetailView: View {
    @Binding var input: AudioInputConfig
    let availableDevices: [DbReaderAudioDevice]
    @State private var showingCalibration = false
    @StateObject private var levelMonitor = LiveTranscriptionLevelMonitor()

    var body: some View {
        Form {
            Section("Name") {
                TextField("Name", text: $input.name)
                ColorPicker("Color", selection: Binding(
                    get: { input.color.swiftUIColor },
                    set: { input.color = CodableColor($0) }
                ))
            }

            Section("Device") {
                Picker("Device", selection: $input.deviceUID) {
                    Text("Default").tag(nil as String?)
                    ForEach(availableDevices) { device in
                        Text(device.name).tag(device.uid as String?)
                    }
                }
                Stepper("Channel: \(input.channelIndex + 1)", value: $input.channelIndex, in: 0...31)
                InputLevelBar(level: levelMonitor.level, peak: levelMonitor.processedPeak)
            }

            Section {
                CalibrationOffsetField(value: $input.calibrationOffsetDb) {
                    // No manual engine update needed — AudioInputsConfigStore.inputs.didSet
                    // propagates the fresh config to AudioAnalysisEngine automatically.
                    // A manual call here would use a stale captured `input` and race with
                    // the didSet task, potentially overwriting the new value with the old one.
                }

                Button("Calibrate…") {
                    showingCalibration = true
                }
                .buttonStyle(.bordered)
            } header: {
                Text("Calibration")
            } footer: {
                Text("Offset applied to all SPL readings from this input across every module.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(input.name)
        .sheet(isPresented: $showingCalibration) {
            AudioInputCalibrationSheet(input: $input)
        }
        .onAppear { levelMonitor.start(deviceUID: input.deviceUID, channelIndex: input.channelIndex) }
        .onChange(of: input.deviceUID) { _, _ in levelMonitor.start(deviceUID: input.deviceUID, channelIndex: input.channelIndex) }
        .onChange(of: input.channelIndex) { _, _ in levelMonitor.start(deviceUID: input.deviceUID, channelIndex: input.channelIndex) }
        .onDisappear { levelMonitor.stop() }
    }
}

// MARK: - TranscriptionInputDetailView

private struct TranscriptionInputDetailView: View {
    @Binding var input: TranscriptionInputConfig
    let availableDevices: [DbReaderAudioDevice]
    @StateObject private var levelMonitor = LiveTranscriptionLevelMonitor()

    var body: some View {
        Form {
            Section("Name") {
                TextField("Name", text: $input.name)
                ColorPicker("Color", selection: Binding(
                    get: { input.color.swiftUIColor },
                    set: { input.color = CodableColor($0) }
                ))
            }

            Section("Device") {
                Picker("Device", selection: $input.deviceUID) {
                    Text("Default").tag(nil as String?)
                    ForEach(availableDevices) { device in
                        Text(device.name).tag(device.uid as String?)
                    }
                }
                Stepper("Channel: \(input.channelIndex + 1)", value: $input.channelIndex, in: 0...31)
                InputLevelBar(level: levelMonitor.level, peak: levelMonitor.processedPeak)
            }

            Section {
                Toggle("Auto-gain", isOn: $input.autoGainEnabled)
                if input.autoGainEnabled {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Sensitivity")
                            Spacer()
                            Text("\(Int(input.sensitivity * 100))%")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        HStack(spacing: 8) {
                            Text("Less").font(.caption).foregroundStyle(.secondary)
                            Slider(value: $input.sensitivity, in: 0.0...1.0)
                            Text("More").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Input Gain")
            } footer: {
                Text("Auto-gain normalizes signal to the transcription engine. Higher sensitivity picks up quieter speech; lower reduces background noise pickup.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Engine", selection: $input.enginePreference) {
                    Text("Auto").tag(TranscriptionEnginePreference.auto)
                    Text("On-Device").tag(TranscriptionEnginePreference.onDevice)
                    Text("Cloud").tag(TranscriptionEnginePreference.cloud)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Engine")
            } footer: {
                Text("Auto uses on-device when available for a single source, cloud otherwise. Multiple simultaneous sources always use the XPC transcription helper.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Profanity filter", isOn: Binding(
                    get: { input.profanitySettings.mode != .off },
                    set: { input.profanitySettings.mode = $0 ? .mask : .off }
                ))

                if input.profanitySettings.mode != .off {
                    Picker("Mode", selection: $input.profanitySettings.mode) {
                        Text("Mask (••••)").tag(LiveTranscriptionProfanityMode.mask)
                        Text("Remove").tag(LiveTranscriptionProfanityMode.remove)
                    }
                    .pickerStyle(.segmented)

                    Toggle("Use built-in list", isOn: $input.profanitySettings.includeDefaultList)

                    CustomBlockedWordsField(words: $input.profanitySettings.customBlockedWords)
                }
            } header: {
                Text("Profanity")
            } footer: {
                Text("Mask replaces detected words with bullets. Remove drops them entirely. Custom words are comma-separated and match whole words, case-insensitively.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach($input.wordFilters) { $filter in
                    HStack(spacing: 8) {
                        TextField("Transcribed", text: $filter.from)
                            .textFieldStyle(.roundedBorder)
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                        TextField("Replace with", text: $filter.to)
                            .textFieldStyle(.roundedBorder)
                        Button(role: .destructive) {
                            input.wordFilters.removeAll { $0.id == filter.id }
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button {
                    input.wordFilters.append(WordReplacementFilter())
                } label: {
                    Label("Add Word Filter", systemImage: "plus")
                }
            } header: {
                Text("Word Substitutions")
            } footer: {
                Text("Case-insensitive. Applied after profanity filtering. Use these for custom corrections or shorthand expansions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(input.name)
        .onAppear { levelMonitor.start(deviceUID: input.deviceUID, channelIndex: input.channelIndex) }
        .onChange(of: input.deviceUID) { _, _ in levelMonitor.start(deviceUID: input.deviceUID, channelIndex: input.channelIndex) }
        .onChange(of: input.channelIndex) { _, _ in levelMonitor.start(deviceUID: input.deviceUID, channelIndex: input.channelIndex) }
        .onDisappear { levelMonitor.stop() }
    }
}

// MARK: - CustomBlockedWordsField

/// Comma-separated editor for `customBlockedWords`. Edits are committed on Return or when the
/// field loses focus, not per keystroke, because every change to an input restarts its
/// transcription pipeline.
private struct CustomBlockedWordsField: View {
    @Binding var words: [String]

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Custom words", text: $text, prompt: Text("word, another word"))
            .focused($isFocused)
            .onAppear { text = words.joined(separator: ", ") }
            .onChange(of: words) { _, newValue in
                if !isFocused { text = newValue.joined(separator: ", ") }
            }
            .onChange(of: isFocused) { _, focused in
                if !focused { commit() }
            }
            .onSubmit(commit)
    }

    private func commit() {
        let parsed = text
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if parsed != words { words = parsed }
        text = parsed.joined(separator: ", ")
    }
}

// MARK: - CalibrationOffsetField

/// A text-field-based row that edits a dB calibration offset.
private struct CalibrationOffsetField: View {
    @Binding var value: Double
    let onChange: () -> Void

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Offset (dB)", text: $text)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .focused($isFocused)
            .onAppear { text = formattedValue }
            .onChange(of: value) { _, _ in if !isFocused { text = formattedValue } }
            .onSubmit { commit() }
            .onChange(of: isFocused) { _, focused in if !focused { commit() } }
            // Update value immediately as user types so dismissing the sheet
            // (e.g. tapping Done) without pressing Return still saves the entry.
            .onChange(of: text) { _, newText in
                guard isFocused else { return }
                let cleaned = newText.trimmingCharacters(in: .whitespaces)
                if let parsed = Double(cleaned) {
                    let clamped = max(-200, min(200, parsed))
                    if clamped != value {
                        value = clamped
                        onChange()
                    }
                }
            }
        if value != 0 {
            Button("Reset to 0 dB", role: .destructive) {
                value = 0
                text = "0.0"
                onChange()
            }
            .font(.callout)
        }
    }

    private var formattedValue: String {
        value == 0 ? "0.0" : String(format: "%.1f", value)
    }

    private func commit() {
        let cleaned = text.trimmingCharacters(in: .whitespaces)
        if let parsed = Double(cleaned) {
            let clamped = max(-200, min(200, parsed))
            value = clamped
            text = String(format: "%.1f", clamped)
            onChange()
        } else {
            text = formattedValue
        }
    }
}

// MARK: - AudioInputCalibrationSheet

struct AudioInputCalibrationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var input: AudioInputConfig

    @State private var targetDb: Double = 94.0
    @State private var targetText: String = "94.0"
    @State private var offsetText: String = "0.0"
    @State private var offsetDisplay: Double = 0.0

    @State private var liveRawDbFS: Double = -120.0
    @State private var isCapturing: Bool = false
    @State private var captureValues: [Double] = []
    @State private var captureRemaining: TimeInterval = 0
    @State private var capturedRawDbFS: Double? = nil
    @State private var warningText: String = ""
    @State private var applyAfterCapture: Bool = false
    @State private var captureTask: Task<Void, Never>? = nil
    @State private var splTask: Task<Void, Never>? = nil
    @State private var splSubID: UUID? = nil

    private let captureDuration: TimeInterval = 5
    private let captureTick: TimeInterval = 0.1

    var body: some View {
        let measuredRawDbFS = capturedRawDbFS ?? liveRawDbFS
        let offsetRequired = targetDb - measuredRawDbFS
        let captureProgress = isCapturing
            ? max(0, min(1, 1 - (captureRemaining / max(0.01, captureDuration))))
            : 1.0

        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Calibration Progress")
                    .font(.headline)
                ProgressView(value: captureProgress)
                    .progressViewStyle(.linear)
                Text("\(Int(captureProgress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Measured Level is: \(String(format: "%.1f", measuredRawDbFS)) dBFS RMS")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !warningText.isEmpty {
                Text(warningText)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            // Set target
            HStack {
                Text("Set this value to:")
                Spacer()
                TextField("", text: $targetText)
                    .frame(width: 70)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: targetText) { _, newValue in
                        if let v = Double(newValue) { targetDb = v }
                    }
                Text("dB")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Offset required is:")
                Spacer()
                Text(String(format: "%.1f dB", offsetRequired))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Mic sensitivity is:")
                Spacer()
                Text("NA")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Current Offset")
                Spacer()
                Text(String(format: "%.1f dB", offsetDisplay))
                    .foregroundStyle(.secondary)
            }

            // Manual set offset
            HStack {
                TextField("Offset dB", text: $offsetText)
                    .frame(width: 90)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                Button("Set Offset") {
                    let value = Double(offsetText) ?? offsetDisplay
                    applyOffset(value)
                }
                .buttonStyle(.bordered)
            }

            // Capture & Apply
            HStack {
                Spacer()
                Button(isCapturing ? "Capturing…" : (capturedRawDbFS == nil ? "Capture & Apply" : "Apply Calibration")) {
                    handleApplyTap()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCapturing)
            }

            // Cancel / Done
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Done") {
                    if let v = Double(offsetText) { applyOffset(v) }
                    if let captured = capturedRawDbFS {
                        let newOffset = targetDb - captured
                        applyOffset(newOffset)
                    }
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .frame(minWidth: 340)
        .onAppear {
            offsetDisplay = input.calibrationOffsetDb
            offsetText = String(format: "%.1f", input.calibrationOffsetDb)
            startSPLSubscription()
        }
        .onDisappear {
            stopSPLSubscription()
            captureTask?.cancel()
        }
    }

    // MARK: - SPL subscription

    private func startSPLSubscription() {
        splTask?.cancel()
        splTask = Task {
            let (subID, stream) = await AudioAnalysisEngine.shared.subscribeSPL(
                to: input.id,
                config: input
            )
            await MainActor.run { splSubID = subID }
            for await payload in stream {
                guard !Task.isCancelled else { break }
                await MainActor.run { liveRawDbFS = payload.rawDbFS - input.calibrationOffsetDb }
            }
        }
    }

    private func stopSPLSubscription() {
        splTask?.cancel()
        splTask = nil
        if let subID = splSubID {
            Task { await AudioAnalysisEngine.shared.unsubscribeSPL(id: subID) }
            splSubID = nil
        }
    }

    // MARK: - Capture

    private func handleApplyTap() {
        warningText = ""
        if capturedRawDbFS == nil {
            applyAfterCapture = true
            startCapture()
        } else {
            applyCalibration()
        }
    }

    private func startCapture() {
        captureTask?.cancel()
        captureValues.removeAll()
        capturedRawDbFS = nil
        warningText = ""
        // Zero the current offset so capture measures raw
        applyOffset(0.0)
        captureRemaining = captureDuration
        isCapturing = true
        let start = Date()
        captureTask = Task {
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(start)
                await MainActor.run {
                    captureRemaining = max(0, captureDuration - elapsed)
                    if liveRawDbFS > -115 { captureValues.append(liveRawDbFS) }
                }
                if elapsed >= captureDuration { break }
                let sleepNs = UInt64(captureTick * 1_000_000_000)
                try? await Task.sleep(nanoseconds: sleepNs)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run { finishCapture() }
        }
    }

    private func finishCapture() {
        isCapturing = false
        guard !captureValues.isEmpty else { return }
        let minVal = captureValues.min() ?? 0
        let maxVal = captureValues.max() ?? 0
        let variance = maxVal - minVal
        guard variance <= 2.0 else {
            warningText = "Signal varied by \(String(format: "%.1f", variance)) dB. Keep it within ±1 dB."
            applyAfterCapture = false
            return
        }
        capturedRawDbFS = captureValues.reduce(0, +) / Double(captureValues.count)
        if applyAfterCapture {
            applyAfterCapture = false
            applyCalibration()
        }
    }

    private func applyCalibration() {
        guard let measured = capturedRawDbFS else { return }
        let newOffset = targetDb - measured
        applyOffset(newOffset)
    }

    private func applyOffset(_ value: Double) {
        offsetDisplay = value
        offsetText = String(format: "%.1f", value)
        input.calibrationOffsetDb = value
        Task { await AudioAnalysisEngine.shared.updateInputConfig(input) }
    }
}
