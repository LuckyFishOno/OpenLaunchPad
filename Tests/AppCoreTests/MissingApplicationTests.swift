import Foundation
import XCTest

@testable import AppCore

final class MissingApplicationTests: XCTestCase {
    private let alpha = application("alpha")
    private let beta = application("beta")
    private let gamma = application("gamma")
    private let delta = application("delta")

    func testApplicationReplacedByAnUpdateKeepsItsPlaceAndFolder() async throws {
        let store = try await storeWithFolder()
        let before = try await store.load()

        let during = try await store.reconcileAndCommit(applications: [beta, gamma], now: 100)
        let after = try await store.reconcileAndCommit(applications: [alpha, beta, gamma], now: 130)

        // The folder's remaining application takes its place at once.
        XCTAssertEqual(during.document.items, [reference(gamma), reference(beta)])
        XCTAssertEqual(during.reviewDelay, 60)
        XCTAssertEqual(after.document.pages, before.pages)
        XCTAssertNil(after.reviewDelay)
    }

    func testFolderWithTwoAvailableApplicationsIsKept() async throws {
        let store = try await storeWithFolder(members: [alpha, gamma, delta])
        let before = try await store.load()

        let during = try await store.reconcileAndCommit(applications: [beta, gamma, delta], now: 100)

        XCTAssertEqual(during.document.pages, before.pages)
    }

    func testFolderIsRestoredOnPagesThatChangedMeanwhile() async throws {
        let store = try await storeWithFolder()
        let during = try await store.reconcileAndCommit(applications: [beta, gamma], now: 100)
        _ = try await store.transact(expectedRevision: during.document.revision) { [beta, gamma] in
            $0.pages = [
                [.application(LauncherApplicationReference(application: beta))],
                [.application(LauncherApplicationReference(application: gamma))],
            ]
            return .commit
        }

        let after = try await store.reconcileAndCommit(applications: [alpha, beta, gamma], now: 159)

        XCTAssertEqual(after.document.pages.count, 2)
        XCTAssertEqual(after.document.pages[0], [reference(beta)])
        guard case let .folder(folder) = after.document.pages[1].first else { return XCTFail("no folder") }
        XCTAssertEqual(folder.customTitle, "Work")
        XCTAssertEqual(folder.applications.map(\.identity), [alpha.id, gamma.id])
        XCTAssertEqual(after.document.pages[1].count, 1)
    }

    func testFolderIsNotRestoredAfterTheGrace() async throws {
        let store = try await storeWithFolder()

        _ = try await store.reconcileAndCommit(applications: [beta, gamma], now: 100)
        _ = try await store.reconcileAndCommit(applications: [beta, gamma], now: 160)
        let reinstalled = try await store.reconcileAndCommit(applications: [alpha, beta, gamma], now: 200)

        XCTAssertEqual(reinstalled.document.items, [reference(gamma), reference(beta), reference(alpha)])
    }

    func testApplicationMovedByTheUserMeanwhileIsNotPutBack() async throws {
        let store = try await storeWithFolder()
        let during = try await store.reconcileAndCommit(applications: [beta, gamma], now: 100)
        let moved = try await store.transact(expectedRevision: during.document.revision) { [beta, gamma] in
            $0.items = [
                .folder(LauncherFolder(applications: [
                    LauncherApplicationReference(application: beta),
                    LauncherApplicationReference(application: gamma),
                ])),
            ]
            return .commit
        }

        let after = try await store.reconcileAndCommit(applications: [alpha, beta, gamma], now: 130)

        XCTAssertEqual(after.document.items, moved.items + [reference(alpha)])
    }

    func testPartialScanKeepsTheFolder() async throws {
        let store = try await storeWithFolder()
        let before = try await store.load()

        let partial = try await store.reconcileAndCommit(applications: [beta, gamma], completeness: .partial, now: 100)

        XCTAssertEqual(partial.document.pages, before.pages)
    }

    func testApplicationStillMissingAfterTheGraceIsRemoved() async throws {
        let store = try await storeWithoutFolder()

        let first = try await store.reconcileAndCommit(applications: [beta, gamma], now: 100)
        let second = try await store.reconcileAndCommit(applications: [beta, gamma], now: 159)
        let third = try await store.reconcileAndCommit(applications: [beta, gamma], now: 160)

        XCTAssertEqual(first.reviewDelay, 60)
        XCTAssertEqual(second.reviewDelay, 1)
        XCTAssertNil(third.reviewDelay)
        XCTAssertEqual(third.report.removedApplications, [alpha.id])
        XCTAssertEqual(third.document.items, [reference(gamma), reference(beta)])
    }

    func testReturningApplicationStartsANewGraceWhenItDisappearsAgain() async throws {
        let store = try await storeWithoutFolder()

        _ = try await store.reconcileAndCommit(applications: [beta, gamma], now: 100)
        _ = try await store.reconcileAndCommit(applications: [alpha, beta, gamma], now: 150)
        let again = try await store.reconcileAndCommit(applications: [beta, gamma], now: 170)

        XCTAssertEqual(again.reviewDelay, 60)
        XCTAssertTrue(again.report.removedApplications.isEmpty)
    }

    func testPartialScanNeitherStartsNorEndsTheGrace() async throws {
        let store = try await storeWithoutFolder()

        let partial = try await store.reconcileAndCommit(applications: [beta], completeness: .partial, now: 100)
        let first = try await store.reconcileAndCommit(applications: [beta, gamma], now: 150)
        _ = try await store.reconcileAndCommit(applications: [beta], completeness: .partial, now: 400)
        let expired = try await store.reconcileAndCommit(applications: [beta, gamma], now: 400)

        XCTAssertNil(partial.reviewDelay)
        XCTAssertEqual(first.reviewDelay, 60)
        XCTAssertEqual(expired.report.removedApplications, [alpha.id])
    }

    func testEachMissingApplicationHasItsOwnGrace() async throws {
        let store = try await storeWithoutFolder()

        _ = try await store.reconcileAndCommit(applications: [beta, gamma], now: 100)
        let both = try await store.reconcileAndCommit(applications: [gamma], now: 140)
        let one = try await store.reconcileAndCommit(applications: [gamma], now: 160)

        XCTAssertEqual(both.reviewDelay, 20)
        XCTAssertEqual(one.report.removedApplications, [alpha.id])
        XCTAssertEqual(one.reviewDelay, 40)
    }

    /// A bundle without Info.plist has only its path for an identity. When the
    /// copy completes, the path entry must merge into the reserved one.
    func testApplicationSeenWhileBeingCopiedReturnsToItsPlace() async throws {
        let store = try await storeWithFolder()
        let before = try await store.load()
        let incomplete = ApplicationRecord(
            displayName: "alpha", bundleIdentifier: nil, bundleURL: alpha.bundleURL)

        let during = try await store.reconcileAndCommit(applications: [incomplete, beta, gamma], now: 100)
        let after = try await store.reconcileAndCommit(applications: [alpha, beta, gamma], now: 110)

        XCTAssertEqual(during.document.items.first, reference(gamma))
        XCTAssertEqual(after.document.pages, before.pages)
    }

    private func storeWithoutFolder() async throws -> LauncherLayoutStore {
        try await store(items: [alpha, gamma, beta].map(reference))
    }

    private func storeWithFolder(members: [ApplicationRecord]? = nil) async throws -> LauncherLayoutStore {
        let members = (members ?? [alpha, gamma]).map(LauncherApplicationReference.init(application:))
        return try await store(items: [
            .folder(LauncherFolder(customTitle: "Work", applications: members)), reference(beta),
        ])
    }

    private func store(items: [LauncherLayoutItem]) async throws -> LauncherLayoutStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = LauncherLayoutStore(
            fileURL: directory.appendingPathComponent("layout.json"), missingApplicationGrace: 60)
        _ = try await store.transact(expectedRevision: 0) { document in
            document.items = items
            return .commit
        }
        return store
    }

    private func reference(_ application: ApplicationRecord) -> LauncherLayoutItem {
        .application(LauncherApplicationReference(application: application))
    }

    private static func application(_ name: String) -> ApplicationRecord {
        ApplicationRecord(
            displayName: name, bundleIdentifier: "test.missing.\(name)",
            bundleURL: URL(fileURLWithPath: "/Applications/\(name).app"))
    }
}
