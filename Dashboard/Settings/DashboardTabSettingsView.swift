//
//  DashboardTabSettingsView.swift
//  Relay
//
//  Created by OpenAI Codex on 4/14/26.
//

import SwiftUI
import UniformTypeIdentifiers

struct DashboardTabSettingsView: View {
    @Binding var tab: DashboardTab
    let onMakeSyncedTab: () -> Void
    let onStopSyncingTab: () -> Void
    let onResizeCanvas: (CGSize) -> Void

    @State private var selection: TabSettingsPage = .general
    #if os(iOS)
    private var isIPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tab Settings")
                .font(.title2.bold())

            Text("Configure settings that apply to this tab, including canvas size, sync, Planning Center, and scheduling.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            #if os(macOS)
            Picker("Section", selection: $selection) {
                ForEach(TabSettingsPage.allCases) { page in
                    Text(page.rawValue).tag(page)
                }
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 4)

            Group {
                switch selection {
                case .general:
                    TabGeneralSettingsView(tab: $tab, onMakeSyncedTab: onMakeSyncedTab, onStopSyncingTab: onStopSyncingTab, onResizeCanvas: onResizeCanvas)
                case .planningCenter:
                    PCOTabServiceConfigView(tab: $tab)
                case .schedule:
                    TabScheduleSettingsView(tab: $tab)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            #else
            if isIPad {
                Picker("Section", selection: $selection) {
                    ForEach(TabSettingsPage.allCases) { page in
                        Text(page.rawValue).tag(page)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 4)

                Group {
                    switch selection {
                    case .general:
                        TabGeneralSettingsView(tab: $tab, onMakeSyncedTab: onMakeSyncedTab, onStopSyncingTab: onStopSyncingTab, onResizeCanvas: onResizeCanvas)
                    case .planningCenter:
                        PCOTabServiceConfigView(tab: $tab)
                    case .schedule:
                        TabScheduleSettingsView(tab: $tab)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                NavigationStack {
                    List {
                        ForEach(TabSettingsPage.allCases) { page in
                            NavigationLink(value: page) {
                                Label(page.rawValue, systemImage: page.systemImage)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .navigationDestination(for: TabSettingsPage.self) { page in
                        Group {
                            switch page {
                            case .general:
                                TabGeneralSettingsView(tab: $tab, onMakeSyncedTab: onMakeSyncedTab, onStopSyncingTab: onStopSyncingTab, onResizeCanvas: onResizeCanvas)
                            case .planningCenter:
                                PCOTabServiceConfigView(tab: $tab)
                            case .schedule:
                                TabScheduleSettingsView(tab: $tab)
                            }
                        }
                        .navigationTitle(page.rawValue)
                        .navigationBarTitleDisplayMode(.inline)
                    }
                }
            }
            #endif
        }
        .padding(24)
        #if os(macOS)
        .frame(minWidth: 720, idealWidth: 860, maxWidth: 980, minHeight: 560, idealHeight: 640, maxHeight: 760)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        #endif
    }
}

private enum TabSettingsPage: String, CaseIterable, Identifiable {
    case general = "General"
    case planningCenter = "Planning Center"
    case schedule = "Schedule"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .general:
            return "slider.horizontal.below.rectangle"
        case .planningCenter:
            return "calendar.badge.clock"
        case .schedule:
            return "clock.badge"
        }
    }
}

private struct TabGeneralSettingsView: View {
    @Binding var tab: DashboardTab
    @EnvironmentObject private var lanService: LANSharedTabsService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.proUpgradeAction) private var proUpgradeAction
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    let onMakeSyncedTab: () -> Void
    let onStopSyncingTab: () -> Void
    let onResizeCanvas: (CGSize) -> Void

    @State private var widthText: String = ""
    @State private var heightText: String = ""
    @State private var showsStopSyncConfirmation = false

    private var currentCanvasSize: CGSize {
        tab.canvasSize ?? DashboardCanvasBoundsStore.shared.size
    }

    private func syncSizeDraftFromTab() {
        let size = currentCanvasSize
        widthText = "\(Int(size.width))"
        heightText = "\(Int(size.height))"
    }

    /// Applies the width/height draft only if it parses and actually differs from the tab's
    /// current size. Called from Save, not as the user types — Cancel relies on this never
    /// having run so it can just dismiss without reverting anything.
    private func saveCanvasSizeIfChanged() {
        guard let width = Double(widthText), let height = Double(heightText) else { return }
        let clampedWidth = min(max(width, DashboardCanvasBoundsStore.minSize.width), DashboardCanvasBoundsStore.maxSize.width)
        let clampedHeight = min(max(height, DashboardCanvasBoundsStore.minSize.height), DashboardCanvasBoundsStore.maxSize.height)
        let newSize = CGSize(width: clampedWidth, height: clampedHeight)
        guard newSize != currentCanvasSize else { return }
        onResizeCanvas(newSize)
    }

    private func saveAndDismiss() {
        saveCanvasSizeIfChanged()
        dismiss()
    }

    private var isSynced: Bool { tab.syncGroupID != nil }

    private var pairedEnabledDevices: [PairedDevice] {
        lanService.pairedDevices.values
            .filter { $0.isEnabled }
            .sorted { $0.deviceName.localizedCaseInsensitiveCompare($1.deviceName) == .orderedAscending }
    }

    private func isLive(_ device: PairedDevice) -> Bool {
        guard let groupID = tab.syncGroupID else { return false }
        return lanService.liveSubscriberDeviceIDs(for: groupID).contains(device.deviceId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("General")
                        .font(.title3.bold())
                    Text("Tab-wide layout and sync. Sync can also be toggled from the tab's right-click menu.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if tab.lanMirrorShareId != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("This tab mirrors another device")
                            .font(.headline)
                        Text("Canvas size and sync are controlled by the host device, not from here.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.secondary.opacity(0.05))
                    )
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Canvas")
                            .font(.headline)

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Width")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("Width", text: $widthText)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 90)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Height")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("Height", text: $heightText)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 90)
                            }
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: Binding(
                            get: { isSynced },
                            set: { newValue in
                                if newValue {
                                    guard subscriptionManager.hasPro else {
                                        proUpgradeAction()
                                        return
                                    }
                                    onMakeSyncedTab()
                                } else if tab.syncIsOwner {
                                    onStopSyncingTab()
                                } else {
                                    showsStopSyncConfirmation = true
                                }
                            }
                        )) {
                            Text("Sync This Tab")
                                .font(.headline)
                        }

                        Text("Share this tab live with paired devices. Edits from any device appear on all of them.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if isSynced {
                            Divider()

                            Text("Devices")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            if pairedEnabledDevices.isEmpty {
                                Text("No paired devices yet. Pair devices in Settings → Sync & Mirror.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(pairedEnabledDevices, id: \.deviceId) { device in
                                        HStack {
                                            Text(device.deviceName)
                                                .font(.subheadline)
                                            Spacer()
                                            if isLive(device) {
                                                Label("Live", systemImage: "circle.fill")
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(.green)
                                                    .labelStyle(.titleAndIcon)
                                            } else {
                                                Text("Not open")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                            }

                            Text("Manage pairing and permissions in Settings → Sync & Mirror.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            syncSizeDraftFromTab()
        }
        .onChange(of: tab.id, initial: false) { _, _ in
            syncSizeDraftFromTab()
        }
        .onChange(of: tab.canvasSize, initial: false) { _, _ in
            syncSizeDraftFromTab()
        }

        HStack {
            Spacer()
            Button("Cancel") {
                dismiss()
            }
            Button("Save") {
                saveAndDismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.top, 12)
        }
        .confirmationDialog(
            "Stop syncing this tab?",
            isPresented: $showsStopSyncConfirmation,
            titleVisibility: .visible
        ) {
            Button("Stop Syncing", role: .destructive) {
                onStopSyncingTab()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll keep a local copy and stop receiving updates from other devices.")
        }
    }
}

private struct TabScheduleSettingsView: View {
    @Binding var tab: DashboardTab
    @Environment(\.dismiss) private var dismiss
    @Environment(\.proUpgradeAction) private var proUpgradeAction
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared

    @State private var scheduleEnabledDraft: Bool = false
    @State private var scheduleRulesDraft: [DashboardTabScheduleRule] = []
    @State private var initialScheduleEnabled: Bool = false
    @State private var initialScheduleRules: [DashboardTabScheduleRule] = []

    private let weekdays: [(value: Int, label: String)] = [
        (1, "Su"),
        (2, "Mo"),
        (3, "Tu"),
        (4, "We"),
        (5, "Th"),
        (6, "Fr"),
        (7, "Sa")
    ]

    private var hasScheduleChanges: Bool {
        scheduleEnabledDraft != initialScheduleEnabled || scheduleRulesDraft != initialScheduleRules
    }

    private func syncDraftFromTab() {
        scheduleEnabledDraft = tab.tabScheduleEnabled
        scheduleRulesDraft = tab.tabScheduleRules
        initialScheduleEnabled = tab.tabScheduleEnabled
        initialScheduleRules = tab.tabScheduleRules
    }

    private func applyDraftToTab() {
        tab.tabScheduleEnabled = scheduleEnabledDraft
        tab.tabScheduleRules = scheduleRulesDraft
        initialScheduleEnabled = scheduleEnabledDraft
        initialScheduleRules = scheduleRulesDraft
    }

    private func revertDraft() {
        scheduleEnabledDraft = initialScheduleEnabled
        scheduleRulesDraft = initialScheduleRules
    }

    private func addRule() {
        let defaultName = "Rule \(scheduleRulesDraft.count + 1)"
        scheduleRulesDraft.append(DashboardTabScheduleRule(name: defaultName))
    }

    private func deleteRule(at index: Int) {
        guard scheduleRulesDraft.indices.contains(index) else { return }
        scheduleRulesDraft.remove(at: index)
    }

    private func moveRule(at index: Int, by delta: Int) {
        let newIndex = index + delta
        guard scheduleRulesDraft.indices.contains(index),
              scheduleRulesDraft.indices.contains(newIndex) else { return }
        let rule = scheduleRulesDraft.remove(at: index)
        scheduleRulesDraft.insert(rule, at: newIndex)
    }

    private func summaryText(for rule: DashboardTabScheduleRule) -> String {
        let dayLabels = weekdays
            .filter { rule.weekdays.contains($0.value) }
            .map(\.label)
            .joined(separator: " ")
        if rule.isAllDay {
            return "\(dayLabels.isEmpty ? "No days" : dayLabels) • All day"
        }
        return "\(dayLabels.isEmpty ? "No days" : dayLabels) • \(timeLabel(minutes: rule.startMinutes)) - \(timeLabel(minutes: rule.endMinutes))"
    }

    private func timeLabel(minutes: Int) -> String {
        let clamped = max(0, min(24 * 60, minutes))
        let components = DateComponents(hour: clamped / 60, minute: clamped % 60)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: Calendar.current.date(from: components) ?? .now)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("Tab Schedule")
                            .font(.title3.bold())
                        if !subscriptionManager.hasPro {
                            ProBadgeView(fontSize: 10)
                        }
                    }
                    Text("Schedule when this tab should become active. Rules are checked in order, and the first matching tab wins.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !subscriptionManager.hasPro {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.secondary)
                            Text("Tab scheduling requires Pro.")
                                .font(.headline)
                        }

                        Text("Free mode includes a single tab, so scheduled tab switching is only available with Pro.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button("Upgrade to Pro") {
                            proUpgradeAction()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.secondary.opacity(0.08))
                    )
                } else {
                    Toggle("Enable scheduled tab switching for this tab", isOn: $scheduleEnabledDraft)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Rules")
                                .font(.headline)
                            Spacer()
                            Button {
                                addRule()
                            } label: {
                                Label("Add Rule", systemImage: "plus")
                            }
                        }

                        if scheduleRulesDraft.isEmpty {
                            Text("No schedule rules yet. Add a rule to choose weekdays and time ranges for this tab.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach($scheduleRulesDraft) { $rule in
                                // Position (for move up/down bounds and the "at index" mutators)
                                // is re-resolved by stable rule.id, not captured from the
                                // ForEach's enumeration, so a delete/reorder mid-list can't
                                // leave a later row acting on the wrong rule. `rule` always
                                // comes from `scheduleRulesDraft` in this same synchronous
                                // render pass, so the lookup provably can't fail; force-unwrap
                                // so a future refactor that breaks that invariant crashes
                                // loudly instead of silently retargeting row 0.
                                let index = scheduleRulesDraft.firstIndex(where: { $0.id == rule.id })!
                                TabScheduleRuleEditor(
                                    rule: $rule,
                                    index: index,
                                    totalCount: scheduleRulesDraft.count,
                                    weekdays: weekdays,
                                    summaryText: summaryText(for: rule),
                                    onMoveUp: { moveRule(at: index, by: -1) },
                                    onMoveDown: { moveRule(at: index, by: 1) },
                                    onDelete: { deleteRule(at: index) }
                                )
                            }
                        }
                    }
                    .disabled(!scheduleEnabledDraft)

                    HStack {
                        Spacer()
                        Button("Cancel") {
                            revertDraft()
                            dismiss()
                        }
                        Button("Save") {
                            applyDraftToTab()
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!hasScheduleChanges)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            syncDraftFromTab()
        }
        .onChange(of: tab.id, initial: false) { _, _ in
            syncDraftFromTab()
        }
    }
}

private struct TabScheduleRuleEditor: View {
    @Binding var rule: DashboardTabScheduleRule

    let index: Int
    let totalCount: Int
    let weekdays: [(value: Int, label: String)]
    let summaryText: String
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    private var startTimeBinding: Binding<Date> {
        Binding(
            get: { date(for: rule.startMinutes) },
            set: { rule.startMinutes = minutes(for: $0) }
        )
    }

    private var endTimeBinding: Binding<Date> {
        Binding(
            get: { date(for: rule.endMinutes) },
            set: { rule.endMinutes = minutes(for: $0) }
        )
    }

    private func toggleWeekday(_ weekday: Int) {
        if let existingIndex = rule.weekdays.firstIndex(of: weekday) {
            rule.weekdays.remove(at: existingIndex)
        } else {
            rule.weekdays.append(weekday)
            rule.weekdays.sort()
        }
    }

    private func date(for minutes: Int) -> Date {
        let clamped = max(0, min(24 * 60 - 1, minutes))
        let components = DateComponents(hour: clamped / 60, minute: clamped % 60)
        return Calendar.current.date(from: components) ?? .now
    }

    private func minutes(for date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = comps.hour ?? 0
        let minute = comps.minute ?? 0
        return max(0, min((hour * 60) + minute, 24 * 60 - 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Rule Name", text: $rule.name)
                        .textFieldStyle(.roundedBorder)
                    Text(summaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button(action: onMoveUp) {
                        Image(systemName: "arrow.up")
                    }
                    .disabled(index == 0)

                    Button(action: onMoveDown) {
                        Image(systemName: "arrow.down")
                    }
                    .disabled(index >= (totalCount - 1))

                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                }
                .buttonStyle(.borderless)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Days")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(weekdays, id: \.value) { day in
                        let isSelected = rule.weekdays.contains(day.value)
                        Button {
                            toggleWeekday(day.value)
                        } label: {
                            Text(day.label)
                                .font(.caption.weight(.semibold))
                                .frame(width: 34, height: 30)
                                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12))
                                .foregroundStyle(isSelected ? Color.white : Color.primary)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Toggle("All Day", isOn: $rule.isAllDay)

            if !rule.isAllDay {
                HStack(spacing: 12) {
                    DatePicker("Start", selection: startTimeBinding, displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: endTimeBinding, displayedComponents: .hourAndMinute)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}

