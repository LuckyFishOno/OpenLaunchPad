import Foundation

public struct AppMetadataResolver: Sendable {
    public init() {}

    public func resolve(bundleURL: URL) -> ApplicationRecord? {
        guard bundleURL.pathExtension.localizedCaseInsensitiveCompare("app") == .orderedSame else {
            return nil
        }

        // Read icons and launch the actual bundle, avoiding Finder's shortcut
        // badge on application symlinks such as /Applications/Safari.app.
        let resolvedBundleURL = bundleURL.resolvingSymlinksInPath()
        let bundle = Bundle(url: resolvedBundleURL)
        let fallbackName = resolvedBundleURL.deletingPathExtension().lastPathComponent
        let displayName = localizedName(from: bundle) ?? fallbackName

        return ApplicationRecord(
            displayName: displayName,
            bundleIdentifier: bundle?.bundleIdentifier,
            bundleURL: resolvedBundleURL
        )
    }

    private func localizedName(from bundle: Bundle?) -> String? {
        let keys = ["CFBundleDisplayName", "CFBundleName"]
        for key in keys {
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
