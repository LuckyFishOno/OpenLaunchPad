import AppKit

// OPENLAUNCHPAD_DOCK_AGENT_ARCHITECTURE_V1
//
// This process is intentionally tiny and short-lived.
//
// The Dock tile points at OpenLaunchPad.app, but all persistent UI lives in
// OpenLaunchPadAgent.app. Both processes use accessory activation policy, so
// neither process owns a normal macOS menu bar. The agent has a distinct bundle
// identifier, so keeping the launcher tile in the Dock does not expose the
// agent's running state, Hide/Quit menu items, or running indicator.

private enum DockLauncherIPC {
    static let agentBundleIdentifier =
        "org.openlaunchpad.OpenLaunchPadAgent"

    static let toggleNotification =
        Notification.Name(
            "org.openlaunchpad.OpenLaunchPadAgent.toggle"
        )

    static func agentApplicationURL() -> URL? {
        let embeddedURL =
            Bundle.main.bundleURL
                .appendingPathComponent("Contents")
                .appendingPathComponent("Library")
                .appendingPathComponent("LoginItems")
                .appendingPathComponent(
                    "OpenLaunchPadAgent.app"
                )

        if FileManager.default.fileExists(
            atPath: embeddedURL.path
        ) {
            return embeddedURL
        }

        let siblingURL =
            Bundle.main.bundleURL
                .deletingLastPathComponent()
                .appendingPathComponent(
                    "OpenLaunchPadAgent.app"
                )

        if FileManager.default.fileExists(
            atPath: siblingURL.path
        ) {
            return siblingURL
        }

        return nil
    }
}

@MainActor
private final class DockLauncherDelegate:
    NSObject,
    NSApplicationDelegate {
    func applicationDidFinishLaunching(
        _: Notification
    ) {
        dispatchToggle()
    }

    private func dispatchToggle() {
        let runningAgents =
            NSRunningApplication
                .runningApplications(
                    withBundleIdentifier:
                        DockLauncherIPC
                            .agentBundleIdentifier
                )
                .filter {
                    !$0.isTerminated
                }

        let agentURL =
            DockLauncherIPC
                .agentApplicationURL()

        // An agent left over from a replaced copy of the app lacks this
        // version's features and would otherwise run until the next login.
        if let agentURL {
            let outdatedAgents =
                outdatedAgents(
                    in: runningAgents,
                    embeddedAgentURL: agentURL
                )

            if !outdatedAgents.isEmpty {
                replace(
                    outdatedAgents,
                    withAgentAt: agentURL
                )
                return
            }
        }

        if !runningAgents.isEmpty {
            toggleRunningAgent()
            return
        }

        guard let agentURL else {
            fputs(
                "OpenLaunchPad: embedded agent was not found.\n",
                stderr
            )
            NSSound.beep()
            NSApplication.shared.terminate(nil)
            return
        }

        launchAgent(at: agentURL)
    }

    private func toggleRunningAgent() {
        DistributedNotificationCenter
            .default()
            .postNotificationName(
                DockLauncherIPC
                    .toggleNotification,
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )

        terminateLauncherSoon()
    }

    private func outdatedAgents(
        in runningAgents: [NSRunningApplication],
        embeddedAgentURL: URL
    ) -> [NSRunningApplication] {
        guard !runningAgents.isEmpty else { return [] }

        let embeddedHashes =
            AgentIdentity.embeddedHashes(
                ofAgentAt: embeddedAgentURL
            )

        return runningAgents.filter {
            AgentIdentity.isOutdated(
                running: AgentIdentity.runningCode(
                    of: $0.processIdentifier
                ),
                embedded: embeddedHashes
            )
        }
    }

    /// Asks the outdated agents to quit and starts the embedded one. An agent
    /// that does not quit keeps working: it is toggled, never killed.
    private func replace(
        _ outdatedAgents: [NSRunningApplication],
        withAgentAt agentURL: URL
    ) {
        outdatedAgents.forEach { $0.terminate() }

        Task { @MainActor in
            let deadline =
                ContinuousClock.now + .seconds(3)

            while outdatedAgents.contains(where: {
                !$0.isTerminated
            }) {
                guard ContinuousClock.now < deadline else {
                    toggleRunningAgent()
                    return
                }

                try? await Task.sleep(
                    for: .milliseconds(20)
                )
            }

            launchAgent(at: agentURL)
        }
    }

    private func launchAgent(at agentURL: URL) {
        let configuration =
            NSWorkspace.OpenConfiguration()

        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.createsNewApplicationInstance = false

        NSWorkspace.shared.openApplication(
            at: agentURL,
            configuration: configuration
        ) { _, error in
            let errorMessage =
                error?.localizedDescription

            DispatchQueue.main.async {
                if let errorMessage {
                    fputs(
                        "OpenLaunchPad: failed to launch agent: "
                            + errorMessage
                            + "\n",
                        stderr
                    )
                    NSSound.beep()
                }

                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func terminateLauncherSoon() {
        Task { @MainActor in
            try? await Task.sleep(
                for: .milliseconds(24)
            )
            NSApplication.shared.terminate(nil)
        }
    }
}

let application = NSApplication.shared
private let delegate = DockLauncherDelegate()

application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
