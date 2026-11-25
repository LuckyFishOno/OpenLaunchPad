import AppCore
import AppKit
import Sparkle

/// Connects Sparkle to `AppUpdates`. The agent hosts the updater, Sparkle
/// replaces the outer OpenLaunchPad.app, and then reopens the agent inside it.
///
/// Nothing is contacted until the user chooses Check for Updates: the outer
/// Info.plist turns scheduled checks off and Sparkle starts on the first check.
@MainActor final class SparkleUpdates: NSObject, AppUpdates.Updater, SPUStandardUserDriverDelegate {
    private static var current: SparkleUpdates?

    private let hostBundle: Bundle
    private var userDriver: SPUStandardUserDriver?
    private var updater: SPUUpdater?

    static func connect() {
        guard current == nil,
            let hostURL = UpdateHost.applicationURL(embedding: Bundle.main.bundleURL),
            let hostBundle = Bundle(url: hostURL),
            UpdateHost.isConfigured(infoDictionary: hostBundle.infoDictionary ?? [:])
        else { return }
        let updates = SparkleUpdates(hostBundle: hostBundle)
        current = updates
        AppUpdates.shared.connect(updates)
    }

    private init(hostBundle: Bundle) {
        self.hostBundle = hostBundle
        super.init()
    }

    var canCheckForUpdates: Bool { updater?.canCheckForUpdates ?? true }

    func checkForUpdates() {
        do {
            try startedUpdater().checkForUpdates()
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn’t Check for Updates"
            alert.informativeText = error.localizedDescription
            NSApplication.shared.activate()
            alert.runModal()
            AppUpdates.shared.sessionFinished()
        }
    }

    private func startedUpdater() throws -> SPUUpdater {
        if let updater { return updater }
        let userDriver = SPUStandardUserDriver(hostBundle: hostBundle, delegate: self)
        let updater = SPUUpdater(
            hostBundle: hostBundle, applicationBundle: .main, userDriver: userDriver, delegate: nil)
        try updater.start()
        self.userDriver = userDriver
        self.updater = updater
        return updater
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        // Sparkle closes its window after this call.
        Task { @MainActor in AppUpdates.shared.sessionFinished() }
    }
}
