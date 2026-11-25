import Foundation

/// Identifies the files an application's name and icon come from, so that an
/// application updated at the same path can be told apart from an unchanged one.
public struct ApplicationContentStamp: Codable, Hashable, Sendable, CustomStringConvertible {
    private struct FileStamp: Codable, Hashable {
        let inode: UInt64
        let seconds: Int
        let nanoseconds: Int

        init?(path: String) {
            var status = stat()
            guard stat(path, &status) == 0 else { return nil }
            inode = status.st_ino
            seconds = status.st_mtimespec.tv_sec
            nanoseconds = status.st_mtimespec.tv_nsec
        }
    }

    private let bundle: FileStamp
    private let info: FileStamp?

    /// Returns nil when the bundle is gone.
    public init?(bundleURL: URL) {
        guard let bundle = FileStamp(path: bundleURL.path) else { return nil }
        self.bundle = bundle
        info = FileStamp(path: bundleURL.appendingPathComponent("Contents/Info.plist").path)
    }

    public var description: String {
        [bundle, info].map { stamp in
            stamp.map { "\($0.inode).\($0.seconds).\($0.nanoseconds)" } ?? "-"
        }.joined(separator: "/")
    }
}
