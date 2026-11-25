import Foundation
import Synchronization

public struct AppMetadataResolver: Sendable {
    /// What each path contained when `Bundle` first read it. Bundle's own cache
    /// lasts as long as the process, so this does too.
    private static let stampsReadByBundle = Mutex<[String: ApplicationContentStamp?]>([:])

    public init() {}

    public func resolve(bundleURL: URL) -> ApplicationRecord? {
        guard bundleURL.pathExtension.localizedCaseInsensitiveCompare("app") == .orderedSame else {
            return nil
        }

        // Read icons and launch the actual bundle, avoiding Finder's shortcut
        // badge on application symlinks such as /Applications/Safari.app.
        let resolvedBundleURL = bundleURL.resolvingSymlinksInPath()
        let fallbackName = resolvedBundleURL.deletingPathExtension().lastPathComponent
        let stamp = ApplicationContentStamp(bundleURL: resolvedBundleURL)

        if Self.changedSinceBundleRead(resolvedBundleURL, stamp: stamp),
           let reader = BundleInfoReader(bundleURL: resolvedBundleURL) {
            return ApplicationRecord(
                displayName: Self.nameKeys.lazy.compactMap(reader.string(forKey:)).first ?? fallbackName,
                bundleIdentifier: reader.bundleIdentifier,
                bundleURL: resolvedBundleURL,
                contentStamp: stamp
            )
        }

        let bundle = Bundle(url: resolvedBundleURL)
        return ApplicationRecord(
            displayName: localizedName(from: bundle) ?? fallbackName,
            bundleIdentifier: bundle?.bundleIdentifier,
            bundleURL: resolvedBundleURL,
            contentStamp: stamp
        )
    }

    private static let nameKeys = ["CFBundleDisplayName", "CFBundleName"]

    private static func changedSinceBundleRead(_ url: URL, stamp: ApplicationContentStamp?) -> Bool {
        stampsReadByBundle.withLock { stamps in
            guard let first = stamps[url.path] else {
                stamps[url.path] = .some(stamp)
                return false
            }
            return first != stamp
        }
    }

    private func localizedName(from bundle: Bundle?) -> String? {
        for key in Self.nameKeys {
            if let value = bundle?.localizedInfoDictionary?[key] as? String, !value.isEmpty {
                return value
            }
            if let value = bundle?.infoDictionary?[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }
}
