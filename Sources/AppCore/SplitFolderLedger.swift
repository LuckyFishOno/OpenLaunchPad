import Foundation

/// Folders taken apart because only one of their applications is available.
///
/// The remaining application takes the folder's place at once, and the missing
/// ones leave the layout, so they take no slot. If one returns within `grace`,
/// the folder is put back where the remaining application is, with its
/// identifier, title, and order. The memory is not saved: after a restart, a
/// returning application is added at the end like a new one.
struct SplitFolderLedger: Sendable {
    private let grace: TimeInterval
    private var folders: [UUID: (folder: LauncherFolder, since: TimeInterval)] = [:]

    init(grace: TimeInterval) { self.grace = grace }

    mutating func apply(
        to pages: [[LauncherLayoutItem]],
        available: Set<ApplicationIdentity>,
        at now: TimeInterval
    ) -> [[LauncherLayoutItem]] {
        folders = folders.filter { now - $0.value.since < grace }
        return split(reassemble(pages, available: available), available: available, at: now)
    }

    private mutating func reassemble(
        _ pages: [[LauncherLayoutItem]],
        available: Set<ApplicationIdentity>
    ) -> [[LauncherLayoutItem]] {
        var pages = pages
        for (id, entry) in folders.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            let folder = entry.folder
            let members = Set(folder.applications.map(\.identity))
            let present = Set(Self.topLevelApplications(in: pages)).intersection(members).intersection(available)
            // The user moved the remaining application away, or reused the folder.
            guard !present.isEmpty, !Self.contains(folder: id, in: pages) else {
                folders[id] = nil
                continue
            }
            guard present.count >= 2 else { continue }
            var restored = folder
            restored.applications = folder.applications.filter { present.contains($0.identity) }
            pages = Self.replace(present, with: .folder(restored), in: pages)
            folders[id] = nil
        }
        return pages
    }

    private mutating func split(
        _ pages: [[LauncherLayoutItem]],
        available: Set<ApplicationIdentity>,
        at now: TimeInterval
    ) -> [[LauncherLayoutItem]] {
        var result: [[LauncherLayoutItem]] = []
        for page in pages {
            var items: [LauncherLayoutItem] = []
            for item in page {
                guard case let .folder(folder) = item,
                    let remaining = Self.onlyAvailable(in: folder, available: available)
                else {
                    items.append(item)
                    continue
                }
                folders[folder.id] = (folder, now)
                items.append(.application(remaining))
            }
            result.append(items)
        }
        return result
    }

    private static func onlyAvailable(
        in folder: LauncherFolder,
        available: Set<ApplicationIdentity>
    ) -> LauncherApplicationReference? {
        let references = folder.applications.filter { available.contains($0.identity) }
        return references.count == 1 ? references[0] : nil
    }

    private static func topLevelApplications(in pages: [[LauncherLayoutItem]]) -> [ApplicationIdentity] {
        pages.flatMap { $0 }.compactMap { item in
            guard case let .application(reference) = item else { return nil }
            return reference.identity
        }
    }

    private static func contains(folder id: UUID, in pages: [[LauncherLayoutItem]]) -> Bool {
        pages.flatMap { $0 }.contains { item in
            guard case let .folder(folder) = item else { return false }
            return folder.id == id
        }
    }

    /// Puts `item` where the first of `members` is and removes the others.
    private static func replace(
        _ members: Set<ApplicationIdentity>,
        with item: LauncherLayoutItem,
        in pages: [[LauncherLayoutItem]]
    ) -> [[LauncherLayoutItem]] {
        var placed = false
        return pages.map { page in
            page.compactMap { candidate in
                guard case let .application(reference) = candidate, members.contains(reference.identity) else {
                    return candidate
                }
                defer { placed = true }
                return placed ? nil : item
            }
        }
    }
}
