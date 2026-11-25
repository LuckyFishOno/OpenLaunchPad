// Catalog changes while the launcher is in use, on the real root view.
// The window stays hidden and the layout path must point into /private/tmp, so
// neither the user's arrangement nor the application folders are modified.
import AppCore
import AppKit
import LayoutCore
import QuartzCore

@MainActor
final class CatalogRefreshCheck {
    private let controller = LaunchpadWindowController()
    private var failures = 0
    private let directory: URL

    private var window: NSWindow { controller.window! }
    private var root: LaunchpadRootView {
        guard let root = controller.window?.contentView as? LaunchpadRootView else {
            fatalError("Expected the launcher root view")
        }
        return root
    }

    init(directory: URL) { self.directory = directory }

    private func check(_ condition: Bool, _ message: String) {
        print("\(condition ? "PASS" : "FAIL") \(message)")
        if !condition { failures += 1 }
    }

    private func pause(_ milliseconds: Int) async { try? await Task.sleep(for: .milliseconds(milliseconds)) }

    private func until(_ message: String, timeout: Double = 5, _ predicate: () -> Bool) async {
        let deadline = CACurrentMediaTime() + timeout
        while !predicate(), CACurrentMediaTime() < deadline { await pause(20) }
        check(predicate(), message)
    }

    private func storedRevision() async -> UInt64? { try? await root.layoutStore.load().revision }

    func run() async throws -> Int {
        await until("catalog loads") { !root.isLoadingApplications }
        await verifyHiddenRefresh()
        root.prepareForPresentation(displayContext: root.displayContext)
        await pause(600)
        await verifyOpenFolder()
        try await verifyDrag()
        try await verifyFolderWithMissingApplication()
        try await verifyIconUpdate()
        try await verifyMonitor()
        check(!window.isVisible, "window is never shown")
        return failures
    }

    private func verifyHiddenRefresh() async {
        await pause(1000)
        root.iconPrewarmTasks.cancelIdleFirstPage()
        root.applications.removeLast()
        await root.refreshApplicationsFromDisk()
        check(root.iconPrewarmTasks.idleFirstPage != nil, "a hidden catalog change warms the first page's icons")
    }

    private func openFirstFolder() -> UUID {
        let folderID = root.layoutDocument.items.compactMap { item -> UUID? in
            if case .folder(let folder) = item { return folder.id }
            return nil
        }.first!
        root.openFolder(folderID, sourceFrame: CGRect(x: 200, y: 600, width: 100, height: 100))
        return folderID
    }

    private func verifyOpenFolder() async {
        let folderID = openFirstFolder()
        await pause(600)
        let surfaces = root.contentRevision
        await root.refreshApplicationsFromDisk()
        check(root.openFolderID == folderID, "an unchanged catalog leaves the folder open")
        check(root.contentRevision == surfaces, "an unchanged catalog does not rebuild the pages")

        let full = root.applications
        root.applications.removeLast()
        await root.refreshApplicationsFromDisk()
        await pause(700)
        check(root.openFolderID == folderID, "a changed catalog leaves the folder open")
        check(root.applications.count == full.count - 1, "the change waits while the folder is open")
        root.closeFolder(animated: false)
        await until("the change is applied after the folder closes") { root.applications == full }
        root.layoutSubtreeIfNeeded()
        await pause(400)
    }

    private func event(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
        NSEvent.mouseEvent(
            with: type, location: root.convert(point, to: nil), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    /// Drags the third application of the page to the gap after the ninth, and
    /// returns whether its saved position changed.
    private func drag(whileDragging: () async throws -> Void = {}) async throws -> Bool {
        root.needsLayout = true
        root.layoutSubtreeIfNeeded()
        let entries = root.activeSurface!.entries.filter { entry in
            if case .application = entry.item { return true }
            return false
        }
        let source = entries[2]
        let start = CGPoint(x: source.frames.icon.midX, y: source.frames.icon.midY)
        let end = CGPoint(x: entries[8].frames.cell.maxX - 1, y: entries[8].frames.icon.midY)
        source.button.mouseDown(with: event(.leftMouseDown, start))
        for step in 1...8 {
            let fraction = CGFloat(step) / 8
            let point = CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction)
            source.button.mouseDragged(with: event(.leftMouseDragged, point))
            await pause(40)
        }
        await pause(500)
        check(root.dragSession != nil, "drag is active")
        try await whileDragging()
        let before = try await savedIndex(of: source)
        source.button.mouseUp(with: event(.leftMouseUp, end))
        for _ in 0..<80 where root.isCommittingLayout || root.dragSession != nil { await pause(25) }
        await pause(600)
        return try await savedIndex(of: source) != before
    }

    private func savedIndex(of entry: LaunchpadPageEntry) async throws -> Int? {
        try await root.layoutStore.load().items.firstIndex { item in
            guard case .application(let reference) = item else { return false }
            return .application(reference.identity) == entry.item.id
        }
    }

    private func verifyDrag() async throws {
        check(try await drag(), "a plain drag is saved")

        let full = root.applications
        root.applications.removeLast()
        let saved = try await drag {
            await root.refreshApplicationsFromDisk()
            check(root.applications.count == full.count - 1, "the catalog change waits for the drag")
        }
        check(saved, "a drag during a catalog change is saved")
        await until("the change is applied after the drop") { root.applications == full }

        // Another writer advances the store: this drop cannot be saved, but the
        // next one must not inherit the stale revision.
        let temporary = ApplicationRecord(
            displayName: "Temporary", bundleIdentifier: "test.catalog.temporary",
            bundleURL: directory.appendingPathComponent("Temporary.app"))
        let conflicting = try await drag {
            _ = try await root.layoutStore.reconcileAndCommit(applications: root.applications + [temporary])
        }
        check(!conflicting, "a conflicting drop is not saved")
        check(await storedRevision() == root.layoutDocument.revision, "the view adopts the stored layout after it")
        check(try await drag(), "the next drag is saved")
        check(await storedRevision() == root.layoutDocument.revision, "view and store stay in step")
    }

    private func verifyFolderWithMissingApplication() async throws {
        let folderID = openFirstFolder()
        root.closeFolder(animated: false)
        let folder = root.resolvedFolder(id: folderID)!
        let all = root.applications
        let removed = Set(folder.applications.dropFirst().map(\.id))
        root.applications = all.filter { !removed.contains($0.id) }
        check(
            root.resolvedFolder(id: folderID)?.applications.map(\.id) == [folder.applications[0].id],
            "a folder keeps showing its remaining application")
        root.openFolder(folderID)
        check(root.openFolderID == folderID, "that folder opens")
        root.closeFolder(animated: false)
        root.applications = all
    }

    private func verifyIconUpdate() async throws {
        let bundle = directory.appendingPathComponent("IconProbe.app")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        func record() -> ApplicationRecord { AppMetadataResolver().resolve(bundleURL: bundle)! }
        func setIcon(_ color: NSColor) {
            let image = NSImage(size: NSSize(width: 256, height: 256), flipped: false) { rect in
                color.setFill()
                rect.fill()
                return true
            }
            check(NSWorkspace.shared.setIcon(image, forFile: bundle.path), "fixture icon is set")
        }
        let cache = AppIconCache()
        func isBlue(_ record: ApplicationRecord) -> Bool? {
            guard let image = cache.cgImage(for: record, pointSize: 96, scale: 2),
                let color = NSBitmapImageRep(cgImage: image).colorAt(x: image.width / 2, y: image.height / 2)?
                    .usingColorSpace(.sRGB)
            else { return nil }
            return color.blueComponent > color.redComponent
        }
        func warm() async {
            cache.retainPinnedFirstPageApplications([record()])
            await cache.warmPinnedFirstPage([record()], pointSize: 96, scale: 2)
        }
        setIcon(.red)
        await pause(800)
        await warm()
        check(isBlue(record()) == false, "pinned icon shows the first artwork")
        let pinned = cache.cgImage(for: record(), pointSize: 96, scale: 2)
        await warm()
        check(
            cache.cgImage(for: record(), pointSize: 96, scale: 2) === pinned, "an unchanged icon is not decoded again")
        setIcon(.blue)
        await pause(800)
        await warm()
        check(isBlue(record()) == true, "pinned icon follows the updated artwork")
    }

    private func verifyMonitor() async throws {
        let files = FileManager.default
        let existing = directory.appendingPathComponent("Applications")
        let later = directory.appendingPathComponent("Later")
        try files.createDirectory(
            at: existing.appendingPathComponent("Utilities/Old.app/Contents/Resources"),
            withIntermediateDirectories: true)
        await pause(1500)
        var changes = 0
        let monitor = ApplicationDirectoryMonitor(roots: [existing, later]) { changes += 1 }
        monitor.start()
        await pause(500)
        check(changes == 0, "starting reports nothing")

        func expectChange(_ message: String, _ work: () throws -> Void) async rethrows {
            let before = changes
            try work()
            await until(message) { changes > before }
            await pause(300)
        }
        try await expectChange("an application added in a subfolder is noticed") {
            try files.createDirectory(
                at: existing.appendingPathComponent("Utilities/New.app/Contents"), withIntermediateDirectories: true)
        }
        try await expectChange("a rewritten Info.plist is noticed") {
            try "x".write(
                to: existing.appendingPathComponent("Utilities/Old.app/Contents/Info.plist"), atomically: true,
                encoding: .utf8)
        }
        try await expectChange("a removed application is noticed") {
            try files.moveItem(
                at: existing.appendingPathComponent("Utilities/New.app"),
                to: directory.appendingPathComponent("Moved.app"))
        }
        try await expectChange("a folder created later is noticed") {
            try files.createDirectory(at: later.appendingPathComponent("Late.app"), withIntermediateDirectories: true)
        }
        let before = changes
        try "x".write(
            to: existing.appendingPathComponent("Utilities/Old.app/Contents/Resources/data"), atomically: false,
            encoding: .utf8)
        await pause(2200)
        check(changes == before, "files an application writes inside its bundle are ignored")
    }
}

@main
struct CatalogRefreshCheckMain {
    @MainActor static func main() async throws {
        guard let path = ProcessInfo.processInfo.environment["OPENLAUNCHPAD_LAYOUT_PATH"],
            path.hasPrefix("/private/tmp/")
        else { fatalError("Set OPENLAUNCHPAD_LAYOUT_PATH inside /private/tmp") }
        NSApplication.shared.setActivationPolicy(.prohibited)
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
            .appendingPathComponent("catalog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let failures = try await CatalogRefreshCheck(directory: directory).run()
        print("CATALOG REFRESH: \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
