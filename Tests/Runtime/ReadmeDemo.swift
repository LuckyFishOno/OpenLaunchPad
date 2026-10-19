// Interactive README capture fixture. Compile with the production UI sources.
// Every run owns a fresh temporary layout; the user's layout is never loaded.
import AppCore
import AppKit

@MainActor
final class ReadmeDemoDelegate: NSObject, NSApplicationDelegate {
    private var controller: LaunchpadWindowController?
    private let catalog = AppCatalogActor(excludedBundleIdentifiers: [
        "org.openlaunchpad.OpenLaunchPad", "org.openlaunchpad.OpenLaunchPadAgent",
        "org.openlaunch.OpenLaunch", "org.openlaunch.OpenLaunchAgent",
        "org.launchpane.LaunchPane", "org.launchpane.LaunchPaneAgent",
        "org.openlaunchpad.ReadmeDemo",
    ])

    func applicationDidFinishLaunching(_: Notification) {
        Task { @MainActor in
            do {
                let outcome = await catalog.refreshOutcome()
                precondition(outcome.completeness == .complete, "Needs a complete app catalog")
                var remaining = outcome.applications
                var items: [LauncherLayoutItem] = []
                func take(_ names: [String]) -> [LauncherApplicationReference] {
                    names.compactMap { name in
                        guard let index = remaining.firstIndex(where: { $0.displayName == name }) else { return nil }
                        return LauncherApplicationReference(application: remaining.remove(at: index))
                    }
                }
                // A representative arrangement made only from installed apps.
                for name in ["Safari", "Mail", "Messages", "Calendar", "Notes", "Reminders", "Photos",
                             "Music", "Podcasts", "TV", "Books", "App Store", "Maps", "Weather",
                             "FaceTime", "Contacts", "Clock", "Calculator", "Freeform", "Preview", "TextEdit"] {
                    items += take([name]).map(LauncherLayoutItem.application)
                }
                for (title, names) in [
                    ("Create", ["Pages", "Numbers", "Keynote", "iMovie", "GarageBand", "Image Playground"]),
                    ("Developer", ["Xcode", "Code", "Terminal", "Docker", "GitHub Desktop", "Termius"]),
                    ("Utilities", [
                        "Activity Monitor", "Disk Utility", "Console", "System Information", "Screenshot",
                        "ColorSync Utility", "Digital Color Meter", "Keychain Access", "Automator",
                    ]),
                ] {
                    let children = take(names)
                    if children.count >= 2 {
                        items.append(.folder(LauncherFolder(customTitle: title, applications: children)))
                    } else {
                        items += children.map(LauncherLayoutItem.application)
                    }
                }
                items += take(["Firefox", "Google Chrome", "ChatGPT", "Discord", "Home", "Find My", "System Settings"])
                    .map(LauncherLayoutItem.application)
                items += remaining.map { .application(LauncherApplicationReference(application: $0)) }
                let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["OPENLAUNCHPAD_LAYOUT_PATH"]!)
                try JSONEncoder().encode(LauncherLayoutDocument(items: items)).write(to: url, options: .atomic)
                controller = LaunchpadWindowController()
                controller?.showWindow(on: NSScreen.main!)
                NSApp.activate(ignoringOtherApps: true)
                print("README DEMO ready — isolated layout: \(url.path)")
                try? await Task.sleep(for: .seconds(900))
                NSApp.terminate(nil)
            } catch {
                print("README DEMO failed: \(error)")
                NSApp.terminate(nil)
            }
        }
    }

    func applicationWillTerminate(_: Notification) {
        controller?.restoreSystemPresentationForTermination()
        controller?.close()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        controller?.showWindow(on: NSScreen.main!)
        return true
    }
}

@main
struct ReadmeDemo {
    @MainActor static func main() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("openlaunchpad-readme-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        setenv("OPENLAUNCHPAD_LAYOUT_PATH", directory.appendingPathComponent("layout.json").path, 1)
        let app = NSApplication.shared
        let delegate = ReadmeDemoDelegate()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}
