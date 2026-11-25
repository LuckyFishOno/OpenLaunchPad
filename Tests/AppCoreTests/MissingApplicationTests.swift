import Foundation
import XCTest

@testable import AppCore

final class MissingApplicationTests: XCTestCase {
    private let alpha = application("alpha")
    private let beta = application("beta")
    private let gamma = application("gamma")

    func testApplicationReplacedByAnUpdateKeepsItsPlaceAndFolder() async throws {
        let store = try await storeWithFolder()
        let before = try await store.load()

        let during = try await store.reconcileAndCommit(applications: [beta, gamma], now: 100)
        let after = try await store.reconcileAndCommit(applications: [alpha, beta, gamma], now: 130)

        XCTAssertEqual(during.document, before)
        XCTAssertEqual(during.reviewDelay, 60)
        XCTAssertFalse(during.changed)
        XCTAssertEqual(after.document, before)
        XCTAssertNil(after.reviewDelay)
    }

    func testApplicationStillMissingAfterTheGraceIsRemoved() async throws {
        let store = try await storeWithFolder()

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
        let store = try await storeWithFolder()

        _ = try await store.reconcileAndCommit(applications: [beta, gamma], now: 100)
        _ = try await store.reconcileAndCommit(applications: [alpha, beta, gamma], now: 150)
        let again = try await store.reconcileAndCommit(applications: [beta, gamma], now: 170)

        XCTAssertEqual(again.reviewDelay, 60)
        XCTAssertTrue(again.report.removedApplications.isEmpty)
    }

    func testPartialScanNeitherStartsNorEndsTheGrace() async throws {
        let store = try await storeWithFolder()

        let partial = try await store.reconcileAndCommit(applications: [beta], completeness: .partial, now: 100)
        let first = try await store.reconcileAndCommit(applications: [beta, gamma], now: 150)
        _ = try await store.reconcileAndCommit(applications: [beta], completeness: .partial, now: 400)
        let expired = try await store.reconcileAndCommit(applications: [beta, gamma], now: 400)

        XCTAssertNil(partial.reviewDelay)
        XCTAssertEqual(first.reviewDelay, 60)
        XCTAssertEqual(expired.report.removedApplications, [alpha.id])
    }

    func testEachMissingApplicationHasItsOwnGrace() async throws {
        let store = try await storeWithFolder()

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

        XCTAssertEqual(during.document.items.first, before.items.first)
        XCTAssertEqual(after.document.pages, before.pages)
    }

    private func storeWithFolder() async throws -> LauncherLayoutStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = LauncherLayoutStore(
            fileURL: directory.appendingPathComponent("layout.json"), missingApplicationGrace: 60)
        _ = try await store.transact(expectedRevision: 0) { [alpha, beta, gamma] document in
            document.items = [
                .folder(LauncherFolder(customTitle: "Work", applications: [
                    LauncherApplicationReference(application: alpha), LauncherApplicationReference(application: gamma),
                ])),
                .application(LauncherApplicationReference(application: beta)),
            ]
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
