import Foundation
import XCTest

@testable import AppCore

final class LauncherBrandMigrationTests: XCTestCase {
    func testCopiesOpenLaunchBeforeLaunchPaneAndOriginalOpenLaunchpad() throws {
        try withSupportDirectory { support in
            let recent = try writeLayout("OpenLaunch", revision: 20, under: support)
            _ = try writeLayout("LaunchPane", revision: 12, under: support)
            _ = try writeLayout("OpenLaunchpad", revision: 4, under: support)
            let result = try LauncherLayoutStore.resolveDefaultFileURL(applicationSupport: support)
            XCTAssertEqual(result, currentURL(under: support))
            XCTAssertEqual(try Data(contentsOf: result), try Data(contentsOf: recent))
            XCTAssertTrue(FileManager.default.fileExists(atPath: recent.path))
        }
    }

    func testExistingOpenLaunchPadLayoutIsNeverReplaced() throws {
        try withSupportDirectory { support in
            let current = try writeLayout("OpenLaunchPad/Layout", revision: 30, under: support)
            _ = try writeLayout("OpenLaunch", revision: 20, under: support)
            let result = try LauncherLayoutStore.resolveDefaultFileURL(applicationSupport: support)
            XCTAssertEqual(result, current)
            XCTAssertEqual(try LauncherLayoutCodec().decode(Data(contentsOf: result)).revision, 30)
        }
    }

    func testFallsBackToLaunchPaneBeforeOriginalOpenLaunchpad() throws {
        try withSupportDirectory { support in
            let recent = try writeLayout("LaunchPane", revision: 12, under: support)
            _ = try writeLayout("OpenLaunchpad", revision: 4, under: support)
            let result = try LauncherLayoutStore.resolveDefaultFileURL(applicationSupport: support)
            XCTAssertEqual(try Data(contentsOf: result), try Data(contentsOf: recent))
        }
    }

    func testFallsBackToOriginalOpenLaunchpadLayout() throws {
        try withSupportDirectory { support in
            let legacy = try writeLayout("OpenLaunchpad", revision: 4, under: support)
            let result = try LauncherLayoutStore.resolveDefaultFileURL(applicationSupport: support)
            XCTAssertEqual(try Data(contentsOf: result), try Data(contentsOf: legacy))
            XCTAssertNotEqual(result, legacy)
        }
    }

    func testMissingLayoutsReturnNewPathWithoutCreatingFile() throws {
        try withSupportDirectory { support in
            let result = try LauncherLayoutStore.resolveDefaultFileURL(applicationSupport: support)
            XCTAssertEqual(result, currentURL(under: support))
            XCTAssertFalse(FileManager.default.fileExists(atPath: result.path))
        }
    }

    func testCaseInsensitiveLegacyDirectoryCannotShadowRecentLayout() throws {
        try withSupportDirectory { support in
            let legacy = try writeLayout("OpenLaunchPad", revision: 4, under: support)
            let recent = try writeLayout("OpenLaunch", revision: 20, under: support)
            let original = try Data(contentsOf: legacy)
            let result = try LauncherLayoutStore.resolveDefaultFileURL(applicationSupport: support)
            XCTAssertEqual(result, currentURL(under: support))
            XCTAssertEqual(try Data(contentsOf: result), try Data(contentsOf: recent))
            XCTAssertEqual(try Data(contentsOf: legacy), original)
        }
    }

    func testRepeatedResolutionDoesNotReimportChangedLegacyLayout() throws {
        try withSupportDirectory { support in
            _ = try writeLayout("OpenLaunch", revision: 20, under: support)
            let first = try LauncherLayoutStore.resolveDefaultFileURL(applicationSupport: support)
            _ = try writeLayout("OpenLaunch", revision: 21, under: support)
            let second = try LauncherLayoutStore.resolveDefaultFileURL(applicationSupport: support)
            XCTAssertEqual(first, second)
            XCTAssertEqual(try LauncherLayoutCodec().decode(Data(contentsOf: second)).revision, 20)
        }
    }

    private func currentURL(under support: URL) -> URL {
        support.appendingPathComponent("OpenLaunchPad/Layout/LauncherLayout.json")
    }

    private func withSupportDirectory(_ body: (URL) throws -> Void) throws {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: support) }
        try body(support)
    }

    private func writeLayout(_ name: String, revision: UInt64, under support: URL) throws -> URL {
        let url = support.appendingPathComponent(name).appendingPathComponent("LauncherLayout.json")
        let document = LauncherLayoutDocument(revision: revision)
        try AtomicLauncherLayoutFileIO().writeDataAtomically(LauncherLayoutCodec().encode(document), to: url)
        return url
    }
}
