import Foundation

/// Reads an application's Info.plist and localized names from disk every time.
///
/// `Bundle` and `CFBundle` keep the first metadata they read for a path until
/// the process exits. The agent outlives application updates, so a cached bundle
/// would keep showing the old name, or no identifier at all for an application
/// that was first seen while it was still being copied.
struct BundleInfoReader {
    private let info: [String: Any]
    private let localizedInfo: [String: Any]

    /// Returns nil for layouts this reader does not know, such as wrapped iOS
    /// applications, and for bundles whose Info.plist has not been copied yet.
    init?(bundleURL: URL) {
        let contents = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        guard let info = Self.dictionary(at: contents.appendingPathComponent("Info.plist")) else { return nil }
        self.info = info
        localizedInfo = Self.localizedInfo(
            resources: contents.appendingPathComponent("Resources", isDirectory: true),
            developmentRegion: info["CFBundleDevelopmentRegion"] as? String
        )
    }

    var bundleIdentifier: String? { info["CFBundleIdentifier"] as? String }

    func string(forKey key: String) -> String? {
        for source in [localizedInfo, info] {
            for candidate in ["\(key)-macos", key] {
                if let value = source[candidate] as? String, !value.isEmpty { return value }
            }
        }
        return nil
    }

    private static func localizedInfo(resources: URL, developmentRegion: String?) -> [String: Any] {
        let table = dictionary(at: resources.appendingPathComponent("InfoPlist.loctable")) ?? [:]
        let directories = (try? FileManager.default.contentsOfDirectory(atPath: resources.path)) ?? []
        var localizations = Set(directories.filter { $0.hasSuffix(".lproj") }.map { String($0.dropLast(6)) })
        localizations.formUnion(table.keys)
        localizations.subtract(["Base", "LocProvenance"])

        for localization in preferred(localizations, developmentRegion: developmentRegion) {
            if let values = table[localization] as? [String: Any] { return values }
            let strings = resources.appendingPathComponent("\(localization).lproj/InfoPlist.strings")
            if let values = dictionary(at: strings) { return values }
        }
        return [:]
    }

    /// `Bundle` gives other bundles the language the running application uses,
    /// so a name read here does not change language after an update.
    private static func preferred(_ localizations: Set<String>, developmentRegion: String?) -> [String] {
        guard !localizations.isEmpty else { return [] }
        var result = Bundle.preferredLocalizations(
            from: localizations.sorted(), forPreferences: Bundle.main.preferredLocalizations
        )
        if let developmentRegion, !result.contains(developmentRegion) { result.append(developmentRegion) }
        return result
    }

    private static func dictionary(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }
}
