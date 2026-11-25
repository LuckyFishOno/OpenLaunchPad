import Foundation

/// In-app updates, as the launcher menu sees them. The agent connects Sparkle
/// through `Updater`, so this module, its tests, and the runtime checks do not
/// link Sparkle. Without an updater the menu command stays hidden.
@MainActor public final class AppUpdates {
    @MainActor public protocol Updater: AnyObject {
        /// False while a check or an installation is already under way.
        var canCheckForUpdates: Bool { get }
        func checkForUpdates()
    }

    public static let shared = AppUpdates()

    private var updater: Updater?

    /// Called when Sparkle has no more windows to show for the current check.
    public var onSessionFinished: (() -> Void)?

    public init() {}

    public var isAvailable: Bool { updater != nil }
    public var canCheck: Bool { updater?.canCheckForUpdates ?? false }

    public func connect(_ updater: Updater) { self.updater = updater }

    public func check() {
        guard let updater, updater.canCheckForUpdates else { return }
        updater.checkForUpdates()
    }

    public func sessionFinished() { onSessionFinished?() }
}

/// Finds the application that an update replaces. The agent runs the updater,
/// but the published bundle is the OpenLaunchPad.app that embeds it.
public enum UpdateHost {
    /// The app embedding the agent at `Contents/Library/LoginItems`, or nil for
    /// an agent that runs on its own.
    public static func applicationURL(embedding agentURL: URL) -> URL? {
        let parents = agentURL.standardizedFileURL.pathComponents.dropLast()
        guard Array(parents.suffix(3)) == ["Contents", "Library", "LoginItems"] else { return nil }
        let application = URL(fileURLWithPath: NSString.path(withComponents: Array(parents.dropLast(3))))
        return application.pathExtension == "app" ? application : nil
    }

    /// Updates need a secure feed and the public key that verifies downloads.
    public static func isConfigured(infoDictionary: [String: Any]) -> Bool {
        guard let feed = infoDictionary["SUFeedURL"] as? String, URL(string: feed)?.host != nil,
            let key = infoDictionary["SUPublicEDKey"] as? String
        else { return false }
        return Data(base64Encoded: key)?.count == 32
    }
}
