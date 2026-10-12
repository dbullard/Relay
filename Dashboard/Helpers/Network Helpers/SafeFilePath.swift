import Foundation

/// Resolves a client-supplied filename to a file that lives directly inside `folder`.
/// Rejects separators, dot names, NULs, absolute paths, and symlinks that point outside.
enum SafeFilePath {
    static func resolve(filename: String, inFolder folder: String) -> String? {
        guard !filename.isEmpty,
              filename != ".", filename != "..",
              !filename.contains("/"), !filename.contains("\\"), !filename.contains("\0")
        else { return nil }

        let base = URL(fileURLWithPath: folder, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
        let candidate = base.appendingPathComponent(filename, isDirectory: false)
            .resolvingSymlinksInPath().standardizedFileURL

        guard candidate.deletingLastPathComponent().path == base.path else { return nil }
        return candidate.path
    }
}
