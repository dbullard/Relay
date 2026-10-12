import Foundation
import Combine

final class SyncedFileCache: ObservableObject {
    static let shared = SyncedFileCache()

    private let cacheDir: URL
    private var inFlight: [String: Task<URL?, Never>] = [:]

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDir = base.appendingPathComponent("RelaySync/Files", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    func localURL(for key: String, remoteURL: URL) async -> URL? {
        let dest = cacheDir.appendingPathComponent(key.replacingOccurrences(of: "/", with: "_"))
        if FileManager.default.fileExists(atPath: dest.path) { return dest }

        if let existing = inFlight[key] { return await existing.value }

        let task = Task<URL?, Never> { [weak self] in
            defer { Task { [weak self] in self?.inFlight.removeValue(forKey: key) } }
            do {
                let (data, resp) = try await URLSession.shared.data(from: remoteURL)
                guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
                try data.write(to: dest, options: .atomic)
                return dest
            } catch {
                return nil
            }
        }
        inFlight[key] = task
        return await task.value
    }

    func clearAll() {
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        inFlight.removeAll()
    }
}
