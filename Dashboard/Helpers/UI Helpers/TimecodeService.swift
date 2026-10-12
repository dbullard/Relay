//
//  TimecodeService.swift
//  Relay
//
//  Created by David Bullard on 11/22/25.
//

import Foundation
import CoreMIDI
import Combine

final class TimecodeService: ObservableObject {
    static let shared = TimecodeService()

    /// UserDefaults key shared with @AppStorage("timecode_midi_source_filter")
    private let midiSourceFilterKey = "timecode_midi_source_filter"

    @Published var timecodeString: String = "--:--:--:--"
    @Published var isLocked: Bool = false
    @Published var frameRateLabel: String = "Unknown"

    /// Human-readable names of available MIDI input sources.
    @Published var availableSources: [String] = []

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()

    private let parser = MIDITimecodeParser()
    // Timer used to drop the lock state if we stop receiving MTC
    private var lockTimer: Timer?

    /// Returns the current MIDI source filter string from UserDefaults.
    /// When empty, all sources will be considered.
    private var currentMidiSourceFilter: String {
        UserDefaults.standard.string(forKey: midiSourceFilterKey) ?? ""
    }

    init() {
        parser.onUpdate = { [weak self] update in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.timecodeString = update.formatted
                self.isLocked = true
                if let label = update.frameRateLabel {
                    self.frameRateLabel = label
                }
                self.bumpLockTimeout()
            }
        }
        setupMIDI()
    }

    private func setupMIDI() {
        MIDIClientCreate("RelayTimecodeClient" as CFString, nil, nil, &client)
        MIDIInputPortCreate(client, "TimecodeIn" as CFString, midiReadProc, Unmanaged.passUnretained(self).toOpaque(), &inputPort)

        let filter = currentMidiSourceFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceCount = MIDIGetNumberOfSources()

        var discoveredNames: [String] = []

        for i in 0..<sourceCount {
            let src = MIDIGetSource(i)

            if let name = nameForEndpoint(src) {
                discoveredNames.append(name)
            }

            // If no filter is set, connect to all sources.
            guard !filter.isEmpty else {
                MIDIPortConnectSource(inputPort, src, nil)
                continue
            }

            // If a filter is set, only connect to sources whose name contains it.
            if let name = nameForEndpoint(src),
               name.range(of: filter, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                MIDIPortConnectSource(inputPort, src, nil)
            }
        }

        // Publish the discovered source names on the main thread.
        DispatchQueue.main.async { [weak self] in
            self?.availableSources = discoveredNames.sorted()
        }
    }

    /// Returns the name of a MIDI endpoint (device/port) if available.
    private func nameForEndpoint(_ endpoint: MIDIEndpointRef) -> String? {
        var property: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &property)
        guard status == noErr, let cfStr = property?.takeRetainedValue() else {
            return nil
        }
        return cfStr as String
    }
    /// Handles a CoreMIDI packet list and extracts any MTC quarter-frame messages.
    fileprivate func handlePacketList(_ pktList: UnsafePointer<MIDIPacketList>) {
        parser.handlePacketList(pktList)
    }

    /// Resets the lock timer so that `isLocked` will be dropped if MTC stops.
    private func bumpLockTimeout() {
        lockTimer?.invalidate()
        lockTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.isLocked = false
        }
    }
}
// MARK: - CoreMIDI Read Callback (Global C function)

func midiReadProc(pktList: UnsafePointer<MIDIPacketList>,
                  readProcRefCon: UnsafeMutableRawPointer?,
                  srcConnRefCon: UnsafeMutableRawPointer?) {
    guard let refCon = readProcRefCon else { return }
    let service = Unmanaged<TimecodeService>.fromOpaque(refCon).takeUnretainedValue()
    service.handlePacketList(pktList)
}
