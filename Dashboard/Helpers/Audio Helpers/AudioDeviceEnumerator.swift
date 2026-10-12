import Foundation
@preconcurrency import AVFoundation
import Combine

#if os(macOS)
import CoreAudio
import AudioToolbox

struct AudioInputDevice: Identifiable, Equatable, Sendable {
    var id: AudioDeviceID { deviceId }
    let deviceId: AudioDeviceID
    let uid: String
    let name: String
    let channelCount: Int
}

enum AudioDeviceEnumerator {
    nonisolated static func inputDevices() -> [AudioInputDevice] {
        var devices: [AudioInputDevice] = []
        var propertySize: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize)
        guard status == noErr else { return [] }
        let count = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIds = Array(repeating: AudioDeviceID(0), count: count)
        var size = propertySize
        let fetchStatus = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIds)
        guard fetchStatus == noErr else { return [] }

        for deviceId in deviceIds {
            let uid = stringProperty(deviceId, selector: kAudioDevicePropertyDeviceUID) ?? ""
            let name = stringProperty(deviceId, selector: kAudioObjectPropertyName) ?? "Audio Device"
            let channelCount = inputChannelCount(deviceId: deviceId)
            if channelCount > 0 {
                devices.append(AudioInputDevice(deviceId: deviceId, uid: uid, name: name, channelCount: channelCount))
            }
        }

        return devices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    nonisolated static func inputChannelCount(deviceId: AudioDeviceID) -> Int {
        inputChannelCountImpl(deviceId)
    }

    nonisolated static func inputChannelCount(_ deviceId: AudioDeviceID) -> Int {
        inputChannelCount(deviceId: deviceId)
    }

    nonisolated static func inputSampleRate(deviceId: AudioDeviceID) -> Double? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var sampleRate: Double = 0
        var size = UInt32(MemoryLayout<Double>.size)
        let status = AudioObjectGetPropertyData(deviceId, &address, 0, nil, &size, &sampleRate)
        guard status == noErr, sampleRate > 0 else { return nil }
        return sampleRate
    }

    nonisolated static func deviceId(for uid: String) -> AudioDeviceID? {
        guard !uid.isEmpty else { return defaultInputDeviceId() }
        return inputDevices().first(where: { $0.uid == uid })?.deviceId
    }

    nonisolated static func defaultInputDeviceId() -> AudioDeviceID? {
        var deviceId = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceId)
        guard status == noErr, deviceId != 0 else { return nil }
        return deviceId
    }

    nonisolated private static func stringProperty(_ deviceId: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfString: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &cfString) { pointer in
            AudioObjectGetPropertyData(deviceId, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else { return nil }
        return cfString as String
    }

    nonisolated private static func inputChannelCountImpl(_ deviceId: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard deviceId != 0 else { return 0 }
        guard AudioObjectHasProperty(deviceId, &address) else { return 0 }
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceId, &address, 0, nil, &size)
        guard status == noErr, size > 0 else { return 0 }
        let rawPointer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { rawPointer.deallocate() }
        let bufferListPointer = rawPointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        var dataSize = size
        let fetchStatus = AudioObjectGetPropertyData(deviceId, &address, 0, nil, &dataSize, bufferListPointer)
        guard fetchStatus == noErr else { return 0 }
        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        var channels = 0
        for buffer in bufferList {
            channels += Int(buffer.mNumberChannels)
        }
        return channels
    }
}
#else

struct AudioInputDevice: Identifiable, Equatable, Sendable {
    var id: String { uid }
    let uid: String
    let name: String
    let channelCount: Int
}

enum AudioDeviceEnumerator {
    nonisolated static func inputDevices() -> [AudioInputDevice] {
        return [AudioInputDevice(uid: "current", name: "Current Microphone", channelCount: 1)]
    }
}
#endif

@MainActor
final class AudioInputDeviceCache: ObservableObject {
    static let shared = AudioInputDeviceCache()

    @Published private(set) var devices: [AudioInputDevice] = []

    private var refreshTask: Task<Void, Never>?

    private init() {
        refresh()

        #if os(macOS)
        registerCoreAudioInvalidation()
        #endif
    }

    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            let fetched = await Task.detached(priority: .userInitiated) {
                AudioDeviceEnumerator.inputDevices()
            }.value
            guard !Task.isCancelled else { return }
            devices = fetched
        }
    }

    func device(for uid: String?) -> AudioInputDevice? {
        guard let uid, !uid.isEmpty else { return nil }
        return devices.first { $0.uid == uid }
    }

    #if os(macOS)
    private func registerCoreAudioInvalidation() {
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            DispatchQueue.global(qos: .utility)
        ) { [weak self] _, _ in
            Task { @MainActor in
                self?.refresh()
            }
        }

        var defaultInputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultInputAddress,
            DispatchQueue.global(qos: .utility)
        ) { [weak self] _, _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }
    #endif
}
