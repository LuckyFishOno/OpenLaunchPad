import Foundation

public protocol LauncherLayoutFileIO: Sendable {
    func readData(at url: URL) throws -> Data?
    func writeDataAtomically(_ data: Data, to url: URL) throws
    func preservePreMigrationData(_ data: Data, at url: URL) throws
}

public extension LauncherLayoutFileIO {
    /// Custom/in-memory stores may supply their own backup policy.
    func preservePreMigrationData(_: Data, at _: URL) throws {}
}

public struct AtomicLauncherLayoutFileIO: LauncherLayoutFileIO {
    public init() {}

    public func readData(at url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    public func writeDataAtomically(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    public func preservePreMigrationData(_ data: Data, at url: URL) throws {
        let backupURL = url.deletingPathExtension()
            .appendingPathExtension("pre-pages.backup.json")
        guard !FileManager.default.fileExists(atPath: backupURL.path) else { return }
        do {
            try data.write(to: backupURL, options: .withoutOverwriting)
        } catch let error as CocoaError where error.code == .fileWriteFileExists {
            // Another reader already preserved the original. Never replace it.
        }
    }
}
