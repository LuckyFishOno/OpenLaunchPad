import Foundation

/// Decides whether a changed directory can change the application catalog.
public enum ApplicationDirectoryChange {
    /// Applications write inside their own bundles. Only the bundle itself and
    /// `Contents`, which holds Info.plist, can change a name, an icon or whether
    /// the application exists.
    public static func affectsCatalog(path: String) -> Bool {
        let components = path.split(separator: "/")
        guard let bundle = components.firstIndex(where: { $0.lowercased().hasSuffix(".app") }) else { return true }
        let inside = components[(bundle + 1)...]
        return inside.isEmpty || inside.elementsEqual(["Contents"])
    }
}
