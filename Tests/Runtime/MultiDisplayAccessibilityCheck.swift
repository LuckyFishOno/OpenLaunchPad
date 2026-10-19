import AppCore
import AppKit
import DisplayCore
import LayoutCore

@MainActor final class MultiDisplayAccessibilityDelegate: NSObject, NSApplicationDelegate {
    private var controller: LaunchpadWindowController!
    private let previousApp = NSWorkspace.shared.frontmostApplication
    private var failures = 0
    private var assertions = 0
    private var label = ""
    private var root: LaunchpadRootView {
        guard let root = controller.window?.contentView as? LaunchpadRootView else {
            fatalError("Expected launcher root")
        }
        return root
    }
    private var layoutURL: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["OPENLAUNCHPAD_LAYOUT_PATH"]!)
    }

    private func check(_ condition: Bool, _ message: String) {
        assertions += 1
        if !condition { failures += 1 }
        print("\(condition ? "PASS" : "FAIL") \(label): \(message)")
    }

    private func pause(_ seconds: Double = 0.4) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private func key(_ code: UInt16) {
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: controller.window!.windowNumber, context: nil, characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: code)!
        root.keyDown(with: event)
        root.layoutSubtreeIfNeeded()
    }

    private func settle() async {
        for _ in 0..<150 {
            root.layoutSubtreeIfNeeded()
            if !root.isLoadingApplications { break }
            await pause(0.2)
        }
        check(!root.isLoadingApplications, "catalog loaded")
        if let task = root.iconPrewarmTasks.visiblePage { await task.value }
        await pause()
    }

    private func prepareFixture() async throws {
        let catalog = await AppCatalogActor().refreshOutcome()
        let references = catalog.applications.map(LauncherApplicationReference.init(application:))
        precondition(references.count >= 40, "Needs 40 installed apps for real folder paging")
        let folder = LauncherFolder(customTitle: "Accessibility Fixture", applications: Array(references.prefix(40)))
        let document = LauncherLayoutDocument(
            revision: 100, items: [.folder(folder)] + references.dropFirst(40).map { .application($0) })
        try JSONEncoder().encode(document).write(to: layoutURL, options: .atomic)
    }

    private func verifyGeometry(_ display: DisplayContext) {
        check(controller.window!.isVisible, "production window is visible")
        check(controller.window!.frame == display.frame, "window follows display origin and dimensions")
        check(root.bounds.size == display.frame.size, "root uses display-local bounds")
        check(controller.window!.backingScaleFactor == display.backingScaleFactor,
              "backing scale matches target display")
        guard let backdrop = Mirror(reflecting: controller!).children
            .first(where: { $0.label == "menuBarBackdrop" })?.value as? MenuBarBackdropWindow else {
            fatalError("Missing menu backdrop")
        }
        check(backdrop.isVisible && backdrop.frame.minX == display.frame.minX,
              "menu continuation follows selected display")
        check(backdrop.frame.width == display.frame.width && backdrop.frame.maxY == display.frame.maxY,
              "menu continuation covers selected display top")
        let entries = root.activeSurface!.entries
        check(entries.allSatisfy { root.bounds.contains($0.frames.icon) }, "visible icons fit the display")
        check(entries.allSatisfy { $0.button.frame == $0.frames.icon }, "hit targets follow solved icon geometry")
        check(entries.allSatisfy { $0.iconLayer.contentsScale == display.backingScaleFactor },
              "icons use target scale")
        check(entries.allSatisfy { !$0.button.isHidden && $0.button.isEnabled }, "visible hit targets remain usable")
        check(entries.allSatisfy { !($0.button.accessibilityLabel() ?? "").isEmpty },
              "tiles expose accessibility names")
        check(entries.allSatisfy { $0.button.accessibilityRole() == .button }, "tiles expose button roles")
        check(entries.allSatisfy { $0.button.isAccessibilityElement() }, "tiles participate in accessibility tree")
    }

    private func verifyInteraction(isRTL: Bool) async throws {
        let before = try Data(contentsOf: layoutURL)
        root.selectedIndex = 0
        key(isRTL ? 123 : 124)
        check(root.selectedIndex == 1, "logical next selection follows horizontal direction")
        key(isRTL ? 124 : 123)
        check(root.selectedIndex == 0, "logical previous selection returns to folder")
        key(36)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            check(root.folderPresentation.folderContentAnimationLayer?.animation(forKey: "folderExpandIn") == nil,
                  "Reduce Motion skips folder expansion")
        }
        await pause()
        check(root.openFolderID != nil, "Enter opens selected folder")
        key(isRTL ? 123 : 124)
        check(root.folderPaging.selectedIndex == 0, "first folder arrow selects first visible item")
        key(isRTL ? 123 : 124)
        check(root.folderPaging.selectedIndex == 1, "folder arrow navigation follows layout direction")
        key(121)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            check(!root.folderPaging.animator.isAnimating, "Reduce Motion changes folder page without sliding")
        }
        await pause()
        check(root.folderPaging.page == 1, "Page Down advances folder page")
        key(116)
        await pause()
        check(root.folderPaging.page == 0, "Page Up returns to first page")
        key(53)
        await pause()
        check(root.openFolderID == nil && controller.window!.isVisible,
              "Escape closes folder without dismissing launcher")
        guard let folderButton = root.subviews.compactMap({ $0 as? FolderTileButton }).first else {
            check(false, "folder target missing after close; presentation may have lost focus")
            return
        }
        check(folderButton.accessibilityPerformPress(), "accessibility press is accepted")
        await pause()
        check(root.openFolderID != nil, "accessibility press opens the real folder")
        root.closeFolder(animated: false)
        root.searchField.stringValue = root.applications.first!.displayName
        root.searchField.onTextChanged?()
        root.layoutSubtreeIfNeeded()
        await pause()
        check(!root.activeSurface!.entries.isEmpty, "search renders matching results")
        root.resetForNewPresentation()
        root.layoutSubtreeIfNeeded()
        check(root.searchField.stringValue.isEmpty, "search resets for next presentation")
        check(try Data(contentsOf: layoutURL) == before, "navigation leaves persisted layout unchanged")
    }

    private func run() async throws {
        try await prepareFixture()
        controller = LaunchpadWindowController()
        let resolver = ScreenDisplayContextResolver()
        print("Reduce Motion: \(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)")
        for pass in 1...2 {
            for screen in NSScreen.screens {
                let display = resolver.resolve(screen)
                label = "pass \(pass), \(screen.localizedName), \(display.frame.size) @\(display.backingScaleFactor)x"
                controller.showWindow(on: screen)
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    check(root.layer?.animation(forKey: "OpenLaunchPad.nativeWindowVisibility") == nil,
                          "Reduce Motion skips opening motion")
                }
                await settle()
                for isRTL in [false, true] {
                    root.userInterfaceLayoutDirection = isRTL ? .rightToLeft : .leftToRight
                    root.resetForNewPresentation()
                    root.needsLayout = true
                    root.layoutSubtreeIfNeeded()
                    await pause()
                    check(root.currentMetrics!.isRightToLeft == isRTL, "solver adopts \(isRTL ? "RTL" : "LTR")")
                    verifyGeometry(display)
                    try await verifyInteraction(isRTL: isRTL)
                }
            }
        }
        key(53)
        await pause()
        check(!controller.window!.isVisible && !root.presentationResourcesActive,
              "Escape releases presentation resources")
    }

    func applicationDidFinishLaunching(_: Notification) {
        Task { @MainActor in
            do { try await run() } catch { check(false, "unexpected error: \(error)") }
            controller?.restoreSystemPresentationForTermination()
            controller?.close()
            previousApp?.activate(options: [])
            print("MULTI DISPLAY ACCESSIBILITY: \(assertions) assertions, \(failures) failures")
            exit(failures == 0 ? 0 : 1)
        }
    }
}

@main struct MultiDisplayAccessibilityCheck {
    @MainActor static func main() {
        precondition(
            ProcessInfo.processInfo.environment["OPENLAUNCHPAD_LAYOUT_PATH"]?.hasPrefix("/private/tmp/") == true)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = MultiDisplayAccessibilityDelegate()
        app.delegate = delegate
        app.run()
    }
}
