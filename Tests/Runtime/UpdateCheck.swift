// Drives the real Check for Updates menu command with a stand-in updater.
// The layout path must point into /private/tmp so user data is never touched.
import AppCore
import AppKit

@MainActor
private final class StandInUpdater: AppUpdates.Updater {
    var canCheckForUpdates = true
    var checks = 0
    var onCheck: (() -> Void)?
    func checkForUpdates() {
        checks += 1
        onCheck?()
    }
}

@MainActor
final class UpdateCheckDelegate: NSObject, NSApplicationDelegate {
    private var controller: LaunchpadWindowController!
    private let updater = StandInUpdater()
    private var failures = 0
    private let previousApp = NSWorkspace.shared.frontmostApplication

    private var launcher: LaunchpadWindow {
        guard let window = controller.window as? LaunchpadWindow else { fatalError("Expected the launcher window") }
        return window
    }

    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private var search: LaunchpadSearchField {
        guard let root = launcher.contentView,
            let field = descendants(root).compactMap({ $0 as? LaunchpadSearchField }).first
        else { fatalError("Expected the search field") }
        return field
    }

    private func check(_ condition: Bool, _ message: String) {
        print("\(condition ? "PASS" : "FAIL") \(message)")
        if !condition { failures += 1 }
    }

    private func until(_ message: String, _ predicate: () -> Bool) async {
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        while !predicate(), ProcessInfo.processInfo.systemUptime < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        check(predicate(), message)
    }

    private func chooseCheckForUpdates() { search.settingsMenu.performActionForItem(at: 0) }

    private func run() async {
        controller = LaunchpadWindowController()
        controller.showWindow(nil)
        await until("launcher opens") { launcher.isVisible && launcher.isKeyWindow }
        check(search.updateMenuItem.isHidden, "command is hidden without an updater")

        AppUpdates.shared.connect(updater)
        search.refreshUpdateMenuItem()
        check(
            search.settingsMenu.items.filter { !$0.isHidden }.map(\.title) == ["Check for Updates", "Reset Launchpad"],
            "both commands are listed with an updater")
        updater.canCheckForUpdates = false
        search.refreshUpdateMenuItem()
        check(!search.updateMenuItem.isEnabled, "command is disabled during an update")
        updater.canCheckForUpdates = true
        search.refreshUpdateMenuItem()

        var launcherWasVisible = true
        var agentWasActive = false
        updater.onCheck = { [self] in
            launcherWasVisible = launcher.isVisible
            agentWasActive = NSApp.isActive
        }
        chooseCheckForUpdates()
        check(updater.checks == 0, "check waits for the launcher to close")
        await until("check starts") { updater.checks == 1 }
        check(!launcherWasVisible, "launcher is closed when the check starts")
        check(agentWasActive, "agent stays active for the update window")

        AppUpdates.shared.sessionFinished()
        await until("agent yields when the update session ends") { !NSApp.isActive }

        // An ordinary dismissal, or reopening before the close finishes, must
        // not start a check.
        controller.showWindow(nil)
        await until("launcher reopens") { launcher.isVisible }
        launcher.dismiss()
        await until("launcher closes") { !launcher.isVisible }
        check(updater.checks == 1, "ordinary dismissal does not check")

        controller.showWindow(nil)
        await until("launcher reopens again") { launcher.isVisible }
        // Closing a launcher that has not begun to fade in finishes at once.
        try? await Task.sleep(for: .milliseconds(400))
        chooseCheckForUpdates()
        controller.showWindow(nil)
        try? await Task.sleep(for: .milliseconds(600))
        check(launcher.isVisible && updater.checks == 1, "reopening cancels the pending check")
        AppUpdates.shared.sessionFinished()
        check(launcher.isPresentedOrPresenting, "session end leaves an open launcher alone")
        launcher.dismiss()
        await until("launcher closes at the end") { !launcher.isVisible }
    }

    func applicationDidFinishLaunching(_: Notification) {
        Task { @MainActor in
            await run()
            print("UPDATE CHECK: \(failures) failures")
            previousApp?.activate(options: [])
            exit(failures == 0 ? 0 : 1)
        }
    }
}

@main
@MainActor
struct UpdateCheck {
    static func main() {
        guard ProcessInfo.processInfo.environment["OPENLAUNCHPAD_LAYOUT_PATH"]?.hasPrefix("/private/tmp/") == true else {
            fatalError("Set OPENLAUNCHPAD_LAYOUT_PATH inside /private/tmp")
        }
        let application = NSApplication.shared
        let delegate = UpdateCheckDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
